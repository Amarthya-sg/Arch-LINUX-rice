pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // True while the shell holds a systemd inhibitor against idle and sleep.
    property bool active: false
    readonly property bool enabled: active

    function toggle(): void {
        root.setActive(!root.active)
    }

    function setActive(value): void {
        root.active = Boolean(value)
    }

    // The child process holds the block inhibitor until active is cleared.
    property Process inhibitor: Process {
        command: ["systemd-inhibit", "--what=idle:sleep",
                  "--who=quickshell", "--why=Caffeine mode",
                  "--mode=block", "sleep", "infinity"]
        running: root.active
        onExited: (code, status) => {
            if (root.active) {
                root.active = false
                console.warn("[Caffeine] systemd inhibitor exited; code=", code, "status=", status)
            }
        }
    }
}
