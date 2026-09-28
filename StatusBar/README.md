# Hyprland Control Center

A standalone Quickshell control center built from the Odyssey architecture as a reference, without modifying the Odyssey checkout.

## Architecture

```text
shell.qml
  ├── top clock pill
  └── overlay popup + HyprlandFocusGrab

core/
  ├── Theme.qml
  └── ShellState.qml

services/
  ├── NetworkService.qml       Quickshell.Networking
  ├── BluetoothService.qml     bluetoothctl adapter
  ├── AudioService.qml         Quickshell.Services.Pipewire
  ├── BrightnessService.qml   brightnessctl adapter
  ├── NightLightService.qml    hyprsunset IPC
  ├── NotificationService.qml  Quickshell notification server
  └── SystemService.qml        lightweight system stats

components/
  ├── ToggleSwitch.qml
  └── LevelSlider.qml

style.css
  └── shared design tokens mirrored by core/Theme.qml

panels/
  └── ControlPanel.qml         six UI tabs
```

## Run

From a Hyprland session with Quickshell installed:

```sh
cd /path/to/sat-working
quickshell -p ./shell.qml
```

For normal use, add it to Hyprland startup or a user service.

## Dependencies

- Quickshell 0.3.1 or compatible
- Hyprland
- NetworkManager
- `nmcli`
- BlueZ
- `bluetoothctl` and Bash
- PipeWire / WirePlumber
- `pactl`
- `brightnessctl` for brightness
- `hyprsunset` and `hyprctl` for Night Light
- `powerprofilesctl` for power-profile controls
- `systemd-inhibit` for the caffeine action
- `wlogout` or the HyDE logout script for the power-menu action (optional)
- the HyDE `system.update.py` helper for package-update status/actions (optional)
- Nerd Font plus a UI sans-serif font

The UI reports unavailable hardware/backends where it can detect them; unsupported fan hardware is shown as unavailable rather than offering controls that only change the display.

## Full HTML prototype recreation

The QML recreation follows the attached Odyssey HTML prototype across the full
surface, not only the top island. It includes the four-workspace switcher,
live clock, portal/DND status cluster, quick-tray, animated black/orange island,
404×672 rounded panel, system-status header, now-playing card, six-tab layout,
Wi-Fi network expandos/details/password reveal, Bluetooth device cards, sound
sliders, display and Night Light controls, notification history actions, and
system battery/gauge/fan-availability/power-profile cards.

The caffeine action uses `systemd-inhibit` to keep the session awake until
toggled off. Hardware features that are unavailable on a host remain visually
present with an unavailable/placeholder state rather than breaking the layout.

## UI customization

The complete palette, spacing scale, radii, font stack, and control sizes are
defined in `style.css`. Because QtQuick does not apply web CSS files directly,
`core/Theme.qml` is the runtime bridge and mirrors those tokens for QML. Edit
both files when changing the visual system.

The Wi-Fi panel shows the network name prominently, requests keyboard focus for
password entry, includes a **Show/Hide** password action, and can retrieve a
saved NetworkManager Wi-Fi password locally on request. The secret is read via
`nmcli --show-secrets` into the running UI; it is not sent to an external
service. Treat the visible password as sensitive and hide it when finished.

The control panel uses a `StackLayout` driven by the selected tab index, so only
the active page occupies the viewport instead of coordinating opacity and
z-order across overlapping siblings. Each tab is a direct page in the stack;
its content starts at the top and scrolls within that page when it exceeds the
available height. The tab labels and control symbols use portable text glyphs
instead of depending on a Nerd Font for core UI readability.

## Odyssey reference

The source architecture was informed by `/home/ubuntu/odyssey`, especially:

- singleton service registration through per-folder `qmldir`
- Quickshell Networking and Bluetooth as reactive sources of truth
- layer-shell `OnDemand` focus
- same-window `HyprlandFocusGrab`
- release-by-state rather than destroying popup windows
- Hyprsunset IPC for Hyprland-compatible Night Light
