pragma Singleton
import QtQuick
import Quickshell.Networking
import Quickshell.Io

QtObject {
    id: root

    readonly property bool available: Networking.backend !== NetworkBackendType.None
    readonly property var devices: Networking.devices.values
    readonly property var wifiDevices: devices.filter(d => d.type === DeviceType.Wifi)
    readonly property var wifiDevice: wifiDevices.find(d => d.connected) || wifiDevices[0] || null
    readonly property bool wifiEnabled: available && Networking.wifiEnabled
    property bool scanning: false
    property var scannedNetworks: []
    readonly property var networks: scannedNetworks.length > 0 ? scannedNetworks
        : (wifiDevice?.networks?.values || [])
    readonly property var savedNetworks: networks.filter(n => n.known)
    readonly property var activeNetwork: networks.find(n => n.connected) || null
    readonly property bool connected: !!activeNetwork
        || Networking.connectivity === NetworkConnectivity.Full
        || Networking.connectivity === NetworkConnectivity.Limited
        || Networking.connectivity === NetworkConnectivity.Portal
    readonly property bool captivePortal: Networking.connectivity === NetworkConnectivity.Portal
    readonly property string ssid: activeNetwork?.name || activeNetwork?.ssid || ""
    readonly property int signalPercent: activeNetwork
        ? Math.round(Number(activeNetwork.signalStrength || activeNetwork.signal || 0) * 100) : 0
    readonly property string status: !available ? "Network backend unavailable"
        : !wifiEnabled ? "Wi-Fi off"
        : activeNetwork ? "Connected to " + ssid : "Not connected"
    property string ipAddress: "—"
    property string gateway: "—"
    property string dnsServer: "—"
    property string connectingNetworkKey: ""
    property string connectingSsid: ""
    property string connectingProfile: ""
    property string revealedPassword: ""
    property string revealedPasswordKey: ""
    property string passwordLookupKey: ""
    property bool passwordLookupBusy: false
    property int passwordRequestToken: 0
    property var forgetCandidates: []
    property int forgetCandidateIndex: 0

    function splitTerse(line): var {
        const fields = []
        let current = ""
        for (let i = 0; i < line.length; i++) {
            const ch = line[i]
            if (ch === "\\" && i + 1 < line.length) {
                current += line[i + 1] === ":" ? ":" : line[i + 1]
                i++
            } else if (ch === ":") {
                fields.push(current); current = ""
            } else current += ch
        }
        fields.push(current)
        return fields
    }

    function refreshDetails(): void { if (!detailsQuery.running) detailsQuery.running = true }
    // ── Saved (known) networks, read from NetworkManager profiles ─────────
    property var savedSsids: []
    function isKnown(network): bool {
        if (!network) return false
        const name = String(network.ssid || network.name || "")
        return !!network.known || (!!name && savedSsids.indexOf(name) !== -1)
    }
    function refreshSaved(): void {
        if (!savedQuery.running) savedQuery.running = true
    }
    property Process savedQuery: Process {
        command: ["bash", "-c", 'nmcli -g UUID connection show 2>/dev/null | while IFS= read -r u; do [ -n "$u" ] || continue; nmcli -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null | head -n 1; done']
        stdout: StdioCollector {
            onStreamFinished: root.savedSsids = text.split("\n").map(x => x.trim()).filter(x => x.length > 0)
        }
    }
    Component.onCompleted: refreshSaved()

    function networkKey(network): string {
        return String(network?.bssid || network?.ssid || network?.name || "")
    }
    function profileNameFor(network): string {
        const key = String(network?.bssid || network?.ssid || network?.name || "")
        return key ? "sat-wifi-" + key.replace(/[^A-Za-z0-9_.-]/g, "_") : ""
    }
    function revealSavedPassword(network): void {
        if (!network) return
        const ssid = String(network.ssid || network.name || "")
        if (!ssid) return
        passwordLookupKey = ""
        if (savedPasswordQuery.running) savedPasswordQuery.running = false
        revealedPassword = ""
        revealedPasswordKey = networkKey(network)
        passwordLookupKey = revealedPasswordKey
        passwordLookupBusy = true
        // Tag this lookup so a late/killed response from a previous
        // request (e.g. switching networks before it finished) can't
        // overwrite the state of this newer request.
        passwordRequestToken += 1
        savedPasswordQuery.token = passwordRequestToken
        savedPasswordQuery.command = ["bash", "-c",
            'target="$1"; nmcli -g NAME connection show 2>/dev/null | while IFS= read -r profile; do [ -n "$profile" ] || continue; profile_ssid=$(nmcli -g 802-11-wireless.ssid connection show id "$profile" 2>/dev/null | head -n 1); if [ "$profile_ssid" = "$target" ]; then nmcli --show-secrets -g 802-11-wireless-security.psk connection show id "$profile" 2>/dev/null; exit 0; fi; done',
            "sat-wifi-secret", ssid]
        savedPasswordQuery.running = true
    }
    function clearSavedPassword(): void {
        passwordLookupKey = ""
        revealedPasswordKey = ""
        revealedPassword = ""
        passwordLookupBusy = false
        passwordRequestToken += 1
        if (savedPasswordQuery.running) savedPasswordQuery.running = false
    }
    function toggleWifi(): void {
        console.log("[SAT][WiFi] toggle requested; current enabled=", wifiEnabled)
        if (available && wifiDevice) Networking.wifiEnabled = !wifiEnabled
    }
    function scan(): void {
        console.log("[SAT][WiFi] scan requested; enabled=", wifiEnabled, "running=", wifiScan.running)
        if (!wifiEnabled || wifiScan.running) return
        refreshSaved()
        scanning = true
        wifiScan.running = true
        scanStop.restart()
    }
    function stopScan(): void {
        console.log("[SAT][WiFi] scan stop requested")
        scanStop.stop()
        if (wifiScan.running) wifiScan.running = false
        scanning = false
    }
    function connect(network, password = ""): void {
        if (!network) { console.log("[SAT][WiFi] connect ignored: no network"); return }
        const ssid = String(network.ssid || network.name || "")
        const networkKey = String(network.bssid || network.ssid || network.name || "")
        const securityName = typeof network.security === "string" ? network.security : "Secured"
        console.log("[SAT][WiFi] connect requested; ssid=", ssid, "key=", networkKey, "security=", securityName, "password supplied=", !!password)
        if (!ssid || ssid === "(hidden)") { console.log("[SAT][WiFi] connect ignored: hidden/empty SSID"); return }
        if (securityName !== "Open" && !password && !isKnown(network)) { console.log("[SAT][WiFi] secured connect waiting for password"); return }
        if (networkConnect.running) { console.log("[SAT][WiFi] connect ignored: another attempt is running"); return }
        connectingNetworkKey = String(network.bssid || network.ssid || network.name || "")
        connectingSsid = ssid
        connectingProfile = ""
        // Reuse an existing saved profile for this SSID (updating its password
        // if one was typed); otherwise let nmcli create the profile itself.
        const script = 'ssid="$1"; pw="$2"; ' +
            'prof=$(nmcli -g NAME connection show 2>/dev/null | while IFS= read -r p; do [ -n "$p" ] || continue; s=$(nmcli -g 802-11-wireless.ssid connection show id "$p" 2>/dev/null | head -n 1); if [ "$s" = "$ssid" ]; then printf "%s" "$p"; break; fi; done); ' +
            'if [ -n "$prof" ]; then ' +
                '[ -n "$pw" ] && nmcli connection modify id "$prof" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pw" wifi-sec.psk-flags 0; ' +
                'exec nmcli --wait 20 connection up id "$prof"; ' +
            'elif [ -n "$pw" ]; then exec nmcli --wait 20 device wifi connect "$ssid" password "$pw"; ' +
            'else exec nmcli --wait 20 device wifi connect "$ssid"; fi'
        networkConnect.command = ["bash", "-c", script, "sat-connect", ssid, password]
        networkConnect.running = true
    }
    function disconnect(network): void {
        console.log("[SAT][WiFi] disconnect requested; ssid=", network?.ssid || network?.name || "")
        if (!network) return
        networkDisconnect.command = ["sh", "-c", "device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"wifi\" && $3==\"connected\" {print $1; exit}'); [ -n \"$device\" ] && nmcli device disconnect \"$device\""]
        networkDisconnect.running = true
    }
    function forget(network): void {
        const target = network || activeNetwork
        if (!target) return
        const ssid = String(target.ssid || target.name || "")
        if (!ssid || ssid === "(hidden)") return
        if (networkForget.running) return
        console.log("[SAT][WiFi] forget requested; ssid=", ssid)
        // Delete every saved profile for this SSID (including any created by
        // earlier versions of this shell) so the stored password is gone.
        networkForget.command = ["bash", "-c",
            'ssid="$1"; nmcli -g UUID connection show 2>/dev/null | while IFS= read -r u; do [ -n "$u" ] || continue; s=$(nmcli -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null | head -n 1); if [ "$s" = "$ssid" ]; then nmcli connection delete uuid "$u" >/dev/null 2>&1; fi; done; exit 0',
            "sat-forget", ssid]
        networkForget.running = true
    }
    function security(network): string {
        if (!network) return "Unknown"
        if (typeof network.security === "string") return network.security || "Open"
        if (network.security === WifiSecurityType.Open) return "Open"
        if (network.security === WifiSecurityType.Sae) return "WPA3"
        return "Secured"
    }

    property Process wifiScan: Process {
        id: wifiScan
        command: ["sh", "-c", "nmcli radio wifi on >/dev/null 2>&1 || true; nmcli --wait 30 device wifi rescan >/dev/null 2>&1 || true; nmcli -t -e yes -f IN-USE,SSID,BSSID,SECURITY,SIGNAL,FREQ,RATE device wifi list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = []
                for (const line of text.trim().split("\n")) {
                    if (!line.trim()) continue
                    const p = root.splitTerse(line)
                    if (p.length < 7) continue
                    const ssid = p[1] || "(hidden)"
                    const nativeNetworks = root.wifiDevice?.networks?.values || []
                    const native = nativeNetworks.find(n =>
                        String(n.ssid || n.name || "") === ssid
                        || (p[2] && String(n.bssid || "") === p[2]))
                    result.push({
                        name: ssid, ssid: ssid, bssid: p[2],
                        security: p[3] || "Open", signal: Number(p[4]) || 0,
                        signalStrength: (Number(p[4]) || 0) / 100,
                        frequency: p[5], rate: p[6], connected: p[0] === "*",
                        known: !!native?.known, password: String(native?.password || ""),
                        profileName: root.profileNameFor({ssid: ssid, bssid: p[2]}), stateChanging: false
                    })
                    console.log("[SAT][WiFi] detected; ssid=", p[1] || "(hidden)", "bssid=", p[2], "security=", p[3] || "Open", "signal=", Number(p[4]) || 0, "connected=", p[0] === "*")
                }
                result.sort((a, b) => Number(b.connected) - Number(a.connected) || b.signal - a.signal)
                root.scannedNetworks = result
                console.log("[SAT][WiFi] scan complete; detected count=", result.length)
                root.scanning = false
            }
        }
        onExited: (code, status) => { console.log("[SAT][WiFi] scan process exited; code=", code, "status=", status); root.scanning = false }
    }
    property Process networkConnect: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][WiFi] connect exited; code=", code, "status=", status)
            if (code !== 0) {
                failedCleanup.command = ["sh", "-c",
                    'dev=$(nmcli -t -f DEVICE,TYPE device status | grep ":wifi$" | cut -d: -f1 | head -n1); [ -n "$dev" ] && nmcli device disconnect "$dev" >/dev/null 2>&1; exit 0']
                failedCleanup.running = true
            }
            root.finishConnect()
        }
    }
    function finishConnect(): void {
            console.log("[SAT][WiFi] connection flow finished; ssid=", root.connectingSsid)
            root.connectingNetworkKey = ""
            root.connectingSsid = ""
            root.connectingProfile = ""
            root.refreshSaved()
            root.refreshDetails()
            if (root.wifiEnabled && !root.wifiScan.running) root.wifiScan.running = true
    }
    property Process connectionUp: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][WiFi] connection up exited; code=", code)
            if (code !== 0) {
                // Wrong password / timeout: abort the pending activation (this
                // also closes the agent's password dialog) and drop the bad profile.
                failedCleanup.command = ["sh", "-c",
                    'dev=$(nmcli -t -f DEVICE,TYPE device status | grep ":wifi$" | cut -d: -f1 | head -n1); [ -n "$dev" ] && nmcli device disconnect "$dev" >/dev/null 2>&1; nmcli connection delete "$1" >/dev/null 2>&1; exit 0',
                    "sat-cleanup", root.connectingProfile]
                failedCleanup.running = true
            }
            root.finishConnect()
        }
    }
    property Process failedCleanup: Process {
        command: []
    }
    property Process profileCleanup: Process {
        command: []
        onExited: networkConnect.running = true
    }
    property Process savedPasswordQuery: Process {
        id: savedPasswordQuery
        property int token: 0
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                // Ignore results from a request that's no longer the
                // current one (e.g. it was superseded before it finished).
                if (root.passwordLookupKey && savedPasswordQuery.token === root.passwordRequestToken) {
                    root.revealedPassword = text.trim()
                    root.passwordLookupBusy = false
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.passwordLookupKey && savedPasswordQuery.token === root.passwordRequestToken) {
                root.revealedPassword = ""
                root.passwordLookupBusy = false
            }
        }
    }
    property Process networkForget: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][WiFi] forget exited; code=", code)
            root.refreshSaved()
            root.refreshDetails()
            if (root.wifiEnabled && !root.wifiScan.running) root.wifiScan.running = true
        }
    }
    property Process networkDisconnect: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][WiFi] disconnect process exited; code=", code, "status=", status)
            root.refreshDetails()
            if (root.wifiEnabled && !root.wifiScan.running) root.wifiScan.running = true
        }
    }
    property Process detailsQuery: Process {
        id: detailsQuery
        command: ["sh", "-c", "ip -4 route get 1.1.1.1 2>/dev/null; ip -4 route show default 2>/dev/null; awk '/^nameserver/{print $2; exit}' /etc/resolv.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const routeLine = lines[0] || ""
                const gatewayLine = lines[1] || ""
                root.ipAddress = (routeLine.match(/\bsrc\s+(\S+)/) || ["", "—"])[1]
                root.gateway = (gatewayLine.match(/default via\s+(\S+)/) || ["", "—"])[1]
                root.dnsServer = lines[2] || "—"
            }
        }
    }
    property Timer scanStop: Timer {
        interval: 35000; repeat: false
        onTriggered: { if (root.wifiScan.running) root.wifiScan.running = false; root.scanning = false }
    }
    property Timer detailsTimer: Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshDetails()
    }
}
