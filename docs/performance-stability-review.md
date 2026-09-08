# Performance and stability review

Reviewed 2026-09-07 against `bef2434`. This review fixes avoidable latency and recovery problems in the new action runtime. It does not certify hardware behavior or full Logi Options+ parity.

## Findings and fixes

| Finding | Change |
| --- | --- |
| Each single action launched three `hyprctl` processes: initial application lookup, focus verification, and dispatch. | Direct UNIX socket requests use Hyprland's existing command protocol. Focus verification and explicit target-window selection remain. |
| Every action waited 60 ms after its last step, reducing throughput for repeated clicks. | Wait only between sequence steps. Single shortcuts have no artificial sleep. |
| Reader and worker threads woke every 200 ms while idle. | Block on the input descriptor/queue. A wake pipe and queue sentinel interrupt shutdown immediately. |
| Listener errors restored HID++ settings from a background thread using the main thread's command handle. | Stop the workers and wake the helper. The main thread owns restoration and configuration writes. |
| Solaar's read-error path could close the listener descriptor before session cleanup closed it again. | Read the independent nonblocking descriptor directly and retain a single owner for closing it. Join workers before releasing resources. |
| Every settings write paused all action sessions. | Keep listeners running for ordinary setting changes. Profile save/apply pauses only the target device. |
| Failed sessions and crashed helpers could retry repeatedly without backoff. | Exponential retry delays, capped at 60 seconds. Session failures wake the helper and are restored before retry. Successful heartbeat verification resets session backoff. |
| Startup snapshot polling could continue indefinitely without a writable device. | Bound fallback polling to 150 ticks at 400 ms; keep file watching active. Stale snapshots do not reset the limit. |
| A live snapshot with no remaining devices could be discarded, preserving stale UI state. | Accept authoritative file snapshots on disconnect while still ignoring late discovery scans. |

Socket requests have a 350 ms deadline and a 256 KiB response limit. Dispatch failures are not automatically retried, preventing duplicate shortcut injection after an ambiguous response. The existing eight-item action queue and one-second stale-event cutoff remain.

## Measurements and verification

A read-only benchmark on this machine queried the current Hyprland instance 100 times through each transport. No shortcuts were sent and no device settings were changed.

| Transport | Median | 95th percentile |
| --- | ---: | ---: |
| Direct socket | 0.042 ms | 0.053 ms |
| `hyprctl -j activewindow` | 3.665 ms | 4.725 ms |

These numbers measure query transport overhead, not end-to-end button latency. They depend on machine load and compositor version. Regression tests separately verify that a one-step action performs no spacing wait and an N-step sequence waits N−1 times.

Validation includes the Python suite; Model.js checks; plugin manifest validation; QML parsing; and `python3 test/service_recovery.py`, an offscreen Quickshell integration test with a temporary runtime directory and a fake helper. The integration test measured restart gaps of 1.02, 2.02, and 4.03 seconds and checks disconnect handling, stale-cache handling, and the polling limit.

Action regressions cover chunked IPC replies, size limits, total response deadlines, cancellation during focus lookup, dispatch errors, repeated setup failures, target-only profile pauses, main-thread restoration, real threaded packet delivery using a pipe, and prompt/idempotent shutdown. Hardware APIs are mocked for these tests.

## Remaining validation

Before treating software actions as production-proven, exercise Bluetooth and receiver connections with repeated clicks, sequences, device sleep/wake, unplug/replug, graceful helper shutdown, and restoration after startup failure. Forced process death cannot run Python cleanup; nonpersistent hardware diversion can require reconnecting the device. Restoration also depends on successful HID++ replies.

Repeated modifier shortcuts need explicit testing on the installed compositor. Hyprland has [upstream reports of stuck modifier state in `sendshortcut`](https://github.com/hyprwm/Hyprland/discussions/14099), and this machine's Omarchy clipboard bindings contain a workaround using separate key-down/key-up dispatches. This review retains the plugin's existing window-targeted shortcut dispatcher; transport and lifecycle tests do not establish that the compositor issue is absent.

The socket path and command framing follow [Hyprland's IPC documentation](https://wiki.hypr.land/IPC/). No live peripheral configuration was changed during this review.
