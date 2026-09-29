// LevelSlider.qml: smooth port of input[type=range] from the HTML prototype.
//
// API:
//   value      - 0..1 current level
//   valueEdited(v) - emitted on user interaction
//   title      - optional leading label text (shown above row when set)
//   valueLabel - formatted string shown at the right, e.g. "68%"
//   accent     - filled-track colour (defaults to Theme.fg)
import QtQuick
import QtQuick.Controls
import "../core"

Item {
    id: root

    // ── Public API ──────────────────────────────────────────────────────
    property string title:      ""
    property string valueLabel: ""
    property real   value:      0        // 0..1
    property color  accent:     Theme.fg

    signal valueEdited(real value)

    implicitWidth:  200
    implicitHeight: title !== "" ? 44 : 24

    // ── Local display state ─────────────────────────────────────────────
    // What is actually drawn. Follows `value`, except while dragging,
    // when it follows the cursor immediately (no backend round trip).
    property real shown: 0
    readonly property bool dragging: dragArea.pressed
    readonly property real thumbSize: 14

    Component.onCompleted: shown = value
    onValueChanged: if (!dragging) shown = value
    onDraggingChanged: if (!dragging) shown = value

    // Short trailing while dragging, longer ease for external changes
    Behavior on shown {
        NumberAnimation {
            duration: root.dragging ? 60 : 200
            easing.type: Easing.OutCubic
        }
    }

    // ── Optional title row ──────────────────────────────────────────────
    Item {
        id: titleRow
        visible: root.title !== ""
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height: 16

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text:  root.title
            color: Theme.fg
            font.family:    Theme.uiFont
            font.pixelSize: 12
            font.weight:    Font.Medium
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:  root.valueLabel
            color: root.accent
            font.family:    Theme.uiFont
            font.pixelSize: 12
            font.weight:    Font.DemiBold
        }
    }

    // ── Slider row ──────────────────────────────────────────────────────
    Item {
        id: sliderRow
        anchors.top:       root.title !== "" ? titleRow.bottom : parent.top
        anchors.topMargin: root.title !== "" ? 4 : 0
        anchors.left:      parent.left
        anchors.right:     parent.right
        anchors.bottom:    parent.bottom

        // Track (unfilled)
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            anchors.left:  parent.left
            anchors.right: parent.right
            height: 3
            radius: 9
            color:  Theme.line

            // Filled portion, ends at the thumb's center
            Rectangle {
                anchors.left:   parent.left
                anchors.top:    parent.top
                anchors.bottom: parent.bottom
                width:  Math.max(0, Math.min(1, root.shown))
                        * (track.width - root.thumbSize) + root.thumbSize / 2
                radius: parent.radius
                color:  root.accent
            }
        }

        // Thumb
        Rectangle {
            id: thumb
            width:  root.thumbSize
            height: root.thumbSize
            radius: width / 2
            color:  Theme.fg
            anchors.verticalCenter: track.verticalCenter
            x: Math.max(0, Math.min(1, root.shown)) * (track.width - width)
        }

        // Hit area (full row height for easy dragging)
        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            // Inverse of the thumb mapping, so the thumb stays under the cursor
            function posToValue(mx) {
                const v = (mx - root.thumbSize / 2) / (track.width - root.thumbSize)
                return Math.max(0, Math.min(1, v))
            }

            function update(mx) {
                const v = posToValue(mx)
                root.shown = v          // instant local feedback
                root.valueEdited(v)     // tell the backend
            }

            onPressed: (mouse) => update(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) update(mouse.x) }
        }
    }
}
