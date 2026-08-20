#!/usr/bin/env python3
# Copyright (C) 2026 Zach Wilke
# Copyright (C) 2012-2026 Solaar contributors (logitech_receiver / solaar)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

"""JSON CLI for Omarchy MX Control. Talks to Logitech HID++ devices via Solaar."""

from __future__ import annotations

import errno
import fcntl
import importlib.util
import json
import logging
import os
import re
import select
import stat
import sys
import time
from pathlib import Path

logging.disable(logging.CRITICAL)

KIND_NAMES = {
    0x01: "toggle",
    0x02: "choice",
    0x04: "range",
    0x0A: "map_choice",
    0x10: "multiple_toggle",
    0x20: "packed_range",
    0x21: "graphic_eq",
    0x40: "multiple_range",
    0x80: "hetero",
    0x102: "map_range",
    0x200: "color",
}

# Settings that need a live Solaar process (gestures, sliding DPI, rules).
SKIP_WRITE_KINDS = {"packed_range", "graphic_eq", "color"}

# Serve blocks on inotify. Topology is only rescanned when hidraw changes,
# or on this heartbeat if inotify is unavailable.
IDLE_TIMEOUT_SEC = 30.0
TOPOLOGY_FALLBACK_SEC = 2.0
EXIT_PEER_SERVING = 3
IN_CREATE = 0x00000100
IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_DELETE = 0x00000200
IN_RUNTIME_MASK = IN_CREATE | IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_DELETE
IN_HIDRAW_MASK = IN_CREATE | IN_DELETE | IN_MOVED_TO
IN_WATCH_MASK = IN_RUNTIME_MASK

# Filled the first time Solaar is actually imported (serve / set), never on
# the cheap sysfs discover path.
_KNOWN_RECEIVER_PIDS: set[str] | None = None
_KNOWN_RECEIVERS: dict | None = None


def emit(payload: dict, code: int = 0) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False, default=str)
    sys.stdout.write("\n")
    raise SystemExit(code)


def fail(message: str, **extra) -> None:
    payload = {"ok": False, "message": plain_hid_text(message), "devices": []}
    payload.update(extra)
    emit(payload, 1)


