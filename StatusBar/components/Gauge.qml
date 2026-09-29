// Gauge.qml — dual-mode circular gauge.
//
// Normal mode  (hero:false, default):  compact 88×92 widget used in system tab.
//   Canvas: 56×56, r=24, track stroke-width=5, progress arc accent-coloured.
//
// Hero mode    (hero:true):  large 132×132 battery hero ring used in v-batt.
//   SVG-equivalent via Canvas: 132×132, viewBox 104×104:
//     Outer dotted ring: cx=52 cy=52 r=49, stroke-opacity=0.35,
//                        stroke-width=1.5, stroke-dasharray="1 3.1"  (dots)
//     Track ring:        cx=52 cy=52 r=40, stroke-width=9,  color=Theme.line
//     Progress ring:     cx=52 cy=52 r=40, stroke-width=9,  color=accent
//                        animated by stroke-dashoffset (circumference=251.3)
//     Centre text:       font-size 34px tabular-nums  (the percentage)
//
// Both modes: value 0..1, accent colour, valueText string, label string.
import QtQuick
import "../core"

Item {
    id: root

    // ── Public API ──────────────────────────────────────────────────────
    property bool   hero:      false          // true = 132px battery hero ring
    property real   value:     0              // 0..1
    property string valueText: "0%"
    property string label:     ""
    property color  accent:    Theme.islandAccent

    // ── Sizing ──────────────────────────────────────────────────────────
    implicitWidth:  hero ? 132 : 88
    implicitHeight: hero ? 132 : (label !== "" ? 92 : 70)

    // ── Canvas ──────────────────────────────────────────────────────────
    Canvas {
        id: canvas
        anchors.top:              parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width:  root.hero ? 132 : 56
        height: root.hero ? 132 : 56

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            if (root.hero) {
                // ── Hero ring (132×132, logical viewBox 104×104 scaled) ────
                // Scale factor: canvas 132 / viewBox 104
                const scale  = 132 / 104
                const cx     = 52 * scale
                const cy     = 52 * scale
                const rDot   = 49 * scale
                const rTrack = 40 * scale
                const twTrack = 9 * scale
                const start  = -Math.PI / 2          // top
                const v      = Math.max(0, Math.min(1, root.value))
                const circ   = 2 * Math.PI * rTrack  // ≈ 241 at canvas scale

                // — Outer dotted ring —
                ctx.save()
                ctx.lineWidth   = 1.5 * scale
                ctx.globalAlpha = 0.35
                ctx.strokeStyle = Theme.muted
                ctx.setLineDash([1 * scale, 3.1 * scale])
                ctx.beginPath()
                ctx.arc(cx, cy, rDot, 0, Math.PI * 2)
                ctx.stroke()
                ctx.restore()

                // — Track ring (unfilled arc) —
                ctx.lineWidth   = twTrack
                ctx.lineCap     = "round"
                ctx.strokeStyle = Theme.line
                ctx.beginPath()
                ctx.arc(cx, cy, rTrack, 0, Math.PI * 2)
                ctx.stroke()

                // — Progress arc —
                if (v > 0) {
                    ctx.strokeStyle = root.accent
                    ctx.beginPath()
                    ctx.arc(cx, cy, rTrack, start, start + v * Math.PI * 2)
                    ctx.stroke()
                }
            } else {
                // ── Compact ring (56×56) ───────────────────────────────────
                const cx     = width  / 2
                const cy     = height / 2
                const r      = 24
                const v      = Math.max(0, Math.min(1, root.value))
                const start  = -Math.PI / 2

                // Track
                ctx.lineWidth   = 5
                ctx.lineCap     = "round"
                ctx.strokeStyle = Theme.outline
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.stroke()

                // Progress
                if (v > 0) {
                    ctx.strokeStyle = root.accent
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, start, start + v * Math.PI * 2)
                    ctx.stroke()
                }
            }
        }

        // Re-paint on any data change
        Connections {
            target: root
            function onValueChanged()  { canvas.requestPaint() }
            function onAccentChanged() { canvas.requestPaint() }
            function onHeroChanged()   { canvas.requestPaint() }
        }
        // Also repaint when theme colours change (dark/light switch)
        Connections {
            target: Theme
            function onOutlineChanged() { canvas.requestPaint() }
            function onLineChanged()    { canvas.requestPaint() }
            function onMutedChanged()   { canvas.requestPaint() }
        }
    }

    // ── Centre value text ───────────────────────────────────────────────
    Text {
        anchors.centerIn: canvas
        text:  root.valueText
        color: Theme.fg

        font.family:    Theme.uiFont
        font.pixelSize: root.hero ? 34 : 10
        font.weight:    Font.DemiBold
        // Tabular numerics (matches CSS font-variant-numeric: tabular-nums)
        font.features:  ({ "tnum": 1 })
        // Percentage sign below (hero only — rendered as separate Text)
        visible: !root.hero
    }

    // Hero mode: split "84" and "%" like the HTML <span>/<small> structure
    Text {
        visible: root.hero
        anchors.centerIn: canvas
        text: root.valueText.replace("%", "")
        color: Theme.fg
        font.family:    Theme.uiFont
        font.pixelSize: 34
        font.weight:    Font.DemiBold
        font.features:  ({ "tnum": 1 })
        font.letterSpacing: -1
    }
    Text {
        visible: root.hero
        anchors.horizontalCenter: canvas.horizontalCenter
        anchors.verticalCenter:   canvas.verticalCenter
        anchors.verticalCenterOffset: 18   // sits below the main number
        text: "%"
        color: Theme.muted
        font.family:    Theme.uiFont
        font.pixelSize: 13
        font.weight:    Font.Medium
    }

    // ── Bottom label (compact mode only) ───────────────────────────────
    Text {
        visible: !root.hero && root.label !== ""
        anchors.top:              canvas.bottom
        anchors.topMargin:        7
        anchors.horizontalCenter: parent.horizontalCenter
        text:  root.label
        color: Theme.muted
        font.family:    Theme.uiFont
        font.pixelSize: 10
    }
}
