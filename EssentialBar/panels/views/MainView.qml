// MainView.qml
// Default landing view of the control panel (v-main).
// Contains: time/date header + battery card, Wi-Fi row, Bluetooth row,
// quick-tile grid (Focus/Night/Location/Screencast), volume slider,
// brightness slider, and media transport controls.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../core"
import "../../components"
import "../../services"

Item {
    id: root

    // ── Props threaded in from ControlPanel ───────────────────────────────
    property int    pendingUpdates: 0
    property string updateTooltip:  ""

    // ── Helper ────────────────────────────────────────────────────────────
    function formatMediaTime(us): string {
        const s = Math.max(0, Math.floor((Number(us) || 0) / 1000000))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    Flickable {
        anchors.fill:   parent
        contentWidth:   width
        contentHeight:  mainCol.implicitHeight + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: mainCol
            width: parent.width
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
            spacing: Theme.spacingSize(14)

            // ── Time / date header + battery shortcut card ────────────────
            Item {
                Layout.fillWidth:        true
                Layout.preferredHeight:  Theme.dimensionSize(62)

                RowLayout {
                    anchors.fill: parent

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSize(3)
                        Text {
                            text:  Qt.formatTime(ShellState.now, "h:mm AP")
                            color: Theme.fg
                            font.family:       Theme.uiFont
                            font.pixelSize:    Theme.fontSize(30)
                            font.weight:       Theme.fontWeightLight
                            font.letterSpacing: Theme.letterSpacingValue(-1)
                        }
                        Text {
                            text:  Qt.formatDate(ShellState.now, "dddd, MMMM d")
                            color: Theme.muted
                            font.family:    Theme.uiFont
                            font.pixelSize: Theme.fontSize(12)
                        }
                    }

                    // Battery shortcut card
                    Rectangle {
                        Layout.preferredWidth:  Theme.dimensionSize(128)
                        Layout.preferredHeight: Theme.dimensionSize(44)
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        radius: Theme.radiusSize(12)
                        color: batteryCardMouse.pressed
                            ? Theme.surfaceHover
                            : batteryCardMouse.containsMouse ? Theme.surfaceRaised : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.duration(110) } }

                        RowLayout {
                            anchors.fill:    parent
                            anchors.margins: Theme.marginSize(8)
                            spacing: Theme.spacingSize(7)

                            SvgIcon {
                                Layout.preferredWidth:  Theme.dimensionSize(22)
                                Layout.preferredHeight: Theme.dimensionSize(22)
                                iconName: SystemService.batteryCharging ? "battery-charging"
                                    : SystemService.batteryPercent <= 15 ? "battery-low"
                                    : SystemService.batteryPercent < 40  ? "battery-medium" : "battery-full"
                                tone: SystemService.batteryCharging ? "success"
                                    : SystemService.batteryPercent <= 15 ? "error" : "muted"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: Theme.spacingSize(0)
                                Text { text: Math.round(SystemService.batteryPercent) + "%"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightSemibold }
                                Text { text: SystemService.batteryCharging ? "Charging" : "Discharging"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight }
                                Text { text: (SystemService.batteryStatus.split("\n")[1] || ""); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8); elide: Text.ElideRight }
                            }
                        }

                        MouseArea {
                            id: batteryCardMouse
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: (e) => { e.accepted = true; ShellState.goTo("batt") }
                        }
                    }
                }
            }

            // ── Wi-Fi row ─────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth:  true
                implicitHeight:    Theme.dimensionSize(56)
                radius:            Theme.radiusCard
                color:             Theme.surfaceRaised
                border.width:      NetworkService.connected ? 1 : 0
                border.color:      Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.20))

                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.marginSize(14); spacing: Theme.spacingSize(12)

                    Item {
                        Layout.preferredWidth: Theme.dimensionSize(20); Layout.minimumWidth: Theme.dimensionSize(20); Layout.alignment: Qt.AlignVCenter
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(20); height: Theme.dimensionSize(20); iconName: "wifi"; tone: "fg" }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.minimumWidth: Theme.dimensionSize(0); spacing: Theme.spacingSize(1)
                        Text { text: "Wi-Fi"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightMedium }
                        Text { text: !NetworkService.wifiEnabled ? "Off" : NetworkService.connected ? NetworkService.ssid : "Not connected"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    ToggleSwitch { Layout.alignment: Qt.AlignVCenter; checked: NetworkService.wifiEnabled; onToggled: NetworkService.toggleWifi() }
                    Rectangle {
                        Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9)
                        color: wifiArrowHov.containsMouse ? Theme.surfaceHover : "transparent"
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "muted" }
                        MouseArea { id: wifiArrowHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("wifi") }
                    }
                }
                MouseArea { anchors.fill: parent; z: -1; onClicked: ShellState.goTo("wifi") }
            }

            // ── Bluetooth row ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth:  true
                implicitHeight:    Theme.dimensionSize(56)
                radius:            Theme.radiusCard
                color:             Theme.surfaceRaised
                border.width:      BluetoothService.enabled && BluetoothService.connectedDevices.length > 0 ? 1 : 0
                border.color:      Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.20))

                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.marginSize(14); spacing: Theme.spacingSize(12)

                    Item {
                        Layout.preferredWidth: Theme.dimensionSize(20); Layout.minimumWidth: Theme.dimensionSize(20); Layout.alignment: Qt.AlignVCenter
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(20); height: Theme.dimensionSize(20); iconName: "bluetooth"; tone: "fg" }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.minimumWidth: Theme.dimensionSize(0); spacing: Theme.spacingSize(1)
                        Text { text: "Bluetooth"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightMedium }
                        Text { text: !BluetoothService.enabled ? "Off" : BluetoothService.connectedDevices.length > 0 ? BluetoothService.connectedDevices.length + " connected" : "On"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    ToggleSwitch { Layout.alignment: Qt.AlignVCenter; checked: BluetoothService.enabled; enabled: BluetoothService.available; onToggled: BluetoothService.toggle() }
                    Rectangle {
                        Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9)
                        color: btArrowHov.containsMouse ? Theme.surfaceHover : "transparent"
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "muted" }
                        MouseArea { id: btArrowHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("bt") }
                    }
                }
                MouseArea { anchors.fill: parent; z: -1; onClicked: ShellState.goTo("bt") }
            }

            // ── Quick-tile grid: Focus / Night light / Location / Screencast
            GridLayout {
                Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8

                // Focus
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard
                    color: ShellState.focusEnabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised
                    border.width: ShellState.focusEnabled ? 1 : 0; border.color: Theme.acc
                    RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                        SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "moon"; tone: ShellState.focusEnabled ? "accent" : "muted" }
                        Text { text: "Focus"; color: ShellState.focusEnabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                    }
                    MouseArea { anchors.fill: parent; onClicked: ShellState.focusEnabled = !ShellState.focusEnabled }
                }

                // Night light
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard
                    color: NightLightService.enabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised
                    border.width: NightLightService.enabled ? 1 : 0; border.color: Theme.acc
                    RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                        SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "sun"; tone: NightLightService.enabled ? "accent" : "muted" }
                        Text { text: "Night light"; color: NightLightService.enabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                    }
                    MouseArea { anchors.fill: parent; onClicked: if (NightLightService.available) NightLightService.toggle() }
                }

                // Location
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard
                    color: LocationService.enabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised
                    border.width: LocationService.enabled ? 1 : 0; border.color: Theme.acc
                    RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                        SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "map-pin"; tone: LocationService.enabled ? "accent" : "muted" }
                        Text { text: "Location"; color: LocationService.enabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                    }
                    MouseArea { anchors.fill: parent; onClicked: LocationService.toggle() }
                }

                // Screencast
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard
                    color: ShellState.screencastEnabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised
                    border.width: ShellState.screencastEnabled ? 1 : 0; border.color: Theme.acc
                    RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                        SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "screen-share"; tone: ShellState.screencastEnabled ? "accent" : "muted" }
                        Text { text: "Screencast"; color: ShellState.screencastEnabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                    }
                    MouseArea { anchors.fill: parent; onClicked: ShellState.screencastEnabled = !ShellState.screencastEnabled }
                }
            }

            // ── Volume slider ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacingSize(12)
                SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: AudioService.muted ? "volume-x" : "volume-2"; tone: "muted" }
                LevelSlider { Layout.fillWidth: true; value: AudioService.outputMaster; onValueEdited: function(v) { AudioService.setVolume(v) } }
                Text { text: Math.round(AudioService.outputMaster * 100) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.features: ({ "tnum": 1 }) }
                Rectangle {
                    Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9)
                    color: soundOpenHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "muted" }
                    MouseArea { id: soundOpenHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("sound") }
                }
            }

            // ── Brightness slider ─────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacingSize(12)
                SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: "sun"; tone: "muted" }
                LevelSlider { Layout.fillWidth: true; value: BrightnessService.level; onValueEdited: function(v) { BrightnessService.set(v * 100) } }
                Text { text: Math.round(BrightnessService.level * 100) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.features: ({ "tnum": 1 }) }
            }

            // ── Media transport (only when a track is playing) ─────────────
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                visible: MediaService.hasTrack

                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                        Text { Layout.fillWidth: true; text: MediaService.title; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: MediaService.artist; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); elide: Text.ElideRight }
                    }
                    Rectangle {
                        Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9)
                        color: mediaSoundHov.containsMouse ? Theme.surfaceRaised : "transparent"
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "volume-2"; tone: "muted" }
                        MouseArea { id: mediaSoundHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("sound") }
                    }
                }

                // Seek bar
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                    Text { text: root.formatMediaTime(MediaService.displayPosition); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8); font.features: ({ "tnum": 1 }) }
                    Rectangle {
                        Layout.fillWidth: true; height: Theme.dimensionSize(5); radius: Theme.radiusSize(3); color: Theme.surfaceRaised
                        Rectangle { width: parent.width * MediaService.progress; height: parent.height; radius: Theme.radiusSize(3); color: Theme.acc; Behavior on width { NumberAnimation { duration: Theme.duration(120) } } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: function(m) { MediaService.seekToRatio(m.x / width) } }
                    }
                    Text { text: root.formatMediaTime(MediaService.length); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8); font.features: ({ "tnum": 1 }) }
                }

                // Transport buttons
                RowLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacingSize(20)
                    Item { Layout.fillWidth: true }
                    Rectangle { implicitWidth: Theme.dimensionSize(34); implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: mainPrevHov.containsMouse ? Theme.surfaceRaised : "transparent"
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "skip-back"; tone: "muted" }
                        MouseArea { id: mainPrevHov; anchors.fill: parent; hoverEnabled: true; onClicked: MediaService.previous() }
                    }
                    Rectangle { implicitWidth: Theme.dimensionSize(42); implicitHeight: Theme.dimensionSize(42); radius: Theme.radiusSize(21); color: Theme.fg
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: MediaService.playing ? "pause" : "play"; tone: "ink" }
                        MouseArea { anchors.fill: parent; onClicked: MediaService.toggle() }
                    }
                    Rectangle { implicitWidth: Theme.dimensionSize(34); implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: mainNextHov.containsMouse ? Theme.surfaceRaised : "transparent"
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "skip-forward"; tone: "muted" }
                        MouseArea { id: mainNextHov; anchors.fill: parent; hoverEnabled: true; onClicked: MediaService.next() }
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
