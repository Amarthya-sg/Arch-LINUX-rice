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

    // ── Volume / PipeWire ───────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    property bool muted:  Pipewire.defaultAudioSink?.audio?.muted  ?? false
    function setVolume(v) {
        if (Pipewire.defaultAudioSink?.audio)
            Pipewire.defaultAudioSink.audio.volume = Math.max(0, Math.min(1.5, v))
    }
    function toggleMute() {
        if (Pipewire.defaultAudioSink?.audio)
            Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
    }

    // ── Brightness ──────────────────────────────────────────────────
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

    // ── Wi-Fi ───────────────────────────────────────────────────────
    property bool wifiEnabled: false
    property string wifiSsid: "Not connected"
    property int wifiSignal: 0
    property string wifiIp: ""
    property var wifiNetworks: []
    property string hiddenSsid: ""
    property string hiddenPass: ""
    property bool hotspotActive: false

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
                if (!found) { wifiSsid = "Not connected"; wifiSignal = 0 }
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
        id: hotspotStatus
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: hotspotActive = text.indexOf("Hotspot") !== -1 || text.indexOf("hotspot") !== -1
        }
    }

    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"])
        wifiEnabled = !wifiEnabled
        refreshWifi()
    }
    function connectWifi(ssid) {
        Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid])
        Qt.callLater(refreshWifi)
    }
    function forgetWifi(ssid) {
        Quickshell.execDetached(["nmcli", "connection", "delete", ssid])
        Qt.callLater(refreshWifi)
    }
    function connectHidden() {
        if (!hiddenSsid) return
        const args = ["nmcli", "dev", "wifi", "connect", hiddenSsid]
        if (hiddenPass) args.push("password", hiddenPass)
        Quickshell.execDetached(args)
        hiddenSsid = ""; hiddenPass = ""
        Qt.callLater(refreshWifi)
    }
    function toggleHotspot() {
        if (hotspotActive)
            Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"])
        else
            Quickshell.execDetached(["nmcli", "device", "wifi", "hotspot", "ssid", "QuickShell-Hotspot", "password", "quickshell123"])
        Qt.callLater(() => { hotspotStatus.running = true })
    }
    function refreshWifi() {
        wifiStatus.running = true
        wifiCurrent.running = true
        wifiIpProc.running = true
        wifiScan.running = true
        hotspotStatus.running = true
    }

    // ── Bluetooth ───────────────────────────────────────────────────
    property bool btEnabled: false
    property bool btDiscoverable: false
    property var btDevices: []

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
                    // Device XX:XX:XX:XX:XX:XX Name
                    const m = line.match(/^Device\s+([0-9A-F:]{17})\s+(.+)$/i)
                    if (m) list.push({ mac: m[1], name: m[2], connected: false })
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
                for (let i = 0; i < btDevices.length; i++)
                    btDevices[i].connected = !!connectedMacs[btDevices[i].mac]
                btDevices = btDevices.slice() // trigger update
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
    function pairBt(mac) {
        Quickshell.execDetached(["bluetoothctl", "pair", mac])
    }
    function removeBt(mac) {
        Quickshell.execDetached(["bluetoothctl", "remove", mac])
        Qt.callLater(() => { btScan.running = true })
    }

    // ── System ──────────────────────────────────────────────────────
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

    // ── Notifications / DND ─────────────────────────────────────────
    property bool dnd: false
    function toggleDnd() {
        Quickshell.execDetached(["swaync-client", dnd ? "-dnd_off" : "-dnd_on"])
        dnd = !dnd
    }

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
        }
    }

    // ── Bar + Dynamic Island ────────────────────────────────────────
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
            width: pillContent.implicitWidth + (popup.visible ? 48 : 36)
            height: root.theme.pillHeight
            radius: height / 2
            color: "#000000"
            border.color: "#1c1c1e"
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

        // ── Control Center ──────────────────────────────────────────
        PopupWindow {
            id: popup
            anchor.window: bar
            anchor.rect.x: bar.width / 2 - implicitWidth / 2
            anchor.rect.y: bar.height + 6
            implicitWidth: 360
            implicitHeight: 480
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

                    // Tabs
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: [
                                { id: "wifi", icon: "󰤨", label: "Wi-Fi" },
                                { id: "bluetooth", icon: "󰂯", label: "BT" },
                                { id: "sound", icon: "󰕾", label: "Sound" },
                                { id: "brightness", icon: "󰃠", label: "Bright" },
                                { id: "notif", icon: "󰂚", label: "Notif" },
                                { id: "system", icon: "󰒓", label: "System" }
                            ]
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                radius: 12
                                color: activeSection === modelData.id ? root.theme.accent : root.theme.surface
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

                    // Content
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
                            contentHeight: wifiCol.implicitHeight + 20
                            clip: true
                            ColumnLayout {
                                id: wifiCol
                                width: parent.width
                                anchors.margins: 12
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
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
                                    // Toggle
                                    Rectangle {
                                        width: 46; height: 26; radius: 13
                                        color: wifiEnabled ? root.theme.green : root.theme.surface2
                                        Rectangle {
                                            width: 22; height: 22; radius: 11
                                            color: "#fff"
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: wifiEnabled ? parent.width - 24 : 2
                                            Behavior on x { NumberAnimation { duration: 160 } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: toggleWifi() }
                                    }
                                }

                                // Active connection card
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

                                // Hotspot
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: 10
                                    color: hotspotActive ? root.theme.orange : root.theme.surface2
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        Text {
                                            text: "Hotspot"
                                            color: hotspotActive ? "#000" : root.theme.text
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 13
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: hotspotActive ? "ON" : "OFF"
                                            color: hotspotActive ? "#000" : root.theme.textMuted
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 12
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: toggleHotspot() }
                                }

                                // Hidden network
                                Text {
                                    text: "Connect to Hidden Network"
                                    color: root.theme.textMuted
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 11
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholderText: "SSID"
                                    color: root.theme.text
                                    placeholderTextColor: root.theme.textMuted
                                    background: Rectangle { color: root.theme.surface2; radius: 8 }
                                    onTextChanged: hiddenSsid = text
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholderText: "Password (optional)"
                                    echoMode: TextInput.Password
                                    color: root.theme.text
                                    placeholderTextColor: root.theme.textMuted
                                    background: Rectangle { color: root.theme.surface2; radius: 8 }
                                    onTextChanged: hiddenPass = text
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: 8
                                    color: root.theme.accent
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Connect"
                                        color: "#000"
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: connectHidden() }
                                }

                                // Scan header
                                RowLayout {
                                    Layout.fillWidth: true
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
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 48
                                        radius: 10
                                        color: modelData.active ? Qt.rgba(0.04, 0.52, 1, 0.15) : "transparent"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
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
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (!modelData.active) connectWifi(modelData.ssid)
                                        }
                                    }
                                }
                            }
                        }

                        // ═══════════════ Bluetooth ═══════════════
                        Flickable {
                            visible: activeSection === "bluetooth"
                            anchors.fill: parent
                            contentHeight: btCol.implicitHeight + 20
                            clip: true
                            ColumnLayout {
                                id: btCol
                                width: parent.width
                                anchors.margins: 12
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
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
                                    Rectangle {
                                        width: 46; height: 26; radius: 13
                                        color: btEnabled ? root.theme.accent : root.theme.surface2
                                        Rectangle {
                                            width: 22; height: 22; radius: 11
                                            color: "#fff"
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: btEnabled ? parent.width - 24 : 2
                                            Behavior on x { NumberAnimation { duration: 160 } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: toggleBt() }
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
                                    Rectangle {
                                        width: 46; height: 26; radius: 13
                                        color: btDiscoverable ? root.theme.green : root.theme.surface2
                                        Rectangle {
                                            width: 22; height: 22; radius: 11
                                            color: "#fff"
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: btDiscoverable ? parent.width - 24 : 2
                                            Behavior on x { NumberAnimation { duration: 160 } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: toggleDiscoverable() }
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
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 52
                                        radius: 10
                                        color: modelData.connected ? Qt.rgba(0.04, 0.52, 1, 0.15) : "transparent"
                                        visible: btEnabled
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            Column {
                                                Layout.fillWidth: true
                                                Text {
                                                    text: modelData.name
                                                    color: root.theme.text
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 13
                                                }
                                                Text {
                                                    text: modelData.mac + (modelData.connected ? " · Connected" : "")
                                                    color: root.theme.textMuted
                                                    font.family: root.theme.fontUi
                                                    font.pixelSize: 10
                                                }
                                            }
                                            Text {
                                                text: modelData.connected ? "Disconnect" : "Connect"
                                                color: root.theme.accent
                                                font.family: root.theme.fontUi
                                                font.pixelSize: 11
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: modelData.connected ? disconnectBt(modelData.mac) : connectBt(modelData.mac)
                                                }
                                            }
                                            Text {
                                                text: "✕"
                                                color: root.theme.red
                                                font.pixelSize: 12
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: removeBt(modelData.mac)
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
                                        onClicked: Quickshell.execDetached(["blueman-manager"])
                                    }
                                }
                            }
                        }

                        // ═══════════════ Sound ═══════════════
                        ColumnLayout {
                            visible: activeSection === "sound"
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 16

                            Text {
                                text: "Sound"
                                color: root.theme.text
                                font.family: root.theme.fontUi
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    text: muted ? "󰝟" : "󰕾"
                                    color: root.theme.text
                                    font.family: root.theme.fontIcon
                                    font.pixelSize: 22
                                    MouseArea { anchors.fill: parent; onClicked: toggleMute() }
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
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 12
                                color: muted ? root.theme.red : root.theme.surface2
                                Text {
                                    anchors.centerIn: parent
                                    text: muted ? "Unmute" : "Mute"
                                    color: muted ? "#fff" : root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 13
                                }
                                MouseArea { anchors.fill: parent; onClicked: toggleMute() }
                            }
                        }

                        // ═══════════════ Brightness ═══════════════
                        ColumnLayout {
                            visible: activeSection === "brightness"
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 16

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
                                Rectangle {
                                    width: 46; height: 26; radius: 13
                                    color: dnd ? root.theme.orange : root.theme.surface2
                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: "#fff"
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: dnd ? parent.width - 24 : 2
                                        Behavior on x { NumberAnimation { duration: 160 } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: toggleDnd() }
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
                                    onClicked: Quickshell.execDetached(["swaync-client", "-t"])
                                }
                            }
                        }

                        // ═══════════════ System ═══════════════
                        ColumnLayout {
                            visible: activeSection === "system"
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Text {
                                text: "System"
                                color: root.theme.text
                                font.family: root.theme.fontUi
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            // CPU
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

                            // RAM
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

                            // Power profile
                            Text {
                                text: "Power Profile"
                                color: root.theme.textMuted
                                font.family: root.theme.fontUi
                                font.pixelSize: 11
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [
                                        { id: "power-saver", label: "Saver" },
                                        { id: "balanced", label: "Balanced" },
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
