pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool numLock: false
    property bool capsLock: false

    property string numPath: ""
    property string capsPath: ""

    // One-time discovery of the LED files. The 1 s poll below then reads them
    // in-process (FileView) instead of spawning sh + cat + grep every second.
    property Process discover: Process {
        running: true
        command: ["sh", "-c",
            "for f in /sys/class/leds/*numlock/brightness; do [ -e \"$f\" ] && echo \"N $f\" && break; done; " +
            "for f in /sys/class/leds/*capslock/brightness; do [ -e \"$f\" ] && echo \"C $f\" && break; done; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    if (line.startsWith("N ")) root.numPath = line.slice(2).trim()
                    else if (line.startsWith("C ")) root.capsPath = line.slice(2).trim()
                }
            }
        }
    }

    property FileView numFile: FileView {
        path: root.numPath
        onLoaded: root.numLock = text().trim() === "1"
    }
    property FileView capsFile: FileView {
        path: root.capsPath
        onLoaded: root.capsLock = text().trim() === "1"
    }

    property Timer poll: Timer {
        interval: 1000
        running: root.numPath !== "" || root.capsPath !== ""
        repeat: true
        onTriggered: {
            if (root.numPath !== "")  root.numFile.reload()
            if (root.capsPath !== "") root.capsFile.reload()
        }
    }
}
