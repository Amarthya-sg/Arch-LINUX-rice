import QtQuick
import QtQuick.Controls
import "../core"

Button {
    id: root
    property bool danger: false
    property bool compact: false
    property bool iconOnly: false
    property string iconName: ""
    property string iconTone: "fg"
    implicitHeight: compact ? 30 : Theme.controlHeight
    implicitWidth: iconOnly ? implicitHeight : Math.max(74, contentItem.implicitWidth + 24)
    padding: iconOnly ? 0 : 10
    font.family: Theme.uiFont
    font.pixelSize: Theme.fontSize(compact ? 10 : 11)
    font.weight: Theme.fontWeightSemibold
    opacity: enabled ? Theme.opacityValue(1) : Theme.opacityValue(0.48)

    contentItem: Item {
        implicitWidth: root.iconName !== "" ? 16 : buttonLabel.implicitWidth
        implicitHeight: root.iconName !== "" ? 16 : buttonLabel.implicitHeight
        SvgIcon {
            anchors.centerIn: parent
            visible: root.iconName !== ""
            width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
            iconName: root.iconName
            tone: root.down || root.highlighted ? "ink" : root.danger ? "error" : root.iconTone
        }
        Text {
            id: buttonLabel
            anchors.fill: parent
            visible: root.iconName === ""
            text: root.text
            color: root.down ? Theme.background
                : root.danger ? Theme.error
                : root.highlighted ? Theme.background : Theme.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font: root.font
            elide: Text.ElideRight
        }
    }

    background: Rectangle {
        radius: root.iconOnly ? root.implicitHeight / 2 : Theme.controlRadius
        color: root.down ? Theme.primaryStrong
            : root.highlighted ? Theme.primary
            : root.hovered ? Theme.surfaceHover : Theme.surfaceRaised
        border.width: Theme.dimensionSize(1)
        border.color: root.danger ? Qt.alpha(Theme.error, 0.72)
            : root.highlighted ? Theme.primary
            : root.hovered ? Theme.primaryStrong : Theme.outline
        Behavior on color { ColorAnimation { duration: Theme.duration(120) } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration(120) } }
    }
}
