import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io

ShellRoot {
    // ── Volume service (PipeWire) ───────────────────────────────────
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

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

    // ── Brightness service (brightnessctl) ──────────────────────────
    property real brightness: 0.5

    Process {
        id: brightnessGet
        command: ["brightnessctl", "g"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = parseInt(text.trim())
                brightnessMax.running = true
            }
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
                if (max > 0)
                    brightness = cur / max
            }
        }
    }

    function setBrightness(v) {
        v = Math.max(0, Math.min(1, v))
        brightness = v
        Quickshell.execDetached(["brightnessctl", "s", Math.round(v * 100) + "%"])
    }

    // ── The bar ─────────────────────────────────────────────────────
    PanelWindow {
        id: bar

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 40
        color: "transparent"

        // Center pill
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
                    text: "󰥔"          // clock icon (Nerd Font)
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
                        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
                    }
                }
            }

            // Click the pill → open / close the popup
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.visible = !popup.visible
            }
        }

        // ── The popup (anchored under the bar) ──────────────────────
        PopupWindow {
            id: popup

            anchor.window: bar
            anchor.rect.x: bar.width / 2 - implicitWidth / 2
            anchor.rect.y: bar.height + 6

            implicitWidth: 280
            implicitHeight: contentCol.implicitHeight + 32

            visible: false
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1e1e2e"
                radius: 16
                border.color: "#313244"
                border.width: 1

                ColumnLayout {
                    id: contentCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 16
                    }
                    spacing: 16

                    // Brightness
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

                        Text {
                            text: "☀"
                            color: "#cdd6f4"
                            font.pixelSize: 14
                        }

                        Slider {
                            id: brightnessSlider
                            Layout.fillWidth: true
                            from: 0.0
                            to: 1.0
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

                    // Volume
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
                            text: muted ? "🔇" : "🔊"
                            color: "#cdd6f4"
                            font.pixelSize: 14

                            MouseArea {
                                anchors.fill: parent
                                onClicked: toggleMute()
                            }
                        }

                        Slider {
                            id: volumeSlider
                            Layout.fillWidth: true
                            from: 0.0
                            to: 1.0
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
            }
        }
    }
}
