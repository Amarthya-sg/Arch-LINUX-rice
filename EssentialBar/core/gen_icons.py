#!/usr/bin/env python3
"""Regenerate icons/*.svg from colours in style.css (old files are replaced)."""
import re, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSS, ICONS, SRC = ROOT / "style.css", ROOT / "icons", ROOT / "icons-src"
TMP = ROOT / ".icons-new"

# fallback tone colours, used when an icon has no --cc-icon-<name> token
TONE_VARS = {
    "fg": "--cc-icon-fg", "muted": "--cc-icon-muted", "accent": "--cc-icon-accent",
    "ink": "--cc-icon-ink", "success": "--cc-icon-success",
    "warning": "--cc-icon-warning", "error": "--cc-icon-error",
}
TONE_RE = re.compile(r"-(fg|muted|accent|ink|success|warning|error)\.svg$")
HEX = re.compile(r"#[0-9a-fA-F]{3,8}\b")

def css_vars(text):
    return {m.group(1): m.group(2)
            for m in re.finditer(r"(--[\w-]+)\s*:\s*(#[0-9a-fA-F]{6})\s*;", text)}

def recolor(svg, color):
    return HEX.sub(color, svg).replace("currentColor", color)

def main():
    css = css_vars(CSS.read_text())
    missing = [v for v in TONE_VARS.values() if v not in css]
    if missing:
        print(f"gen_icons: missing in style.css: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    tones = {t: css[v] for t, v in TONE_VARS.items()}

    if not SRC.exists():
        SRC.mkdir()
        for f in ICONS.glob("*.svg"):
            shutil.copy2(f, SRC / f.name)

    if TMP.exists():
        shutil.rmtree(TMP)
    TMP.mkdir()

    bases, statuses, kept = {}, 0, []
    for f in sorted(SRC.glob("*.svg")):
        stem = f.stem
        m = TONE_RE.search(f.name)
        if m:
            bases.setdefault(f.name[:m.start()], f)
        else:
            # status-*.svg: colour comes from --cc-icon-<stem>
            col = css.get(f"--cc-icon-{stem}") or css.get(f"--cc-icon-{stem.replace('-off', '-on')}")
            if col:
                (TMP / f.name).write_text(recolor(f.read_text(), col))
                statuses += 1
            else:
                shutil.copy2(f, TMP / f.name)
                kept.append(f.name)
    for base, tmpl in bases.items():
        svg = tmpl.read_text()
        own = css.get(f"--cc-icon-{base}")          # per-icon token wins, like Theme.qml
        for tone, col in tones.items():
            (TMP / f"{base}-{tone}.svg").write_text(recolor(svg, own or col))

    for f in ICONS.glob("*.svg"):
        f.unlink()
    for f in TMP.glob("*.svg"):
        shutil.move(str(f), ICONS / f.name)
    shutil.rmtree(TMP)
    print(f"icons: {len(bases)} icons x {len(tones)} tones, {statuses} status icons recoloured")
    if kept:
        print("no token, copied as-is: " + ", ".join(kept))

main()
