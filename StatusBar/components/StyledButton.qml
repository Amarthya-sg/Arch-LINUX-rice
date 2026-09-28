import QtQuick
import QtQuick.Controls
import "../core"

Button {
    id: root
    property bool danger: false
    property bool compact: false
    property bool iconOnly: false
    implicitHeight: compact ? 30 : Theme.controlHeight
    implicitWidth: iconOnly ? implicitHeight : Math.max(74, contentItem.implicitWidth + 24)
    padding: iconOnly ? 0 : 10
    font.family: iconOnly ? Theme.iconFont : Theme.uiFont
    font.pixelSize: compact ? 10 : 11
    font.weight: 600
    opacity: enabled ? 1 : 0.48

    contentItem: Text {
        text: root.text
        color: root.down ? Theme.background
            : root.danger ? Theme.error
            : root.highlighted ? Theme.background : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font: root.font
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: root.iconOnly ? root.implicitHeight / 2 : Theme.controlRadius
        color: root.down ? Theme.primaryStrong
            : root.highlighted ? Theme.primary
            : root.hovered ? Theme.surfaceHover : Theme.surfaceRaised
        border.width: 1
        border.color: root.danger ? Qt.alpha(Theme.error, 0.72)
            : root.highlighted ? Theme.primary
            : root.hovered ? Theme.primaryStrong : Theme.outline
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
