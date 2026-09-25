import QtQuick

Rectangle {
    id: root
    property bool checked: false
    property color onColor:  "#30d158"
    property color offColor: "#2c2c2e"
    signal toggled()

    implicitWidth: 46
    implicitHeight: 26
    radius: height / 2
    color: checked ? onColor : offColor
    Behavior on color { ColorAnimation { duration: 160 } }

    Rectangle {
        width: 22; height: 22; radius: 11
        color: "#fff"
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - 24 : 2
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.checked = !root.checked; root.toggled() }
    }
}
