pragma Singleton
import QtQuick
import Quickshell.Io

// Location is a permission gate: it runs the GeoClue demo agent so GeoClue
// can obtain a desktop authorization. It does not start/stop geoclue.service.
QtObject {
    id: root

    property bool enabled: agent.running
    readonly property bool permissionGranted: enabled
    readonly property bool available: true

    function toggle(): void {
        if (agent.running) {
            agent.running = false
            return
        }
        agent.running = true
    }

    property Process agent: Process {
        id: agent
        command: ["sh", "-c", "for p in /usr/lib/geoclue-2.0/demos/agent /usr/libexec/geoclue-2.0/demos/agent; do if [ -x \"$p\" ]; then exec \"$p\"; fi; done; exit 127"]
        running: false
    }
}
