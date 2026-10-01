pragma Singleton
import QtQuick
import Quickshell.Io
import "../core"

QtObject {
    id: root
    Component.onCompleted: query.running = true   // one initial read

    property bool available: false
    property int percent: 0
    property string errorMessage: ""
    readonly property real level: percent / 100

    function parse(text): void {
        const match = /(\d+)%/.exec(text)
        if (!match) { available = false
 errorMessage = "Could not read brightness"
 return }
        percent = Math.max(0, Math.min(100, Number(match[1])))
        available = true
 errorMessage = ""
    }
    function set(value): void {
        if (!available) return
        setProcess.command = ["brightnessctl", "set", Math.round(Math.max(1, Math.min(100, value))) + "%"]
        setProcess.running = true
    }
    property Timer refreshTimer: Timer { interval: 3000
 running: ShellState.popupOpen
 repeat: true
 triggeredOnStart: true
 onTriggered: query.running = true }
    property Process query: Process {
        id: query
 command: ["brightnessctl", "-m"]
 running: false
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        onExited: (code, status) => { if (code !== 0) { root.available = false
 root.errorMessage = "brightnessctl unavailable" } }
    }
    property Process setProcess: Process {
 running: false
 onExited: query.running = true }
}
