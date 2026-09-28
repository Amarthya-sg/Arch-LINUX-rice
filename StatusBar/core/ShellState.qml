pragma Singleton
import QtQuick

QtObject {
    property bool popupOpen: false
    property string activeTab: "wifi"
    property date now: new Date()

    readonly property string time: Qt.formatDateTime(now, "h:mm AP")

    function open(tab = "wifi"): void {
        activeTab = tab
        popupOpen = true
        now = new Date()
    }

    function toggle(): void {
        popupOpen ? popupOpen = false : open("wifi")
    }

    property Timer clockTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: ShellState.now = new Date()
    }
}
