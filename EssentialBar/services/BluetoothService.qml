pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"

QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: !!adapter
    readonly property bool enabled: adapter ? adapter.enabled : false
    readonly property bool scanning: adapter ? adapter.discovering : false
    property bool autoPairEnabled: false
    property var devices: []
    property var wantedConnections: ({})
    property var pairingJobs: ({})
    property bool hardwareBlocked: false
    property string errorMessage: ""
    // Device waiting for discovery to fully stop before connect() is issued
    property var pendingConnect: null
    // Device waiting for the post-bonding link to settle before connect()
    property var pendingPostPairConnect: null
    // address -> time of last successful pair; used to hold the row on
    // "Connecting…" while BlueZ/the phone flap the link after bonding.
    property var postPairAt: ({})
    // Pair requests are handled by our own BlueZ Agent1 so confirmations can
    // be rendered inline in BtView instead of in the desktop notification UI.
    property bool pairingAgentReady: false
    property bool pairingOperationBusy: false
    property string pairingAddress: ""
    property string queuedPairAddress: ""
    property string queuedPairPath: ""
    property var pairingPrompt: null
    readonly property var connectedDevices: devices.filter(device => root.value(device, "connected"))
    readonly property string status: !available ? "Bluetooth unavailable"
        : !enabled ? "Bluetooth off"
        : connectedDevices.length > 0 ? connectedDevices.length + " connected"
        : devices.length + " known device" + (devices.length === 1 ? "" : "s")

    readonly property var defaults: ({
        address: "", name: "", deviceName: "", icon: "", connected: false,
        paired: false, pairing: false, batteryAvailable: false, battery: 0, state: 0
    })

    // Retry logic stays quiet for this long after a successful pair so the
    // first connect can finish and a brief post-bonding drop is not "fixed"
    // by a second competing connect().
    readonly property int postPairGraceMs: 6000

    function value(device, key) {
        try {
            const v = device ? device[key] : undefined
            return v === undefined || v === null ? defaults[key] : v
        } catch (error) {
            return defaults[key]
        }
    }

    function isAddress(value): bool {
        return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(String(value || ""))
    }

    function displayName(device): string {
        const name = String(value(device, "name") || value(device, "deviceName") || "")
        return name && !isAddress(name) ? name : ""
    }

    function deviceStatus(device): string {
        const address = String(value(device, "address") || "")
        const job = pairingJobs[address]
        if (value(device, "pairing") || job?.state === "pairing") return "Pairing…"
        if (value(device, "state") === BluetoothDeviceState.Connecting) return "Connecting…"
        if (value(device, "state") === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (value(device, "connected")) return "Connected"
        if (value(device, "paired")) return "Paired"
        return "Not paired"
    }

    function refreshDevices(): void {
        if (!adapter) {
            devices = []
            return
        }
        const all = adapter.devices?.values || []
        devices = all.filter(device => value(device, "paired") || value(device, "connected")
            || displayName(device) !== "")
            .sort((a, b) => Number(value(b, "connected")) - Number(value(a, "connected"))
                || Number(value(b, "paired")) - Number(value(a, "paired"))
                || displayName(a).localeCompare(displayName(b)))
    }

    function scan(): void {
        if (!adapter || !adapter.enabled) return
        adapter.discovering = true
        scanStop.restart()
        refreshDevices()
    }

    function stopScan(): void {
        if (adapter && adapter.discovering) adapter.discovering = false
        scanStop.stop()
        refreshDevices()
    }

    function toggleScan(): void {
        if (scanning) stopScan()
        else scan()
    }

    function toggle(): void {
        setPower(!enabled)
    }

    function setPower(on): void {
        if (!adapter) {
            errorMessage = "No Bluetooth adapter found"
            return
        }
        errorMessage = ""
        if (!on) {
            connectDelay.stop()
            postPairConnectDelay.stop()
            pairStartDelay.stop()
            pendingConnect = null
            pendingPostPairConnect = null
            stopScan()
            adapter.enabled = false
            return
        }
        hardwareBlocked = false
        rfkillCheck.command = ["rfkill", "-n", "-o", "SOFT,HARD", "list", "bluetooth"]
        rfkillCheck.running = true
    }

    function deviceForPath(path) {
        const all = adapter?.devices?.values || []
        return all.find(device => String(value(device, "dbusPath") || "") === String(path)) || null
    }

    function writePairingAgent(message): void {
        if (!pairingAgentProcess.running) return
        pairingAgentProcess.write(JSON.stringify(message) + "\n")
    }

    function startQueuedPair(): void {
        if (!pairingAgentReady || !queuedPairPath || !queuedPairAddress) return
        writePairingAgent({ type: "pair", devicePath: queuedPairPath, address: queuedPairAddress })
        queuedPairPath = ""
        queuedPairAddress = ""
    }

    function handlePairingAgentMessage(line): void {
        let message
        try { message = JSON.parse(String(line)) }
        catch (error) { console.warn("[Bluetooth] invalid pairing-agent message:", line); return }
        if (message.type === "ready") {
            pairingAgentReady = true
            // Discovery was already stopped in runPair(); wait for it to settle.
            pairStartDelay.restart()
        } else if (message.type === "prompt") {
            const device = deviceForPath(message.devicePath)
            pairingPrompt = {
                requestId: String(message.requestId || ""),
                kind: String(message.kind || "confirmation"),
                passkey: String(message.passkey || ""),
                service: String(message.service || ""),
                address: String(value(device, "address") || ""),
                deviceName: displayName(device) || String(value(device, "address") || "Bluetooth device"),
                requiresDecision: true
            }
        } else if (message.type === "display") {
            const device = deviceForPath(message.devicePath)
            pairingPrompt = {
                requestId: "", kind: "display", displayKind: String(message.kind || "passkey"),
                passkey: String(message.passkey || ""), entered: Number(message.entered || 0),
                address: String(value(device, "address") || ""),
                deviceName: displayName(device) || String(value(device, "address") || "Bluetooth device"),
                requiresDecision: false
            }
        } else if (message.type === "prompt_cancelled") {
            if (pairingPrompt && pairingPrompt.requestId === String(message.requestId || ""))
                pairingPrompt = null
        } else if (message.type === "pair_result") {
            pairingOperationBusy = false
            pairingAddress = ""
            pairingPrompt = null
            const address = String(message.address || "")
            const jobs = Object.assign({}, pairingJobs)
            jobs[address] = { state: message.success ? "done" : "failed", started: Date.now() }
            pairingJobs = jobs
            if (message.success) {
                stopScan()
                const wanted = Object.assign({}, wantedConnections)
                // Grace period: retry logic must not race the first connect.
                wanted[address] = { tries: 0, since: Date.now() + postPairGraceMs }
                wantedConnections = wanted
                const stamps = Object.assign({}, postPairAt)
                stamps[address] = Date.now()
                postPairAt = stamps
                const device = deviceForPath(message.devicePath)
                if (device) {
                    device.trusted = true
                    console.warn("[Bluetooth] pair ok; connecting", address)
                    // Quickshell's device.connect() refuses ("already connected")
                    // while the pairing link is up, so Device1.Connect() is never
                    // sent and BlueZ drops the idle link. Call BlueZ directly.
                    const path = String(value(device, "dbusPath") || "")
                    if (path && !postPairConnectProc.running) {
                        postPairConnectProc.address = address
                        postPairConnectProc.command = ["busctl", "--system", "call",
                            "org.bluez", path, "org.bluez.Device1", "Connect"]
                        postPairConnectProc.running = true
                    }
                } else {
                    console.warn("[Bluetooth] pair ok but device not found for", message.devicePath)
                }
                errorMessage = String(message.warning || "")
            } else {
                errorMessage = String(message.error || "Bluetooth pairing failed")
            }
            refreshDevices()
        } else if (message.type === "error") {
            pairingAgentReady = false
            errorMessage = String(message.message || "Could not start the Bluetooth pairing agent")
        } else if (message.type === "agent_released") {
            pairingAgentReady = false
        }
    }

    function respondToPairingPrompt(accepted, value = ""): void {
        if (!pairingPrompt || !pairingPrompt.requiresDecision) return
        writePairingAgent({ type: "reply", requestId: pairingPrompt.requestId,
                            accepted: Boolean(accepted), value: String(value) })
        pairingPrompt = null
    }

    // Queue until the helper has registered its application-scoped BlueZ
    // Agent1. Device1.Pair() is called by that same D-Bus client, so BlueZ
    // delivers passkey confirmation to this UI rather than a desktop popup.
    function runPair(address, device): void {
        if (!isAddress(address) || pairingOperationBusy) return
        const devicePath = String(value(device, "dbusPath") || "")
        if (!devicePath) {
            errorMessage = "Could not identify the Bluetooth device for pairing"
            return
        }
        pairingOperationBusy = true
        pairingAddress = address
        queuedPairAddress = address
        queuedPairPath = devicePath
        // Pairing while inquiry is active makes some controllers drop the
        // link, so stop discovery first and let it actually stop.
        stopScan()
        if (!pairingAgentProcess.running) pairingAgentProcess.running = true
        pairStartDelay.restart()
    }

    function pair(device): void {
        if (!device || !value(device, "address")) return
        if (pairingOperationBusy) return
        const address = String(value(device, "address"))
        const jobs = Object.assign({}, pairingJobs)
        jobs[address] = { state: "pairing", started: Date.now() }
        pairingJobs = jobs
        errorMessage = ""
        runPair(address, device)
        refreshDevices()
    }

    function activate(device): void {
        if (!device) return
        if (!value(device, "paired")) {
            pair(device)
            return
        }
        // Remember whether discovery was running: connecting while inquiry is
        // still active makes some controllers drop the link.
        const wasScanning = scanning
        stopScan()
        const address = String(value(device, "address"))
        if (value(device, "state") === BluetoothDeviceState.Connecting
                || value(device, "state") === BluetoothDeviceState.Disconnecting
                || value(device, "pairing")) return
        const wanted = Object.assign({}, wantedConnections)
        if (value(device, "connected")) {
            delete wanted[address]
            wantedConnections = wanted
            connectDelay.stop()
            postPairConnectDelay.stop()
            pendingConnect = null
            pendingPostPairConnect = null
            device.disconnect()
        } else {
            device.trusted = true
            wanted[address] = { tries: 0, since: 0 }
            wantedConnections = wanted
            if (wasScanning) {
                pendingConnect = device
                connectDelay.restart()      // let discovery actually stop first
            } else {
                device.connect()
            }
        }
        refreshDevices()
    }

    function forget(device): void {
        if (!device) return
        const address = String(value(device, "address"))
        const wanted = Object.assign({}, wantedConnections)
        delete wanted[address]
        wantedConnections = wanted
        if (pendingConnect && String(value(pendingConnect, "address")) === address) {
            connectDelay.stop()
            pendingConnect = null
        }
        if (pendingPostPairConnect && String(value(pendingPostPairConnect, "address")) === address) {
            postPairConnectDelay.stop()
            pendingPostPairConnect = null
        }
        // device.forget() fails with "Resource Not Ready" while the link is up,
        // so disconnect and remove through bluetoothctl instead.
        if (isAddress(address) && !removeProc.running) {
            const jobs = Object.assign({}, pairingJobs)
            delete jobs[address]
            pairingJobs = jobs
            removeProc.address = address
            removeProc.command = ["sh", "-c",
                'bluetoothctl disconnect "$1" >/dev/null 2>&1; bluetoothctl remove "$1"',
                "sh", address]
            removeProc.running = true
        } else {
            device.forget()
        }
        refreshDevices()
    }

    function toggleAutoPair(): void {
        autoPairEnabled = !autoPairEnabled
    }

    function autoPairEligible(device): bool {
        const icon = String(value(device, "icon") || "")
        const address = String(value(device, "address") || "00")
        // Do not automatically pair randomized LE addresses (e.g. trackers/watches).
        if ((parseInt(address.substring(0, 2), 16) & 0x02) !== 0) return false
        return icon.indexOf("audio-") === 0 || icon.indexOf("input-") === 0
    }

    // True while pairing, reconnecting, or scanning; otherwise housekeeping
    // only needs a slow tick.
    property bool housekeepingBusy: false

    function housekeeping(): void {
        if (!adapter) return
        let busy = adapter.discovering || pairingOperationBusy
        refreshDevices()
        const all = adapter.devices?.values || []
        let pairingInProgress = pairingOperationBusy
            || Object.keys(pairingJobs).some(key => pairingJobs[key].state === "pairing")
        const updatedJobs = Object.assign({}, pairingJobs)
        const updatedWanted = Object.assign({}, wantedConnections)

        for (const device of all) {
            const address = String(value(device, "address") || "")
            if (!address) continue
            const job = updatedJobs[address]
            const name = displayName(device) || address
            if (job?.state === "pairing" || job?.state === "paired") busy = true
            if (job?.state === "pairing") {
                if (value(device, "paired")) {
                    updatedJobs[address] = { state: "paired", started: Date.now() }
                    device.trusted = true
                    // If the link drops later, the retry logic below reconnects,
                    // but only after the post-pair grace period.
                    updatedWanted[address] = { tries: 0, since: Date.now() + postPairGraceMs }
                    // The registered agent's Pair() call completes first; the
                    // result handler then connects this newly trusted device.
                } else if (!pairingOperationBusy && !value(device, "pairing")
                           && Date.now() - job.started > 8000) {
                    updatedJobs[address] = { state: "failed", started: Date.now() }
                    errorMessage = "Pairing with " + name + " failed"
                }
            } else if (job?.state === "paired") {
                if (value(device, "connected")) updatedJobs[address] = { state: "done", started: Date.now() }
                else if (value(device, "state") !== BluetoothDeviceState.Connecting
                         && Date.now() - job.started > 5000) {
                    updatedJobs[address] = { state: "done", started: Date.now() }
                }
            } else if (!job && !pairingInProgress && autoPairEnabled && adapter.discovering
                       && !value(device, "paired") && !value(device, "pairing")
                       && displayName(device) && autoPairEligible(device)) {
                pairingInProgress = true
                updatedJobs[address] = { state: "pairing", started: Date.now() }
                runPair(address, device)
            }

            const wanted = updatedWanted[address]
            if (!wanted) continue
            if (value(device, "connected")) {
                updatedWanted[address] = { tries: 0, since: 0 }
                continue
            }
            busy = true   // wanted but not connected: keep retry timing accurate
            if (value(device, "state") === BluetoothDeviceState.Connecting || value(device, "pairing")) continue
            if (pairingOperationBusy && pairingAddress === address) continue
            if (pendingPostPairConnect
                    && String(value(pendingPostPairConnect, "address")) === address) continue
            if (!wanted.since) {
                updatedWanted[address] = { tries: wanted.tries, since: Date.now() }
                continue
            }
            if (Date.now() - wanted.since < 4000) continue
            if (wanted.tries < 3) {
                const tries = wanted.tries + 1
                updatedWanted[address] = { tries: tries, since: Date.now() }
                device.connect()
            } else {
                delete updatedWanted[address]
                errorMessage = "Couldn't keep " + name + " connected; reconnect manually"
            }
        }
        pairingJobs = updatedJobs
        wantedConnections = updatedWanted
        housekeepingBusy = busy
    }

    property Process removeProc: Process {
        property string address: ""
        command: []
        onExited: (code, status) => {
            if (code !== 0) root.errorMessage = "Could not remove device (bluetoothctl exit " + code + ")"
            root.refreshDevices()
        }
    }
    property Process pairingAgentProcess: Process {
        id: pairingAgentProcess
        command: ["python3", Quickshell.shellPath("services/bluetooth_agent.py")]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: line => root.handlePairingAgentMessage(line)
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("[Bluetooth agent]", text.trim())
        }
        onExited: (code, status) => {
            root.pairingAgentReady = false
            if (root.pairingOperationBusy) {
                const jobs = Object.assign({}, root.pairingJobs)
                jobs[root.pairingAddress] = { state: "failed", started: Date.now() }
                root.pairingJobs = jobs
                root.pairingOperationBusy = false
                root.pairingAddress = ""
                root.queuedPairAddress = ""
                root.queuedPairPath = ""
                root.pairingPrompt = null
                root.errorMessage = code === 0 ? "Bluetooth pairing agent stopped"
                    : "Bluetooth pairing agent exited (code " + code + ")"
            }
        }
    }
    property Process postPairConnectProc: Process {
        property string address: ""
        command: []
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("[Bluetooth] post-pair Connect:", text.trim())
        }
        onExited: (code, status) => {
            console.warn("[Bluetooth] post-pair Connect exited", code, "for", address)
            root.refreshDevices()
        }
    }
    property Timer scanStop: Timer {
        interval: 60000
        repeat: false
        onTriggered: if (root.adapter && root.adapter.discovering) root.adapter.discovering = false
    }
    // Lets discovery actually stop before Device1.Pair() is issued.
    property Timer pairStartDelay: Timer {
        interval: 600
        repeat: false
        onTriggered: root.startQueuedPair()
    }
    property Timer connectDelay: Timer {
        interval: 800
        repeat: false
        onTriggered: {
            const d = root.pendingConnect
            root.pendingConnect = null
            if (d && root.value(d, "state") !== BluetoothDeviceState.Connecting)
                d.connect()
        }
    }
    // Lets the link settle after bonding before the first connect().
    property Timer postPairConnectDelay: Timer {
        interval: 300
        repeat: false
        onTriggered: {
            const d = root.pendingPostPairConnect
            root.pendingPostPairConnect = null
            // Connect even if the link is already up: Device1.Connect() is what
            // brings up the profiles. Skipping it leaves an idle post-pairing
            // link that BlueZ drops a few seconds later.
            if (d && root.value(d, "state") !== BluetoothDeviceState.Connecting)
                d.connect()
        }
    }
    property Timer deviceTimer: Timer {
        interval: (ShellState.popupOpen || root.housekeepingBusy) ? 1000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.housekeeping()
    }
    property Connections popupWatch: Connections {
        target: ShellState
        function onPopupOpenChanged() { if (ShellState.popupOpen) root.housekeeping() }
    }
    property Timer powerEnableTimer: Timer {
        interval: 700
        repeat: false
        onTriggered: if (root.adapter) root.adapter.enabled = true
    }
    property Process rfkillCheck: Process {
        command: []
        stdout: StdioCollector {
            onStreamFinished: root.hardwareBlocked = text.split("\n").some(line =>
                line.trim().split(/\s+/)[1] === "blocked")
        }
        onExited: (code, status) => {
            if (root.hardwareBlocked) {
                root.errorMessage = "Bluetooth is hard-blocked by a hardware switch or firmware"
                return
            }
            if (code !== 0) {
                root.powerEnableTimer.restart()
                return
            }
            rfkillUnblock.command = ["rfkill", "unblock", "bluetooth"]
            rfkillUnblock.running = true
        }
    }
    property Process rfkillUnblock: Process {
        command: []
        onExited: (code, status) => {
            if (code !== 0) root.errorMessage = "Could not unblock Bluetooth"
            root.powerEnableTimer.restart()
        }
    }

    onAdapterChanged: refreshDevices()
}
