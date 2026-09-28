pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool available: true
    property bool enabled: true
    property bool scanning: false
    property bool scanRequested: false
    property var devices: []
    readonly property var connectedDevices: devices.filter(d => d.connected)
    readonly property string status: connectedDevices.length + " connected"

    function scan(): void {
        console.log("[SAT][Bluetooth] scan requested; enabled=", enabled, "running=", scanProcess.running)
        if (scanRequested || scanProcess.running) return
        scanRequested = true
        scanning = true
        scanProcess.running = true
    }
    function stopScan(): void {
        console.log("[SAT][Bluetooth] scan stop requested")
        scanProcess.running = false
        scanRequested = false
        scanning = false
    }
    function toggle(): void {
        console.log("[SAT][Bluetooth] power toggle requested; current enabled=", enabled)
        adapterCommand.command = ["bluetoothctl", "power", enabled ? "off" : "on"]
        adapterCommand.running = true
        enabled = !enabled
    }
    function toggleDiscoverable(): void {}
    function activate(device): void {
        console.log("[SAT][Bluetooth] device action requested; name=", device?.name || "unknown", "address=", device?.address || "", "connected=", !!device?.connected, "paired=", !!device?.paired)
        if (!device) return
        deviceCommand.command = ["bluetoothctl", device.connected ? "disconnect" : (device.paired ? "connect" : "pair"), device.address]
        deviceCommand.running = true
    }
    function forget(device): void {
        console.log("[SAT][Bluetooth] forget requested; name=", device?.name || "unknown", "address=", device?.address || "")
        if (!device) return
        deviceCommand.command = ["bluetoothctl", "remove", device.address]
        deviceCommand.running = true
    }

    property Process scanProcess: Process {
        id: scanProcess
        // Power the adapter on before discovery, keep the scan active long
        // enough for slow advertisers, then merge discovered, cached, and
        // paired devices. Querying only `bluetoothctl devices` after a short
        // scan can miss a device that has just started advertising.
        command: ["bash", "-c", "set -o pipefail; bluetoothctl power on >/dev/null 2>&1 || true; bluetoothctl --timeout 20 scan on >/dev/null 2>&1 || true; { bluetoothctl devices; bluetoothctl devices Paired 2>/dev/null || true; } | awk 'NF >= 2 && $2 ~ /^[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}$/ { if (!seen[$2]++) print $2 }' | while read -r mac; do name=$(bluetoothctl info \"$mac\" 2>/dev/null | sed -n 's/^[[:space:]]*Name: //p' | head -n 1); alias=$(bluetoothctl info \"$mac\" 2>/dev/null | sed -n 's/^[[:space:]]*Alias: //p' | head -n 1); [ -n \"$name\" ] || name=\"$alias\"; [ -n \"$name\" ] || name=\"Bluetooth device\"; printf 'DEVICE|%s|%s\\n' \"$mac\" \"$name\"; bluetoothctl info \"$mac\" 2>/dev/null | grep -E 'Connected:|Paired:|Bonded:|Icon:|RSSI:' || true; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = []
                let current = null
                for (const raw of text.split("\n")) {
                    const line = raw.trim()
                    if (line.startsWith("DEVICE|")) {
                        if (current) result.push(current)
                        const p = line.split("|")
                        let deviceName = p.slice(2).join("|").trim()
                        if (!deviceName || /^\d+$/.test(deviceName)) deviceName = "Bluetooth device"
                        current = { address: p[1] || "", name: deviceName, deviceName: deviceName, paired: false, bonded: false, connected: false, icon: "" }
                        console.log("[SAT][Bluetooth] detected; name=", deviceName, "address=", p[1] || "")
                    } else if (current) {
                        if (line.startsWith("Connected:") && line.includes("yes")) current.connected = true
                        if (line.startsWith("Paired:") && line.includes("yes")) current.paired = true
                        if (line.startsWith("Bonded:") && line.includes("yes")) current.bonded = true
                        if (line.startsWith("Icon:")) current.icon = line.split(":").slice(1).join(":").trim()
                        if (line.startsWith("RSSI:")) current.rssi = line.split(":").slice(1).join(":").trim()
                    }
                }
                if (current) result.push(current)
                root.devices = result
                console.log("[SAT][Bluetooth] scan complete; detected count=", result.length)
                root.scanning = false
                root.scanRequested = false
            }
        }
        onExited: (code, status) => { console.log("[SAT][Bluetooth] scan process exited; code=", code, "status=", status); root.scanning = false; root.scanRequested = false }
    }
    property Process deviceCommand: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][Bluetooth] device command exited; code=", code, "status=", status)
            // bluetoothctl's connection state needs a moment to settle before
            // a rescan reflects it; without this the device list stays
            // stale (e.g. still "available" right after a successful pair).
            deviceCommandRescan.restart()
        }
    }
    property Timer deviceCommandRescan: Timer {
        interval: 600
        repeat: false
        onTriggered: root.scan()
    }
    property Process adapterCommand: Process {
        command: []
        onExited: (code, status) => console.log("[SAT][Bluetooth] adapter command exited; code=", code, "status=", status)
    }
}
