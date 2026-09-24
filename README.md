# Arch Linux Rice

Personal Arch Linux rice — a growing collection of custom Wayland shell components, desktop widgets, and compositor utilities built for Hyprland + Quickshell.

This is just the beginning. More components are on the way.

---

## 💬 Note

I built this for personal use but decided to share it since a few people seemed to like it. Even though it started as a personal project, I've put effort into making it as customizable as possible given my current knowledge.

Criticism is welcomed. Advice is welcomed. Collaboration is most welcomed.

---

## System

- **Device:** HP Victus 15 fb0108ax
- **OS:** Arch Linux
- **WM:** Hyprland
- **Terminal:** kitty 0.48.2
- **Display:** 1920x1080 @ 144Hz (Built-in)
- **CPU:** AMD Ryzen 5 5600H
- **GPU:** AMD Radeon RX 6500M / AMD Radeon Vega (integrated)
- **RAM:** 8GB
- **Storage:** 512GB

> Not tested on any other devices or distros.

---

## 🗂️ Repository Index

```
Arch-LINUX-rice/
├── README.md
└── Round launcher/
    ├── README.md
    ├── first_look.png
    ├── round launcher.qml
    ├── rl_theme.css
    └── rl_layout.json
```

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