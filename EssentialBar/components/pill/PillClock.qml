// PillClock.qml
// Clock button in the collapsed pill row.
// Displays current time; clicking it opens the calendar popup.
import QtQuick
import "../../core"

Rectangle {
    id: root

    // ── Signal ─────────────────────────────────────────────────────────────
    signal timeClicked()

    // ── Sizing ─────────────────────────────────────────────────────────────
    implicitWidth:  clockText.implicitWidth + 16
    implicitHeight: Theme.dimensionSize(28)
    radius:         Theme.radiusSize(99)

    color: clockHov.containsMouse ? Theme.surfaceRaised : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.duration(140) } }

    Text {
        id: clockText
        anchors.centerIn: parent
        text:  ShellState.time
        color: Theme.fg
        font.family:    Theme.uiFont
        font.pixelSize: Theme.fontSize(11)
        font.weight:    Theme.fontWeightSemibold
        font.features:  ({ "tnum": 1 })
    }

    MouseArea {
        id: clockHov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked: (e) => { e.accepted = true; root.timeClicked() }
    }
}
