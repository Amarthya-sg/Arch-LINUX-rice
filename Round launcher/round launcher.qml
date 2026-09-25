import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: hitArea }

    // Daemon mode hides rather than destroys the window between
    // invocations (see finishClose), so Component.onCompleted alone won't
    // fire again on re-show. Catch that case here and replay the open
    // animation each time the window becomes visible again — guarded so
    // the very first show (already handled by circleRoot's own
    // Component.onCompleted) doesn't trigger it a second time.
    property bool everCompleted: false
    onVisibleChanged: {
        if (visible && everCompleted) circleRoot.beginOpen()
    }

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
    // ── daemon mode: --daemon flag or DAEMON_MODE=1 env ──
    // When true, runCell hides the window instead of quitting the process,
    // so a persistent Quickshell instance can reopen the wheel on the next
    // hotkey press instead of respawning it from scratch each time.
    readonly property bool daemonMode:
        Qt.application.arguments.indexOf("--daemon") !== -1 || Quickshell.env("DAEMON_MODE") === "1"

    // ── actually hide/quit ──
    // Called once by closeAnim.onStopped, after the shrink-and-fade has
    // finished playing — never called directly by an input handler, so
    // the animation always gets to run to completion first.
    function finishClose() {
        if (window.daemonMode) {
            window.visible = false
        } else {
            Qt.quit()
        }
    }

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

        // ── open/close animation ──
        // `entranceProgress` drives both scale and opacity together, from
        // 0 (fully closed — invisible, collapsed to a point) to 1 (fully
        // open). It's a single 0..1 driver rather than two separate
        // properties so scale and fade always stay in lockstep. openAnim
        // and closeAnim each animate this one property with their own
        // easing/duration — see below.
        //
        // Opening uses OutBack easing for the springy overshoot (scale
        // pokes slightly past 1.0 then settles) — that only reads as a
        // "pop" on the way IN. Closing reuses the same property but with
        // a plain InCubic ease with no overshoot, so the wheel shrinks
        // straight back to nothing rather than bouncing outward again on
        // its way out, which would look like it's reopening.
        property real entranceProgress: 0
        // final on-screen opacity = the theme's --opacity multiplied by
        // the entrance/exit progress, so --opacity still caps the fully-
        // open brightness exactly as before, just animated through it.
        opacity: wheelOpacity * entranceProgress
        scale: circleRoot.entranceProgress
        transformOrigin: Item.Center

        // true for the duration of the closing animation, so the escape/
        // run handlers below know not to re-trigger it and can instead
        // just wait it out.
        property bool closing: false

        NumberAnimation {
            id: openAnim
            target: circleRoot
            property: "entranceProgress"
            from: 0
            to: 1
            duration: 220
            easing.type: Easing.OutBack
            easing.overshoot: 1.7
        }
        NumberAnimation {
            id: closeAnim
            target: circleRoot
            property: "entranceProgress"
            from: 1
            to: 0
            duration: 140
            easing.type: Easing.InCubic
            onStopped: {
                if (circleRoot.closing) window.finishClose()
            }
        }

        // ── begin the close animation, then actually hide/quit once it's
        // done (via closeAnim.onStopped -> window.finishClose) ──
        // Guarded by `closing` so a double Esc-press or an accidental
        // second click mid-animation doesn't restart the shrink from
        // wherever it currently is.
        function beginClose() {
            if (closing) return
            closing = true
            hoveredIndex = -1
            closeAnim.start()
        }

        // Re-entry point for daemon mode: the window is only hidden (not
        // destroyed) between invocations, so on re-show `closing` needs
        // resetting or a second beginClose() call would silently no-op,
        // and entranceProgress needs to restart from 0 so the pop-in
        // animation actually plays again instead of snapping straight to
        // fully open (its state from before the window was last hidden).
        function beginOpen() {
            closing = false
            entranceProgress = 0
            forceActiveFocus()
            openAnim.start()
        }

        Component.onCompleted: {
            console.log("circleRoot size:", width, height)
            beginOpen()
            window.everCompleted = true
        }

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
        function tc(name, fallback) {
            return (theme && theme[name] !== undefined && theme[name] !== "") ? theme[name] : fallback
        }
        function tn(name, fallback) {
            if (theme && theme[name] !== undefined) {
                var n = parseFloat(theme[name])
                return isNaN(n) ? fallback : n
            }
            return fallback
        }
        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, color.a * alpha)
        }

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
        // after the wheel quits/hides. In one-shot mode (default, e.g.
        // `qs -p "round launcher.qml"` on a hotkey) the process exits via
        // Qt.quit() same as before. In daemon mode (--daemon flag or
        // DAEMON_MODE=1 env) the window is hidden instead — the Quickshell
        // process stays resident and the wheel can be shown again next time
        // without respawning, so the same instance keeps its FileView
        // watchers/state alive across invocations. Either way, the close
        // animation plays first — see beginClose().
        function runCell(idx) {
            var cell = cells[idx]
            if (!cell || !cell.script) return
            Quickshell.execDetached(["/bin/sh", "-c", cell.script])
            beginClose()
        }
        function activateCurrent() {
            if (activeIndex !== -1) runCell(activeIndex)
        }

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

        // Esc: play the close animation, then quit outright (one-shot
        // mode) or just hide (daemon mode) once it finishes — see
        // beginClose() / closeAnim.onStopped / window.finishClose().
        Keys.onEscapePressed: beginClose()
        Keys.onReturnPressed: activateCurrent()
        Keys.onEnterPressed: activateCurrent()

        Keys.onLeftPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex - 1 + count) % count }
        Keys.onRightPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex + 1) % count }
        Keys.onUpPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex + Math.floor(count / 2)) % count }
        Keys.onDownPressed: { hoveredIndex = -1; mousePresent = false; selectionMade = true; selectionSource = "keyboard"; selectedIndex = (selectedIndex + Math.floor(count / 2)) % count }

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

        readonly property real uiScale: tn("scale", 1.0)
        readonly property real wheelOpacity: tn("opacity", 1.0)
        readonly property real blurAmount: tn("blur", 0)
        readonly property real dimness: tn("dimness", 0.45)
        readonly property real centerOpacity: tn("opacity-center", 1.0)
        readonly property real sliceOpacity: tn("opacity-slice", 1.0)
        readonly property real backgroundOpacity: tn("opacity-background", 1.0)

        property real outerRBase: layoutDefaults.outerR
        property real innerRRatio: layoutDefaults.innerRRatio
        property real gapDeg: layoutDefaults.gapDeg
        property real iconGlyphPxBase: layoutDefaults.iconGlyphPx
        property real iconBadgeScale: layoutDefaults.iconBadgeScale
        property real popOutPxBase: layoutDefaults.popOutPx
        property real hoverScale: layoutDefaults.hoverScale

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
        readonly property real outerR: outerRBase * uiScale
        readonly property real innerR: outerR * innerRRatio
        readonly property real iconGlyphPx: iconGlyphPxBase * uiScale
        readonly property real iconBadgeSize: iconGlyphPx * iconBadgeScale

        // ── letter-fallback badge text ──
        // Previously charAt(0) — fine for a single all-caps word like
        // "MUSIC" ("M"), but a multi-word name ("SCREEN SHOT") only ever
        // showed one character, and a non-ASCII first character (emoji or
        // anything outside the BMP) could be sliced in half by charAt,
        // which indexes UTF-16 code units rather than full codepoints.
        // Now: two words -> first letter of each, up to two ("SS").
        // One word -> its first full codepoint, grabbed safely via
        // codePointAt/fromCodePoint instead of charAt/substring.
        function badgeText(name) {
            if (!name) return ""
            var words = name.trim().split(/\s+/).filter(function(w) { return w.length > 0 })
            function firstCodePoint(s) {
                if (s.length === 0) return ""
                var cp = s.codePointAt(0)
                return String.fromCodePoint(cp)
            }
            if (words.length >= 2) {
                return (firstCodePoint(words[0]) + firstCodePoint(words[1])).toUpperCase()
            }
            return firstCodePoint(words[0] || name).toUpperCase()
        }

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
        property bool selectionMade: false
        property string selectionSource: "keyboard"
        property bool mousePresent: false
        readonly property int activeIndex: hoveredIndex !== -1
            ? hoveredIndex
            : (selectionMade && selectionSource === "mouse"
                ? selectedIndex
                : (mousePresent ? -1 : (selectionMade ? selectedIndex : -1)))
        readonly property var activeCell: activeIndex === -1 ? null : cells[activeIndex]

        function pt(r, deg) {
            var rad = deg * Math.PI / 180
            return Qt.point(cx + r * Math.sin(rad), cy - r * Math.cos(rad))
        }
        function angleOf(idx) { return idx * step }

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

        Repeater {
            model: circleRoot.count

            Item {
                id: slot
                anchors.fill: parent
                property int idx: index
                property bool active: circleRoot.activeIndex === idx

                opacity: circleRoot.activeIndex === -1 ? 1.0 : (active ? 1.0 : circleRoot.dimness)
                Behavior on opacity { NumberAnimation { duration: circleRoot.fadeAnimDuration } }

                property real aC: circleRoot.angleOf(idx)
                property real a0: aC - circleRoot.step / 2 + circleRoot.gapDeg
                property real a1: aC + circleRoot.step / 2 - circleRoot.gapDeg

                property real popOuterR: circleRoot.outerR + (active ? circleRoot.popOutPxBase * circleRoot.uiScale : 0)
                property real popInnerR: circleRoot.innerR
                Behavior on popOuterR { NumberAnimation { duration: circleRoot.popAnimDuration; easing.type: Easing.OutBack; easing.overshoot: circleRoot.popOvershoot } }

                Shape {
                    id: fillShape
                    anchors.fill: parent
                    antialiasing: true
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
                                text: circleRoot.badgeText(circleRoot.cells[slot.idx].name)
                                color: circleRoot.cream
                                font.pixelSize: text.length > 1 ? circleRoot.iconGlyphPx * 0.72 : circleRoot.iconGlyphPx
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
                var maxR = circleRoot.outerR + circleRoot.popOutPxBase * circleRoot.uiScale
                if (dist < circleRoot.innerR || dist > maxR) {
                    circleRoot.hoveredIndex = -1
                    return
                }
                var deg = Math.atan2(dx, -dy) * 180 / Math.PI
                if (deg < 0) deg += 360
                circleRoot.hoveredIndex = Math.round(deg / circleRoot.step) % circleRoot.count
            }
            onExited: { circleRoot.hoveredIndex = -1; circleRoot.mousePresent = false }
            onClicked: if (circleRoot.hoveredIndex !== -1) circleRoot.runCell(circleRoot.hoveredIndex)
        }

        Rectangle {
            anchors.centerIn: parent
            width: circleRoot.innerR * 2 - 4
            height: width
            radius: width / 2
            color: circleRoot.withAlpha(circleRoot.ringFill, circleRoot.centerOpacity)
            border.color: circleRoot.ringBorder
            border.width: circleRoot.ringBorderWidth * circleRoot.uiScale
        }

        Column {
            id: centerCard
            anchors.centerIn: parent
            width: circleRoot.innerR * circleRoot.centerCardWidthRatio
            spacing: circleRoot.centerSpacing * circleRoot.uiScale
            property var c: circleRoot.activeCell

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
                    text: centerCard.c ? circleRoot.badgeText(centerCard.c.name) : ""
                    color: circleRoot.cream
                    font.pixelSize: text.length > 1 ? circleRoot.iconGlyphPx * circleRoot.centerGlyphScale * 0.72 : circleRoot.iconGlyphPx * circleRoot.centerGlyphScale
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
