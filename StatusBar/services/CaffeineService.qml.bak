pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool enabled: inhibitor.running
    property Process inhibitor: Process {
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=Odyssey", "--why=Keep awake", "sleep", "infinity"]
        running: false
    }

    function toggle(): void {
        inhibitor.running = !inhibitor.running
    }
}
