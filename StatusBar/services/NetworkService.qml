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
    readonly property var networks: wifiDevice?.networks?.values || []
    readonly property var savedNetworks: networks.filter(n => n.known)
    readonly property var activeNetwork: networks.find(n => n.connected) || null
    readonly property bool connected: !!activeNetwork
        || Networking.connectivity === NetworkConnectivity.Full
        || Networking.connectivity === NetworkConnectivity.Limited
        || Networking.connectivity === NetworkConnectivity.Portal
    readonly property bool captivePortal: Networking.connectivity === NetworkConnectivity.Portal
    readonly property string connectivityStatus: Networking.connectivity === NetworkConnectivity.Full ? "Internet OK"
        : Networking.connectivity === NetworkConnectivity.Portal ? "Captive portal"
        : Networking.connectivity === NetworkConnectivity.Limited ? "Limited connectivity"
        : connected ? "Checking internet" : "Offline"
    readonly property string ssid: activeNetwork?.name || activeNetwork?.ssid || ""
    readonly property int signalPercent: root.signalPercentage(activeNetwork)
    readonly property string status: !available ? "Network backend unavailable"
        : !wifiEnabled ? "Wi-Fi off"
        : activeNetwork ? "Connected to " + ssid : "Not connected"
    property string ipAddress: "—"
    property string gateway: "—"
    property string dnsServer: "—"
    property string connectingNetworkKey: ""
    property string connectingSsid: ""
    property string connectingProfile: ""
    property string pendingPassword: ""
    property string pendingSecurity: ""
    property string matchedProfileUuid: ""
    property string activationProfileRef: ""
    property string activationProfileSelector: ""
    property string lastConnectProcessError: ""
    property string connectionErrorKey: ""
    property string connectionError: ""
    property string forgetSsid: ""
    property string revealedPassword: ""
    property string revealedPasswordKey: ""
    property string passwordLookupKey: ""
    property string passwordLookupError: ""
    property bool passwordLookupBusy: false
    property var forgetCandidates: []
    property int forgetCandidateIndex: 0
    property string forgetProfileUuid: ""
    signal connectionFinished(bool success, string networkKey)
    signal networkListUpdated()
    property Connections wifiScannerConnection: Connections {
        target: root.wifiDevice
        ignoreUnknownSignals: true
        function onScannerEnabledChanged(enabled) {
            root.scanning = enabled
            root.networkListUpdated()
        }
    }
    property Connections wifiToggleConnection: Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (!root.wifiEnabled) root.stopScan()
        }
    }
    readonly property string profileLookupScript: [
        'target="$1"',
        'while IFS= read -r uuid; do',
        '    [ -n "$uuid" ] || continue',
        '    profile_ssid=$(nmcli --escape no -g 802-11-wireless.ssid connection show uuid "$uuid" 2>/dev/null | head -n 1)',
        '    if [ "$profile_ssid" = "$target" ]; then printf "%s\\n" "$uuid"; exit 0; fi',
        'done < <(nmcli --escape no -g UUID connection show 2>/dev/null)',
        'exit 1'
    ].join("\n")

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
    function networkKey(network): string {
        return String(network?.ssid || network?.name || network?.bssid || "")
    }
    function profileNameFor(network): string {
        const key = String(network?.bssid || network?.ssid || network?.name || "")
        return key ? "sat-wifi-" + key.replace(/[^A-Za-z0-9_.-]/g, "_") : ""
    }
    function normalizeSecurity(value): string {
        const security = String(value || "").trim()
        if (!security || security === "--" || /^(open|none)$/i.test(security)) return "Open"
        return security
    }
    function signalPercentage(network): int {
        if (!network) return 0
        const signal = Number(network.signalStrength || network.signal || 0)
        if (!Number.isFinite(signal)) return 0
        return Math.max(0, Math.min(100, Math.round(signal > 1 ? signal : signal * 100)))
    }
    function bandChannel(network): string {
        const match = String(network?.frequency || "").match(/\d+(?:\.\d+)?/)
        if (!match) {
            const channel = Number(network?.channel || 0)
            if (Number.isFinite(channel) && channel > 0) {
                if (channel <= 14) return "2.4 GHz · channel " + channel
                if (channel >= 1 && channel <= 233) return "5/6 GHz · channel " + channel
            }
            return "Band unavailable"
        }
        const mhz = Math.round(Number(match[0]))
        if (!Number.isFinite(mhz) || mhz <= 0) return "—"
        if (mhz >= 2400 && mhz < 2500)
            return "2.4 GHz · channel " + (mhz === 2484 ? 14 : Math.round((mhz - 2407) / 5))
        if (mhz >= 5000 && mhz < 5925)
            return "5 GHz · channel " + Math.round((mhz - 5000) / 5)
        if (mhz >= 5925 && mhz <= 7125)
            return "6 GHz · channel " + Math.round((mhz - 5950) / 5)
        return mhz + " MHz"
    }
    function keyManagementFor(securityName): string {
        return /wpa3/i.test(String(securityName || "")) && !/wpa2/i.test(String(securityName || ""))
            ? "sae" : "wpa-psk"
    }
    function activateProfile(profileId, password = ""): void {
        const reference = String(profileId)
        const selector = /^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(reference) ? "uuid" : "id"
        const deleteOnFailure = root.matchedProfileUuid ? "no" : "yes"
        activationProfileRef = reference
        activationProfileSelector = selector
        // Keep the profile's original autoconnect value intact. It is
        // disabled only for this manual attempt and restored after the
        // command exits. On failure, explicitly bring the profile down while
        // autoconnect is disabled so restoring the original value cannot cause
        // NetworkManager to immediately retry the bad password.
        connectionUp.command = ["bash", "-c",
            'set -u; selector="$1"; ref="$2"; secret="$3"; delete_on_failure="$4"; old=$(nmcli -g connection.autoconnect connection show "$selector" "$ref" 2>/dev/null | head -n 1); [ -n "$old" ] || old=yes; nmcli connection modify "$selector" "$ref" connection.autoconnect no >/dev/null 2>&1 || exit 1; tmp=$(mktemp); if [ -n "$secret" ]; then nmcli connection down "$selector" "$ref" >/dev/null 2>&1 || true; printf "802-11-wireless-security.psk:%s\\n" "$secret" > "$tmp"; nmcli --wait 30 connection up "$selector" "$ref" passwd-file "$tmp"; rc=$?; else nmcli --wait 30 connection up "$selector" "$ref"; rc=$?; fi; if [ "$rc" -ne 0 ]; then nmcli connection down "$selector" "$ref" >/dev/null 2>&1 || true; if [ "$delete_on_failure" = "yes" ]; then nmcli connection delete "$selector" "$ref" >/dev/null 2>&1 || true; fi; fi; if [ "$delete_on_failure" != "yes" ] || [ "$rc" -eq 0 ]; then nmcli connection modify "$selector" "$ref" connection.autoconnect "$old" >/dev/null 2>&1 || true; fi; rm -f "$tmp"; exit "$rc"',
            "sat-wifi-up", selector, reference, String(password), deleteOnFailure]
        connectionUp.running = true
    }
    function persistConnectedPassword(): void {
        const profileRef = root.matchedProfileUuid || root.connectingProfile
        const selector = root.matchedProfileUuid ? "uuid" : "id"
        const persistCommand = ["nmcli", "connection", "modify", selector, profileRef,
            "802-11-wireless-security.psk-flags", "0",
            "802-11-wireless-security.key-mgmt", root.keyManagementFor(root.pendingSecurity),
            "802-11-wireless-security.psk", root.pendingPassword]
        if (!root.matchedProfileUuid)
            persistCommand.push("connection.autoconnect", "yes")
        persistPassword.command = persistCommand
        persistPassword.running = true
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
        passwordLookupError = ""
        passwordLookupBusy = false
        const knownPassword = String(network.password || "")
        if (knownPassword) {
            revealedPassword = knownPassword
            passwordLookupBusy = false
            return
        }
        passwordLookupBusy = true
        savedPasswordQuery.command = ["bash", "-c",
            'target="$1"; while IFS= read -r uuid; do [ -n "$uuid" ] || continue; profile_ssid=$(nmcli --escape no -g 802-11-wireless.ssid connection show uuid "$uuid" 2>/dev/null | head -n 1); if [ "$profile_ssid" = "$target" ]; then secret=$(nmcli --show-secrets --escape no -g 802-11-wireless-security.psk connection show uuid "$uuid" 2>/dev/null | head -n 1); if [ -n "$secret" ] && [ "$secret" != "--" ]; then printf "%s\\n" "$secret"; exit 0; fi; fi; done < <(for uuid in $(nmcli --escape no -g UUID connection show --active 2>/dev/null) $(nmcli --escape no -g UUID connection show 2>/dev/null); do printf "%s\\n" "$uuid"; done); exit 1',
            "sat-wifi-secret", ssid]
        savedPasswordQuery.running = true
    }
    function clearSavedPassword(): void {
        passwordLookupKey = ""
        revealedPasswordKey = ""
        revealedPassword = ""
        passwordLookupError = ""
        passwordLookupBusy = false
        if (savedPasswordQuery.running) savedPasswordQuery.running = false
    }
    function toggleWifi(): void {
        console.log("[SAT][WiFi] toggle requested; current enabled=", wifiEnabled)
        if (available) Networking.wifiEnabled = !wifiEnabled
    }
    function scan(): void {
        console.log("[SAT][WiFi] scan requested; enabled=", wifiEnabled, "device=", !!wifiDevice)
        if (!wifiEnabled || !wifiDevice) return
        if (wifiDevice.scannerEnabled) {
            scanning = true
            return
        }
        scanning = true
        wifiDevice.scannerEnabled = true
        networkListUpdated()
    }
    function stopScan(): void {
        console.log("[SAT][WiFi] scan stop requested")
        if (wifiDevice && wifiDevice.scannerEnabled) wifiDevice.scannerEnabled = false
        scanning = false
        networkListUpdated()
    }
    function connect(network, password = ""): void {
        if (!network) { console.log("[SAT][WiFi] connect ignored: no network"); return }
        if (connectingNetworkKey) { console.log("[SAT][WiFi] connect ignored: another connection is in progress"); return }
        const ssid = String(network.ssid || network.name || "")
        const networkKey = root.networkKey(network)
        const securityName = root.security(network)
        console.log("[SAT][WiFi] connect requested; ssid=", ssid, "key=", networkKey, "security=", securityName, "password supplied=", !!password)
        if (!ssid || ssid === "(hidden)") { console.log("[SAT][WiFi] connect ignored: hidden/empty SSID"); return }
        if (securityName !== "Open" && !password && !network.known) {
            console.log("[SAT][WiFi] secured connect waiting for inline password")
            return
        }
        connectionErrorKey = ""
        connectionError = ""
        lastConnectProcessError = ""
        connectingNetworkKey = root.networkKey(network)
        connectingSsid = ssid
        connectingProfile = profileNameFor(network)
        pendingPassword = password
        pendingSecurity = securityName
        matchedProfileUuid = ""
        profileLookup.command = ["bash", "-c", profileLookupScript, "sat-profile-lookup", ssid]
        profileLookup.running = true
    }
    function connectionFailureMessage(): string {
        const detail = String(lastConnectProcessError || "").toLowerCase()
        if (/not found|no network|unavailable|not available/.test(detail))
            return "Wi-Fi network unavailable. Check that it is in range and try again."
        if (pendingSecurity !== "Open")
            return "Wrong Wi-Fi password or authentication failed. Check the password and try again."
        return "Could not connect to this Wi-Fi network. Check that it is available and try again."
    }
    function finishConnect(success: bool, message = ""): void {
        const key = connectingNetworkKey
        console.log("[SAT][WiFi] connection flow finished; ssid=", connectingSsid, "success=", success)
        if (success) {
            connectionErrorKey = ""
            connectionError = ""
        } else if (key) {
            connectionErrorKey = key
            connectionError = message || connectionFailureMessage()
        }
        connectingNetworkKey = ""
        connectingSsid = ""
        connectingProfile = ""
        pendingPassword = ""
        pendingSecurity = ""
        matchedProfileUuid = ""
        refreshDetails()
        networkListUpdated()
        connectionFinished(success, key)
    }
    function disconnect(network): void {
        console.log("[SAT][WiFi] disconnect requested; ssid=", network?.ssid || network?.name || "")
        if (!network) return
        networkDisconnect.command = ["sh", "-c", "device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"wifi\" && $3==\"connected\" {print $1; exit}'); [ -n \"$device\" ] && nmcli device disconnect \"$device\""]
        networkDisconnect.running = true
    }
    function forget(network = activeNetwork): void {
        if (!network) return
        const ssid = String(network.ssid || network.name || "")
        forgetSsid = ssid
        const candidates = [network.connectionName || network.profileName || profileNameFor(network), ssid]
            .filter((name, index, all) => !!name && all.indexOf(name) === index)
        if (candidates.length === 0) return
        console.log("[SAT][WiFi] forget requested; ssid=", ssid)
        forgetCandidates = candidates
        forgetCandidateIndex = 0
        forgetProfileUuid = ""
        forgetProfileLookup.command = ["bash", "-c", profileLookupScript, "sat-forget-profile", ssid]
        forgetProfileLookup.running = true
    }
    function runForgetCandidate(): void {
        if (forgetCandidateIndex >= forgetCandidates.length) {
            console.warn("[SAT][WiFi] no matching connection profile found to forget")
            return
        }
        networkForget.command = ["nmcli", "connection", "delete", "id", forgetCandidates[forgetCandidateIndex]]
        networkForget.running = true
    }
    function security(network): string {
        if (!network) return "Unknown"
        if (typeof network.security === "string") return root.normalizeSecurity(network.security)
        if (network.security === WifiSecurityType.Open) return "Open"
        if (network.security === WifiSecurityType.Sae) return "WPA3"
        return "Secured"
    }

    property Process networkConnect: Process {
        command: []
        stderr: StdioCollector { onStreamFinished: root.lastConnectProcessError = text.trim() }
        onExited: (code, status) => {
            console.log("[SAT][WiFi] profile create exited; code=", code, "status=", status)
            const createdProfile = root.connectingProfile
            command = []
            if (code === 0) {
                root.lastConnectProcessError = ""
                root.activateProfile(createdProfile, root.pendingPassword)
                return
            }
            root.finishConnect(false, root.connectionFailureMessage())
        }
    }
    property Process profileLookup: Process {
        command: []
        stdout: StdioCollector { onStreamFinished: root.matchedProfileUuid = text.trim() }
        onExited: (code, status) => {
            const uuid = root.matchedProfileUuid
            if (code === 0 && uuid) {
                if (root.pendingPassword) {
                    root.lastConnectProcessError = ""
                    root.activateProfile(uuid, root.pendingPassword)
                } else {
                    root.lastConnectProcessError = ""
                    root.activateProfile(uuid)
                }
                return
            }
            if (root.pendingSecurity !== "Open" && !root.pendingPassword) {
                root.finishConnect(false, "Saved Wi-Fi profile was not found. Enter the password and retry.")
                return
            }
            const profile = root.connectingProfile
            const command = ["nmcli", "--wait", "30", "connection", "add",
                "type", "wifi", "ifname", "*", "con-name", profile, "ssid", root.connectingSsid,
                "connection.autoconnect", "no"]
            if (root.pendingSecurity !== "Open")
                command.push("wifi-sec.key-mgmt", root.keyManagementFor(root.pendingSecurity))
            root.lastConnectProcessError = ""
            networkConnect.command = command
            networkConnect.running = true
        }
    }
    property Process persistPassword: Process {
        command: []
        stderr: StdioCollector { onStreamFinished: root.lastConnectProcessError = text.trim() }
        onExited: (code, status) => {
            command = []
            // A successful activation is already a successful join. If
            // persistence fails, do not turn the valid connection into an
            // authentication failure; simply leave the secret unsaved.
            root.finishConnect(true)
        }
    }
    property Process verifyConnection: Process {
        command: []
        stderr: StdioCollector { onStreamFinished: root.lastConnectProcessError = text.trim() }
        onExited: (code, status) => {
            command = []
            if (code === 0) {
                root.persistConnectedPassword()
                return
            }
            root.finishConnect(false, root.connectionFailureMessage())
        }
    }
    property Process connectionUp: Process {
        command: []
        stderr: StdioCollector { onStreamFinished: root.lastConnectProcessError = text.trim() }
        onExited: (code, status) => {
            const profileRef = root.matchedProfileUuid || root.connectingProfile
            command = []
            if (code !== 0) {
                root.finishConnect(false, root.connectionFailureMessage())
                return
            }
            if (!root.pendingPassword) {
                root.finishConnect(true)
                return
            }
            // nmcli's exit code alone is not the save condition. Confirm the
            // target profile is actually active before persisting the secret.
            const selector = root.matchedProfileUuid ? "uuid" : "id"
            verifyConnection.command = ["bash", "-c",
                'state=$(nmcli -t -g GENERAL.STATE connection show --active "$1" "$2" 2>/dev/null | head -n 1); [ "$state" = "activated" ] || [ "$state" = "activated (externally)" ]',
                "sat-wifi-verify", selector, profileRef]
            verifyConnection.running = true
        }
    }
    property Process savedPasswordQuery: Process {
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.passwordLookupKey) {
                    const secret = text.replace(/[\r\n]+$/, "")
                    root.revealedPassword = secret === "--" ? "" : secret
                    if (!root.revealedPassword)
                        root.passwordLookupError = "No readable password is saved for this network."
                    root.passwordLookupBusy = false
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.passwordLookupKey) {
                root.revealedPassword = ""
                root.passwordLookupError = "NetworkManager could not read a saved password for this network."
                root.passwordLookupBusy = false
            }
        }
    }
    property Process networkForget: Process {
        command: []
        onExited: (code, status) => {
            if (code === 0) {
                root.refreshDetails()
                root.networkListUpdated()
            } else {
                root.forgetCandidateIndex += 1
                root.runForgetCandidate()
            }
        }
    }
    property Process forgetProfileLookup: Process {
        command: []
        stdout: StdioCollector { onStreamFinished: root.forgetProfileUuid = text.trim() }
        onExited: (code, status) => {
            if (code === 0 && root.forgetProfileUuid) {
                networkForget.command = ["nmcli", "connection", "delete", "uuid", root.forgetProfileUuid]
                networkForget.running = true
            } else root.runForgetCandidate()
        }
    }
    property Process networkDisconnect: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][WiFi] disconnect process exited; code=", code, "status=", status)
            root.refreshDetails()
            root.networkListUpdated()
        }
    }
    property Process detailsQuery: Process {
        id: detailsQuery
        command: ["sh", "-c", "device=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" && $3==\"connected\" {print $1; exit}'); [ -n \"$device\" ] && nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show \"$device\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let ipAddress = "—"
                let gateway = "—"
                const dnsServers = []
                for (const line of text.trim().split("\n")) {
                    if (!line) continue
                    const fields = root.splitTerse(line)
                    if (fields.length < 2) continue
                    const field = fields[0]
                    const value = fields.slice(1).join(":").trim()
                    if (field.indexOf("IP4.ADDRESS") === 0 && ipAddress === "—")
                        ipAddress = value.split("/")[0]
                    else if (field === "IP4.GATEWAY")
                        gateway = value
                    else if (field.indexOf("IP4.DNS") === 0 && value && !dnsServers.includes(value))
                        dnsServers.push(value)
                }
                root.ipAddress = ipAddress
                root.gateway = gateway
                root.dnsServer = dnsServers.length ? dnsServers.join(", ") : "—"
            }
        }
    }
    property Timer detailsTimer: Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshDetails()
    }
}