def hid_name_from_uevent(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("HID_NAME="):
            return line.split("=", 1)[1].strip()
    return ""


def plain_hid_text(value: str) -> str:
    """HID identity is untrusted. Strip markup so QML AutoText cannot fetch URLs."""
    text = str(value or "")
    if "<" not in text and ">" not in text:
        return text
    return text.replace("<", "").replace(">", "")


def hid_id_from_uevent(text: str) -> tuple[str, str]:
    for line in text.splitlines():
        if line.startswith("HID_ID="):
            parts = line.split("=", 1)[1].strip().split(":")
            if len(parts) >= 3:
                return parts[1][-4:].upper(), parts[2][-4:].upper()
    return "", ""


FALLBACK_RECEIVER_PIDS = {
    "C517", "C518", "C51A", "C51B", "C521", "C525", "C526", "C52B", "C52E",
    "C52F", "C531", "C532", "C534", "C535", "C537", "C539", "C53A", "C53D",
    "C53F", "C541", "C545", "C547", "C548", "C54D", "6042",
}

MX_NAME_RE = re.compile(
    r"(?:\bmx\b|master|anywhere|vertical|ergo|lift|mechanical|keys mini|mx keys|mx master)",
    re.IGNORECASE,
)


def hid_field(text: str, key: str) -> str:
    prefix = key + "="
    for line in text.splitlines():
        if line.startswith(prefix):
            return line.split("=", 1)[1].strip()
    return ""


def solaar_available() -> bool:
    return importlib.util.find_spec("logitech_receiver") is not None


def receiver_pids() -> set[str]:
    pids = set(FALLBACK_RECEIVER_PIDS)
    if _KNOWN_RECEIVER_PIDS:
        pids |= _KNOWN_RECEIVER_PIDS
    return pids


def receiver_kind_for_pid(product: str) -> str:
    pid = (product or "").upper()
    known = _KNOWN_RECEIVERS
    if known:
        try:
            info = known.get(int(pid, 16)) or known.get(pid)
        except ValueError:
            info = known.get(pid)
        if isinstance(info, dict):
            return str(info.get("receiver_kind") or info.get("name") or "receiver").lower()
    if pid == "C548":
        return "bolt"
    if pid in {"C52B", "C532"}:
        return "unifying"
    if pid.startswith("C53") or pid in {"C541", "C545", "C547", "C54D"}:
        return "lightspeed"
    if pid.startswith("C5"):
        return "nano"
    return "receiver"


def bus_from_uevent(text: str) -> str:
    if "0005:" in text:
        return "bluetooth"
    if "0003:" in text or "usb" in text.lower():
        return "usb"
    return "hid"


def kind_from_name(name: str) -> str:
    lower = name.lower()
    if any(token in lower for token in ("key", "keyboard", "mechanical")):
        return "keyboard"
    if any(token in lower for token in ("master", "mouse", "anywhere", "ergo", "vertical", "lift", "trackball")):
        return "mouse"
    return "device"


def is_mx_name(name: str) -> bool:
    lower = (name or "").lower()
    if any(token in lower for token in ("webcam", "camera", "brio", "headset", "speaker", "audio")):
        return False
    if any(token in lower for token in ("unifying receiver", "bolt receiver", "nano receiver", "lightspeed receiver")):
        return False
    return bool(MX_NAME_RE.search(lower))


def is_receiver_name(name: str, product: str) -> bool:
    if (product or "").upper() in receiver_pids():
        return True
    lower = (name or "").lower()
    return any(token in lower for token in ("unifying receiver", "bolt receiver", "nano receiver", "lightspeed receiver", "usb receiver"))


def hidraw_topology() -> tuple[str, ...]:
    items = []
    root = Path("/sys/class/hidraw")
    if not root.is_dir():
        return tuple()
    for entry in sorted(root.glob("hidraw*")):
        try:
            text = (entry / "device" / "uevent").read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        vendor, product = hid_id_from_uevent(text)
        if vendor != "046D":
            continue
        items.append(f"{entry.name}:{product}:{hid_field(text, 'HID_UNIQ')}:{hid_field(text, 'HID_NAME')}")
    return tuple(items)


def scan_hidraw() -> tuple[list[dict], list[dict]]:
    devices = []
    adapters = []
    seen = set()
    root = Path("/sys/class/hidraw")
    if not root.is_dir():
        return devices, adapters
    pids = receiver_pids()
    for entry in sorted(root.glob("hidraw*")):
        uevent_path = entry / "device" / "uevent"
        try:
            text = uevent_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        vendor, product = hid_id_from_uevent(text)
        if vendor != "046D":
            continue
        name = hid_name_from_uevent(text) or f"Logitech {product}"
        if name.lower().startswith("logitech "):
            name = name[9:]
        node = f"/dev/{entry.name}"
        uniq = hid_field(text, "HID_UNIQ")
        bus = bus_from_uevent(text)
        driver = hid_field(text, "DRIVER")
        if is_receiver_name(name, product) or product in pids:
            adapter_id = uniq or product or entry.name
            if adapter_id in seen:
                continue
            seen.add(adapter_id)
            kind = receiver_kind_for_pid(product)
            adapters.append(
                {
                    "id": adapter_id,
                    "name": plain_hid_text(name) or kind.title() + " receiver",
                    "kind": kind if kind in {"bolt", "unifying", "lightspeed", "nano"} else "receiver",
                    "productId": product,
                    "path": node,
                    "connection": kind if kind != "receiver" else "usb",
                    "accessible": os.access(node, os.R_OK | os.W_OK),
                }
            )
            continue
        if not (is_mx_name(name) or driver == "logitech-hidpp-device"):
            continue
        if not is_mx_name(name) and driver == "logitech-hidpp-device":
            # HID++ yes, but not an MX device (G-series, etc.).
            continue
        dedupe = uniq or f"{product}:{hid_field(text, 'HID_PHYS')}"
        if dedupe in seen:
            continue
        seen.add(dedupe)
        devices.append(
            {
                "id": uniq or entry.name,
                "name": plain_hid_text(name),
                "codename": plain_hid_text(name),
                "kind": kind_from_name(name),
                "online": True,
                "path": node,
                "productId": product,
                "serial": uniq,
                "unitId": uniq,
                "protocol": "",
                "connection": bus,
                "accessible": os.access(node, os.R_OK | os.W_OK),
                "battery": None,
                "hosts": [],
                "settings": [],
                "readonly": True,
                "adapter": "",
            }
        )
    return devices, adapters


def jsonable(value):
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    name = type(value).__name__
    if name == "NamedInt" or hasattr(value, "name") and isinstance(value, int):
        try:
            return {"id": int(value), "name": str(value)}
        except Exception:
            return str(value)
    if isinstance(value, dict):
        return {str(key): jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [jsonable(item) for item in value]
    return str(value)


def choice_list(choices) -> list[dict]:
    result = []
    if not choices:
        return result
    for item in choices:
        try:
            result.append({"id": int(item), "name": str(item)})
        except Exception:
            result.append({"id": None, "name": str(item)})
    return result


def serialize_setting(setting) -> dict | None:
    kind = KIND_NAMES.get(int(getattr(setting, "kind", 0) or 0), "unknown")
    if kind in SKIP_WRITE_KINDS:
        return None
    if getattr(setting, "display", True) is False:
        return None

    try:
        # Cached read still hits the device once, then reuses the value.
        # live_readable+cached=False re-pokes HID++ for every setting and is
        # what made the first snapshot feel slow.
        value = setting.read(True)
    except Exception as exc:
        value = None
        read_error = str(exc)
    else:
        read_error = ""

    payload = {
        "name": setting.name,
        "label": getattr(setting, "label", setting.name) or setting.name,
        "description": getattr(setting, "description", "") or "",
        "kind": kind,
        "persist": bool(getattr(setting, "persist", True)),
        "value": jsonable(value),
        "display": jsonable(setting.val_to_string(value) if value is not None and hasattr(setting, "val_to_string") else value),
        "min": None,
        "max": None,
        "choices": [],
        "keys": [],
        "readError": read_error,
    }

    if kind == "range":
        span = getattr(setting, "range", None)
        if span:
            payload["min"], payload["max"] = int(span[0]), int(span[1])
    elif kind == "choice":
        payload["choices"] = choice_list(getattr(setting, "choices", None))
    elif kind == "map_choice":
        choices = getattr(setting, "choices", None) or {}
        current = value if isinstance(value, dict) else {}
        for key in choices:
            space = choices[key]
            entry = {
                "key": str(int(key)) if hasattr(key, "__int__") else str(key),
                "label": str(key),
            }
            current_value = current.get(int(key), current.get(str(int(key)) if hasattr(key, "__int__") else str(key)))
            if type(space).__name__ == "Range" or (hasattr(space, "min") and hasattr(space, "max") and not hasattr(space, "__iter__")):
                entry.update({"kind": "range", "min": int(space.min), "max": int(space.max), "value": jsonable(current_value)})
            else:
                entry.update({"kind": "choice", "choices": choice_list(space), "value": jsonable(current_value)})
            payload["keys"].append(entry)
    elif kind == "multiple_toggle":
        labels = getattr(setting, "_labels", None) or {}
        current = value if isinstance(value, dict) else {}
        for key in labels:
            kid = str(int(key)) if hasattr(key, "__int__") else str(key)
            current_value = current.get(kid, current.get(int(key) if hasattr(key, "__int__") else key))
            payload["keys"].append(
                {
                    "key": kid,
                    "label": str(key),
                    "kind": "toggle",
                    "value": bool(current_value),
                }
            )
    elif kind == "multiple_range":
        current = value if isinstance(value, dict) else {}
        for key, item in current.items():
            payload["keys"].append({"key": str(key), "label": str(key), "kind": "object", "value": jsonable(item)})

    return payload


def device_id(dev) -> str:
    for attr in ("serial", "unitId"):
        value = getattr(dev, attr, None)
        if value:
            return str(value)
    path = getattr(dev, "path", "") or ""
    if path:
        return Path(path).name
    return str(getattr(dev, "name", "device"))


def battery_payload(dev) -> dict | None:
    try:
        battery = dev.battery()
    except Exception:
        return None
    if battery is None:
        return None
    level = getattr(battery, "level", None)
    try:
        level_n = int(level) if level is not None and not hasattr(level, "name") else None
    except Exception:
        level_n = None
    status = str(getattr(battery, "status", "") or "")
    voltage = getattr(battery, "voltage", None)
    return {
        "level": level_n,
        "status": status,
        "voltage": int(voltage) if isinstance(voltage, (int, float)) else None,
        "text": f"{level_n}%" if level_n is not None else (str(level) if level is not None else status),
    }


def hosts_payload(dev) -> list[dict]:
    try:
        from logitech_receiver import hidpp20

        names = hidpp20.Hidpp20().get_host_names(dev) or {}
    except Exception:
        return []
    hosts = []
    for index, info in names.items():
        paired, name = info if isinstance(info, tuple) and len(info) >= 2 else (False, str(info))
        hosts.append({"index": int(index), "name": plain_hid_text(str(name or f"Host {index}")), "paired": bool(paired)})
    return hosts


def receiver_connection(dev) -> str:
    recv = getattr(dev, "receiver", None)
    if recv is None:
        return ""
    pid = str(getattr(recv, "product_id", "") or "").upper()
    kind = receiver_kind_for_pid(pid)
    name = str(getattr(recv, "name", "") or "").lower()
    if "bolt" in name or kind == "bolt":
        return "bolt"
    if "unifying" in name or kind == "unifying":
        return "unifying"
    if "lightspeed" in name or kind == "lightspeed":
        return "lightspeed"
    if "nano" in name or kind == "nano":
        return "nano"
    return "receiver"


def connection_for(dev, path: str) -> str:
    via_receiver = receiver_connection(dev)
    if via_receiver:
        return via_receiver
    product = str(getattr(dev, "product_id", "") or "").upper()
    if product.startswith("B"):
        return "bluetooth"
    if path.startswith("/dev/hidraw"):
        try:
            text = Path(f"/sys/class/hidraw/{Path(path).name}/device/uevent").read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        bus = bus_from_uevent(text)
        if bus != "hid":
            return bus
        _, hid_product = hid_id_from_uevent(text)
        if hid_product in receiver_pids():
            return receiver_kind_for_pid(hid_product)
    name = str(getattr(dev, "name", "") or "").lower()
    if "bolt" in name:
        return "bolt"
    if "unifying" in name:
        return "unifying"
    return "usb"


def import_solaar():
    global _KNOWN_RECEIVERS, _KNOWN_RECEIVER_PIDS
    try:
        from logitech_receiver import base
        from logitech_receiver import device as device_mod
        from logitech_receiver import receiver as receiver_mod
        from logitech_receiver import settings_templates
        from logitech_receiver.base_usb import KNOWN_RECEIVERS
        from solaar import configuration
    except ImportError as exc:
        return None, str(exc)
    _KNOWN_RECEIVERS = KNOWN_RECEIVERS
    pids = set()
    for key in KNOWN_RECEIVERS:
        try:
            pids.add(f"{int(key):04X}")
        except (TypeError, ValueError):
            pids.add(str(key).upper())
    _KNOWN_RECEIVER_PIDS = pids
    return {
        "base": base,
        "device": device_mod,
        "receiver": receiver_mod,
        "settings_templates": settings_templates,
        "configuration": configuration,
    }, ""


def open_devices(mods, skip_paths=None):
    opened = []
    permission_error = ""
    skip = {path for path in (skip_paths or []) if path}
    for info in mods["base"].receivers_and_devices():
        path = getattr(info, "path", None)
        if path and path in skip:
            continue
        try:
            if getattr(info, "isDevice", False):
                handle = mods["device"].create_device(mods["base"], info)
            else:
                handle = mods["receiver"].create_receiver(mods["base"], info)
        except PermissionError as exc:
            permission_error = str(exc)
            continue
        except OSError as exc:
            if getattr(exc, "errno", None) == 13:
                permission_error = str(exc)
                continue
            continue
        except Exception:
            continue
        if handle is not None:
            opened.append(handle)
    return opened, permission_error


def add_new_devices(mods, opened):
    existing = {getattr(handle, "path", None) for handle in opened}
    extra, permission_error = open_devices(mods, skip_paths=existing)
    return opened + extra, permission_error


def iter_devices(opened):
    for handle in opened:
        if getattr(handle, "isDevice", False):
            yield handle
            continue
        try:
            count = handle.count()
        except Exception:
            count = 0
        if not count:
            continue
        seen = 0
        for child in handle:
            yield child
            seen += 1
            if seen >= count:
                break


def is_mouse_dev(dev) -> bool:
    kind = str(getattr(dev, "kind", "") or "").lower()
    if kind in {"mouse", "trackball", "touchpad"}:
        return True
    return kind_from_name(str(getattr(dev, "name", "") or "")) == "mouse"


def ordered_devices(opened) -> list:
    devices = list(iter_devices(opened))
    devices.sort(key=lambda dev: (0 if is_mouse_dev(dev) else 1, str(getattr(dev, "name", "") or "").lower()))
    return devices


def device_is_online(dev) -> bool:
    if getattr(dev, "online", None) is True:
        return True
    if getattr(dev, "protocol", None) or getattr(dev, "_protocol", None):
        return True
    try:
        return bool(dev.ping())
    except Exception:
        return bool(getattr(dev, "online", False))


def load_settings(mods, dev) -> list[dict]:
    try:
        mods["configuration"].attach_to(dev)
    except Exception:
        pass
    raw = list(getattr(dev, "settings", None) or [])
    # Feature discovery is a HID++ round-trip burst. Do it once; later
    # snapshots reuse the settings already attached to the open handle.
    if not any(item is not None for item in raw):
        try:
            mods["settings_templates"].check_feature_settings(dev, raw)
        except Exception:
            pass
    settings = []
    seen = set()
    for setting in raw:
        if setting is None or setting.name in seen:
            continue
        seen.add(setting.name)
        serialized = serialize_setting(setting)
        if serialized:
            settings.append(serialized)
    return settings


def runtime_path(xdg_runtime_dir: str | None, uid: int) -> str:
    if xdg_runtime_dir:
        return f"{xdg_runtime_dir}/omarchy-mx"
    return f"/run/user/{uid}/omarchy-mx"


def ensure_private_dir(path: Path) -> Path:
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        path.unlink()
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def runtime_dir() -> Path:
    return ensure_private_dir(Path(runtime_path(os.environ.get("XDG_RUNTIME_DIR"), os.getuid())))


def _is_nofollow_error(exc: OSError) -> bool:
    return exc.errno in (errno.ELOOP, getattr(errno, "EMLINK", errno.ELOOP))


def _create_exclusive(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".tmp")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    try:
        fd = os.open(tmp, flags, 0o600)
    except FileExistsError:
        try:
            tmp.unlink()
        except OSError:
            pass
        fd = os.open(tmp, flags, 0o600)
    try:
        os.write(fd, data)
        os.fchmod(fd, 0o600)
    finally:
        os.close(fd)
    os.replace(tmp, path)


def write_bytes(path: Path, data: bytes) -> None:
    """Write without following a planted symlink. Keep a regular file in place."""
    flags = os.O_WRONLY | os.O_NOFOLLOW | os.O_TRUNC
    try:
        fd = os.open(path, flags)
    except FileNotFoundError:
        _create_exclusive(path, data)
        return
    except OSError as exc:
        if not _is_nofollow_error(exc):
            raise
        path.unlink()
        _create_exclusive(path, data)
        return
    try:
        os.write(fd, data)
        os.fchmod(fd, 0o600)
    finally:
        os.close(fd)


def atomic_write(path: Path, payload: dict) -> None:
    write_status(path, payload, last_text=None)


def write_status(path: Path, payload: dict, last_text: list[str] | None = None) -> bool:
    text = json.dumps(payload, ensure_ascii=False, default=str) + "\n"
    if last_text is not None and last_text[0] == text:
        return False
    write_bytes(path, text.encode("utf-8"))
    if last_text is not None:
        last_text[0] = text
    return True


def open_inotify(path: Path, mask: int = IN_RUNTIME_MASK) -> int | None:
    """Watch a directory. None if inotify is unavailable."""
    try:
        import ctypes
        import ctypes.util

        if not path.is_dir():
            return None
        libc_name = ctypes.util.find_library("c")
        if not libc_name:
            return None
        libc = ctypes.CDLL(libc_name, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        fd = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
        if fd < 0:
            return None
        watch = libc.inotify_add_watch(fd, os.fsencode(str(path)), mask)
        if watch < 0:
            os.close(fd)
            return None
        return fd
    except Exception:
        return None


def drain_inotify(fd: int) -> None:
    try:
        os.read(fd, 4096)
    except BlockingIOError:
        pass
    except OSError:
        pass


def wait_for_event(fds: list[int | None], timeout: float) -> bool:
    """Block until an inotify fd is readable. True if something woke us."""
    watched = [fd for fd in fds if fd is not None]
    if not watched:
        if timeout > 0:
            time.sleep(timeout)
        return False
    ready, _, _ = select.select(watched, [], [], max(0.0, timeout))
    for fd in ready:
        drain_inotify(fd)
    return bool(ready)


def close_inotify(*fds: int | None) -> None:
    for fd in fds:
        if fd is None:
            continue
        try:
            os.close(fd)
        except OSError:
            pass


def acquire_lock(blocking: bool = True):
    path = runtime_dir() / "mxctl.lock"
    flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as exc:
        if not _is_nofollow_error(exc):
            raise
        try:
            path.unlink()
        except OSError:
            pass
        fd = os.open(path, flags, 0o600)
    handle = os.fdopen(fd, "r+")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX if blocking else (fcntl.LOCK_EX | fcntl.LOCK_NB))
    except OSError:
        handle.close()
        return None
    return handle


def describe_device(mods, dev, full: bool = True) -> dict | None:
    online = device_is_online(dev)
    path = getattr(dev, "path", "") or ""
    name = str(getattr(dev, "name", "") or getattr(dev, "codename", "") or "Logitech device")
    if not is_mx_name(name):
        return None
    if not online and not name:
        return None
    kind = str(getattr(dev, "kind", "") or kind_from_name(name) or "device")
    product = str(getattr(dev, "product_id", "") or getattr(dev, "wpid", "") or "").upper()
    protocol = getattr(dev, "protocol", None)
    recv = getattr(dev, "receiver", None)
    adapter = ""
    if recv is not None:
        adapter = str(getattr(recv, "name", "") or receiver_connection(dev) or "")
    payload = {
        "id": device_id(dev),
        "name": plain_hid_text(name),
        "codename": plain_hid_text(str(getattr(dev, "codename", "") or name)),
        "kind": kind,
        "online": online,
        "path": path,
        "productId": product,
        "serial": str(getattr(dev, "serial", "") or ""),
        "unitId": str(getattr(dev, "unitId", "") or ""),
        "protocol": f"HID++ {protocol:.1f}" if isinstance(protocol, (int, float)) and protocol else "",
        "connection": connection_for(dev, path),
        "accessible": True,
        "battery": battery_payload(dev) if online else None,
        "hosts": hosts_payload(dev) if online and full else [],
        "settings": load_settings(mods, dev) if online and full else [],
        "readonly": False,
        "adapter": plain_hid_text(adapter),
    }
    return payload


def identity_keys(item: dict) -> set[str]:
    keys = set()
    for field in ("id", "unitId", "serial", "path", "name", "codename"):
        value = item.get(field)
        if value:
            keys.add(str(value).lower())
    path = str(item.get("path") or "")
    if path:
        keys.add(Path(path).name.lower())
    return keys


def merge_discovery(solaar_devices: list[dict], hidraw_devices: list[dict]) -> list[dict]:
    merged = list(solaar_devices)
    known = set()
    for item in merged:
        known |= identity_keys(item)
    for hid in hidraw_devices:
        if identity_keys(hid) & known:
            continue
        merged.append(hid)
        known |= identity_keys(hid)
    merged.sort(key=lambda item: (0 if item.get("kind") == "mouse" else 1, item.get("name") or ""))
    return merged


def close_all(mods) -> None:
    try:
        for inst in list(getattr(mods["device"].Device, "instances", []) or []):
            try:
                inst.close()
            except Exception:
                pass
    except Exception:
        pass


def find_device(devices, needle: str):
    text = (needle or "").strip().lower()
    if not text:
        return None
    for dev in devices:
        hay = [
            str(getattr(dev, "serial", "") or ""),
            str(getattr(dev, "unitId", "") or ""),
            str(getattr(dev, "path", "") or ""),
            Path(str(getattr(dev, "path", "") or "")).name,
            str(getattr(dev, "name", "") or ""),
            str(getattr(dev, "codename", "") or ""),
            str(getattr(dev, "product_id", "") or ""),
        ]
        if any(text == item.lower() for item in hay if item):
            return dev
    for dev in devices:
        name = str(getattr(dev, "name", "") or "").lower()
        if text in name:
            return dev
    return None


def find_setting(dev, name: str):
    target = name.strip().lower()
    for setting in getattr(dev, "settings", None) or []:
        if setting and setting.name.lower() == target:
            return setting
    return None


def parse_value(raw: str):
    text = raw if raw is not None else ""
    stripped = text.strip()
    if stripped == "":
        return stripped
    lower = stripped.lower()
    if lower in ("true", "on", "yes", "t", "y", "1"):
        return True
    if lower in ("false", "off", "no", "f", "n", "0"):
        return False
    try:
        return json.loads(stripped)
    except Exception:
        pass
    if re.fullmatch(r"-?\d+", stripped):
        return int(stripped)
    return stripped


def coerce_choice(setting, value, choices):
    if choices is None:
        return value
    if isinstance(value, bool):
        value = int(value)
    text = str(value).lower()
    for choice in choices:
        if str(choice).lower() == text or str(int(choice)) == text:
            return choice
    if isinstance(value, int):
        for choice in choices:
            if int(choice) == value:
                return choice
    raise ValueError(f"{setting.name}: possible values are [{', '.join(str(c) for c in choices)}]")


def apply_setting(setting, key, value):
    kind = KIND_NAMES.get(int(getattr(setting, "kind", 0) or 0), "unknown")
    if kind == "toggle":
        if isinstance(value, str):
            value = parse_value(value)
        result = setting.write(bool(value), save=True)
    elif kind == "range":
        result = setting.write(int(value), save=True)
    elif kind == "choice":
        result = setting.write(coerce_choice(setting, value, setting.choices), save=True)
    elif kind in ("map_choice", "multiple_toggle", "multiple_range", "map_range"):
        if key is None:
            raise ValueError(f"{setting.name}: this setting needs a key and a value")
        if kind == "map_choice":
            match = None
            for item in setting.choices:
                if str(item).lower() == str(key).lower() or str(int(item)) == str(key):
                    match = item
                    break
            if match is None:
                raise ValueError(f"{setting.name}: key '{key}' not in setting")
            space = setting.choices[match]
            if hasattr(space, "min") and hasattr(space, "max") and not hasattr(space, "__iter__"):
                written = int(value)
            else:
                written = coerce_choice(setting, value, space)
            result = setting.write_key_value(int(match), written, save=True)
        elif kind == "multiple_toggle":
            match = None
            for item in getattr(setting, "_labels", {}) or {}:
                if str(item).lower() == str(key).lower() or str(int(item)) == str(key):
                    match = item
                    break
            if match is None:
                raise ValueError(f"{setting.name}: key '{key}' not in setting")
            result = setting.write_key_value(str(int(match)), bool(value), save=True)
        else:
            result = setting.write_key_value(int(key), value if not isinstance(value, str) else parse_value(value), save=True)
    elif kind == "hetero":
        result = setting.write(value, save=True)
    else:
        raise ValueError(f"{setting.name}: setting kind '{kind}' is not writable from this plugin")
    if result is None:
        raise RuntimeError(f"{setting.name}: device rejected the write")
    return result


def discover_payload() -> dict:
    hid_devices, adapters = scan_hidraw()
    installed = solaar_available()
    visible = hid_devices + adapters
    return {
        "ok": True,
        "installed": installed,
        "accessible": any(item.get("accessible") for item in visible) or not visible,
        "message": "" if installed else "Solaar is not installed. Install it with `omarchy pkg add solaar`, then reconnect the device.",
        "importError": "" if installed else "logitech_receiver not found",
        "devices": hid_devices,
        "adapters": adapters,
        "serving": False,
    }


def progress_payload(done: int, total: int, label: str = "", phase: str = "hidpp") -> dict:
    total_n = max(int(total or 0), 0)
    done_n = max(0, int(done or 0))
    if total_n > 0:
        done_n = min(done_n, total_n)
        percent = int(round(100.0 * done_n / total_n))
    else:
        percent = 100 if phase == "idle" else 0
    return {
        "done": done_n,
        "total": total_n,
        "percent": percent,
        "label": plain_hid_text(label),
        "phase": phase,
    }


def status_from_described(described, hid_devices, adapters, permission_error, last_error: str = "") -> dict:
    devices = merge_discovery(described, hid_devices)
    accessible = any(item.get("accessible") for item in devices + adapters) or bool(described)
    message = ""
    if not devices and not adapters:
        message = "No MX devices found. Plug in a Bolt/Unifying receiver, USB cable, or connect over Bluetooth."
    elif permission_error and not described:
        message = (
            "Found Logitech devices but cannot open them. "
            "Install Solaar (`omarchy pkg add solaar`), then reconnect the mouse "
            "or run `sudo udevadm trigger` so the hidraw rules apply."
        )
        accessible = False
    return {
        "ok": True,
        "installed": True,
        "accessible": accessible,
        "message": message,
        "permissionError": permission_error,
        "devices": devices,
        "adapters": adapters,
        "serving": True,
        "lastError": plain_hid_text(last_error),
        "progress": progress_payload(len(described), len(described), "", "idle"),
    }


def refresh_one_device(mods, opened, hid_devices, adapters, permission_error, needle: str, previous: dict | None, last_error: str = "") -> dict:
    """Re-read a single device after a set, keeping the rest of the snapshot."""
    devices = list(iter_devices(opened))
    dev = find_device(devices, needle)
    item = describe_device(mods, dev, full=True) if dev else None
    described = []
    replaced = False
    for old in (previous or {}).get("devices") or []:
        if item and identity_keys(old) & identity_keys(item):
            described.append(item)
            replaced = True
        elif old.get("settings"):
            described.append(old)
    if item and not replaced:
        described.append(item)
    if not described:
        return collect_status(mods, opened, hid_devices, adapters, permission_error, full=True)
    return status_from_described(described, hid_devices, adapters, permission_error, last_error)


def collect_status(mods, opened, hid_devices, adapters, permission_error, full: bool = True, on_partial=None) -> dict:
    pending = ordered_devices(opened)
    total = len(pending)
    described = []
    last_error = ""
    for dev in pending:
        payload = describe_device(mods, dev, full=full)
        if payload:
            described.append(payload)
            if on_partial and full:
                snap = status_from_described(described, hid_devices, adapters, permission_error, last_error)
                snap["progress"] = progress_payload(len(described), total, payload.get("name") or "", "hidpp")
                on_partial(snap)
    snap = status_from_described(described, hid_devices, adapters, permission_error, last_error)
    snap["progress"] = progress_payload(len(described), total, "", "idle" if described else "hidpp")
    return snap


def status_command() -> None:
    hid_devices, adapters = scan_hidraw()
    mods, import_error = import_solaar()
    installed = mods is not None
    if not installed:
        emit(
            {
                "ok": True,
                "installed": False,
                "accessible": any(item.get("accessible") for item in hid_devices + adapters),
                "message": "Solaar is not installed. Install it with `omarchy pkg add solaar`, then reconnect the device.",
                "importError": import_error,
                "devices": hid_devices,
                "adapters": adapters,
            }
        )

    lock = acquire_lock(blocking=True)
    opened, permission_error = open_devices(mods)
    try:
        payload = collect_status(mods, opened, hid_devices, adapters, permission_error, full=True)
        payload["serving"] = False
        emit(payload)
    finally:
        close_all(mods)
        if lock:
            lock.close()


def set_command(argv: list[str]) -> None:
    if len(argv) < 2:
        fail("usage: mxctl.py set <device> <setting> [key] <value>", installed=True)
    device_name = argv[0]
    setting_name = argv[1]
    if len(argv) == 2:
        fail("missing value", installed=True)
    if len(argv) == 3:
        key = None
        value = parse_value(argv[2])
    else:
        key = argv[2]
        value = parse_value(argv[3])

    mods, import_error = import_solaar()
    if mods is None:
        fail("Solaar is not installed", installed=False, importError=import_error)

    opened, permission_error = open_devices(mods)
    try:
        devices = list(iter_devices(opened))
        dev = find_device(devices, device_name)
        if not dev:
            fail(f"no device matching '{device_name}'", installed=True, accessible=not permission_error)
        try:
            online = bool(dev.ping())
        except Exception:
            online = False
        if not online:
            fail(f"{plain_hid_text(getattr(dev, 'name', device_name))} is offline", installed=True, accessible=True)
        mods["configuration"].attach_to(dev)
        raw = list(getattr(dev, "settings", None) or [])
        try:
            mods["settings_templates"].check_feature_settings(dev, raw)
        except Exception:
            pass
        setting = find_setting(dev, setting_name)
        if setting is None:
            names = [s.name for s in raw if s]
            fail(f"no setting '{setting_name}'", installed=True, accessible=True, settings=names)
        result = apply_setting(setting, key, value)
        emit(
            {
                "ok": True,
                "installed": True,
                "accessible": True,
                "message": f"Set {setting.name}",
                "device": device_id(dev),
                "setting": setting.name,
                "key": key,
                "value": jsonable(result),
            }
        )
    except Exception as exc:
        fail(plain_hid_text(str(exc)), installed=True, accessible=True)
    finally:
        close_all(mods)


PROFILE_SKIP = {"change-host", "change_host"}
PROFILE_MAX_COUNT = 40
PROFILE_MAX_BYTES = 262144


def profiles_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return ensure_private_dir(Path(base) / "omarchy-mx")


def profiles_file() -> Path:
    return profiles_dir() / "profiles.json"


def load_profiles() -> dict:
    empty = {"version": 1, "profiles": []}
    path = profiles_file()
    flags = os.O_RDONLY | os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except FileNotFoundError:
        return empty
    except OSError as exc:
        if _is_nofollow_error(exc):
            return empty
        raise
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return empty
        raw = os.read(fd, PROFILE_MAX_BYTES + 1)
    finally:
        os.close(fd)
    if not raw or len(raw) > PROFILE_MAX_BYTES:
        return empty
    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception:
        return empty
    if not isinstance(data, dict) or not isinstance(data.get("profiles"), list):
        return empty
    return {"version": 1, "profiles": data["profiles"][:PROFILE_MAX_COUNT]}


def write_profiles(data: dict) -> None:
    profiles = list(data.get("profiles") or [])
    if len(profiles) > PROFILE_MAX_COUNT:
        profiles = profiles[-PROFILE_MAX_COUNT:]
    payload = {"version": 1, "profiles": profiles}
    raw = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(raw) > PROFILE_MAX_BYTES:
        raise ValueError("profile store is too large")
    path = profiles_file()
    write_bytes(path, raw)
    os.chmod(path, 0o600)


def sanitize_profile_name(raw) -> str:
    text = plain_hid_text(" ".join(str(raw or "").split()))
    if not text:
        raise ValueError("profile name is empty")
    if len(text) > 40:
        text = text[:40].rstrip()
    return text


def snapshot_settings(mods, dev) -> list[dict]:
    rows = []
    for setting in load_settings(mods, dev):
        name = str(setting.get("name") or "")
        if not name or name in PROFILE_SKIP:
            continue
        keys = setting.get("keys") or []
        if keys:
            for key in keys:
                rows.append(
                    {
                        "name": name,
                        "key": str(key.get("key") or ""),
                        "value": jsonable(key.get("value")),
                    }
                )
        else:
            rows.append({"name": name, "key": "", "value": jsonable(setting.get("value"))})
    return rows


def profile_save(mods, opened, cmd: dict) -> None:
    name = sanitize_profile_name(cmd.get("name"))
    devices = list(iter_devices(opened))
    dev = find_device(devices, str(cmd.get("device") or ""))
    if not dev:
        raise RuntimeError(f"no device matching '{cmd.get('device')}'")
    if not device_is_online(dev):
        raise RuntimeError(f"{plain_hid_text(getattr(dev, 'name', 'device'))} is offline")
    entry = {
        "name": name,
        "deviceId": device_id(dev),
        "deviceName": plain_hid_text(str(getattr(dev, "name", "") or "")),
        "kind": str(getattr(dev, "kind", "") or kind_from_name(str(getattr(dev, "name", "") or ""))),
        "settings": snapshot_settings(mods, dev),
    }
    data = load_profiles()
    next_profiles = [item for item in data["profiles"] if str(item.get("name") or "") != name]
    next_profiles.append(entry)
    data["profiles"] = next_profiles
    write_profiles(data)


def profile_delete(cmd: dict) -> None:
    name = sanitize_profile_name(cmd.get("name"))
    data = load_profiles()
    data["profiles"] = [item for item in data["profiles"] if str(item.get("name") or "") != name]
    write_profiles(data)


def profile_apply(mods, opened, cmd: dict) -> None:
    name = sanitize_profile_name(cmd.get("name"))
    found = None
    for item in load_profiles().get("profiles") or []:
        if str(item.get("name") or "") == name:
            found = item
            break
    if not found:
        raise RuntimeError(f"no profile named '{name}'")
    devices = list(iter_devices(opened))
    dev = find_device(devices, str(cmd.get("device") or found.get("deviceId") or ""))
    if not dev:
        raise RuntimeError(f"no device matching '{cmd.get('device')}'")
    if not device_is_online(dev):
        raise RuntimeError(f"{plain_hid_text(getattr(dev, 'name', 'device'))} is offline")
    mods["configuration"].attach_to(dev)
    raw = list(getattr(dev, "settings", None) or [])
    if not any(item is not None for item in raw):
        try:
            mods["settings_templates"].check_feature_settings(dev, raw)
        except Exception:
            pass
    for row in found.get("settings") or []:
        setting_name = str(row.get("name") or "")
        if not setting_name or setting_name in PROFILE_SKIP:
            continue
        setting = find_setting(dev, setting_name)
        if setting is None:
            continue
        key = row.get("key")
        apply_setting(setting, None if key in ("", None) else key, row.get("value"))


def apply_cmd(mods, opened, cmd: dict) -> None:
    if not isinstance(cmd, dict):
        return
    op = str(cmd.get("op") or "")
    if op == "refresh":
        return
    if op == "profile-save":
        profile_save(mods, opened, cmd)
        return
    if op == "profile-apply":
        profile_apply(mods, opened, cmd)
        return
    if op == "profile-delete":
        profile_delete(cmd)
        return
    if op != "set":
        return
    devices = list(iter_devices(opened))
    dev = find_device(devices, str(cmd.get("device") or ""))
    if not dev:
        raise RuntimeError(f"no device matching '{cmd.get('device')}'")
    if not device_is_online(dev):
        raise RuntimeError(f"{plain_hid_text(getattr(dev, 'name', 'device'))} is offline")
    mods["configuration"].attach_to(dev)
    raw = list(getattr(dev, "settings", None) or [])
    if not any(item is not None for item in raw):
        try:
            mods["settings_templates"].check_feature_settings(dev, raw)
        except Exception:
            pass
    setting = find_setting(dev, str(cmd.get("setting") or ""))
    if setting is None:
        raise RuntimeError(f"no setting '{cmd.get('setting')}'")
    key = cmd.get("key")
    value = cmd.get("value")
    apply_setting(setting, None if key in ("", None) else key, value)


def write_cmd_command(argv: list[str]) -> None:
    raw = argv[0] if argv else sys.stdin.read()
    if not str(raw).strip():
        fail("missing command json")
    try:
        cmd = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"invalid command json: {exc}")
    if not isinstance(cmd, dict):
        fail("command json must be an object")
    path = runtime_dir() / "cmd.json"
    payload = json.dumps(cmd, ensure_ascii=False, default=str) + "\n"
    try:
        path.unlink()
    except OSError:
        pass
    _create_exclusive(path, payload.encode("utf-8"))
    emit({"ok": True, "path": str(path)})


def runtime_dir_command() -> None:
    sys.stdout.write(str(runtime_dir()) + "\n")
    raise SystemExit(0)


def cleanup_command() -> None:
    paths = runtime_dir()
    lock = None
    for _ in range(20):
        lock = acquire_lock(blocking=False)
        if lock is not None:
            break
        time.sleep(0.05)
    if lock is None:
        emit({"ok": True, "cleaned": False, "message": "helper still running"})
    for name in ("cmd.json",):
        try:
            (paths / name).unlink()
        except OSError:
            pass
    try:
        lock_path = paths / "mxctl.lock"
        lock.close()
        lock_path.unlink()
    except OSError:
        pass
    try:
        paths.rmdir()
    except OSError:
        pass
    emit({"ok": True, "cleaned": True})


def _read_cmd(cmd_path: Path) -> dict | None:
    if not cmd_path.exists():
        return None
    cmd = None
    for attempt in range(2):
        try:
            cmd = json.loads(cmd_path.read_text(encoding="utf-8"))
            break
        except Exception:
            if attempt == 0:
                time.sleep(0.02)
    try:
        cmd_path.unlink()
    except OSError:
        pass
    if not isinstance(cmd, dict):
        return None
    return cmd


def serve_command() -> int:
    paths = runtime_dir()
    status_path = paths / "status.json"
    cmd_path = paths / "cmd.json"
    lock = acquire_lock(blocking=False)
    if lock is None:
        return EXIT_PEER_SERVING
    last_text = [""]
    runtime_fd = open_inotify(paths, IN_RUNTIME_MASK)
    hidraw_root = Path("/sys/class/hidraw")
    hid_fd = open_inotify(hidraw_root, IN_HIDRAW_MASK) if hidraw_root.is_dir() else None
    idle_timeout = IDLE_TIMEOUT_SEC if hid_fd is not None else TOPOLOGY_FALLBACK_SEC

    def publish(payload: dict) -> None:
        payload = dict(payload)
        payload["profiles"] = load_profiles().get("profiles") or []
        write_status(status_path, payload, last_text)

    hid_devices, adapters = scan_hidraw()
    topology = hidraw_topology()
    starting = discover_payload()
    starting["serving"] = True
    starting["progress"] = progress_payload(0, max(len(hid_devices), 1), "Starting", "open")
    publish(starting)
    mods, _import_error = import_solaar()
    if mods is None:
        publish(discover_payload())
        try:
            while True:
                _read_cmd(cmd_path)
                next_topology = hidraw_topology()
                if next_topology != topology:
                    topology = next_topology
                    publish(discover_payload())
                wait_for_event([runtime_fd, hid_fd], idle_timeout)
        except KeyboardInterrupt:
            return 0
        finally:
            close_inotify(runtime_fd, hid_fd)
            if lock:
                lock.close()
        return 0

    starting["progress"] = progress_payload(0, max(len(hid_devices), 1), "Opening devices", "open")
    publish(starting)
    opened, permission_error = open_devices(mods)
    last_error = ""
    try:
        # Keep hidraw open for the session. Closing it rebinds the Bluetooth
        # mouse. Publish after each device so the mouse settings paint before
        # the keyboard HID++ round-trips finish.
        payload = collect_status(
            mods,
            opened,
            hid_devices,
            adapters,
            permission_error,
            full=True,
            on_partial=publish,
        )
        payload["lastError"] = last_error
        publish(payload)
        while True:
            cmd = _read_cmd(cmd_path)
            if cmd is None:
                wait_for_event([runtime_fd, hid_fd], idle_timeout)
                cmd = _read_cmd(cmd_path)
            next_topology = hidraw_topology()
            topology_changed = next_topology != topology
            if cmd is None and not topology_changed:
                continue
            try:
                if cmd is not None:
                    op = str(cmd.get("op") or "")
                    if op == "reopen" or topology_changed:
                        opened, permission_error = add_new_devices(mods, opened)
                    if op == "set":
                        apply_cmd(mods, opened, cmd)
                    last_error = ""
                elif topology_changed:
                    opened, permission_error = add_new_devices(mods, opened)
                    last_error = ""
                need_full = cmd is None or str(cmd.get("op") or "") in {"set", "reopen", "profile-apply"} or topology_changed
                hid_devices, adapters = scan_hidraw()
                if need_full and cmd is not None and str(cmd.get("op") or "") == "set":
                    payload = refresh_one_device(
                        mods,
                        opened,
                        hid_devices,
                        adapters,
                        permission_error,
                        str(cmd.get("device") or ""),
                        payload,
                        last_error,
                    )
                elif need_full:
                    payload = collect_status(mods, opened, hid_devices, adapters, permission_error, full=True)
                else:
                    payload["adapters"] = adapters
                topology = next_topology
            except Exception as exc:
                last_error = plain_hid_text(str(exc))
            payload["lastError"] = last_error
            publish(payload)
    except KeyboardInterrupt:
        pass
    finally:
        close_inotify(runtime_fd, hid_fd)
        close_all(mods)
        if lock:
            lock.close()
    return 0


def main() -> None:
    argv = sys.argv[1:]
    action = argv[0] if argv else "status"
    if action == "discover":
        emit(discover_payload())
    if action == "cleanup":
        cleanup_command()
    if action == "write-cmd":
        write_cmd_command(argv[1:])
    if action == "runtime-dir":
        runtime_dir_command()
    if action == "serve":
        raise SystemExit(serve_command())
    if action in ("status", "show", "list"):
        status_command()
    if action == "set":
        set_command(argv[1:])
    fail(f"unknown command '{action}'")


if __name__ == "__main__":
    main()
