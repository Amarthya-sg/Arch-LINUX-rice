# Dail Launcher

A dial launcher: a radial quick-launcher wheel for Wayland, built with Quickshell (QtQuick / QML).
---

## Preview

![Dail Launcher preview](../Preview/DailLauncher/Preview.png)

> 🎬 **[Watch demo video](../Preview/DailLauncher/preview.mp4)**

---

## What Is This?

Dail Launcher is a fullscreen Wayland overlay that renders a donut-segment radial wheel. Each slice maps to a shell command — hover or navigate to a slice and click/press Enter to launch an app, run a script, or trigger any system action. The wheel closes itself immediately after execution.

Dail Launcher is a fullscreen Wayland overlay that renders a donut-segment radial wheel. Each slice maps to a shell command — hover or navigate to a slice and click/press Enter to launch an app, run a script, or trigger any system action. The wheel closes itself immediately after execution.

New in this version over the original Round Launcher:
- **Open/close animations** — springy pop-in (OutBack easing) and a fast shrink-out on close/Esc
- **Daemon mode** — run as a persistent background process; the wheel hides instead of quitting, so it reopens instantly on the next hotkey press
- **Expanded layout config** — every typography, spacing, animation, and glow value is now tunable from `rl_layout.json` without touching the QML
- **Smarter badge text** — two-word names get two initials (e.g. "SCREEN SHOT" → "SS"); single-character glyphs are handled safely for non-ASCII/emoji

---

## Requirements

