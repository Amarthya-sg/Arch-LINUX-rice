import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"

ColumnLayout {
    id: root

    property real value: 0
    property bool supported: false
    signal valueEdited(real value)

    spacing: Theme.spacingSize(3)
    opacity: supported ? Theme.opacityValue(1) : Theme.opacityValue(0.48)

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSize(6)

        Label {
            text: "Left"
            color: Theme.text
            font.family: Theme.uiFont
            font.pixelSize: Theme.fontSize(9)
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: Theme.muted
            font.family: Theme.uiFont
            font.pixelSize: Theme.fontSize(9)
            text: !root.supported ? "Stereo balance unavailable"
                : Math.abs(root.value) < 0.005 ? "Center"
                : (root.value < 0 ? "Left " : "Right ") + Math.round(Math.abs(root.value) * 100) + "%"
        }
        Label {
            text: "Right"
            color: Theme.text
            font.family: Theme.uiFont
            font.pixelSize: Theme.fontSize(9)
        }
    }

    Item {
        id: track
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.dimensionSize(24)

        readonly property real normalized: Math.max(0, Math.min(1, (root.value + 1) / 2))
        readonly property real handleSize: 16
        readonly property real handleCenter: handle.x + handle.width / 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Theme.dimensionSize(5)
            radius: Theme.radiusSize(3)
            color: Theme.surfaceRaised
            border.width: Theme.dimensionSize(1)
            border.color: Theme.outline
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: Math.min(parent.width / 2, track.handleCenter)
            width: Math.abs(track.handleCenter - parent.width / 2)
            height: Theme.dimensionSize(5)
            radius: Theme.radiusSize(3)
            color: Theme.islandAccent
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width / 2 - 1
            width: Theme.dimensionSize(2)
            height: Theme.dimensionSize(14)
            color: Theme.mutedDim
        }
        Rectangle {
            id: handle
            x: track.normalized * (track.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: track.handleSize
            height: track.handleSize
            radius: width / 2
            color: Theme.background
            border.width: Theme.dimensionSize(3)
            border.color: Theme.islandAccent
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.supported
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            function setFrom(x): void {
                const p = Math.max(0, Math.min(1, (x - track.handleSize / 2) / (track.width - track.handleSize)))
                let next = p * 2 - 1
                if (Math.abs(next) < 0.04) next = 0
                root.valueEdited(next)
            }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
            onDoubleClicked: {
                root.valueEdited(0)
            }
        }
    }
}
