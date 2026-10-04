# EssentialBar

A Hyprland status bar and control center built with [Quickshell](https://quickshell.outfoxxed.me/) (QML). A compact top-bar pill sits permanently on screen; clicking it opens a full control panel with six tabs covering Wi-Fi, Bluetooth, audio, display, notifications, and system stats.

---

## Preview

![EssentialBar preview](../Preview/EssentialBar/Preview.png)

> 🎬 **[Watch demo video](../Preview/EssentialBar/Preview.mp4)**

---

## What Is This?

EssentialBar is a self-contained Wayland shell component that replaces a traditional status bar with a dynamic island-style pill. The pill shows live workspace indicators, battery, Wi-Fi, Bluetooth, volume, DND, and notification previews — all in a single centered capsule at the top of the screen.

Clicking the pill (or any of its status icons) opens a 404×672 rounded control panel anchored below it. The panel uses a `StackLayout` with six tabs so only the active page is in the viewport at any time. Every service is a QML singleton that polls only while the panel is open, keeping idle CPU usage minimal.

---

## File Structure

```
EssentialBar/
├── shell.qml                  ← root scope: bar window, clock popup, workspace/client polling
├── main.qml                   ← alternate standalone UI; also supports inline pairing prompts
├── style.css                  ← design token source of truth (hot-reloaded)
├── run-lean.sh                ← launch script with memory/rendering optimizations
├── qmldir
│
├── core/
│   ├── Theme.qml              ← CSS token reader + all typed theme properties
│   ├── ShellState.qml         ← global panel open/close state + view routing
│   ├── parse_css_tokens.py    ← Python CSS → JSON token parser
│   └── gen_icons.py           ← SVG icon color-variant generator
│
├── services/
│   ├── AudioService.qml       ← PipeWire/pactl volume, mute, device routing, balance
│   ├── BluetoothService.qml   ← BlueZ adapter, device list, pair/connect/forget
│   ├── BrightnessService.qml  ← brightnessctl read/write
│   ├── CaffeineService.qml    ← systemd-inhibit keep-awake toggle
│   ├── LocationService.qml    ← location toggle
│   ├── LockKeysService.qml    ← Caps/Num lock state
│   ├── MediaService.qml       ← MPRIS player, position interpolation
│   ├── NetworkService.qml     ← NetworkManager Wi-Fi scan/connect/forget/details
│   ├── bluetooth_agent.py     ← app-scoped BlueZ agent; sends pairing prompts to the panel
│   ├── NightLightService.qml  ← hyprsunset IPC temperature control
│   ├── NotificationService.qml← Quickshell notification server, DND, grouping
│   └── SystemService.qml      ← CPU/GPU/RAM/battery/fan stats + power profiles
│
├── components/
│   ├── BluetoothPairPrompt.qml← in-panel BlueZ confirmation/PIN prompt
│   ├── SvgIcon.qml            ← bundled Lucide SVG icon renderer
│   ├── StyledButton.qml
│   ├── ToggleSwitch.qml
│   ├── LevelSlider.qml
│   ├── LockBadge.qml
│   ├── Gauge.qml
│   ├── ChannelBalance.qml
│   └── UnifiedPill.qml        ← the top-bar capsule
│
├── panels/
│   ├── ControlPanel.qml       ← six-tab control center panel
│   └── NotificationPanel.qml
│
└── icons/                     ← generated Lucide SVG variants (one per color tone)
```

---

## Requirements

| Dependency | Purpose |
| :--- | :--- |
| [Quickshell](https://quickshell.outfoxxed.me/) ≥ 0.3.1 | QML shell runtime |
| Hyprland | Compositor (IPC + layer-shell) |
| Qt 6 + QtQuick | Bundled with Quickshell |
| Python 3 + `dbus-next` | CSS token parser/icon generator and in-panel BlueZ pairing agent |
| NetworkManager + `nmcli` | Wi-Fi scanning, connecting, saved-profile lookup |
| BlueZ | Bluetooth adapter and device management |
| PipeWire + WirePlumber + `pactl` | Audio volume, device routing, balance |
| `brightnessctl` | Display brightness control |
| `hyprsunset` + `hyprctl` | Night Light (color temperature) |
| `powerprofilesctl` | Power profile switching (power-saver / balanced / performance) |
| `systemd-inhibit` | Caffeine / keep-awake toggle |
| `rfkill` *(optional)* | Soft-block recovery when powering Bluetooth on |
| `wlogout` or HyDE logout scripts *(optional)* | Power menu action |
| HyDE `system.update.py` *(optional)* | Package update status and one-click update |
| A UI sans-serif font | Default: Inter |

---

## Running

### Standard launch

```bash
cd /path/to/EssentialBar
quickshell -p ./shell.qml
```

### Memory-optimized launch (recommended)

```bash
cd /path/to/EssentialBar
./run-lean.sh
```

`run-lean.sh` sets `MALLOC_ARENA_MAX=2`, `MALLOC_TRIM_THRESHOLD_=131072`, and `QT_QUICK_CONTROLS_STYLE=Basic` to reduce idle RAM. It also regenerates the icon variants if `style.css` or `icons-src/` is newer than `icons/`. Set `LEAN_SOFTWARE=1` to additionally use Qt's software renderer (skips loading the GPU driver stack entirely — biggest RAM saving, at the cost of GPU compositing).

With all of these tunings applied, measured RSS (Pss) is approximately **110 MB** right after launch and settles at around **145 MB** after opening all panels at least once. Without the tunings (default Qt rendering + default glibc arenas) expect noticeably higher usage.

### Autostart with Hyprland

Add to your Hyprland config:

```
exec-once = /path/to/EssentialBar/run-lean.sh
```

Or as a systemd user service:

```ini
[Unit]
Description=EssentialBar
After=graphical-session.target

[Service]
ExecStart=/path/to/EssentialBar/run-lean.sh
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

---

## The Bar Pill

The `UnifiedPill` capsule sits centered at the top of the screen. It is a single `PanelWindow` with `WlrLayershell` at the `Top` layer and a 44 px exclusive zone so windows tile below it.

### What the pill shows

| Section | Content |
| :--- | :--- |
| Left | Workspace number dots (active highlighted), hamburger window-list button |
| Center | Live clock (h:mm AM/PM), notification preview takeover |
| Right | Status icon cluster: Wi-Fi, Bluetooth, volume, DND/bell, caffeine, battery %, power button, update badge |

### Interactions

| Action | Result |
| :--- | :--- |
| Click clock | Opens calendar + media popup |
| Click any status icon | Opens control panel on the matching tab |
| Click hamburger | Opens window list popup |
| Click workspace dot | Switches to that workspace |
| Click power icon | Launches power menu (`wlogout` or HyDE helper) |
| Click update badge | Runs system updater |
| Click outside (focus grab) | Closes any open popup |

### Notification takeover

Incoming notifications expand the pill itself — there is no separate corner popup. The pill shows the app name, summary, and up to four wrapped body lines for six seconds. Clicking the pill while a notification is showing opens the Alerts tab.

---

## Control Panel

The panel is a 404×672 rounded `Rectangle` anchored below the pill. It uses a `StackLayout` driven by `ShellState.activeView` so only the active tab is in the viewport.

### Tabs

| Tab | ID | What it does |
| :--- | :--- | :--- |
| Main | `main` | Quick-toggle tiles (Wi-Fi, Bluetooth, DND, Night Light, Caffeine, Location, Screencast) + now-playing card *(Screencast toggle is not tested)* |
| Wi-Fi | `wifi` | Network list with signal bars, connect/disconnect, password entry, saved-password reveal, network details |
| Bluetooth | `bt` | Adapter toggle, device list, pair/connect/disconnect/forget, auto-pair toggle |
| Sound | `sound` | Output/input volume sliders, stereo balance, device + profile dropdowns, mute toggles |
| System | `batt` | Battery health/energy/cycles, CPU model/clock/temp, GPU load/VRAM/temp/power, RAM/swap, fan RPM, power profile selector |
| Alerts | `alerts` | Notification history grouped by app and day, per-app mute, clear-all, action buttons |

### View routing

`ShellState` handles all navigation. Any component can call:

```qml
ShellState.open("wifi")    // open panel on Wi-Fi tab
ShellState.goTo("bt")      // navigate inside an already-open panel
ShellState.back()          // return to main tab
ShellState.close()         // close panel
```

---

## Services

All services are QML singletons registered via `qmldir`. They poll only while the control panel is open (`ShellState.popupOpen`) and fall back to a slow safety-net timer when it is closed.

### AudioService

Backed by `Quickshell.Services.Pipewire` for reactive volume/mute and `pactl` for device enumeration and routing.

- Output and input volume with 100 ms debounce before writing to `pactl`
- Stereo left/right balance — reads `front-left`/`front-right` channel percentages from `pactl list sinks`, computes master + pan, writes back per-channel percentages
- Mono devices show balance as unavailable
- Output and input device dropdowns enumerate real PipeWire sinks/sources with their available ports; monitor sources are filtered from the microphone list
- Card profile switching — activates the hardware port, moves active playback/recording streams, verifies the default sink/source, logs mute and volume
- Automatic speaker fallback — if the active headphone jack reports unavailable, switches to a Speaker profile automatically
- Mute uses the tracked PipeWire node when ready; falls back to `pactl` during WirePlumber rebinding

### BluetoothService

Backed by `Quickshell.Bluetooth`.

- Adapter power on/off with `rfkill` soft-block recovery
- Device list filtered to paired, connected, or named devices; sorted connected-first
- Pairing uses the app-scoped BlueZ agent; after the panel confirms the request, EssentialBar trusts and connects the device
- Bounded reconnect retry — up to 3 attempts at 4 s intervals before giving up with an error message
- Opt-in auto-pair for audio and input devices (skips randomized LE addresses)
- Forget via `bluetoothctl disconnect && bluetoothctl remove` (avoids "Resource Not Ready" on live links)
- Discovery stops before connect to prevent link drops on some controllers
- Numeric passkey confirmation is shown inline in the Bluetooth view with Confirm/Deny controls instead of a separate desktop pairing dialog. The agent is app-scoped; EssentialBar does not request global default-agent ownership.
- The pairing helper requires the Python `dbus-next` package. On Arch Linux, install it with `sudo pacman -S python-dbus-next` (do not use pip against Arch's externally managed system Python). On other distributions, prefer the OS package; use `python3 -m pip install --user -r services/requirements.txt` only where user-site installs are supported.

### NetworkService

Backed by `Quickshell.Networking` (NetworkManager).

- Wi-Fi toggle, scan start/stop (scanner enabled only while the Wi-Fi view is open)
- Network list with signal percentage, security type, known/saved indicator
- Connect flow: profile lookup by SSID → reuse existing profile or create new one → `nmcli --wait 30 connection up` → verify activation → persist password
- Failed secured joins keep the password field open with an inline authentication warning
- Saved-password reveal via `nmcli --show-secrets` (local only, never sent anywhere)
- Disconnect and forget (by UUID lookup first, then by profile name)
- Details view: IP address, gateway, DNS, band/channel, link rate, BSSID, security

### SystemService

Reads hardware stats from `/proc` and `/sys` via a single shell script, plus `powerprofilesctl`.

| Stat | Source |
| :--- | :--- |
| CPU load % | `/proc/stat` delta between polls |
| CPU model, threads | `/proc/cpuinfo`, `nproc` |
| CPU clock (avg + max) | `/sys/devices/system/cpu/*/cpufreq/scaling_cur_freq` |
| CPU temperature | `/sys/class/hwmon/*/temp1_input` (k10temp / zenpower / coretemp) |
| RAM / swap | `/proc/meminfo` |
| Storage | `df -P /` |
| Battery capacity, status, energy, health, cycles, voltage, technology | `/sys/class/power_supply/BAT*` |
| GPU load, VRAM, temperature, power, fan, clock | `/sys/class/drm/card*/device` + hwmon |
| Fan RPM | Board hwmon (non-amdgpu) |
| Power profile | `powerprofilesctl get` |

Suspended AMD GPUs are not polled — their `power/runtime_status` is checked first to avoid waking a discrete GPU with sensor reads.

Polls every 3 s while the panel is open; stops when closed.

### BrightnessService

Reads and writes display brightness via `brightnessctl -m`. Polls every 3 s while the panel is open.

### NightLightService

Controls color temperature via `hyprctl hyprsunset temperature <K>` and `hyprctl hyprsunset identity` (reset). Temperature range: 2500 K – 6500 K. Changes are debounced 180 ms. Detects availability by checking `command -v hyprsunset && command -v hyprctl` at startup.

### MediaService

Backed by `Quickshell.Services.Mpris`. Resolves the active player (playing → paused → first available). Position is interpolated locally using wall-clock time between MPRIS `positionChanged` events, so the progress bar stays smooth even with players that don't emit position ticks every second. Seeks are forwarded to `activePlayer.position`.

### NotificationService

Implements a `NotificationServer` (D-Bus `org.freedesktop.Notifications`).

- Notifications arrive in the pill as a 6-second takeover preview
- DND mode queues toasts but still stores notifications in history; flushing DND releases queued toasts
- Per-app mute — muted apps are dismissed immediately on arrival
- History grouped by app and by Today / Earlier
- Per-group expand/collapse, per-notification action buttons, clear-all and clear-app

### CaffeineService

Runs `systemd-inhibit --what=idle --who=EssentialBar --why=Caffeine --mode=block sleep infinity` as a background process. Killing the process releases the inhibit. Toggle via the caffeine tile on the main tab or the status icon in the pill.

---

## Theming (`style.css`)

`style.css` is the single source of truth for all visual tokens. `core/parse_css_tokens.py` parses it into a JSON object that `core/Theme.qml` applies to typed QML properties. The file is watched at runtime — save it and the bar updates live.

### How it works

The parser reads `--cc-*` custom properties from `:root { }` and converts them to camelCase keys (e.g. `--cc-surface-raised` → `surfaceRaised`). 8-digit hex colors are converted from CSS `#RRGGBBAA` order to Qt's `#AARRGGBB` order automatically.

New tokens are immediately available as `Theme.tokens.<camelCaseName>`. To add a new direct `Theme.<name>` property, declare it once in `core/Theme.qml`.

### Granular numeric tokens

Every hardcoded baseline value in the UI has a corresponding CSS override. The naming pattern is `--cc-<group>-<value>` where negative values use `neg` and decimals drop the dot:

```css
--cc-font-size-13: 13;        /* Theme.fontSize(13) */
--cc-spacing-10: 10;          /* Theme.spacingSize(10) */
--cc-radius-14: 14;           /* Theme.radiusSize(14) */
--cc-size-28: 28;             /* Theme.dimensionSize(28) */
--cc-margin-neg-3: -3;        /* Theme.marginSize(-3) */
--cc-opacity-0-14: 0.14;      /* Theme.opacityValue(0.14) */
--cc-letter-spacing-neg-1: -1;/* Theme.letterSpacingValue(-1) */
--cc-duration-200: 200;       /* Theme.duration(200) */
```

### Font

```css
--cc-font-family: "Inter";    /* any installed system font */
```

### Scroll rates

```css
--cc-scroll-title-rate: 45;   /* ms per pixel — lower = faster */
--cc-scroll-app-rate: 35;
```

### Status icon sizes

```css
--cc-status-icon-size: 18;
--cc-status-icon-button-size: 28;
```

### Color palette (default — warm near-black + red accent)

```css
:root {
  --cc-background:        #0f0d0e;
  --cc-surface:           #171415;
  --cc-surface-raised:    #211c1e;
  --cc-surface-hover:     #2d2629;
  --cc-outline:           #ffffff1a;
  --cc-text:              #f4eeee;
  --cc-text-muted:        #a09598;
  --cc-primary:           #e5334b;
  --cc-primary-strong:    #ff5a6e;
  --cc-success:           #34c17b;
  --cc-warning:           #e8ac3a;
  --cc-error:             #f0505f;
  --cc-island-bg:         #060505;
  --cc-island-accent:     #ee3a52;
  --cc-island-accent-strong: #ff8896;
  --cc-island-muted:      #b3a8ab;
  --cc-island-muted-dim:  #6a5f62;
  --cc-workspace-active:  #e8384f;
  --cc-workspace-inactive:#736869;
  --cc-battery-text:      #cfc6c8;
}
```

### SVG icon colors

Each icon has its own CSS variable so you can recolor individual icons without touching QML. The pattern is `--cc-icon-<name>` for panel icons and `--cc-icon-status-<name>` for pill status icons:

```css
--cc-icon-wifi:                #f1eaeb;
--cc-icon-bluetooth:           #ece5e6;
--cc-icon-volume-2:            #e6dedf;
--cc-icon-battery-charging:    #3ecb86;
--cc-icon-battery-low:         #f04a5b;
--cc-icon-moon:                #d3c6de;
--cc-icon-sun:                 #f0c35c;
/* ... and so on for every icon */
```

Run `python3 core/gen_icons.py` (or just use `run-lean.sh`) to regenerate the `icons/` variants after changing icon colors.

---

## How It Works (Technical)

### Bar window

`shell.qml` is a Quickshell `Scope` (not a window itself). It creates a `PanelWindow` (`bar`) with `WlrLayershell` at the `Top` layer and `exclusiveZone: 44`. The bar's `implicitHeight` grows when the notification takeover expands, but applications only reserve the 44 px zone.

`WlrKeyboardFocus.OnDemand` is requested while the control panel is open so the Wi-Fi password `TextField` receives keyboard events.

### Workspace and client polling

`shell.qml` runs a four-step `hyprctl` chain (`activewindow` → `activeworkspace` → `workspaces` → `clients`) triggered by Hyprland IPC events via `Connections { target: Hyprland }`. A 120 ms debounce timer coalesces rapid event bursts. A 30 s safety-net timer runs when the event chain is idle. Change detection (`_wsText` / `_clText` string comparison) prevents rebuilding the workspace/client model when nothing changed.

### Icon resolution

`guessIconName(cls)` implements a cascade: `DesktopEntries.byId` → substitution map → regex substitutions → exact name → lowercase → reverse-domain last segment → kebab-norm → `DesktopEntries.heuristicLookup` → fallback `application-x-executable`.

### Hyprland dispatch compatibility

`hyprDispatch(legacyArgs, luaExpr)` tries the legacy `hyprctl dispatch` form first. If it exits non-zero, it retries once with the Lua-style form, covering both old and new Hyprland config formats.

### Calendar popup

Created lazily (`LazyLoader`) only while the clock popup is open. Uses a `HyprlandFocusGrab` so clicking outside closes it. The popup width expands when a media panel is open alongside the calendar.

### Theme hot-reload

`core/Theme.qml` watches `style.css` with a `FileView`. On change it debounces 50 ms then runs `python3 core/parse_css_tokens.py style.css`. The parser outputs JSON; `applyCssTokens()` assigns it to `tokens`, which triggers all dependent property bindings to re-evaluate.

### Audio volume debounce

Volume slider changes set `pendingOutputVolume` / `pendingInputVolume` and restart a 100 ms `Timer`. When the timer fires, `flushOutputVolume()` / `flushInputVolume()` runs `pactl set-sink-volume @DEFAULT_SINK@ <args>`. If a `pactl` process is already running, the pending value is held and flushed on the next `onExited`. This serializes writes and avoids flooding `pactl` during fast slider drags.

---

## Acknowledgements

EssentialBar wouldn't exist in its current form without these two projects. I took inspiration from both, studied how they approached the problem, and kept only the parts that made sense for what I was building.

- **[Odyssey](https://github.com/sud0-L/odyssey)** — the control center architecture, singleton service registration via `qmldir`, `HyprlandFocusGrab` for popup dismissal, release-by-state instead of destroying windows, and the overall panel layout all trace back to Odyssey. It was the clearest reference I found for doing a full Quickshell control center properly.

- **[ChillPill Shell](https://github.com/LUCKYS1NGHH/ChillPill-Shell)** — the island-style pill concept, the unified capsule that holds workspaces + clock + status icons in one centered bar element, and the general aesthetic direction came from ChillPill. It showed me what a Quickshell bar could look and feel like.

Thanks to both authors for sharing their work openly.
