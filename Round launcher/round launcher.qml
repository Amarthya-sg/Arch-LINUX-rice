import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ── Radial quick-launcher wheel ──
// Same RDR2-style donut-segment visual as before (an outer ring cut away
// by an inner radius, built with QtQuick.Shapes). Data model: each cell is
// { name, icon, script } — no weapon stats/ammo/category, no emoji glyphs.
// Give a cell an `icon` (a path to a png/svg) and a `script` (a shell
// command), and activating that cell (click, or Enter/Return while it's
// the active cell) runs the script and closes the wheel. Cells left with
// icon: "" fall back to a plain letter badge instead of a broken image.
//
// A single MouseArea over the whole ring computes which slice is hovered
// from the pointer's angle + distance from center, instead of trying to
// hit-test each donut-slice shape individually.
//
// ── Theme + Layout, as arguments ──
// Two separate files, both overridable:
//
//   THEME  — colors + --scale/--opacity/--blur/--dimness. CSS-variable
//            syntax, parsed by the same hand-rolled ":root { --x: y; }"
//            reader as before. Defaults to rl_theme.css next to this file.
//
//   LAYOUT — cells (any count, not just 8) + geometry/sizing knobs. Plain
//            JSON. Every knob is optional — anything omitted falls back to
//            circleRoot.layoutDefaults below (the single source of truth
//            for defaults, read by both the initial property values and
//            applyLayout()'s fallbacks, so they can't drift apart).
//            Defaults to rl_layout.json next to this file.
//
// Both can be overridden two ways, args take priority over env:
//
//   qs -p "round launcher.qml" -- --theme /path/to/theme.css --layout /path/to/layout.json
//   THEME_PATH=/path/to/theme.css LAYOUT_PATH=/path/to/layout.json qs -p "round launcher.qml"
//
// Quickshell doesn't hand QML a parsed argv, so `--theme X` is read by
// scanning Qt.application.arguments for the flag and taking the next
// element. Anything before/instead of a recognized flag is ignored, so
// extra launcher args (if any get added upstream) won't break this.
//
// Both files are watched — editing+saving either updates the wheel live,
// same as before.