| Dependency | Purpose |
| :--- | :--- |
| [Quickshell](https://quickshell.outfoxxed.me/) | QML shell runtime (`qs` binary) |
| A Wayland compositor | e.g. Hyprland, Niri, sway |
| Qt 6 with QtQuick, QtQuick.Shapes, QtQuick.Effects | Bundled with Quickshell |
| A Nerd Font *(optional)* | For glyph icons — e.g. `ttf-firacode-nerd`, `ttf-jetbrains-mono-nerd` |

---

## File Structure

```
DailLauncher/
├── README.md              ← this file
├── round launcher.qml     ← the entire launcher (single-file app)
├── rl_theme.css           ← color theme + effects (hot-reloaded)
└── rl_layout.json         ← cells + geometry (hot-reloaded)
```

---

## Usage

Run with `qs` from inside the `DailLauncher/` directory:

```bash
# Default — uses rl_theme.css and rl_layout.json next to the file
qs -p "round launcher.qml"
```

### Override theme and layout at launch

Both files can be swapped without editing the QML. Flag args take priority over env vars:

```bash
# Via flags
qs -p "round launcher.qml" -- --theme /path/to/theme.css --layout /path/to/layout.json

# Via environment variables
THEME_PATH=/path/to/theme.css LAYOUT_PATH=/path/to/layout.json qs -p "round launcher.qml"
```

### Daemon mode

In daemon mode the Quickshell process stays resident between invocations. The wheel hides on close instead of quitting, so it reopens instantly on the next hotkey press without respawning.

```bash
# Via flag
qs -p "round launcher.qml" -- --daemon

# Via environment variable
DAEMON_MODE=1 qs -p "round launcher.qml"
```

When using daemon mode, bind the hotkey to a command that signals the existing instance to show itself (e.g. via `hyprctl dispatch exec` pointing at the same `qs` invocation — Quickshell will reuse the running instance).

### Bind to a hotkey (Hyprland — Lua config)

```lua
-- One-shot mode (default): spawns a fresh process each press
hl.bind("SUPER + Y", hl.dsp.exec_cmd(
    'qs -p "/home/<user>/DailLauncher/round launcher.qml"'
), {
    description = "[Custom] dail launcher",
    locked = true,
})

-- With explicit theme + layout overrides
hl.bind("SUPER + Y", hl.dsp.exec_cmd(
    'THEME_PATH="/home/<user>/DailLauncher/rl_theme.css" ' ..
    'LAYOUT_PATH="/home/<user>/DailLauncher/rl_layout.json" ' ..
    'qs -p "/home/<user>/DailLauncher/round launcher.qml"'
), {
    description = "[Custom] dail launcher",
    locked = true,
})
```

**Notes:**
- `locked = true` — binding fires even on a locked screen. Remove if you don't want that.
- `..` is Lua string concatenation. Each fragment is joined into one shell command.
- `THEME_PATH` / `LAYOUT_PATH` let you bind multiple keys to the same QML file with different configs — e.g. one wheel for apps, one for system controls.

---

## Controls

| Input | Action |
| :--- | :--- |
| Mouse move | Hover highlights the slice under the cursor |
| Left click | Activates the hovered slice (runs script, closes wheel) |
| ← / → | Step one slice left or right |
| ↑ / ↓ | Jump to the diametrically opposite slice |
| 1 – 9, 0 | Jump directly to slice 1–10 by index |
| Enter / Return | Activate the currently selected slice |
| Esc | Close the wheel without running anything |

---

## Configuring the Layout (`rl_layout.json`)

The layout file controls wheel geometry, typography, spacing, animations, and the cells. Every key except `cells` is optional — omit any and the built-in default is used.

### Geometry

| Key | Default | Description |
| :--- | :--- | :--- |
| `outerR` | `260` | Outer radius of the ring in logical pixels (before `--scale`). |
| `innerRRatio` | `0.66` | Inner radius as a fraction of `outerR`. Lower = thicker band. |
| `gapDeg` | `2.4` | Gap between slices in degrees. `0` = no gap. |
| `iconGlyphPx` | `22` | Font size for glyph icons and the fallback letter badge. |
| `iconBadgeScale` | `1.9` | Badge circle diameter = `iconGlyphPx × iconBadgeScale`. |
| `popOutPx` | `30` | How far the active slice's outer edge pops outward (px). |
| `hoverScale` | `1.35` | Scale applied to the icon+label inside the active slice. |

### Typography & Spacing

| Key | Default | Description |
| :--- | :--- | :--- |
| `labelFontPx` | `11` | Font size for the cell name label inside each slice. |
| `labelLetterSpacing` | `0.4` | Letter spacing for slice labels (px). |
| `centerNameFontPx` | `18` | Font size for the name shown in the center hub card. |
| `hintFontPx` | `10` | Font size for the idle hint text. |
| `runHintFontPx` | `9` | Font size for the "press Enter to run" hint. |
| `hintLetterSpacing` | `1` | Letter spacing for hint text. |
| `badgeSpacing` | `2` | Gap between icon badge and label text inside a slice. |
| `centerSpacing` | `6` | Gap between elements inside the center card. |
| `iconMargin` | `4` | Padding inside slice icon badge circles. |
| `centerIconMargin` | `6` | Padding inside the center card icon badge. |

### Borders & Hit Area

| Key | Default | Description |
| :--- | :--- | :--- |
| `badgeBorderWidth` | `1` | Border width of icon badge circles. |
| `ringBorderWidth` | `2` | Border width of the center hub ring. |
| `backgroundBorderWidth` | `18` | Width of the soft drop-shadow halo outside the wheel. |
| `backgroundPadding` | `24` | Extra radius of the background shadow circle beyond `outerR`. |
| `hitAreaPadding` | `20` | Extra radius beyond `outerR` that still counts as "on the wheel" for mouse hover. |

### Glow / Active Outline

| Key | Default | Description |
| :--- | :--- | :--- |
| `glowStrokeWidth` | `2.4` | Stroke width of the highlight outline on the active slice. |
| `glowInset` | `1.2` | How far inward from the slice edge the glow outline is offset. |

### Center Card

| Key | Default | Description |
| :--- | :--- | :--- |
| `centerIconScale` | `1.8` | Scale multiplier for the center card icon badge (image/svg). |
| `centerGlyphScale` | `1.6` | Same as `centerIconScale` but for glyph/letter fallback. |
| `centerCardWidthRatio` | `1.7` | Center card width as a multiple of the inner ring diameter. |

### Animations

| Key | Default | Description |
| :--- | :--- | :--- |
| `popAnimDuration` | `180` | Duration (ms) of the slice pop-out and icon scale-up. |
| `fadeAnimDuration` | `150` | Duration (ms) of the non-active slice dim fade. |
| `glowAnimDuration` | `120` | Duration (ms) of the glow outline fade-in/out. |
| `popOvershoot` | `2.5` | OutBack easing overshoot for pop/scale animations. Higher = more springy. |
| `blurMaxVal` | `64` | Max raw-pixel blur value that maps to MultiEffect's `blur=1.0`. |

### Cell fields

```json
{
  "name":   "TERMINAL",
  "icon":   "\uf120",
  "script": "kitty"
}
```

| Field | Description |
| :--- | :--- |
| `name` | Label shown in the slice and center card. All-caps short words work best. |
| `icon` | Absolute path to a PNG/SVG **or** a Nerd Font Unicode glyph (e.g. `"\uf120"`). Leave `""` for a plain first-letter badge. |
| `script` | Shell command run via `/bin/sh -c` on activation. Leave `""` to make the cell inert. |

The wheel divides 360° evenly across however many cells you provide. 6–12 is practical. Number-key shortcuts map in order: `1` → index 0, `2` → index 1, …, `0` → index 9.

### Example cells

```json
{ "name": "TERMINAL",   "icon": "\uf120", "script": "kitty" },
{ "name": "BROWSER",    "icon": "\uf269", "script": "firefox" },
{ "name": "FILES",      "icon": "\uf07b", "script": "nautilus" },
{ "name": "MUSIC",      "icon": "\uf001", "script": "spotify" },
{ "name": "LOCK",       "icon": "\uf023", "script": "hyprlock" },
{ "name": "SCREENSHOT", "icon": "\uf03e", "script": "~/.config/scripts/screenshot.sh" },
{ "name": "VOLUME",     "icon": "\uf028", "script": "~/.config/scripts/rofi-media" },
{ "name": "SETTINGS",   "icon": "\uf013", "script": "hyprctl dispatch exec [float] nwg-look" }
```

---

## Configuring the Theme (`rl_theme.css`)

The theme file uses CSS custom-property syntax. Only `:root { --var: value; }` declarations are parsed — everything else (comments, other selectors) is ignored.

> **Color format:** Qt/QML uses `#AARRGGBB` (alpha **first**), not the web's `#RRGGBBAA` (alpha last). Always use the 8-digit form when you need transparency.
>
> Example: web `#ff000080` (red 50%) → Qt `#80ff0000`

### Color variables

| Variable | Description |
| :--- | :--- |
| `--color-cream` | Primary text and icon glow color. |
| `--color-red` | Active-slice highlight outline. Any accent color works here. |
| `--color-ink` | Inactive slice fill — dominant background of the ring. |
| `--color-slice-active-fill` | Active (selected/hovered) slice fill. |
| `--color-slice-stroke` | Border between slices. Supports transparency. |
| `--color-text-secondary` | Secondary text in the center card. |
| `--color-hint` | Hint text shown when nothing is selected. |
| `--color-icon-bg` | Background badge fill behind each icon. |
| `--color-ring-border` | Border of the center hub ring and icon badges. |
| `--color-ring-fill` | Fill of the center hub ring. |

### Effect variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `--scale` | `1.0` | Global size multiplier for the entire wheel. |
| `--opacity` | `1.0` | Overall wheel opacity. |
| `--blur` | `0` | Frosted-glass blur on slice fills (0–64 px). |
| `--dimness` | `0.45` | Opacity of non-active slices when something is selected. |
| `--opacity-center` | `1.0` | Center hub ring fill transparency. |
| `--opacity-slice` | `1.0` | Slice fill transparency (all slices). |
| `--opacity-background` | `1.0` | Drop-shadow halo behind the ring. |

### Default theme (Nordic Teal & Warm Amber)

```css
:root {
  --color-cream:              #f4ebd9;
  --color-red:                #e69875;
  --color-ink:                #1e2326;
  --color-slice-active-fill:  #2d353b;
  --color-slice-stroke:       #80a7c080;
  --color-text-secondary:     #83c092;
  --color-hint:               #859289;
  --color-icon-bg:            #db272e33;
  --color-ring-border:        #7fbbb3;
  --color-ring-fill:          #7fbbb3;

  --scale:   1.0;
  --opacity: 1.0;
  --blur:    0;
  --dimness: 0.45;

  --opacity-center:      1.0;
  --opacity-slice:       1.0;
  --opacity-background:  1.0;
}
```

### Quick tips

- **Dark theme:** dark `--color-ink`, dark `--color-ring-fill`, light `--color-cream`.
- **Glass/frosted look:** set `--blur 8–20`, lower `--opacity-slice` to ~`0.7`, keep `--opacity-center` around `0.85`.
- **Minimal/borderless:** set `--color-slice-stroke` to `#00000000` and `--opacity-background` to `0`.

---

## Hot-Reload

Both `rl_theme.css` and `rl_layout.json` are watched at runtime. Save either file and the wheel updates instantly — no relaunch needed. This makes live theming and layout tuning frictionless.

---

## How It Works (Technical)

- **Window** — `PanelWindow` with `WlrLayershell` at `Overlay` layer, fullscreen transparent canvas. `WlrKeyboardFocus.Exclusive` grabs all keyboard input while the wheel is up.
- **Input mask** — Only the wheel's circular footprint is registered as interactive. Everything outside it click-through passes to whatever is behind.
- **Rendering** — Each slice is a `QtQuick.Shapes` donut segment built from two `PathArc` + two `PathLine` paths. Angle math is done manually from center.
- **Hit detection** — A single `MouseArea` over the whole ring computes the hovered slice from the pointer's angle and radial distance from center. No per-shape hit testing.
- **Open/close animation** — A single `entranceProgress` property (0→1) drives both scale and opacity together via `openAnim` (OutBack easing, 220 ms) and `closeAnim` (InCubic, 140 ms). The wheel only actually quits/hides after `closeAnim` finishes.
- **Daemon mode** — `window.finishClose()` calls `window.visible = false` instead of `Qt.quit()` when `--daemon` is set, keeping the process alive between invocations.
- **Activation** — `Quickshell.execDetached(["/bin/sh", "-c", script])` launches the command fully detached, then `beginClose()` plays the exit animation before quitting/hiding.
- **Theme parsing** — Hand-rolled regex reader extracts `--name: value;` pairs from `:root { }` into a JS object. All color/effect bindings re-evaluate automatically on reassignment.
- **Layout parsing** — `JSON.parse()` with per-key fallbacks from a single `layoutDefaults` object — one source of truth so defaults can never drift between the parser and the properties.
