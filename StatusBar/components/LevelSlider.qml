import QtQuick
import QtQuick.Controls
import "../core"

Column {
    id: root
    property string title: ""
    property string valueLabel: ""
    property real value: 0
    property color accent: Theme.primary
    signal valueEdited(real value)
    spacing: 8

    Row {
        width: parent.width
        spacing: 8
        Label {
            id: titleLabel
            text: root.title
            color: Theme.text
            font.family: Theme.uiFont
            font.pixelSize: 13
            font.weight: 600
        }
        Item { width: parent.width - titleLabel.width - valueLabelItem.width - 16 }
        Label {
            id: valueLabelItem
            text: root.valueLabel
            color: root.accent
            font.family: Theme.iconFont
            font.pixelSize: 11
            font.weight: 600
        }
    }

    Slider {
        id: slider
        width: parent.width
        height: 30
        implicitHeight: 30
        from: 0
        to: 1
        value: root.value
        onMoved: root.valueEdited(value)
        background: Rectangle {
            x: 0
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 7
            radius: 4
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.outline
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accent
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition
                * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 18
            height: 18
            radius: 9
            color: Theme.background
            border.width: 3
            border.color: root.accent
        }
    }
}
