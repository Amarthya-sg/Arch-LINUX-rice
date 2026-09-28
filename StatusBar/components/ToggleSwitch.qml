import QtQuick
import QtQuick.Controls
import "../core"

Switch {
    id: root
    property color accent: Theme.primary
    implicitWidth: 46
    implicitHeight: 27
    indicator: Rectangle {
        implicitWidth: 46
        implicitHeight: 27
        radius: 16
        color: root.checked ? root.accent : Theme.surfaceHigh
        border.width: 1
        border.color: root.checked ? root.accent : Theme.outline
        Rectangle {
            width: 21
            height: 21
            radius: 11
            y: 3
            x: root.checked ? 22 : 3
            color: root.checked ? Theme.background : Theme.muted
            Behavior on x { NumberAnimation { duration: 140 } }
        }
    }
}
