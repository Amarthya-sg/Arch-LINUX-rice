# Arch Linux Rice

Personal Arch Linux rice — a growing collection of custom Wayland shell components, desktop widgets, and compositor utilities built for Hyprland + Quickshell.

This is just the beginning. More components are on the way.

---

## 🗂️ Repository Index

```
Arch-LINUX-rice/
├── README.md                      ← repository overview & file index
└── Round launcher/
    ├── README.md                  ← component documentation & Hyprland guide
    ├── first_look.png             ← preview screenshot
    ├── round launcher.qml         ← single-file launcher app (Quickshell / QML)
    ├── rl_theme.css               ← color theme + effect variables (hot-reloaded)
    └── rl_layout.json             ← cells + geometry config (hot-reloaded)
```

| Path | Type | Description |
| :--- | :--- | :--- |
| [README.md](./README.md) | Markdown | Repository overview, index, and component list |
| [Round launcher/README.md](./Round%20launcher/README.md) | Markdown | Comprehensive component documentation, controls, and Hyprland config |
| [Round launcher/first_look.png](./Round%20launcher/first_look.png) | Image | Visual preview screenshot of the radial launcher |
| [Round launcher/round launcher.qml](./Round%20launcher/round%20launcher.qml) | QML | Main radial quick-launcher application for Wayland layer-shell |
| [Round launcher/rl_theme.css](./Round%20launcher/rl_theme.css) | CSS Variables | Complete theme definition and variable reference |
| [Round launcher/rl_layout.json](./Round%20launcher/rl_layout.json) | JSON | Geometry knobs and active cell/command definitions |

---

## 📦 Components

### 🔵 [Round Launcher](./Round%20launcher/README.md)

An RDR2-inspired radial quick-launcher wheel for Wayland. Slices divide evenly across 360° based on how many cells you define, each mapping to a shell command. Supports mouse hover, keyboard navigation (arrow keys, number keys, Enter), live hot-reload of theme and layout files, and fully detached app launching.

Built with [Quickshell](https://quickshell.outfoxxed.me/) (QML + `WlrLayershell`).

```
Round launcher/
├── README.md              ← component documentation
├── first_look.png         ← preview screenshot
├── round launcher.qml     ← single-file launcher app
├── rl_theme.css           ← color theme + effect variables
└── rl_layout.json         ← cells + geometry config
```

![Round Launcher preview](./Round%20launcher/first_look.png)

→ **[Full documentation](./Round%20launcher/README.md)**

---

*More components coming soon.*
