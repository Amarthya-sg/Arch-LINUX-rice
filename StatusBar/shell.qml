import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io

ShellRoot {
    id: root

    // ── Theme ───────────────────────────────────────────────────────
    property var theme: ({
        bg: "#000000",
        surface: "#1c1c1e",
        surface2: "#2c2c2e",
        surface3: "#3a3a3c",
        border: "#3a3a3c",
        text: "#f5f5f7",
        textMuted: "#8e8e93",
        accent: "#0a84ff",
        green: "#30d158",
        red: "#ff453a",
        orange: "#ff9f0a",
        fontUi: "Inter",
        fontIcon: "JetBrainsMono Nerd Font",
        barHeight: 40,
        pillHeight: 30,
        popupRadius: 22
    })

    property string activeSection: "wifi"

    // ═══════════════════════════════════════════════════════════════
    // AUDIO
    // ═══════════════════════════════════════════════════════════════
    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    property bool muted:  Pipewire.defaultAudioSink?.audio?.muted  ?? false
    property real micVolume: Pipewire.defaultAudioSource?.audio?.volume ?? 0
    property bool micMuted:  Pipewire.defaultAudioSource?.audio?.muted  ?? false

    function setVolume(v) {
        if (Pipewire.defaultAudioSink?.audio)
            Pipewire.defaultAudioSink.audio.volume = Math.max(0, Math.min(1.5, v))
    }
    function toggleMute() {
        if (Pipewire.defaultAudioSink?.audio)
            Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
    }
    function setMicVolume(v) {
        if (Pipewire.defaultAudioSource?.audio)
            Pipewire.defaultAudioSource.audio.volume = Math.max(0, Math.min(1.5, v))
    }
    function toggleMicMute() {
        if (Pipewire.defaultAudioSource?.audio)
            Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted
    }

    property var sinksList: []
    function refreshSinks() {
        const out = []
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : []
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i]
            if (n.isSink && !n.isStream)
                out.push({ id: n.id, name: n.name, desc: n.description || n.name })
        }
        sinksList = out
    }
    function setDefaultSink(id) {
        Quickshell.execDetached(["wpctl", "set-default", String(id)])
    }

    // ═══════════════════════════════════════════════════════════════
    // BRIGHTNESS
    // ═══════════════════════════════════════════════════════════════
    property real brightness: 0.5
    Process {
        id: brightnessGet
        command: ["brightnessctl", "g"]
        running: true
        stdout: StdioCollector { onStreamFinished: brightnessMax.running = true }
    }
    Process {
        id: brightnessMax
        command: ["brightnessctl", "m"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const max = parseInt(text.trim())
                const cur = parseInt(brightnessGet.stdout.text.trim())
                if (max > 0) brightness = cur / max
            }
        }
    }
    function setBrightness(v) {
        v = Math.max(0.01, Math.min(1, v))
        brightness = v
        Quickshell.execDetached(["brightnessctl", "s", Math.round(v * 100) + "%"])
    }

    // ═══════════════════════════════════════════════════════════════
    // NIGHT LIGHT
    // ═══════════════════════════════════════════════════════════════
    property bool nightLight: false
    property int nightTemp: 4000
    function applyNightLight() {
        Quickshell.execDetached(["pkill", "-x", "gammastep"])
        if (nightLight) {
            Quickshell.execDetached([
                "gammastep", "-O", String(nightTemp),
                "-l", "0", "-L", "0"
            ])
        }
    }
    function toggleNightLight() { nightLight = !nightLight; applyNightLight() }
    function setNightTemp(t) { nightTemp = t; if (nightLight) applyNightLight() }

    // ═══════════════════════════════════════════════════════════════
    // WI-FI
    // ═══════════════════════════════════════════════════════════════
    property bool wifiEnabled: false
    property string wifiSsid: "Not connected"
    property int wifiSignal: 0
    property string wifiIp: ""
    property var wifiNetworks: []
    property string pendingSsid: ""
    property string pendingPassword: ""
    property string captiveUrl: ""

    Process {
        id: wifiStatus
        command: ["nmcli", "-t", "-f", "WIFI", "radio"]
        running: true
        stdout: StdioCollector { onStreamFinished: wifiEnabled = text.trim() === "enabled" }
    }
    Process {
        id: wifiCurrent
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let found = false
                for (let line of text.trim().split("\n")) {
                    const p = line.split(":")
                    if (p[0] === "yes") {
                        wifiSsid = p[1] || "Unknown"
                        wifiSignal = parseInt(p[2]) || 0
                        found = true
                        break
                    }
                }
                if (!found) { wifiSsid = "Not connected"; wifiSignal = 0; captiveUrl = "" }
            }
        }
    }
    Process {
        id: wifiIpProc
        command: ["sh", "-c", "nmcli -t -f IP4.ADDRESS device show $(nmcli -t -f DEVICE,TYPE device | grep wifi | head -1 | cut -d: -f1) 2>/dev/null | head -1 | cut -d: -f2 | cut -d/ -f1"]
        running: true
        stdout: StdioCollector { onStreamFinished: wifiIp = text.trim() }
    }
    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,ACTIVE", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [], seen = {}
                for (let line of text.trim().split("\n")) {
                    const p = line.split(":")
                    if (!p[0] || seen[p[0]]) continue
                    seen[p[0]] = true
                    list.push({
                        ssid: p[0],
                        signal: parseInt(p[1]) || 0,
                        security: p[2] || "Open",
                        active: p[3] === "yes"
                    })
                }
                list.sort((a,b) => b.signal - a.signal)
                wifiNetworks = list.slice(0, 15)
            }
        }
    }

    Process {
        id: captiveProbe
        command: ["sh", "-c",
            "curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 http://connectivitycheck.gstatic.com/generate_204"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/)
                const code = parts[0]
                const redirect = parts[1] || ""
                if (code !== "204") {
                    captiveUrl = redirect || "http://connectivitycheck.gstatic.com/generate_204"
                } else {
                    captiveUrl = ""
                }
            }
        }
    }

    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"])
        wifiEnabled = !wifiEnabled
        refreshWifi()
    }
    function connectWifi(ssid, password) {
        const args = ["nmcli", "dev", "wifi", "connect", ssid]
        if (password) args.push("password", password)
        Quickshell.execDetached(args)
        pendingSsid = ""
        pendingPassword = ""
        Qt.callLater(() => { refreshWifi(); captiveProbe.running = true })
    }
    function forgetWifi(ssid) {
        Quickshell.execDetached(["nmcli", "connection", "delete", ssid])
        Qt.callLater(refreshWifi)
    }
    function refreshWifi() {
        wifiStatus.running = true
        wifiCurrent.running = true
        wifiIpProc.running = true
        wifiScan.running = true
    }
    function openCaptive() {
        if (captiveUrl)
            Quickshell.execDetached(["xdg-open", captiveUrl])
    }

    // ═══════════════════════════════════════════════════════════════
    // BLUETOOTH
    // ═══════════════════════════════════════════════════════════════
    property bool btEnabled: false
    property bool btDiscoverable: false
    property var btDevices: []
    property string btExpandedMac: ""

    Process {
        id: btStatus
        command: ["bluetoothctl", "show"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                btEnabled = text.indexOf("Powered: yes") !== -1
                btDiscoverable = text.indexOf("Discoverable: yes") !== -1
            }
        }
    }
    Process {
        id: btScan
        command: ["bluetoothctl", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = []
                for (let line of text.trim().split("\n")) {
                    const m = line.match(/^Device\s+([0-9A-F:]{17})\s+(.+)$/i)
                    if (m) list.push({ mac: m[1], name: m[2], connected: false, battery: -1, codec: "" })
                }
                btDevices = list
                btConnected.running = true
            }
        }
    }
    Process {
        id: btConnected
        command: ["bluetoothctl", "devices", "Connected"]
        stdout: StdioCollector {
            onStreamFinished: {
                const connectedMacs = {}
                for (let line of text.trim().split("\n")) {
                    const m = line.match(/^Device\s+([0-9A-F:]{17})/i)
                    if (m) connectedMacs[m[1]] = true
                }
                const copy = btDevices.slice()
                for (let i = 0; i < copy.length; i++)
                    copy[i].connected = !!connectedMacs[copy[i].mac]
                btDevices = copy
                btInfoQueue = copy.filter(d => d.connected).map(d => d.mac)
                if (btInfoQueue.length > 0) btInfoNext()
            }
        }
    }
    property var btInfoQueue: []
    function btInfoNext() {
        if (btInfoQueue.length === 0) return
        const mac = btInfoQueue[0]
        btInfoQueue = btInfoQueue.slice(1)
        btInfo.mac = mac
        btInfo.running = true
    }
    Process {
        id: btInfo
        property string mac: ""
        command: ["bluetoothctl", "info", btInfo.mac]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text
                let battery = -1
                const bm = t.match(/Battery Percentage:\s*0x[0-9A-Fa-f]+\s*\((\d+)\)/)
                if (bm) battery = parseInt(bm[1])
                let codec = ""
                const cm = t.match(/Codec:\s*(.+)/i)
                if (cm) codec = cm[1].trim()
                const copy = btDevices.slice()
                for (let i = 0; i < copy.length; i++) {
                    if (copy[i].mac === btInfo.mac) {
                        copy[i].battery = battery
                        copy[i].codec = codec
                    }
                }
                btDevices = copy
                Qt.callLater(btInfoNext)
            }
        }
    }

    function toggleBt() {
        Quickshell.execDetached(["bluetoothctl", "power", btEnabled ? "off" : "on"])
        btEnabled = !btEnabled
        Qt.callLater(() => btStatus.running = true)
    }
    function toggleDiscoverable() {
        Quickshell.execDetached(["bluetoothctl", "discoverable", btDiscoverable ? "off" : "on"])
        btDiscoverable = !btDiscoverable
    }
    function connectBt(mac) {
        Quickshell.execDetached(["bluetoothctl", "connect", mac])
        Qt.callLater(() => { btScan.running = true })
    }
    function disconnectBt(mac) {
        Quickshell.execDetached(["bluetoothctl", "disconnect", mac])
        Qt.callLater(() => { btScan.running = true })
    }
    function removeBt(mac) {
        Quickshell.execDetached(["bluetoothctl", "remove", mac])
        Qt.callLater(() => { btScan.running = true })
    }
    function sendFile(mac) {
        Quickshell.execDetached(["bluetooth-sendto", "--device=" + mac])
    }
    function cycleCodec(mac) {
        Quickshell.execDetached(["sh", "-c",
            "card=$(pactl list cards short | awk '/bluez/{print $2; exit}'); " +
            "[ -n \"$card\" ] && pactl set-card-profile \"$card\" a2dp-sink"]
        )
        Qt.callLater(() => { btInfo.mac = mac; btInfo.running = true })
    }

    // ═══════════════════════════════════════════════════════════════
    // SYSTEM
    // ═══════════════════════════════════════════════════════════════
    property int cpuUsage: 0
    property int memUsage: 0
    property string memUsed: "0"
    property string memTotal: "0"
    property string cpuTemp: "--"
    property string powerProfile: "balanced"
    property var lastCpuIdle: 0
    property var lastCpuTotal: 0

    Process {
        id: cpuProc
        command: ["sh", "-c", "head -1 /proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length < 5) return
                const idle = parseInt(p[4]) + parseInt(p[5] || 0)
                let total = 0
                for (let i = 1; i < 8 && i < p.length; i++) total += parseInt(p[i])
                if (lastCpuTotal > 0)
                    cpuUsage = Math.round(100 * (1 - (idle - lastCpuIdle) / (total - lastCpuTotal)))
                lastCpuTotal = total; lastCpuIdle = idle
            }
        }
    }
    Process {
        id: memProc
        command: ["sh", "-c", "free -h | grep Mem"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length >= 3) { memTotal = p[1]; memUsed = p[2] }
            }
        }
    }
    Process {
        id: memPctProc
        command: ["sh", "-c", "free | grep Mem"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length >= 3)
                    memUsage = Math.round(100 * parseInt(p[2]) / parseInt(p[1]))
            }
        }
    }
    Process {
        id: tempProc
        command: ["sh", "-c", "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = parseInt(text.trim())
                cpuTemp = t > 0 ? Math.round(t / 1000) + "°C" : "--"
            }
        }
    }
    Process {
        id: profileProc
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector { onStreamFinished: powerProfile = text.trim() }
    }
    function setPowerProfile(p) {
        Quickshell.execDetached(["powerprofilesctl", "set", p])
        powerProfile = p
    }

    // ═══════════════════════════════════════════════════════════════
    // DND
    // ═══════════════════════════════════════════════════════════════
    property bool dnd: false
    function toggleDnd() {
        Quickshell.execDetached(["swaync-client", dnd ? "-dnd_off" : "-dnd_on"])
        dnd = !dnd
    }

    // ═══════════════════════════════════════════════════════════════
    // Polling
    // ═══════════════════════════════════════════════════════════════
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true
            memProc.running = true
            memPctProc.running = true
            tempProc.running = true
            wifiStatus.running = true
            wifiCurrent.running = true
            wifiIpProc.running = true
            btStatus.running = true
            profileProc.running = true
            refreshSinks()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // BAR + DYNAMIC ISLAND
    // ═══════════════════════════════════════════════════════════════
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        implicitHeight: root.theme.barHeight
        color: "transparent"

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 6
            width: Math.max(120, pillContent.implicitWidth + 36)
            height: root.theme.pillHeight
            radius: height / 2
            color: root.theme.bg
            border.color: root.theme.surface
            border.width: 1
            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            scale: pillMouse.pressed ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: 120 } }

            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: "󰥔"
                    color: root.theme.accent
                    font.family: root.theme.fontIcon
                    font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    id: clockText
                    color: root.theme.text
                    font.family: root.theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                    Timer {
                        interval: 1000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "h:mm AP")
                    }
                }
                Text {
                    visible: captiveUrl !== ""
                    text: "󰖟"
                    color: root.theme.orange
                    font.family: root.theme.fontIcon
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    popup.visible = !popup.visible
                    if (popup.visible) {
                        activeSection = "wifi"
                        refreshWifi()
                        btScan.running = true
                    }
                }
            }
        }

        PopupWindow {
            id: popup
            anchor.window: bar
            anchor.rect.x: bar.width / 2 - implicitWidth / 2
            anchor.rect.y: bar.height + 6
            implicitWidth: 380
            implicitHeight: 520
            visible: false
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: root.theme.bg
                radius: root.theme.popupRadius
                border.color: root.theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // ── Tabs ────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: [
                                { id: "wifi",       icon: "󰤨", label: "Wi-Fi" },
                                { id: "bluetooth",  icon: "󰂯", label: "BT" },
                                { id: "sound",      icon: "󰕾", label: "Sound" },
                                { id: "brightness", icon: "󰃠", label: "Bright" },
                                { id: "notif",      icon: "󰂚", label: "Notif" },
                                { id: "system",     icon: "󰒓", label: "System" }
                            ]
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                radius: 12
                                color: activeSection === modelData.id
                                    ? root.theme.accent
                                    : (tabHover.hovered ? root.theme.surface3 : root.theme.surface)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        color: activeSection === modelData.id ? "#000" : root.theme.text
                                        font.family: root.theme.fontIcon
                                        font.pixelSize: 16
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        color: activeSection === modelData.id ? "#000" : root.theme.textMuted
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 9
                                    }
                                }
                                HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        activeSection = modelData.id
                                        if (modelData.id === "wifi") refreshWifi()
                                        if (modelData.id === "bluetooth") btScan.running = true
                                    }
                                }
                            }
                        }
                    }

                    // ── Content card ────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: root.theme.surface
                        clip: true

                        // ═══════════════ Wi-Fi ═══════════════
                        Flickable {
                            visible: activeSection === "wifi"
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: wifiCol.implicitHeight + 24
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: wifiCol
                                width: parent.width - 24
                                x: 12
                                y: 12
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Wi-Fi"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    ToggleSwitch {
                                        checked: wifiEnabled
                                        onColor: root.theme.green
                                        onToggled: toggleWifi()
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    radius: 10
                                    color: Qt.rgba(1, 0.62, 0.04, 0.18)
                                    visible: captiveUrl !== ""
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        Text {
                                            text: "󰖟  Captive portal detected"
                                            color: root.theme.orange
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 12
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: "Open"
                                            color: root.theme.accent
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 12
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: openCaptive()
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 12
                                    color: root.theme.surface2
                                    visible: wifiEnabled && wifiSsid !== "Not connected"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        Text {
                                            text: wifiSignal >= 70 ? "󰤨" : wifiSignal >= 40 ? "󰤥" : "󰤟"
                                            color: root.theme.accent
                                            font.family: root.theme.fontIcon
                                            font.pixelSize: 22
                                        }
                                        Column {
                                            Layout.fillWidth: true
                                            Text {
                                                text: wifiSsid
                                                color: root.theme.text
                                                font.family: root.theme.fontUi
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                text: (wifiIp ? wifiIp + " · " : "") + "Signal " + wifiSignal + "%"
                                                color: root.theme.textMuted
                                                font.family: root.theme.fontUi
                                                font.pixelSize: 11
                                            }
                                        }
                                        Text {
                                            text: "Forget"
                                            color: root.theme.red
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 11
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: forgetWifi(wifiSsid)
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    Text {
                                        text: "Available Networks"
                                        color: root.theme.textMuted
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 11
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "Scan"
                                        color: root.theme.accent
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 12
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: wifiScan.running = true
                                        }
                                    }
                                }

                                Repeater {
                                    model: wifiNetworks
                                    Rectangle {
                                        id: netRow
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: pendingSsid === modelData.ssid ? 96 : 48
                                        radius: 10
                                        color: modelData.active
                                            ? Qt.rgba(0.04, 0.52, 1, 0.15)
                                            : (netHover.hovered ? root.theme.surface2 : "transparent")
                                        Behavior on Layout.preferredHeight {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }
                                        clip: true

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 32
                                                Text {
                                                    text: modelData.signal >= 70 ? "󰤨" : modelData.signal >= 40 ? "󰤥" : "󰤟"
                                                    color: modelData.active ? root.theme.accent : root.theme.textMuted
                                                    font.family: root.theme.fontIcon
                                                    font.pixelSize: 16
                                                }
                                                Column {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        text: modelData.ssid
                                                        color: root.theme.text
                                                        font.family: root.theme.fontUi
                                                        font.pixelSize: 13
                                                    }
                                                    Text {
                                                        text: modelData.security + " · " + modelData.signal + "%"
                                                        color: root.theme.textMuted
                                                        font.family: root.theme.fontUi
                                                        font.pixelSize: 10
                                                    }
                                                }
                                                Text {
                                                    visible: modelData.active
                                                    text: "✓"
                                                    color: root.theme.accent
                                                    font.pixelSize: 14
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                visible: pendingSsid === modelData.ssid
                                                spacing: 6
                                                TextField {
                                                    id: pwdField
                                                    Layout.fillWidth: true
                                                    placeholderText: "Password"
                                                    echoMode: TextInput.Password
                                                    color: root.theme.text
                                                    placeholderTextColor: root.theme.textMuted
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 12
                                                    leftPadding: 10
                                                    rightPadding: 10
                                                    topPadding: 0
                                                    bottomPadding: 0
                                                    background: Rectangle {
                                                        color: root.theme.surface3
                                                        radius: 8
                                                    }
                                                    onTextChanged: pendingPassword = text
                                                }
                                                Rectangle {
                                                    Layout.preferredWidth: 76
                                                    Layout.fillHeight: true
                                                    radius: 8
                                                    color: root.theme.accent
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Connect"
                                                        color: "#000"
                                                        font.family: root.theme.fontUi
                                                        font.pixelSize: 12
                                                        font.weight: Font.Medium
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: connectWifi(modelData.ssid, pendingPassword)
                                                    }
                                                }
                                            }
                                        }

                                        HoverHandler { id: netHover; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: pendingSsid !== modelData.ssid
                                            onClicked: {
                                                if (modelData.active) return
                                                const open = modelData.security === "Open" || modelData.security === ""
                                                if (open) {
                                                    connectWifi(modelData.ssid, "")
                                                } else {
                                                    pendingSsid = modelData.ssid
                                                    pendingPassword = ""
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══════════════ Bluetooth ═══════════════
                        Flickable {
                            visible: activeSection === "bluetooth"
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: btCol.implicitHeight + 24
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: btCol
                                width: parent.width - 24
                                x: 12
                                y: 12
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Bluetooth"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    ToggleSwitch {
                                        checked: btEnabled
                                        onColor: root.theme.accent
                                        onToggled: toggleBt()
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: btEnabled
                                    Text {
                                        text: "Discoverable"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                        Layout.fillWidth: true
                                    }
                                    ToggleSwitch {
                                        checked: btDiscoverable
                                        onColor: root.theme.green
                                        onToggled: toggleDiscoverable()
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: btEnabled
                                    Text {
                                        text: "Devices"
                                        color: root.theme.textMuted
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 11
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "Scan"
                                        color: root.theme.accent
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 12
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Quickshell.execDetached(["bluetoothctl", "scan", "on"])
                                                Qt.callLater(() => btScan.running = true)
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: btDevices
                                    Rectangle {
                                        id: devRow
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: btExpandedMac === modelData.mac ? 116 : 52
                                        radius: 10
                                        color: modelData.connected
                                            ? Qt.rgba(0.04, 0.52, 1, 0.15)
                                            : (devHover.hovered ? root.theme.surface2 : "transparent")
                                        visible: btEnabled
                                        clip: true
                                        Behavior on Layout.preferredHeight {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36

                                                Column {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        text: modelData.name
                                                        color: root.theme.text
                                                        font.family: root.theme.fontUi
                                                        font.pixelSize: 13
                                                    }
                                                    Row {
                                                        spacing: 6
                                                        Text {
                                                            text: modelData.mac
                                                            color: root.theme.textMuted
                                                            font.family: root.theme.fontUi
                                                            font.pixelSize: 10
                                                        }
                                                        Text {
                                                            visible: modelData.battery >= 0
                                                            text: "· " + modelData.battery + "%"
                                                            color: root.theme.green
                                                            font.family: root.theme.fontUi
                                                            font.pixelSize: 10
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: modelData.connected ? "Disconnect" : "Connect"
                                                    color: root.theme.accent
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 11
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.connected) {
                                                                disconnectBt(modelData.mac)
                                                            } else {
                                                                connectBt(modelData.mac)
                                                            }
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: "✕"
                                                    color: root.theme.red
                                                    font.pixelSize: 12
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: removeBt(modelData.mac)
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 32
                                                visible: btExpandedMac === modelData.mac && modelData.connected
                                                spacing: 6
                                                Text {
                                                    text: modelData.codec ? "Codec: " + modelData.codec : "Codec: —"
                                                    color: root.theme.textMuted
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: "Cycle"
                                                    color: root.theme.accent
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 11
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: cycleCodec(modelData.mac)
                                                    }
                                                }
                                                Text {
                                                    text: "Send File"
                                                    color: root.theme.accent
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 11
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: sendFile(modelData.mac)
                                                    }
                                                }
                                            }
                                        }

                                        HoverHandler { id: devHover; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: btExpandedMac !== modelData.mac
                                            onClicked: {
                                                if (!modelData.connected) {
                                                    btExpandedMac = modelData.mac
                                                } else {
                                                    btExpandedMac = btExpandedMac === modelData.mac ? "" : modelData.mac
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: 10
                                    color: root.theme.surface2
                                    visible: btEnabled
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Open Blueman"
                                        color: root.theme.accent
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["blueman-manager"])
                                    }
                                }
                            }
                        }

                        // ═══════════════ Sound ═══════════════
                        Flickable {
                            visible: activeSection === "sound"
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: sndCol.implicitHeight + 24
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: sndCol
                                width: parent.width - 24
                                x: 12
                                y: 12
                                spacing: 14

                                Text {
                                    text: "Sound"
                                    color: root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: "Output"
                                    color: root.theme.textMuted
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 11
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: muted ? "󰝟" : "󰕾"
                                        color: root.theme.text
                                        font.family: root.theme.fontIcon
                                        font.pixelSize: 22
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggleMute() }
                                    }
                                    Slider {
                                        Layout.fillWidth: true
                                        from: 0; to: 1.5
                                        value: volume
                                        onMoved: setVolume(value)
                                    }
                                    Text {
                                        text: Math.round(volume * 100) + "%"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                        Layout.preferredWidth: 42
                                    }
                                }

                                Text {
                                    text: "Input (Microphone)"
                                    color: root.theme.textMuted
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 11
                                    Layout.topMargin: 6
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: micMuted ? "󰍭" : "󰍬"
                                        color: root.theme.text
                                        font.family: root.theme.fontIcon
                                        font.pixelSize: 22
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggleMicMute() }
                                    }
                                    Slider {
                                        Layout.fillWidth: true
                                        from: 0; to: 1.5
                                        value: micVolume
                                        onMoved: setMicVolume(value)
                                    }
                                    Text {
                                        text: Math.round(micVolume * 100) + "%"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                        Layout.preferredWidth: 42
                                    }
                                }

                                Text {
                                    text: "Output Device"
                                    color: root.theme.textMuted
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 11
                                    Layout.topMargin: 6
                                }
                                Repeater {
                                    model: sinksList
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        radius: 8
                                        color: sinkHover.hovered ? root.theme.surface3 : root.theme.surface2
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            Text {
                                                text: modelData.desc
                                                color: root.theme.text
                                                font.family: root.theme.fontUi
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        HoverHandler { id: sinkHover; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: setDefaultSink(modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        // ═══════════════ Brightness + Night Light ═══════════════
                        Flickable {
                            visible: activeSection === "brightness"
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: brCol.implicitHeight + 24
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: brCol
                                width: parent.width - 24
                                x: 12
                                y: 12
                                spacing: 14

                                Text {
                                    text: "Brightness"
                                    color: root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "󰃠"
                                        color: root.theme.text
                                        font.family: root.theme.fontIcon
                                        font.pixelSize: 22
                                    }
                                    Slider {
                                        Layout.fillWidth: true
                                        from: 0.01; to: 1
                                        value: brightness
                                        onMoved: setBrightness(value)
                                    }
                                    Text {
                                        text: Math.round(brightness * 100) + "%"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                        Layout.preferredWidth: 42
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    Text {
                                        text: "Night Light"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                        Layout.fillWidth: true
                                    }
                                    ToggleSwitch {
                                        checked: nightLight
                                        onColor: root.theme.orange
                                        onToggled: toggleNightLight()
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: nightLight
                                    spacing: 10
                                    Text {
                                        text: "󰖔"
                                        color: root.theme.orange
                                        font.family: root.theme.fontIcon
                                        font.pixelSize: 20
                                    }
                                    Slider {
                                        Layout.fillWidth: true
                                        from: 2500; to: 6500
                                        value: nightTemp
                                        onMoved: setNightTemp(Math.round(value))
                                    }
                                    Text {
                                        text: nightTemp + "K"
                                        color: root.theme.text
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 52
                                    }
                                }
                            }
                        }

                        // ═══════════════ Notifications ═══════════════
                        ColumnLayout {
                            visible: activeSection === "notif"
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            Text {
                                text: "Notifications"
                                color: root.theme.text
                                font.family: root.theme.fontUi
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Do Not Disturb"
                                    color: root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                }
                                ToggleSwitch {
                                    checked: dnd
                                    onColor: root.theme.orange
                                    onToggled: toggleDnd()
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 12
                                color: root.theme.surface2
                                Text {
                                    anchors.centerIn: parent
                                    text: "Open Notification Center"
                                    color: root.theme.accent
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["swaync-client", "-t"])
                                }
                            }
                        }

                        // ═══════════════ System ═══════════════
                        Flickable {
                            visible: activeSection === "system"
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: sysCol.implicitHeight + 24
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: sysCol
                                width: parent.width - 24
                                x: 12
                                y: 12
                                spacing: 12

                                Text {
                                    text: "System"
                                    color: root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 14
                                    color: root.theme.surface2
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        Column {
                                            Layout.fillWidth: true
                                            Text { text: "CPU"; color: root.theme.textMuted; font.family: root.theme.fontUi; font.pixelSize: 11 }
                                            Text { text: cpuUsage + "%"; color: root.theme.accent; font.family: root.theme.fontUi; font.pixelSize: 20; font.weight: Font.Bold }
                                        }
                                        Text {
                                            text: cpuTemp
                                            color: root.theme.orange
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 14
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 14
                                    color: root.theme.surface2
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        Column {
                                            Layout.fillWidth: true
                                            Text { text: "Memory"; color: root.theme.textMuted; font.family: root.theme.fontUi; font.pixelSize: 11 }
                                            Text { text: memUsage + "%"; color: root.theme.red; font.family: root.theme.fontUi; font.pixelSize: 20; font.weight: Font.Bold }
                                            Text { text: memUsed + " / " + memTotal; color: root.theme.textMuted; font.family: root.theme.fontUi; font.pixelSize: 11 }
                                        }
                                    }
                                }

                                Text {
                                    text: "Power Profile"
                                    color: root.theme.textMuted
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 11
                                    Layout.topMargin: 6
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { id: "power-saver", label: "Saver" },
                                            { id: "balanced",    label: "Balanced" },
                                            { id: "performance", label: "Perf" }
                                        ]
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            radius: 10
                                            color: powerProfile === modelData.id ? root.theme.accent : root.theme.surface2
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: powerProfile === modelData.id ? "#000" : root.theme.text
                                                font.family: root.theme.fontUi
                                                font.pixelSize: 12
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: setPowerProfile(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
