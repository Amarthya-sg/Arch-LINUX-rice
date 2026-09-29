pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool numLock: false
    property bool capsLock: false

    property Process reader: Process {
        command: ["sh", "-c",
            "cat /sys/class/leds/*numlock/brightness 2>/dev/null | grep -q 1 && echo N; " +
            "cat /sys/class/leds/*capslock/brightness 2>/dev/null | grep -q 1 && echo C; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.numLock = text.indexOf("N") !== -1
                root.capsLock = text.indexOf("C") !== -1
            }
        }
    }

    property Timer poll: Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.reader.running) root.reader.running = true
    }
}
