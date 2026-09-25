import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io

ShellRoot {
    // ── Volume (PipeWire) ───────────────────────────────────────────
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
        stdout: StdioCollector {
            onStreamFinished: brightnessMax.running = true
        }
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
    property string wifiSsid: "Disconnected"

    Process {
        id: wifiStatus
        command: ["nmcli", "-t", "-f", "WIFI", "radio"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: wifiEnabled = text.trim() === "enabled"
        }
    }
    Process {
        id: wifiCurrent
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                let found = false
                for (let line of lines) {
                    const p = line.split(":")
                    if (p[0] === "yes" && p[1]) {
                        wifiSsid = p[1]
                        found = true
                        break
                    }
                }
                if (!found) wifiSsid = "Disconnected"
            }
        }
    }
    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"])
        wifiEnabled = !wifiEnabled
        wifiStatus.running = true
        wifiCurrent.running = true
    }

    // ── System resources ────────────────────────────────────────────
    property int cpuUsage: 0
    property int memUsage: 0
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
                if (lastCpuTotal > 0) {
                    cpuUsage = Math.round(100 * (1 - (idle - lastCpuIdle) / (total - lastCpuTotal)))
                }
                lastCpuTotal = total
                lastCpuIdle = idle
            }
        }
    }
    Process {
        id: memProc
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
            wifiStatus.running = true
            wifiCurrent.running = true
        }
    }

    // ── Bar ─────────────────────────────────────────────────────────
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        color: "transparent"

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: pillContent.implicitWidth + 32
            height: 32
            radius: 16
            color: "#1e1e2e"
            border.color: "#313244"
            border.width: 1

            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: "󰥔"
                    color: "#89b4fa"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    id: clockText
                    color: "#cdd6f4"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "h:mm AP")
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.visible = !popup.visible
            }
        }

        // ── Quick Settings Popup ────────────────────────────────────
        PopupWindow {
            id: popup
            anchor.window: bar
            anchor.rect.x: bar.width / 2 - implicitWidth / 2
            anchor.rect.y: bar.height + 8

            implicitWidth: 320
            implicitHeight: contentCol.implicitHeight + 28
            visible: false
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1e1e2e"
                radius: 20
                border.color: "#313244"
                border.width: 1

                ColumnLayout {
                    id: contentCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 14
                    }
                    spacing: 14

                    // ── Tile row ────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Wi-Fi tile
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70
                            radius: 16
                            color: wifiEnabled ? "#89b4fa" : "#313244"

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: wifiEnabled ? "󰤨" : "󰤭"
                                    color: wifiEnabled ? "#1e1e2e" : "#cdd6f4"
                                    font.pixelSize: 22
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Wi-Fi"
                                    color: wifiEnabled ? "#1e1e2e" : "#cdd6f4"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: wifiSsid.length > 12 ? wifiSsid.substring(0, 11) + "…" : wifiSsid
                                    color: wifiEnabled ? "#1e1e2e" : "#a6adc8"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toggleWifi()
                            }
                        }

                        // Sound tile
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70
                            radius: 16
                            color: muted ? "#313244" : "#a6e3a1"

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: muted ? "󰝟" : "󰕾"
                                    color: muted ? "#cdd6f4" : "#1e1e2e"
                                    font.pixelSize: 22
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Sound"
                                    color: muted ? "#cdd6f4" : "#1e1e2e"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: muted ? "Muted" : Math.round(volume * 100) + "%"
                                    color: muted ? "#a6adc8" : "#1e1e2e"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toggleMute()
                            }
                        }
                    }

                    // ── Brightness ──────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: "Brightness"
                            color: "#cdd6f4"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: "󰃠"; color: "#cdd6f4"; font.pixelSize: 16 }
                            Slider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                from: 0; to: 1
                                value: brightness
                                onMoved: setBrightness(value)
                            }
                            Text {
                                text: Math.round(brightnessSlider.value * 100) + "%"
                                color: "#cdd6f4"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // ── Volume ──────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: "Volume"
                            color: "#cdd6f4"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: muted ? "󰝟" : "󰕾"
                                color: "#cdd6f4"
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: toggleMute()
                                }
                            }
                            Slider {
                                id: volumeSlider
                                Layout.fillWidth: true
                                from: 0; to: 1
                                value: volume
                                onMoved: setVolume(value)
                            }
                            Text {
                                text: Math.round(volumeSlider.value * 100) + "%"
                                color: "#cdd6f4"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // ── System Resources ────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: 14
                        color: "#313244"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 16

                            // CPU
                            Column {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: "CPU"
                                    color: "#a6adc8"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: cpuUsage + "%"
                                    color: "#89b4fa"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }

                            Rectangle { width: 1; Layout.fillHeight: true; color: "#45475a" }

                            // RAM
                            Column {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: "RAM"
                                    color: "#a6adc8"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: memUsage + "%"
                                    color: "#f38ba8"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
