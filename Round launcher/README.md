# Round Launcher

An RDR2-inspired radial quick-launcher wheel for Wayland, built with [Quickshell](https://quickshell.outfoxxed.me/) (QtQuick / QML).

![Round Launcher preview](first_look.png)

---

## Overview

Round Launcher is a donut-segment radial wheel that sits as a fullscreen Wayland overlay. Each slice maps to a shell command — click a slice or navigate with the keyboard to launch an app, run a script, or trigger a system action. The wheel closes itself immediately after execution.

The design is inspired by the RDR2 weapon wheel: a ring of evenly-divided arc segments, a center hub card that shows the active item, and a pop-out + glow animation on hover/focus.

---

## Requirements

| Dependency | Purpose |
| :--- | :--- |
| [Quickshell](https://quickshell.outfoxxed.me/) | QML shell runtime (`qs` binary) |
| A Wayland compositor | e.g. Hyprland, Niri, sway |
| Qt 6 with QtQuick, QtQuick.Shapes, QtQuick.Effects | Comes bundled with Quickshell |
| A Nerd Font *(optional)* | For glyph icons in the layout — e.g. `ttf-firacode-nerd`, `ttf-jetbrains-mono-nerd` |

---

## File Structure

```
Round launcher/
├── README.md              ← this file
├── first_look.png         ← preview screenshot
├── round launcher.qml     ← the entire launcher (single-file app)
├── rl_theme.css           ← color theme + effects (hot-reloaded)
└── rl_layout.json         ← cells + geometry (hot-reloaded)
```

---

## Usage

Run with `qs` from inside the `Round launcher/` directory:

```bash
# Default — uses rl_theme.css and rl_layout.json
qs -p "round launcher.qml"
```

### Override theme and layout at launch

Both files can be swapped without editing the QML. Two methods — flag args take priority over env vars:

```bash
# Via flags
qs -p "round launcher.qml" -- --theme /path/to/theme.css --layout /path/to/layout.json

# Via environment variables
THEME_PATH=/path/to/theme.css LAYOUT_PATH=/path/to/layout.json qs -p "round launcher.qml"
```

### Bind to a hotkey (Hyprland — Lua config)

Hyprland's Lua config uses `hl.bind()` with `hl.dsp.exec_cmd()`. Pass the theme and layout as environment variables prepended to the command string, concatenated with `..`:

```lua
-- Default wheel (uses rl_theme.css + rl_layout.json)
hl.bind("SUPER + Y", hl.dsp.exec_cmd(
    'qs -p "/home/amarthya/DATABASE/ARCH LINUX rice/Round launcher/round launcher.qml"'
), {
    description = "[Custom] round launcher",
    locked = true,
})

-- With explicit theme + layout overrides
hl.bind("SUPER + Y", hl.dsp.exec_cmd(
    'THEME_PATH="/home/amarthya/DATABASE/ARCH LINUX rice/Round launcher/rl_theme.css" ' ..
    'LAYOUT_PATH="/home/amarthya/DATABASE/ARCH LINUX rice/Round launcher/rl_layout.json" ' ..
    'qs -p "/home/amarthya/DATABASE/ARCH LINUX rice/Round launcher/round launcher.qml"'
), {
    description = "[Custom] apps wheel",
    locked = true,
})
```

**Notes:**
- `locked = true` means the binding fires even on a locked screen — remove it if you don't want the wheel accessible from the lockscreen.
- The `..` operator is Lua string concatenation. Each line fragment is a separate string joined into one shell command.
- `THEME_PATH` and `LAYOUT_PATH` are shell env vars read by the QML at startup — they let you bind multiple keys to the same QML file with different themes/layouts, e.g. one wheel for apps, one for system controls.

---

## Controls

| Input | Action |
| :--- | :--- |
| **Mouse move** | Hover highlights the slice under the cursor |
| **Left click** | Activates the hovered slice (runs script, closes wheel) |
| **← / →** | Step one slice left or right |
| **↑ / ↓** | Jump to the diametrically opposite slice |
| **1 – 9, 0** | Jump directly to slice 1–10 by index |
| **Enter / Return** | Activate the currently selected slice |
| **Esc** | Close the wheel without running anything |

---

## Configuring the Layout (`rl_layout.json`)

The layout file controls the wheel geometry and defines the cells (slices). Every geometry key is optional — omit any and the built-in default is used. Only `cells` is required.

### Geometry keys

| Key | Default | Description |
| :--- | :--- | :--- |
| `outerR` | `260` | Outer radius of the ring in logical pixels (before `--scale`). |
| `innerRRatio` | `0.66` | Inner radius as a fraction of `outerR`. Lower = thicker band. |
| `gapDeg` | `2.4` | Gap between slices in degrees. `0` = no gap. |
| `iconGlyphPx` | `22` | Font size for glyph icons and the fallback letter badge. |
| `iconBadgeScale` | `1.9` | Badge circle diameter = `iconGlyphPx × iconBadgeScale`. |
| `popOutPx` | `30` | How far the active slice's outer edge pops outward (px). |
| `hoverScale` | `1.35` | Scale applied to the icon+label inside the active slice. |

There are also fine-tuning keys for typography, spacing, animations, and the center card — all documented in detail inside `rl_layout.json`.

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
| `name` | Label shown in the slice and the center card. All-caps short words work best. |
| `icon` | Absolute path to a PNG/SVG **or** a Nerd Font Unicode glyph (e.g. `"\uf120"`). Leave `""` for a plain first-letter badge. |
| `script` | Shell command run via `/bin/sh -c` on activation. Leave `""` to make the cell inert. |

The wheel divides 360° evenly across however many cells you provide — no fixed count. 6–12 is practical. Number-key shortcuts map to cells in order: `1` → index 0, `2` → index 1, …, `0` → index 9.

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

The theme file uses CSS custom-property syntax, but only `:root { --var: value; }` declarations are parsed — everything else (comments, other selectors) is ignored.

> **Color format:** Qt/QML uses `#AARRGGBB` (alpha **first**), not the web's `#RRGGBBAA` (alpha last). Always use the 8-digit form when you need transparency.

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

### Default theme values (Nordic Teal & Warm Amber)

```css
:root {
  --color-cream:              #f4ebd9;
  --color-red:                #e69875;
  --color-ink:                #1e2326;
  --color-slice-active-fill:  #2d353b;
  --color-slice-stroke:       #80a7c080;
  --color-text-secondary:     #83c092;
  --color-hint:                #859289;
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

---

## Hot-Reload

Both `rl_theme.css` and `rl_layout.json` are watched at runtime. Save either file and the wheel updates instantly — no need to relaunch. This makes live theming and layout tuning frictionless.

---

## How It Works (Technical)

- **Window**: `PanelWindow` with `WlrLayershell` at `Overlay` layer, fullscreen transparent canvas. `WlrKeyboardFocus.Exclusive` grabs all keyboard input while the wheel is up.
- **Input mask**: Only the wheel's circular footprint is registered as interactive — everything outside it click-through passes to whatever is behind.
- **Rendering**: Each slice is a `QtQuick.Shapes` donut segment built from two `PathArc` + two `PathLine` paths. Angle math is done manually from center — no hit-testing individual shapes.
- **Hit detection**: A single `MouseArea` over the whole ring computes the hovered slice from the pointer's angle and radial distance from center.
- **Activation**: `Quickshell.execDetached(["/bin/sh", "-c", script])` launches the command fully detached, then `Qt.quit()` closes the wheel.
- **Theme parsing**: Hand-rolled regex reader extracts `--name: value;` pairs from `:root { }` into a JS object. All color/effect bindings re-evaluate automatically on reassignment.
- **Layout parsing**: `JSON.parse()` with per-key fallbacks to `layoutDefaults` — a single source of truth so defaults can never drift.
