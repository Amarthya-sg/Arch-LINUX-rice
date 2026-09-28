import QtQuick
import "../core"

Item {
    id: root
    property string label: ""
    property string valueText: "0%"
    property real value: 0
    property color accent: Theme.islandAccent
    implicitWidth: 88
    implicitHeight: 92

    Canvas {
        id: canvas
        width: 56
        height: 56
        anchors.horizontalCenter: parent.horizontalCenter
        onPaint: {
            const ctx = getContext("2d")
            const cx = width / 2
            const cy = height / 2
            const r = 24
            ctx.reset()
            ctx.lineWidth = 5
            ctx.lineCap = "round"
            ctx.strokeStyle = Theme.outline
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI * 1.5)
            ctx.stroke()
            ctx.strokeStyle = root.accent
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2,
                -Math.PI / 2 + Math.max(0, Math.min(1, root.value)) * Math.PI * 2)
            ctx.stroke()
        }
        Connections {
            target: root
            function onValueChanged(): void { canvas.requestPaint() }
            function onAccentChanged(): void { canvas.requestPaint() }
        }
    }
    Text {
        anchors.centerIn: canvas
        text: root.valueText
        color: Theme.text
        font.family: Theme.iconFont
        font.pixelSize: 10
        font.weight: 600
    }
    Text {
        anchors.top: canvas.bottom
        anchors.topMargin: 7
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        color: Theme.muted
        font.family: Theme.iconFont
        font.pixelSize: 10
    }
}
