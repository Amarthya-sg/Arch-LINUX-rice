pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool available: false
    property bool enabled: false
    property bool pending: false
    property int temperature: 4500
    property string errorMessage: ""
    readonly property int minimum: 2500
    readonly property int maximum: 6500
    readonly property real level: (temperature - minimum) / (maximum - minimum)
    readonly property string detail: !available ? (errorMessage || "hyprsunset unavailable")
        : pending ? "Applying…" : enabled ? temperature + "K" : "Off"

    function setTemperature(value): void {
        if (!available) return
        temperature = Math.max(minimum, Math.min(maximum, Math.round(value)))
        pending = true
 errorMessage = ""
        applyDebounce.restart()
    }
    function setEnabled(value): void {
        if (!available) return
        pending = true
 errorMessage = ""
        commandProcess.command = value
            ? ["hyprctl", "hyprsunset", "temperature", String(temperature)]
            : ["hyprctl", "hyprsunset", "identity"]
        commandProcess.running = true
        enabled = value
    }
    function toggle(): void { setEnabled(!enabled) }
    property Timer applyDebounce: Timer { id: applyDebounce
 interval: 180
 onTriggered: {
        commandProcess.command = ["hyprctl", "hyprsunset", "temperature", String(root.temperature)]
        commandProcess.running = true
 root.enabled = true
    }}
    property Process detect: Process {
        id: detect
 command: ["sh", "-c", "command -v hyprsunset >/dev/null && command -v hyprctl"]
        running: true
        onExited: (code, status) => {
            root.available = code === 0
            if (!root.available) root.errorMessage = "Install and start hyprsunset"
        }
    }
    property Process commandProcess: Process {
        id: commandProcess
 running: false
        onExited: (code, status) => {
            root.pending = false
            if (code !== 0) root.errorMessage = "hyprsunset IPC unavailable"
        }
    }
}