PanelWindow {
    id: window
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    // "OnDemand" doesn't guarantee the compositor hands this layer-shell
    // surface keyboard focus just because it's visible. The wheel is meant
    // to behave modally anyway, so grab focus outright — this is what makes
    // Keys.onXPressed actually fire. Esc (below) is the explicit way out,
    // since Exclusive means nothing behind the wheel gets input while it's up.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Only the wheel's own footprint should intercept clicks/hover — the
    // rest of this window is just a transparent full-screen canvas so the
    // wheel can be centered anywhere, and everything outside `hitArea`
    // must click through to whatever is behind it (e.g. your terminal).
    mask: Region { item: hitArea }

    // ── resolve theme/layout paths: --flag arg, then env var, then default ──
    // Read once at startup; Qt.application.arguments includes the binary
    // name at [0], so start scanning from [1].
    function argValue(flag) {
        var args = Qt.application.arguments
        for (var i = 1; i < args.length - 1; i++) {
            if (args[i] === flag) return args[i + 1]
        }
        return ""
    }
    readonly property string themePath:
        argValue("--theme") || Quickshell.env("THEME_PATH") || Qt.resolvedUrl("rl_theme.css")
    readonly property string layoutPath:
        argValue("--layout") || Quickshell.env("LAYOUT_PATH") || Qt.resolvedUrl("rl_layout.json")

    // ── theme file (colors + scale/opacity/blur/dimness) ──
    FileView {
        id: themeFile
        path: window.themePath
        preload: true
        blockLoading: true
        watchChanges: true
        onLoaded: circleRoot.applyTheme(text())
        onFileChanged: reload()
        onLoadFailed: console.log("theme (" + window.themePath + "): couldn't load, using built-in defaults")
    }

    // ── layout file (cells + geometry) ──
    FileView {
        id: layoutFile
        path: window.layoutPath
        preload: true
        blockLoading: true
        watchChanges: true
        onLoaded: circleRoot.applyLayout(text())
        onFileChanged: reload()
        onLoadFailed: console.log("layout (" + window.layoutPath + "): couldn't load, using built-in defaults")
    }

    Item {
        id: circleRoot
        anchors.fill: parent
        focus: true
        opacity: wheelOpacity
        Component.onCompleted: {
            console.log("circleRoot size:", width, height)
            forceActiveFocus()
        }

        // ── theme parsing ──
        // Raw "--name: value;" pairs pulled out of the theme file, as a
        // plain JS object. Reassigned (never mutated) on reload so every
        // binding below that reads `theme[...]` re-evaluates automatically.
        property var theme: ({})

        function applyTheme(cssText) {
            var vars = {}
            var re = /--([a-zA-Z0-9_-]+)\s*:\s*([^;]+);/g
            var m
            while ((m = re.exec(cssText)) !== null) {
                vars[m[1].trim()] = m[2].trim()
            }
            theme = vars
        }
        // string-valued var (colors) with a fallback if missing/unloaded
        function tc(name, fallback) {
            return (theme && theme[name] !== undefined && theme[name] !== "") ? theme[name] : fallback
        }
        // numeric-valued var (scale/opacity/blur/dimness) with a fallback
        function tn(name, fallback) {
            if (theme && theme[name] !== undefined) {
                var n = parseFloat(theme[name])
                return isNaN(n) ? fallback : n
            }
            return fallback
        }
        // returns `color` with its existing alpha channel scaled by
        // `alpha` (0–1) — used to apply the per-layer transparency knobs
        // (--opacity-center / --opacity-slice / --opacity-background)
        // on top of whatever alpha a theme color already carries.
        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, color.a * alpha)
        }

        // ── layout defaults ──
        // Single source of truth for every layout/sizing knob. Both the
        // property initial values below AND applyLayout()'s per-key
        // fallbacks read from this one object, so there's no longer a
        // second hardcoded copy of any default to drift out of sync.
        readonly property var layoutDefaults: ({
            outerR: 260, innerRRatio: 0.66, gapDeg: 2.4, iconGlyphPx: 22,
            iconBadgeScale: 1.9, popOutPx: 30, hoverScale: 1.35,
            labelFontPx: 11, labelLetterSpacing: 0.4, centerNameFontPx: 18,
            hintFontPx: 10, runHintFontPx: 9, hintLetterSpacing: 1,
            badgeSpacing: 2, centerSpacing: 6, iconMargin: 4, centerIconMargin: 6,
            badgeBorderWidth: 1, ringBorderWidth: 2, backgroundBorderWidth: 18,
            backgroundPadding: 24, hitAreaPadding: 20, glowStrokeWidth: 2.4,
            glowInset: 1.2, centerIconScale: 1.8, centerGlyphScale: 1.6,
            centerCardWidthRatio: 1.7, popAnimDuration: 180, fadeAnimDuration: 150,
            glowAnimDuration: 120, popOvershoot: 2.5, blurMaxVal: 64
        })

        // ── layout parsing ──
        // Plain JSON: { outerR, innerRRatio, gapDeg, ..., cells: [...] }.
        // Any key may be omitted — each falls back to layoutDefaults above.
        // A malformed file logs and keeps whatever layout was previously
        // loaded (or the defaults, if this is the first load).
        function applyLayout(jsonText) {
            var parsed
            try {
                parsed = JSON.parse(jsonText)
            } catch (e) {
                console.log("layout: JSON parse error, keeping previous layout — " + e)
                return
            }
            if (!parsed || !Array.isArray(parsed.cells) || parsed.cells.length === 0) {
                console.log("layout: missing/empty 'cells' array, keeping previous layout")
                return
            }
            var d = layoutDefaults
            function num(key) { return typeof parsed[key] === "number" ? parsed[key] : d[key] }

            outerRBase = num("outerR")
            innerRRatio = num("innerRRatio")
            gapDeg = num("gapDeg")
            iconGlyphPxBase = num("iconGlyphPx")
            iconBadgeScale = num("iconBadgeScale")
            popOutPxBase = num("popOutPx")
            hoverScale = num("hoverScale")

            labelFontPx = num("labelFontPx")
            labelLetterSpacing = num("labelLetterSpacing")
            centerNameFontPx = num("centerNameFontPx")
            hintFontPx = num("hintFontPx")
            runHintFontPx = num("runHintFontPx")
            hintLetterSpacing = num("hintLetterSpacing")
            badgeSpacing = num("badgeSpacing")
            centerSpacing = num("centerSpacing")
            iconMargin = num("iconMargin")
            centerIconMargin = num("centerIconMargin")
            badgeBorderWidth = num("badgeBorderWidth")
            ringBorderWidth = num("ringBorderWidth")
            backgroundBorderWidth = num("backgroundBorderWidth")
            backgroundPadding = num("backgroundPadding")
            hitAreaPadding = num("hitAreaPadding")
            glowStrokeWidth = num("glowStrokeWidth")
            glowInset = num("glowInset")
            centerIconScale = num("centerIconScale")
            centerGlyphScale = num("centerGlyphScale")
            centerCardWidthRatio = num("centerCardWidthRatio")
            popAnimDuration = num("popAnimDuration")
            fadeAnimDuration = num("fadeAnimDuration")
            glowAnimDuration = num("glowAnimDuration")
            popOvershoot = num("popOvershoot")
            blurMaxVal = num("blurMaxVal")

            cells = parsed.cells
        }

        // ── run a cell's script ──
        // Launches it fully detached from this process, so it keeps running
        // after the wheel quits. If your Quickshell build doesn't expose
        // Quickshell.execDetached, replace the body with a Process item
        // instead, e.g.:
        //   Process { id: runner }
        //   ... runner.command = ["/bin/sh", "-c", cell.script]; runner.running = true
        function runCell(idx) {
            var cell = cells[idx]
            if (!cell || !cell.script) return
            Quickshell.execDetached(["/bin/sh", "-c", cell.script])
            Qt.quit()
        }
        function activateCurrent() {
            if (activeIndex !== -1) runCell(activeIndex)
        }

        // ── arrow-key navigation: Left/Up = previous, Right/Down = next ──
        // (also drop any mouse hover so the keyboard selection is what shows)
        // Esc closes the wheel outright — necessary since keyboardFocus is
        // Exclusive: while this surface is up it owns ALL keyboard input, so
        // there needs to be an explicit way out. Qt.quit() ends the process,
        // which is right for a wheel spawned fresh per invocation (e.g.
        // `qs -p rdr2_wheel.qml` on a hotkey). If this file instead runs
        // inside a persistent Quickshell daemon, swap for `window.visible = false`.
        // Number keys 1-9,0 jump straight to that slice (clockwise from the
        // top, matching the visible number badge on each slice; 0 = the
        // 10th slice, for layouts with more than 9 cells). Only digits
        // within the current slice count are handled; everything else
        // (arrows, Esc, Enter) is left alone so their own specific handlers
        // below still fire normally.
        Keys.onPressed: (event) => {
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 || event.key === Qt.Key_0) {
                var idx = event.key === Qt.Key_0 ? 9 : (event.key - Qt.Key_1)
                if (idx < count) {
                    hoveredIndex = -1
                    mousePresent = false
                    selectionMade = true
                    selectionSource = "keyboard"
                    selectedIndex = idx
                    event.accepted = true
                }
            }
        }

        Keys.onEscapePressed: Qt.quit()
        // Return/Enter activates whichever cell is currently active (hover
        // or keyboard selection) — runs its script and closes the wheel.
        Keys.onReturnPressed: activateCurrent()
        Keys.onEnterPressed: activateCurrent()

        // also clear mousePresent on every key press: if the cursor happens
        // to be resting anywhere over the wheel (not moving) when a key is
        // pressed, activeIndex's "mousePresent ? -1 : ..." fallback would
        // otherwise swallow the fresh keyboard selection and blank the card.
        Keys.onLeftPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex - 1 + count) % count }
        Keys.onRightPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex + 1) % count }
        // Up/Down don't step by one slot like Left/Right — they jump
        // straight to the slice diametrically opposite whatever's currently
        // selected (count/2 slots away). Both keys land on the same slot
        // since there's only one "opposite".
        Keys.onUpPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex + Math.floor(count / 2)) % count }
        Keys.onDownPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex + Math.floor(count / 2)) % count }

        // ── colors, from theme (with the original palette as fallback) ──
        readonly property color cream: tc("color-cream", "#efe9db")
        readonly property color red: tc("color-red", "#e3241d")
        readonly property color ink: tc("color-ink", "#141311")
        readonly property color sliceActiveFill: tc("color-slice-active-fill", "#2c2a24")
        readonly property color sliceStroke: tc("color-slice-stroke", "#5a968c8a")
        readonly property color textSecondary: tc("color-text-secondary", "#d9d4c7")
        readonly property color hintColor: tc("color-hint", "#8f8c82")
        readonly property color iconBg: tc("color-icon-bg", "#33000000")
        readonly property color ringBorder: tc("color-ring-border", "#77746a")
        readonly property color ringFill: tc("color-ring-fill", "#cc0e0f0d")

        // ── the one size knob, plus the effect controls (theme-driven) ──
        // named uiScale (not "scale") because Item already has a built-in
        // "scale" property (the graphical transform scale) — declaring a
        // custom property with that exact name collides with it, which is
        // why --scale in the theme file previously had no effect.
        readonly property real uiScale: tn("scale", 1.0)
        readonly property real wheelOpacity: tn("opacity", 1.0)
        readonly property real blurAmount: tn("blur", 0)
        readonly property real dimness: tn("dimness", 0.45)
        // per-layer transparency (0 = fully transparent, 1 = fully opaque),
        // independent of the overall --opacity / --dimness knobs above
        readonly property real centerOpacity: tn("opacity-center", 1.0)
        readonly property real sliceOpacity: tn("opacity-slice", 1.0)
        readonly property real backgroundOpacity: tn("opacity-background", 1.0)

        // ── geometry knobs, from layout (mutable — applyLayout reassigns
        // these on load; each starts at layoutDefaults' value, so a
        // missing/failed layout file behaves identically to before) ──
        property real outerRBase: layoutDefaults.outerR
        property real innerRRatio: layoutDefaults.innerRRatio
        property real gapDeg: layoutDefaults.gapDeg
        property real iconGlyphPxBase: layoutDefaults.iconGlyphPx
        property real iconBadgeScale: layoutDefaults.iconBadgeScale
        property real popOutPxBase: layoutDefaults.popOutPx
        property real hoverScale: layoutDefaults.hoverScale

        // ── sizing/spacing knobs, from layout (previously hardcoded) ──
        property real labelFontPx: layoutDefaults.labelFontPx
        property real labelLetterSpacing: layoutDefaults.labelLetterSpacing
        property real centerNameFontPx: layoutDefaults.centerNameFontPx
        property real hintFontPx: layoutDefaults.hintFontPx
        property real runHintFontPx: layoutDefaults.runHintFontPx
        property real hintLetterSpacing: layoutDefaults.hintLetterSpacing
        property real badgeSpacing: layoutDefaults.badgeSpacing
        property real centerSpacing: layoutDefaults.centerSpacing
        property real iconMargin: layoutDefaults.iconMargin
        property real centerIconMargin: layoutDefaults.centerIconMargin
        property real badgeBorderWidth: layoutDefaults.badgeBorderWidth
        property real ringBorderWidth: layoutDefaults.ringBorderWidth
        property real backgroundBorderWidth: layoutDefaults.backgroundBorderWidth
        property real backgroundPadding: layoutDefaults.backgroundPadding
        property real hitAreaPadding: layoutDefaults.hitAreaPadding
        property real glowStrokeWidth: layoutDefaults.glowStrokeWidth
        property real glowInset: layoutDefaults.glowInset
        property real centerIconScale: layoutDefaults.centerIconScale
        property real centerGlyphScale: layoutDefaults.centerGlyphScale
        property real centerCardWidthRatio: layoutDefaults.centerCardWidthRatio
        property real popAnimDuration: layoutDefaults.popAnimDuration
        property real fadeAnimDuration: layoutDefaults.fadeAnimDuration
        property real glowAnimDuration: layoutDefaults.glowAnimDuration
        property real popOvershoot: layoutDefaults.popOvershoot
        property real blurMaxVal: layoutDefaults.blurMaxVal

        readonly property real cx: width / 2
        readonly property real cy: height / 2
        // every size below derives from outerR, which derives from scale —
        // this is the single place wheel size is controlled
        readonly property real outerR: outerRBase * uiScale
        readonly property real innerR: outerR * innerRRatio
        readonly property real iconGlyphPx: iconGlyphPxBase * uiScale
        readonly property real iconBadgeSize: iconGlyphPx * iconBadgeScale

        // ── the cells ──
        // name:   label shown under the icon and in the center card
        // icon:   path to a png/svg icon file (absolute, or relative to
        //         this .qml file). Leave "" to fall back to a plain
        //         letter badge instead of a broken image.
        // script: shell command run (via /bin/sh -c) when this cell is
        //         activated — click it, or select it and press Enter.
        //
        // Sourced from the layout file (see applyLayout); this literal is
        // just the pre-load default so the wheel isn't empty for the one
        // frame before layoutFile.onLoaded fires.
        property var cells: [
            { name: "TERMINAL",   icon: "", script: "" },
            { name: "BROWSER",    icon: "", script: "" },
            { name: "FILES",      icon: "", script: "" },
            { name: "MUSIC",      icon: "", script: "" },
            { name: "LOCK",       icon: "", script: "" },
            { name: "SCREENSHOT", icon: "", script: "" },
            { name: "VOLUME",     icon: "", script: "" },
            { name: "SETTINGS",   icon: "", script: "" }
        ]

        readonly property int count: cells.length
        readonly property real step: 360 / count

        property int hoveredIndex: -1
        property int selectedIndex: 0
        // nothing is "selected" until the user actually does something —
        // hovering/clicking a slice, or pressing an arrow key.
        property bool selectionMade: false
        // which input made the current selection: "keyboard" or "mouse".
        // Only a *keyboard* selection should be cleared just by the mouse
        // being present-but-off-slice — a mouse CLICK is itself a mouse
        // action and must keep showing even after the pointer drifts back
        // to dead center, exactly like hover normally would while over a
        // slice. Without this distinction, moving the mouse away after a
        // click immediately un-selected the item you just clicked.
        property string selectionSource: "keyboard"
        // whether the pointer is currently anywhere over the wheel's hit
        // area at all (inside OR outside the donut band, doesn't matter) —
        // as opposed to having left the window/wheel region entirely.
        property bool mousePresent: false
        // Priority: live hover > click-made selection (persists regardless
        // of where the mouse drifts afterward, as long as it's still on the
        // wheel) > keyboard-made selection (cleared the instant the mouse
        // is present but off-slice, since mouse hover should always be able
        // to override a stale keyboard pick) > nothing.
        readonly property int activeIndex: hoveredIndex !== -1
            ? hoveredIndex
            : (selectionMade && selectionSource === "mouse"
                ? selectedIndex
                : (mousePresent ? -1 : (selectionMade ? selectedIndex : -1)))
        readonly property var activeCell: activeIndex === -1 ? null : cells[activeIndex]

        // angle 0 = straight up, positive = clockwise (screen coords, y-down)
        function pt(r, deg) {
            var rad = deg * Math.PI / 180
            return Qt.point(cx + r * Math.sin(rad), cy - r * Math.cos(rad))
        }
        function angleOf(idx) { return idx * step }

        // soft shadow behind the ring (the "background circle")
        Rectangle {
            anchors.centerIn: parent
            width: circleRoot.outerR * 2 + circleRoot.backgroundPadding
            height: width
            radius: width / 2
            color: "transparent"
            border.color: "#40000000"
            border.width: circleRoot.backgroundBorderWidth * circleRoot.uiScale
            opacity: circleRoot.backgroundOpacity
        }

        // ── donut-slice segments ──
        Repeater {
            model: circleRoot.count

            Item {
                id: slot
                anchors.fill: parent
                property int idx: index
                property bool active: circleRoot.activeIndex === idx

                // full brightness when nothing is active yet, or when this
                // is the active slice; dimmed only once something else has
                // become active (hover or arrow-key selection) — dim level
                // comes from theme's --dimness
                opacity: circleRoot.activeIndex === -1 ? 1.0 : (active ? 1.0 : circleRoot.dimness)
                Behavior on opacity { NumberAnimation { duration: circleRoot.fadeAnimDuration } }

                property real aC: circleRoot.angleOf(idx)
                property real a0: aC - circleRoot.step / 2 + circleRoot.gapDeg
                property real a1: aC + circleRoot.step / 2 - circleRoot.gapDeg

                // hover "pop": push the OUTER edge further out only. The
                // inner edge stays pinned at circleRoot.innerR — that's
                // exactly where the fixed center-ring decoration is drawn,
                // so letting the inner edge move at all made popped slices
                // dip under/behind the center disc. Growing outward-only
                // keeps the slice fully outside the center ring at all times.
                property real popOuterR: circleRoot.outerR + (active ? circleRoot.popOutPxBase * circleRoot.uiScale : 0)
                property real popInnerR: circleRoot.innerR
                Behavior on popOuterR { NumberAnimation { duration: circleRoot.popAnimDuration; easing.type: Easing.OutBack; easing.overshoot: circleRoot.popOvershoot } }

                Shape {
                    id: fillShape
                    anchors.fill: parent
                    antialiasing: true
                    // softness from theme's --blur (0–blurMaxVal), normalized
                    // for MultiEffect's 0–1 blur range
                    layer.enabled: circleRoot.blurAmount > 0
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: Math.min(circleRoot.blurAmount / circleRoot.blurMaxVal, 1.0)
                        blurMax: circleRoot.blurMaxVal
                    }

                    ShapePath {
                        id: fillPath
                        fillColor: circleRoot.withAlpha(slot.active ? circleRoot.sliceActiveFill : circleRoot.ink, circleRoot.sliceOpacity)
                        strokeColor: "transparent"
                        strokeWidth: 0

                        property point p1: circleRoot.pt(slot.popOuterR, slot.a0)
                        property point p2: circleRoot.pt(slot.popOuterR, slot.a1)
                        property point p3: circleRoot.pt(slot.popInnerR, slot.a1)
                        property point p4: circleRoot.pt(slot.popInnerR, slot.a0)

                        startX: p1.x; startY: p1.y
                        PathArc { x: fillPath.p2.x; y: fillPath.p2.y; radiusX: slot.popOuterR; radiusY: slot.popOuterR; direction: PathArc.Clockwise }
                        PathLine { x: fillPath.p3.x; y: fillPath.p3.y }
                        PathArc { x: fillPath.p4.x; y: fillPath.p4.y; radiusX: slot.popInnerR; radiusY: slot.popInnerR; direction: PathArc.Counterclockwise }
                        PathLine { x: fillPath.p1.x; y: fillPath.p1.y }
                    }
                }

                // red highlight outline, only visible while active — separate
                // Shape so it can carry its own opacity (ShapePath itself has
                // no opacity property; only real Items like Shape do)
                Shape {
                    id: glowShape
                    anchors.fill: parent
                    antialiasing: true
                    opacity: slot.active ? 0.9 : 0
                    Behavior on opacity { NumberAnimation { duration: circleRoot.glowAnimDuration } }

                    ShapePath {
                        id: glowPath
                        fillColor: "transparent"
                        strokeColor: circleRoot.red
                        strokeWidth: circleRoot.glowStrokeWidth * circleRoot.uiScale

                        property point p1: circleRoot.pt(slot.popOuterR - circleRoot.glowInset * circleRoot.uiScale, slot.a0)
                        property point p2: circleRoot.pt(slot.popOuterR - circleRoot.glowInset * circleRoot.uiScale, slot.a1)
                        property point p3: circleRoot.pt(slot.popInnerR + circleRoot.glowInset * circleRoot.uiScale, slot.a1)
                        property point p4: circleRoot.pt(slot.popInnerR + circleRoot.glowInset * circleRoot.uiScale, slot.a0)

                        startX: p1.x; startY: p1.y
                        PathArc { x: glowPath.p2.x; y: glowPath.p2.y; radiusX: slot.popOuterR - circleRoot.glowInset * circleRoot.uiScale; radiusY: slot.popOuterR - circleRoot.glowInset * circleRoot.uiScale; direction: PathArc.Clockwise }
                        PathLine { x: glowPath.p3.x; y: glowPath.p3.y }
                        PathArc { x: glowPath.p4.x; y: glowPath.p4.y; radiusX: slot.popInnerR + circleRoot.glowInset * circleRoot.uiScale; radiusY: slot.popInnerR + circleRoot.glowInset * circleRoot.uiScale; direction: PathArc.Counterclockwise }
                        PathLine { x: glowPath.p1.x; y: glowPath.p1.y }
                    }
                }

                // icon (custom image, with a background badge) + label,
                // centered at the slice's mid-radius — reads the SAME
                // popOuterR/popInnerR the shape is built from, so it tracks
                // the growing slice band exactly.
                Item {
                    property point mid: circleRoot.pt((slot.popOuterR + slot.popInnerR) / 2, slot.aC)
                    width: labelCol.width
                    height: labelCol.height
                    x: mid.x - width / 2
                    y: mid.y - height / 2
                    scale: slot.active ? circleRoot.hoverScale : 1.0
                    Behavior on scale { NumberAnimation { duration: circleRoot.popAnimDuration; easing.type: Easing.OutBack; easing.overshoot: circleRoot.popOvershoot } }

                    Column {
                        id: labelCol
                        spacing: circleRoot.badgeSpacing * circleRoot.uiScale

                        // icon badge: background circle + either the cell's
                        // custom icon image, or (if none given / it failed
                        // to load) a plain letter fallback. The background
                        // circle itself is only drawn for the letter
                        // fallback case — a loaded custom icon shows with
                        // no badge behind it.
                        Item {
                            id: iconBadge
                            width: circleRoot.iconBadgeSize
                            height: circleRoot.iconBadgeSize
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: circleRoot.iconBg
                                border.color: circleRoot.ringBorder
                                border.width: circleRoot.badgeBorderWidth * circleRoot.uiScale
                                visible: !cellIcon.visible
                            }
                            Image {
                                id: cellIcon
                                anchors.fill: parent
                                anchors.margins: circleRoot.iconMargin * circleRoot.uiScale
                                source: circleRoot.cells[slot.idx].icon || ""
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                asynchronous: true
                                visible: source != "" && status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !cellIcon.visible
                                text: circleRoot.cells[slot.idx].name.charAt(0)
                                color: circleRoot.cream
                                font.pixelSize: circleRoot.iconGlyphPx
                                font.bold: true
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: circleRoot.cells[slot.idx].name
                            color: circleRoot.cream
                            font.pixelSize: circleRoot.labelFontPx * circleRoot.uiScale
                            font.bold: true
                            font.letterSpacing: circleRoot.labelLetterSpacing
                        }
                    }
                }
            }
        }

        // ── single hit-test surface: pointer angle/radius -> hovered slice ──
        // sized to the wheel's own footprint (not the full screen) so this
        // is also what window.mask uses to define the clickable region.
        //
        // Sized off outerR + max pop-out (popOutPxBase*scale) + a buffer
        // (hitAreaPadding), instead of off the resting outerR alone —
        // otherwise the popped-out edge of an active slice could extend
        // past this area's radius, clipping/blocking clicks on the very
        // tip of the glow. Same fix is mirrored in maxR below, used for
        // the hover/click boundary test.
        MouseArea {
            id: hitArea
            anchors.centerIn: parent
            width: circleRoot.outerR * 2 + circleRoot.hitAreaPadding + 2 * circleRoot.popOutPxBase * circleRoot.uiScale
            height: width
            hoverEnabled: true
            onEntered: circleRoot.mousePresent = true
            onPositionChanged: (mouse) => {
                circleRoot.mousePresent = true
                var dx = mouse.x - width / 2
                var dy = mouse.y - height / 2
                var dist = Math.sqrt(dx * dx + dy * dy)
                var maxR = circleRoot.outerR + circleRoot.popOutPxBase * circleRoot.uiScale  // account for pop-out
                if (dist < circleRoot.innerR || dist > maxR) {
                    circleRoot.hoveredIndex = -1
                    return
                }
                var deg = Math.atan2(dx, -dy) * 180 / Math.PI
                if (deg < 0) deg += 360
                circleRoot.hoveredIndex = Math.round(deg / circleRoot.step) % circleRoot.count
            }
            onExited: { circleRoot.hoveredIndex = -1; circleRoot.mousePresent = false }
            // clicking a slice runs its script immediately and closes the
            // wheel (see circleRoot.runCell)
            onClicked: if (circleRoot.hoveredIndex !== -1) circleRoot.runCell(circleRoot.hoveredIndex)
        }

        // ── center metal ring ──
        Rectangle {
            anchors.centerIn: parent
            width: circleRoot.innerR * 2 - 4
            height: width
            radius: width / 2
            color: circleRoot.withAlpha(circleRoot.ringFill, circleRoot.centerOpacity)
            border.color: circleRoot.ringBorder
            border.width: circleRoot.ringBorderWidth * circleRoot.uiScale
        }

        // ── center card: active cell's icon / name / script preview ──
        // (shows a plain hint until the user hovers a slice or presses an
        // arrow key — see circleRoot.activeCell)
        Column {
            id: centerCard
            anchors.centerIn: parent
            width: circleRoot.innerR * circleRoot.centerCardWidthRatio
            spacing: circleRoot.centerSpacing * circleRoot.uiScale
            property var c: circleRoot.activeCell

            // icon: same image-or-letter-fallback badge as the slices,
            // just bigger, sitting above the name. Badge circle only
            // shows for the letter fallback, same as the slice icons.
            Item {
                id: centerIcon
                visible: !!centerCard.c
                width: circleRoot.iconBadgeSize * circleRoot.centerIconScale
                height: width
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: circleRoot.iconBg
                    border.color: circleRoot.ringBorder
                    border.width: circleRoot.badgeBorderWidth * circleRoot.uiScale
                    visible: !centerIconImg.visible
                }
                Image {
                    id: centerIconImg
                    anchors.fill: parent
                    anchors.margins: circleRoot.centerIconMargin * circleRoot.uiScale
                    source: centerCard.c ? (centerCard.c.icon || "") : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: source != "" && status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !centerIconImg.visible
                    text: centerCard.c ? centerCard.c.name.charAt(0) : ""
                    color: circleRoot.cream
                    font.pixelSize: circleRoot.iconGlyphPx * circleRoot.centerGlyphScale
                    font.bold: true
                }
            }

            Text { visible: !!centerCard.c; anchors.horizontalCenter: parent.horizontalCenter; text: centerCard.c ? centerCard.c.name : ""; color: circleRoot.cream; font.pixelSize: circleRoot.centerNameFontPx * circleRoot.uiScale; font.bold: true }

            Text {
                visible: !!centerCard.c && centerCard.c.script !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CLICK OR ENTER TO RUN"
                color: circleRoot.hintColor
                font.pixelSize: circleRoot.runHintFontPx * circleRoot.uiScale
                font.letterSpacing: circleRoot.hintLetterSpacing
                topPadding: 2 * circleRoot.uiScale
            }

            Text {
                visible: !centerCard.c
                anchors.horizontalCenter: parent.horizontalCenter
                text: "HOVER OR USE ARROW KEYS"
                color: circleRoot.hintColor
                font.pixelSize: circleRoot.hintFontPx * circleRoot.uiScale
                font.letterSpacing: circleRoot.hintLetterSpacing
            }
        }
    }
}
