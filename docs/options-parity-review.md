# MX Control review — September 7, 2026

MX Control is a useful Omarchy interface to Solaar's HID++ settings. It is not yet a replacement for Logi Options+. The discovery, shared service, command spool, hardware settings, and new software action runtime provide a foundation. Real-device validation and the cross-computer/automation workflows remain the largest gaps.

## Findings, in priority order

1. **Implemented; hardware validation pending: software actions.** The plugin now owns a HID++ notification listener and a Hyprland shortcut executor (`mxactions.py`). The settings editor supports click actions, four directional gestures, and sequences of up to eight shortcuts. Setup verifies temporary diversion flags, refuses controls already diverted to Solaar, and restores regular input on normal shutdown/removal. Synthetic packet and lifecycle tests cover these paths. Actual model/transport behavior is not yet verified.
2. **Implemented with limits: app-specific behavior.** Action assignments resolve an exact Hyprland app class, with a required All apps fallback. Each shortcut sequence is pinned to its initial target and stops when focus changes. The UI offers an open-app picker, a manual class field, and a shortcut recorder. This does not reproduce Options+’s application integrations, all Smart Actions steps, or cloud profiles. Compare [Logitech’s feature overview](https://www.logitech.com/en-us/software/logi-options-plus) and [button programming guide](https://hub.sync.logitech.com/options/post/programming-buttons-and-keys-in-options-ntwM6VsAEKhHACY).
3. **Medium, fixed: settings disappeared between dedicated and generic controls.** Pointer speed and report rate were marked as used without any editor. The generic renderer omitted `map_choice` and `multiple_toggle` despite the model returning them. Advanced now renders those controls, including keyed ranges, and supported variants fall through when their dedicated editor cannot handle them.
4. **Medium: profile compatibility and partial application need stronger handling.** The UI filters profiles only by device kind. `profile_apply()` skips missing setting names, but applies matching settings sequentially without preflighting values or rollback. A profile from a different mouse may partially apply before an unsupported choice fails. Profiles are also replaced by name globally, so saving the same name on a second device replaces the earlier entry. These backend behaviors remain unchanged.
5. **Medium: broad device and connection claims exceed the evidence.** `scan_hidraw()` filters device names, while receiver discovery and successful control depend on Solaar and the device's exposed features. Supporting a receiver transport does not prove every peripheral behind it works. Hardware coverage requires an explicit model/transport matrix and real-device tests.
6. **Medium, improved: the settings page obscured tasks and relied on guessed device graphics.** Replaced the single long page and schematic chassis with a responsive sidebar/tab layout, larger headings, themed cards, an action editor, expandable hardware controls, and clear empty states. Keyboard navigation uses normal focus traversal; Ctrl+R refreshes without treating letters in profile names as panel shortcuts.

## Coverage after this change

“Available” means there is an implementation for supported settings, not that every model has been hardware-tested.

| Capability | MX Control status |
| --- | --- |
| Battery and connection status | Available, with kernel/HID++/Bluetooth sources |
| DPI, wheel direction, SmartShift | Available when exposed by the device |
| Pointer speed, report rate, additional keyed settings | Available in Advanced when exposed |
| macOS-style pointer acceleration | Available per mouse through a runtime Hyprland/libinput custom curve; stored locally and in profiles |
| Hardware button/key remaps | Available; choices are limited to the hardware's action table |
| Keyboard Fn, lighting, platform, key disables | Partial; limited to settings and kinds the helper/UI support |
| Application keyboard shortcuts | Implemented with manual entry, recording, and presets; hardware validation pending |
| Launching apps / shell commands | Missing |
| Directional gestures | Click plus four directions using raw XY on supported controls; hardware validation pending |
| App-specific assignments | Exact Hyprland class matching with a required global fallback |
| Automatic hardware profiles | Missing |
| Smart Actions / macro editor | Partial: up to eight shortcut steps with fixed spacing; no delays, app-launch steps, or richer automation |
| Easy Switch | Per-device channel selection and naming; no coordinated mouse/keyboard switching |
| Flow | Missing: no network cursor switching, clipboard, or file transport |
| Local settings profiles | Available; manual snapshots with compatibility caveats above |
| Cloud backup and restoration | Missing |
| Firmware and receiver pairing management | Missing |
| Actions Ring, marketplace integration, haptics workflow | Missing as Options+ workflows; individual HID++ settings may appear in Advanced |
| Caps Lock / low-battery desktop notifications | Battery indication exists; no equivalent notification workflow |
| Webcams, lights, presenters, Creative Console | Outside the current MX mouse/keyboard implementation |

Logitech documents Flow and firmware settings in its [device setup guide](https://hub.sync.logitech.com/options/post/device-setup-in-options-ESnKTSDRb8xy7mL), cloud backup in its [application introduction](https://hub.sync.logitech.com/options/post/introduction-to-the-options-app-jOelKzSp2ph9leq), and current Actions Ring, haptics, enhanced Easy Switch, notifications, and supported device categories in its [Options+ overview](https://www.logitech.com/en-us/software/logi-options-plus). Smart Actions support multi-step automation, described in [Logitech's guide](https://hub.sync.logitech.com/options/post/using-smart-actions-in-options-FAU1yARC27jYpg0).

## Suggested implementation order

1. Validate real devices over Bluetooth and receivers: shortcut presses, gesture thresholds, app overrides, sleep/wake, reconnect, and normal/forced helper shutdown. Tune gesture behavior using observed hardware data.
2. Add profile compatibility checks and explicit reporting of partial failures, then profile import/export. Hardware snapshots remain separate from software action assignments.
3. Extend shortcut sequences into a richer automation editor with controlled delay and application steps; add compositor actions through a separate explicit action type.
4. Treat coordinated Easy Switch, Flow, firmware management, and broader device support as separate projects with their own acceptance tests.

The action implementation follows the installed Solaar `RawXYProcessing` packet format and temporary control-reporting APIs. Solaar documents HID++ diversion and Wayland limitations in its [rules documentation](https://pwr-solaar.github.io/Solaar/rules/). The executor uses the current [Hyprland Lua dispatch API](https://wiki.hypr.land/Configuring/Basics/Dispatchers/).

## Validation

All 72 Python tests, JavaScript model checks, Omarchy manifest validation, and QML parsing pass. New tests cover shortcut validation, app fallback, synthetic gesture packets, target-window checks, failed startup cleanup, existing diversion refusal, listener removal, and action-store rollback. The UI was rendered with the installed Omarchy components/theme and mock device data. Mock QML checks verified assignment payloads and that snapshot refreshes preserve drafts. No live application received shortcuts and no connected device settings were changed. The checkout was not installed into the live shell.
