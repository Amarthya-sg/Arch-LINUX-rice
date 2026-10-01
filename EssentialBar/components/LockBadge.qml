import QtQuick
import "../core"

Rectangle {
    id: root
    property bool active: false
    property string label: "123"

    visible: active
    implicitWidth: badgeText.implicitWidth + 10
    implicitHeight: Theme.dimensionSize(16)
    radius: Theme.radiusSize(5)
    color: Qt.rgba(Theme.acc.r, Theme.acc.g, Theme.acc.b, Theme.opacityValue(0.18))

    Text {
        id: badgeText
        anchors.centerIn: parent
        text: root.label
        color: Theme.acc
        font.family: Theme.uiFont
        font.pixelSize: Theme.fontSize(9)
        font.weight: Theme.fontWeightSemibold
    }
}
