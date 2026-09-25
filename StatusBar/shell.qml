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
        purple: "#bf5af2",
        divider: "#3a3a3c",
        fontUi: "Inter",
        fontIcon: "JetBrainsMono Nerd Font",
        barHeight: 40,
        pillHeight: 30,
        popupRadius: 22,
        tileRadius: 14
    })

    FileView {
        path: Qt.resolvedUrl("style.css")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parseCss(text())
        Component.onCompleted: reload()
    }

    function parseCss(css) {
        if (!css) return
        function get(n, f) {
            const m = css.match(new RegExp("--" + n + "\\s*:\\s*([^;]+)", "i"))
            return m ? m[1].trim().replace(/['"]/g, "") : f
        }
        function getPx(n, f) { return parseInt(get(n, f + "px")) || f }
        theme = {
            bg: get("bg", "#000000"),
            surface: get("surface", "#1c1c1e"),
            surface2: get("surface2", "#2c2c2e"),
            border: get("border", "#3a3a3c"),
            text: get("text", "#f5f5f7"),
            textMuted: get("text-muted", "#8e8e93"),
            accent: get("accent", "#0a84ff"),
            green: get("green", "#30d158"),
            red: get("red", "#ff453a"),
            orange: get("orange", "#ff9f0a"),
            purple: get("purple", "#bf5af2"),
            divider: get("divider", "#3a3a3c"),
            fontUi: get("font-ui", "Inter"),
            fontIcon: get("font-icon", "JetBrainsMono Nerd Font"),
            barHeight: getPx("bar-height", 40),
            pillHeight: getPx("pill-height", 30),
            popupRadius: getPx("popup-radius", 22),
            tileRadius: getPx("tile-radius", 14)
        }
    }

    // ── Section state ───────────────────────────────────────────────
    property string activeSection: "wifi"   // wifi | bluetooth | sound | brightness | notif | system

    // ── Volume ──────────────────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    property bool muted:  Pipewire.defaultAudioSink?.audio?.muted  ?? false
    function setVolume(v) {
        if (Pipewire.defaultAudioSink?.audio)
            Pipewire.defaultAudioSink.audio.volume = Math.max(0, Math.min(1, v))
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
        v = Math.max(0, Math.min(1, v))
        brightness = v
        Quickshell.execDetached(["brightnessctl", "s", Math.round(v * 100) + "%"])
    }

    // ── Wi-Fi ───────────────────────────────────────────────────────
    property bool wifiEnabled: false
    property string wifiSsid: "Not connected"
    property int wifiSignal: 0
    property var wifiNetworks: []

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
                const lines = text.trim().split("\n")
                let found = false
                for (let line of lines) {
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
        id: wifiScan
        property string raw: ""
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,ACTIVE", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const list = []
                const seen = {}
                for (let line of lines) {
                    const p = line.split(":")
                    if (p.length < 2 || !p[0] || seen[p[0]]) continue
                    seen[p[0]] = true
                    list.push({
                        ssid: p[0],
                        signal: parseInt(p[1]) || 0,
                        security: p[2] || "",
                        active: p[3] === "yes"
                    })
                }
                list.sort((a, b) => b.signal - a.signal)
                wifiNetworks = list.slice(0, 12)
            }
        }
    }
    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"])
        wifiEnabled = !wifiEnabled
        Qt.callLater(() => { wifiStatus.running = true; wifiCurrent.running = true })
    }
    function connectWifi(ssid) {
        Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid])
        Qt.callLater(() => { wifiCurrent.running = true; wifiScan.running = true })
    }
    function rescanWifi() {
        wifiScan.running = true
    }

    // ── Bluetooth (basic) ───────────────────────────────────────────
    property bool btEnabled: false
    Process {
        id: btStatus
        command: ["bluetoothctl", "show"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: btEnabled = text.indexOf("Powered: yes") !== -1
        }
    }
    function toggleBt() {
        Quickshell.execDetached(["bluetoothctl", "power", btEnabled ? "off" : "on"])
        btEnabled = !btEnabled
        Qt.callLater(() => btStatus.running = true)
    }

    // ── System resources ────────────────────────────────────────────
    property int cpuUsage: 0
    property int memUsage: 0
    property string memUsed: "0"
    property string memTotal: "0"
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
                lastCpuTotal = total
                lastCpuIdle = idle
            }
        }
    }
    Process {
        id: memProc
        command: ["sh", "-c", "free -h | grep Mem"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length >= 3) {
                    memTotal = p[1]
                    memUsed  = p[2]
                }
            }
        }
    }
    Process {
        id: memPctProc
        command: ["sh", "-c", "free | grep Mem"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length >= 3) {
                    const total = parseInt(p[1]) || 1
                    const used  = parseInt(p[2]) || 0
                    memUsage = Math.round(100 * used / total)
                }
            }
        }
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
            wifiStatus.running = true
            wifiCurrent.running = true
            btStatus.running = true
        }
    }

    // ── Bar ─────────────────────────────────────────────────────────
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        implicitHeight: root.theme.barHeight
        color: "transparent"

        // Dynamic Island pill
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
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

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
                        rescanWifi()
                        activeSection = "wifi"
                    }
                }
            }
        }

        // ── Control Center Popup ────────────────────────────────────
        PopupWindow {
            id: popup
            anchor.window: bar
            anchor.rect.x: bar.width / 2 - implicitWidth / 2
            anchor.rect.y: bar.height + 6
            implicitWidth: 340
            implicitHeight: 420
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
                    spacing: 12

                    // ── Section tabs ────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

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
                                Layout.preferredHeight: 52
                                radius: 12
                                color: activeSection === modelData.id ? root.theme.accent : root.theme.surface

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        color: activeSection === modelData.id ? "#000" : root.theme.text
                                        font.family: root.theme.fontIcon
                                        font.pixelSize: 18
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        color: activeSection === modelData.id ? "#000" : root.theme.textMuted
                                        font.family: root.theme.fontUi
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        activeSection = modelData.id
                                        if (modelData.id === "wifi") rescanWifi()
                                    }
                                }
                            }
                        }
                    }

                    // ── Content area ────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: root.theme.surface
                        clip: true

                        // ── Wi-Fi detail ────────────────────────────
                        ColumnLayout {
                            visible: activeSection === "wifi"
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            // Header + toggle
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
                                Rectangle {
                                    width: 48; height: 26; radius: 13
                                    color: wifiEnabled ? root.theme.green : root.theme.surface2
                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: "#fff"
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: wifiEnabled ? parent.width - width - 2 : 2
                                        Behavior on x { NumberAnimation { duration: 180 } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: toggleWifi()
                                    }
                                }
                            }

                            // Current connection
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                radius: 12
                                color: root.theme.surface2
                                visible: wifiEnabled

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10
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
                                            text: wifiSignal > 0 ? "Signal " + wifiSignal + "%" : "Disconnected"
                                            color: root.theme.textMuted
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }

                            // Scan button
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Available networks"
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
                                    font.weight: Font.Medium
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: rescanWifi()
                                    }
                                }
                            }

                            // Network list
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 4
                                model: wifiNetworks

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 44
                                    radius: 10
                                    color: modelData.active ? Qt.rgba(10/255, 132/255, 255/255, 0.15) : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

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
                                                text: (modelData.security || "Open") + " · " + modelData.signal + "%"
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
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (!modelData.active) connectWifi(modelData.ssid)
                                    }
                                }
                            }
                        }

                        // ── Bluetooth detail ────────────────────────
                        ColumnLayout {
                            visible: activeSection === "bluetooth"
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

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
                                    width: 48; height: 26; radius: 13
                                    color: btEnabled ? root.theme.accent : root.theme.surface2
                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: "#fff"
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: btEnabled ? parent.width - width - 2 : 2
                                        Behavior on x { NumberAnimation { duration: 180 } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: toggleBt() }
                                }
                            }

                            Text {
                                text: btEnabled
                                    ? "Bluetooth is on.\nOpen blueman or bluetoothctl for device pairing."
                                    : "Bluetooth is off."
                                color: root.theme.textMuted
                                font.family: root.theme.fontUi
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 10
                                color: root.theme.surface2
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

                        // ── Sound detail ────────────────────────────
                        ColumnLayout {
                            visible: activeSection === "sound"
                            anchors.fill: parent
                            anchors.margins: 12
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
                                    from: 0; to: 1
                                    value: volume
                                    onMoved: setVolume(value)
                                }
                                Text {
                                    text: Math.round(volume * 100) + "%"
                                    color: root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 40
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                radius: 12
                                color: muted ? root.theme.red : root.theme.surface2
                                Text {
                                    anchors.centerIn: parent
                                    text: muted ? "Unmute" : "Mute"
                                    color: muted ? "#fff" : root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: toggleMute()
                                }
                            }
                        }

                        // ── Brightness detail ───────────────────────
                        ColumnLayout {
                            visible: activeSection === "brightness"
                            anchors.fill: parent
                            anchors.margins: 12
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
                                    text: "󰃞"
                                    color: root.theme.text
                                    font.family: root.theme.fontIcon
                                    font.pixelSize: 22
                                }
                                Slider {
                                    Layout.fillWidth: true
                                    from: 0; to: 1
                                    value: brightness
                                    onMoved: setBrightness(value)
                                }
                                Text {
                                    text: Math.round(brightness * 100) + "%"
                                    color: root.theme.text
                                    font.family: root.theme.fontUi
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 40
                                }
                            }
                        }

                        // ── Notifications placeholder ───────────────
                        ColumnLayout {
                            visible: activeSection === "notif"
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Text {
                                text: "Notifications"
                                color: root.theme.text
                                font.family: root.theme.fontUi
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "Notification history will appear here.\nYou can integrate swaync / dunst later."
                                color: root.theme.textMuted
                                font.family: root.theme.fontUi
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 10
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

                        // ── System detail ───────────────────────────
                        ColumnLayout {
                            visible: activeSection === "system"
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Text {
                                text: "System"
                                color: root.theme.text
                                font.family: root.theme.fontUi
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            // CPU card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 70
                                radius: 14
                                color: root.theme.surface2
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    Column {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "CPU"
                                            color: root.theme.textMuted
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: cpuUsage + "%"
                                            color: root.theme.accent
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 22
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }

                            // RAM card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 70
                                radius: 14
                                color: root.theme.surface2
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    Column {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Memory"
                                            color: root.theme.textMuted
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: memUsage + "%"
                                            color: root.theme.red
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 22
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            text: memUsed + " / " + memTotal
                                            color: root.theme.textMuted
                                            font.family: root.theme.fontUi
                                            font.pixelSize: 11
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
