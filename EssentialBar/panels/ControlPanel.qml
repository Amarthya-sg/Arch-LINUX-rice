// ControlPanel.qml — pixel-perfect port of the HTML .panel + all 8 .view sections.
//
// Panel spec (.panel CSS):
//   width: min(380px, 100vw-20px)   → fixed 380
//   max-height: 480px
//   background: var(--s) = Theme.surface
//   border: 1px solid var(--line)
//   border-radius: 22px
//   box-shadow: 0 20px 50px rgba(0,0,0,.25)
//   transition: opacity .2s, transform .25s cubic-bezier(.16,1,.3,1)
//   closed: opacity 0, transform translateY(-6px)
//
// Views (ShellState.activeView):
//   "main"   → v-main   (time, wifi/bt rows, focus/night tiles, vol/bri sliders, media, battery line)
//   "wifi"   → v-wifi   (back, scan sweep, network list)
//   "bt"     → v-bt     (back, scan sweep, device list)
//   "sound"  → v-sound  (back, mute sw, volume slider, output/input device lists)
//   "batt"   → v-batt   (back, hero ring, RAM/storage rings, network dot, fan)
//   "cal"    → v-cal    (back, big clock, month/year nav, 7-col grid)
//   "alerts" → v-alerts (back, clear all, notification list via NotificationPanel)
//   "update" → v-update (back, install all, package list)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../core"
import "../components"
import "../services"

Item {
    id: root

    // ── Sizing (filled by UnifiedPill when embedded) ──────────────────────
    implicitWidth:  Theme.dimensionSize(380)
    implicitHeight: Theme.dimensionSize(480)

    // ── Props threaded in from UnifiedPill / shell.qml ────────────────────
    property int    pendingUpdates: 0
    property string updateTooltip:  "Checking for package updates…"

    function formatMediaTime(microseconds): string {
        const totalSeconds = Math.floor(Math.max(0, Number(microseconds) || 0) / 1000000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    // ── Panel card ────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.fill: parent
        color:  Theme.surface
        radius: Theme.radiusPanel       // 22px
        border.width: Theme.dimensionSize(1)
        border.color: Theme.line
        clip: true

        // Drop shadow: box-shadow 0 20px 50px rgba(0,0,0,.25)
        layer.enabled: true
        layer.effect:  null             // Quickshell uses layer for clipping; shadow via Rectangle below

        // Open/close animation: opacity + translateY(-6px) → matches CSS closed state
        // The panel is now created on open, so start at 0 for one frame to
        // keep the original 200 ms fade-in.
        property bool shown: false
        Timer { interval: 16; running: true; onTriggered: card.shown = true }
        opacity:   ShellState.popupOpen && shown ? Theme.opacityValue(1) : Theme.opacityValue(0)
        transform: Translate { y: ShellState.popupOpen ? 0 : -6 }
        Behavior on opacity   { NumberAnimation { duration: Theme.duration(200); easing.type: Easing.OutQuad } }
        Behavior on transform { } // transform Behavior must be on the value property — see y below

        // ── View router: swap visible Item children ───────────────────────
        // Keep the Focus tile, DND state and bell icon in sync
        Connections {
            target: ShellState
            function onFocusEnabledChanged() {
                if (NotificationService.dndEnabled !== ShellState.focusEnabled)
                    NotificationService.setDnd(ShellState.focusEnabled)
            }
        }
        Connections {
            target: NotificationService
            function onDndEnabledChanged() {
                if (ShellState.focusEnabled !== NotificationService.dndEnabled)
                    ShellState.focusEnabled = NotificationService.dndEnabled
            }
        }
        // We keep each view as a child Item and show only the active one.
        // This avoids StackLayout's clipping issues and mirrors the CSS
        // `.view { display:none } .view.on { display:flex }` pattern.

        // ── Shared inner padding (18px all sides per .view spec) ──────────
        Item {
            id: viewContainer
            anchors.fill:    parent
            anchors.margins: Theme.marginSize(0)   // individual views handle their own 18px padding

            // ────────────────────────────────────────────────────────────
            // V-MAIN  (default landing view)
            // ────────────────────────────────────────────────────────────
            Flickable {
                id: vMain
                visible:      ShellState.activeView === "main"
                anchors.fill: parent
                contentWidth: width
                contentHeight: mainCol.implicitHeight + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: mainCol
                    width:  parent.width
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    anchors.top:    parent.top
                    anchors.margins: Theme.marginSize(18)
                    spacing: Theme.spacingSize(14)

                    // ── Time / date header ────────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.dimensionSize(62)
                        RowLayout {
                            anchors.fill: parent
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSize(3)
                            Text {
                                text:  Qt.formatTime(ShellState.now, "h:mm AP")
                                color: Theme.fg
                                font.family:    Theme.uiFont
                                font.pixelSize: Theme.fontSize(30)
                                font.weight:    Theme.fontWeightLight
                                font.letterSpacing: Theme.letterSpacingValue(-1)
                            }
                            Text {
                                text:  Qt.formatDate(ShellState.now, "dddd, MMMM d")
                                color: Theme.muted
                                font.family:    Theme.uiFont
                                font.pixelSize: Theme.fontSize(12)
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: Theme.dimensionSize(128)
                            Layout.preferredHeight: Theme.dimensionSize(44)
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            radius: Theme.radiusSize(12)
                            color: batteryCardMouse.pressed
                                ? Theme.surfaceHover
                                : batteryCardMouse.containsMouse ? Theme.surfaceRaised : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.duration(110) } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.marginSize(8)
                                spacing: Theme.spacingSize(7)
                                SvgIcon {
                                    Layout.preferredWidth: Theme.dimensionSize(22); Layout.preferredHeight: Theme.dimensionSize(22)
                                    iconName: SystemService.batteryCharging ? "battery-charging"
                                        : SystemService.batteryPercent <= 15 ? "battery-low"
                                        : SystemService.batteryPercent < 40 ? "battery-medium" : "battery-full"
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
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (event) => {
                                    event.accepted = true
                                    ShellState.goTo("batt")
                                }
                            }
                        }
                    }
                    }

                    // ── Wi-Fi row ─────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.dimensionSize(56)
                        radius: Theme.radiusCard
                        color: Theme.surfaceRaised
                        border.width: NetworkService.connected ? 1 : 0
                        border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.20))
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.marginSize(14); spacing: Theme.spacingSize(12)
                            Item { Layout.preferredWidth: Theme.dimensionSize(20); Layout.minimumWidth: Theme.dimensionSize(20); Layout.alignment: Qt.AlignVCenter
                                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(20); height: Theme.dimensionSize(20); iconName: "wifi"; tone: "fg" }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: Theme.dimensionSize(0); spacing: Theme.spacingSize(1)
                                Text { text: "Wi-Fi"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightMedium }
                                Text { text: !NetworkService.wifiEnabled ? "Off" : NetworkService.connected ? NetworkService.ssid : "Not connected"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            ToggleSwitch { Layout.alignment: Qt.AlignVCenter; checked: NetworkService.wifiEnabled; onToggled: NetworkService.toggleWifi() }
                            Rectangle { Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9); color: wifiArrowHov.containsMouse ? Theme.surfaceHover : "transparent"
                                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "muted" }
                                MouseArea { id: wifiArrowHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("wifi") }
                            }
                        }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: ShellState.goTo("wifi") }
                    }

                    // ── Bluetooth row ─────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.dimensionSize(56)
                        radius: Theme.radiusCard
                        color: Theme.surfaceRaised
                        border.width: BluetoothService.enabled && BluetoothService.connectedDevices.length > 0 ? 1 : 0
                        border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.20))
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.marginSize(14); spacing: Theme.spacingSize(12)
                            Item { Layout.preferredWidth: Theme.dimensionSize(20); Layout.minimumWidth: Theme.dimensionSize(20); Layout.alignment: Qt.AlignVCenter
                                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(20); height: Theme.dimensionSize(20); iconName: "bluetooth"; tone: "fg" }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: Theme.dimensionSize(0); spacing: Theme.spacingSize(1)
                                Text { text: "Bluetooth"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightMedium }
                                Text { text: !BluetoothService.enabled ? "Off" : BluetoothService.connectedDevices.length > 0 ? BluetoothService.connectedDevices.length + " connected" : "On"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            ToggleSwitch { Layout.alignment: Qt.AlignVCenter; checked: BluetoothService.enabled; enabled: BluetoothService.available; onToggled: BluetoothService.toggle() }
                            Rectangle { Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9); color: btArrowHov.containsMouse ? Theme.surfaceHover : "transparent"
                                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "muted" }
                                MouseArea { id: btArrowHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("bt") }
                            }
                        }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: ShellState.goTo("bt") }
                    }

                    // ── Quick tiles: Focus / Night light / Location / Screencast
                    GridLayout {
                        Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8
                        Rectangle { Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard; color: ShellState.focusEnabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised; border.width: ShellState.focusEnabled ? 1 : 0; border.color: Theme.acc
                            RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                                SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "moon"; tone: ShellState.focusEnabled ? "accent" : "muted" }
                                Text { text: "Focus"; color: ShellState.focusEnabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                            }
                            MouseArea { anchors.fill: parent; onClicked: ShellState.focusEnabled = !ShellState.focusEnabled }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard; color: NightLightService.enabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised; border.width: NightLightService.enabled ? 1 : 0; border.color: Theme.acc
                            RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                                SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "sun"; tone: NightLightService.enabled ? "accent" : "muted" }
                                Text { text: "Night light"; color: NightLightService.enabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                            }
                            MouseArea { anchors.fill: parent; onClicked: if (NightLightService.available) NightLightService.toggle() }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard; color: LocationService.enabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised; border.width: LocationService.enabled ? 1 : 0; border.color: Theme.acc
                            RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                                SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "map-pin"; tone: LocationService.enabled ? "accent" : "muted" }
                                Text { text: "Location"; color: LocationService.enabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                            }
                            MouseArea { anchors.fill: parent; onClicked: LocationService.toggle() }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusCard; color: ShellState.screencastEnabled ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18)) : Theme.surfaceRaised; border.width: ShellState.screencastEnabled ? 1 : 0; border.color: Theme.acc
                            RowLayout { anchors.centerIn: parent; spacing: Theme.spacingSize(10)
                                SvgIcon { width: Theme.dimensionSize(17); height: Theme.dimensionSize(17); iconName: "screen-share"; tone: ShellState.screencastEnabled ? "accent" : "muted" }
                                Text { text: "Screencast"; color: ShellState.screencastEnabled ? Theme.acc : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                            }
                            MouseArea { anchors.fill: parent; onClicked: ShellState.screencastEnabled = !ShellState.screencastEnabled }
                        }
                    }

                    // ── Volume slider ─────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSize(12)
                        SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: AudioService.muted ? "volume-x" : "volume-2"; tone: "muted" }
                        LevelSlider {
                            Layout.fillWidth: true
                            value:      AudioService.outputMaster
                            onValueEdited: function(v) { AudioService.setVolume(v) }
                        }
                        Text {
                            text:  Math.round(AudioService.outputMaster * 100) + "%"
                            color: Theme.muted
                            font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12)
                            font.features: ({ "tnum": 1 })
                        }
                        Rectangle {
                            Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28)
                            radius: Theme.radiusSize(9)
                            color: soundOpenHov.containsMouse ? Theme.surfaceRaised : "transparent"
                            SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "muted" }
                            MouseArea { id: soundOpenHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("sound") }
                        }
                    }

                    // ── Brightness slider ─────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSize(12)
                        SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: "sun"; tone: "muted" }
                        LevelSlider {
                            Layout.fillWidth: true
                            value:      BrightnessService.level
                            onValueEdited: function(v) { BrightnessService.set(v * 100) }
                        }
                        Text {
                            text:  Math.round(BrightnessService.level * 100) + "%"
                            color: Theme.muted
                            font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12)
                            font.features: ({ "tnum": 1 })
                        }
                    }

                    // ── Media controls with live progress and seek
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSize(6)
                        visible: MediaService.hasTrack
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                Text { Layout.fillWidth: true; text: MediaService.title; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                                Text { Layout.fillWidth: true; text: MediaService.artist; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); elide: Text.ElideRight }
                            }
                            Rectangle { Layout.preferredWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9); color: mediaSoundHov.containsMouse ? Theme.surfaceRaised : "transparent"
                                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "volume-2"; tone: "muted" }
                                MouseArea { id: mediaSoundHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.goTo("sound") }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                            Text { text: root.formatMediaTime(MediaService.displayPosition); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8); font.features: ({ "tnum": 1 }) }
                            Rectangle {
                                id: mainMediaProgress; Layout.fillWidth: true; height: Theme.dimensionSize(5); radius: Theme.radiusSize(3); color: Theme.surfaceRaised
                                Rectangle { width: parent.width * MediaService.progress; height: parent.height; radius: Theme.radiusSize(3); color: Theme.acc; Behavior on width { NumberAnimation { duration: Theme.duration(120) } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: function(mouse) { MediaService.seekToRatio(mouse.x / width) } }
                            }
                            Text { text: root.formatMediaTime(MediaService.length); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8); font.features: ({ "tnum": 1 }) }
                        }
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

            // ────────────────────────────────────────────────────────────
            // V-WIFI  (real Item with id so children can reference it directly)
            // ────────────────────────────────────────────────────────────
            Item {
                id: wifiView
                visible:      ShellState.activeView === "wifi"
                anchors.fill: parent

                // ── Password / credential state lives here with a stable id ──
                property string pwNetKey:    ""   // key of network awaiting password
                property bool   pwVisible:   false
                property var    pwNetworks:  []   // live copy updated via Connections
                property string detailsNetKey: ""
                property bool   detailsPasswordVisible: false

                function nk(n): string { return String(n?.ssid || n?.name || n?.bssid || "") }
                function openPw(n): void  { pwNetKey = nk(n); pwVisible = false }
                function clearPw(): void  { pwNetKey = ""; pwVisible = false }
                function toggleDetails(n): void {
                    const key = nk(n)
                    if (detailsNetKey === key) {
                        detailsNetKey = ""
                        detailsPasswordVisible = false
                        NetworkService.clearSavedPassword()
                        pwNetworks = NetworkService.networks.slice(0)
                        NetworkService.scan()
                        return
                    }
                    detailsNetKey = key
                    detailsPasswordVisible = !!n?.known
                    NetworkService.clearSavedPassword()
                    if (n?.known) NetworkService.revealSavedPassword(n)
                }

                Component.onCompleted: {
                    pwNetworks = NetworkService.networks.slice(0)
                    if (ShellState.popupOpen && ShellState.activeView === "wifi")
                        NetworkService.scan()
                }

                Connections {
                    target: NetworkService
                    function onNetworkListUpdated() {
                        // Freeze the visible list while a details card is open;
                        // scanner updates must not replace five rows with a
                        // partial intermediate result or re-layout the card.
                        if (!wifiView.detailsNetKey)
                            wifiView.pwNetworks = NetworkService.networks.slice(0)
                    }
                    function onConnectionFinished(success, nk) {
                        if (success) {
                            wifiView.clearPw()
                        } else if (nk) {
                            // Keep the retry and authentication error inline;
                            // never create/show a separate desktop dialog.
                            wifiView.pwNetKey = nk
                            wifiView.pwVisible = false
                        }
                    }
                }
                Connections {
                    target: ShellState
                    function onActiveViewChanged() {
                        if (ShellState.popupOpen && ShellState.activeView === "wifi")
                            NetworkService.scan()
                        else
                            NetworkService.stopScan()
                    }
                    function onPopupOpenChanged() {
                        if (ShellState.popupOpen && ShellState.activeView === "wifi")
                            NetworkService.scan()
                        else
                            NetworkService.stopScan()
                    }
                }
                Connections {
                    target: NetworkService
                    function onWifiDeviceChanged() {
                        if (NetworkService.wifiEnabled && ShellState.popupOpen
                                && ShellState.activeView === "wifi")
                            NetworkService.scan()
                    }
                    function onWifiEnabledChanged() {
                        if (NetworkService.wifiEnabled && ShellState.popupOpen
                                && ShellState.activeView === "wifi")
                            NetworkService.scan()
                        else if (!NetworkService.wifiEnabled)
                            NetworkService.stopScan()
                    }
                }
                Timer {
                    interval: 1000
                    repeat: true
                    running: NetworkService.scanning
                    onTriggered: if (!wifiView.detailsNetKey) wifiView.pwNetworks = NetworkService.networks.slice(0)
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(10)

                    // ── Header: back / scan / toggle ─────────────────────
                    RowLayout {
                        Layout.fillWidth: true

                        // Back button
                        Rectangle {
                            implicitHeight: Theme.dimensionSize(40)
                            implicitWidth: wfBackRow.implicitWidth + 20
                            radius: Theme.radiusSize(12)
                            color: wfBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                            RowLayout {
                                id: wfBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                                SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                                Text { text: "Wi-Fi"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                            }
                            MouseArea { id: wfBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                        }

                        Item { Layout.fillWidth: true }

                        // Scan button
                        Rectangle {
                            implicitHeight: Theme.dimensionSize(34)
                            implicitWidth: wfScanLabel.implicitWidth + 24
                            radius: Theme.radiusSize(10)
                            color: wfScanHov.containsMouse ? Theme.surfaceRaised : "transparent"
                            Text { id: wfScanLabel; anchors.centerIn: parent; text: NetworkService.scanning ? "Stop" : "Scan"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                            MouseArea {
                                id: wfScanHov; anchors.fill: parent; hoverEnabled: true
                                enabled: NetworkService.wifiEnabled || NetworkService.scanning
                                onClicked: NetworkService.scanning ? NetworkService.stopScan() : NetworkService.scan()
                            }
                        }

                        ToggleSwitch { checked: NetworkService.wifiEnabled; onToggled: NetworkService.toggleWifi() }
                    }

                    // ── Scan sweep line ───────────────────────────────────
                    ScanSweep {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.marginSize(8); Layout.rightMargin: Theme.marginSize(8)
                        active: NetworkService.scanning
                    }

                    // ── Empty states ──────────────────────────────────────
                    Text { visible: !NetworkService.wifiEnabled; text: "Turn Wi-Fi on to see networks."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
                    Text {
                        visible: NetworkService.wifiEnabled && wifiView.pwNetworks.length === 0
                        text: NetworkService.scanning ? "Scanning…" : "No networks found. Tap Scan."
                        color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12)
                    }

                    // ── Network list ──────────────────────────────────────
                    Flickable {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        contentWidth: width; contentHeight: wfNetCol.implicitHeight; clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: wfNetCol; width: parent.width; spacing: Theme.spacingSize(6)

                            Repeater {
                                model: wifiView.pwNetworks   // ← direct id reference, no parent chains

                                delegate: Item {
                                    id: netRow
                                    required property var  modelData
                                    required property int  index
                                    Layout.fillWidth: true

                                    // Computed once; refreshed when wifiView state changes
                                    readonly property string thisKey:   String(modelData?.ssid || modelData?.name || modelData?.bssid || "")
                                    readonly property bool   isPwRow:   wifiView.pwNetKey === thisKey
                                    readonly property bool   isDetailsRow: wifiView.detailsNetKey === thisKey
                                    readonly property bool   isConnecting: NetworkService.connectingNetworkKey === thisKey

                                    implicitHeight: netRowInner.implicitHeight + 20
                                    Layout.preferredHeight: netRowInner.implicitHeight + 20

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusCard
                                        color:  modelData.connected ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.10)) : Theme.surfaceRaised
                                        border.width: modelData.connected ? 1 : 0
                                        border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.25))
                                    }

                                    ColumnLayout {
                                        id: netRowInner
                                        anchors { left: parent.left; right: parent.right; top: parent.top }
                                        anchors.margins: Theme.marginSize(10); spacing: Theme.spacingSize(6)

                                        // ── Network info + action button ──────────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: Theme.spacingSize(8)

                                            // Signal icon
                                            SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: "wifi"; tone: "fg" }

                                            ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                                Text { Layout.fillWidth: true; text: modelData.name || "Hidden network"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightSemibold; elide: Text.ElideRight }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: Math.round(Number(modelData.signalStrength || 0) * 100) + "% · "
                                                        + NetworkService.security(modelData)
                                                        + (modelData.connected ? " · connected" : modelData.known ? " · saved" : "")
                                                    color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight
                                                }
                                            }

                                            // Connect / Disconnect button
                                            Rectangle {
                                                implicitWidth: connLabel.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                                                color: connHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                                Text {
                                                    id: connLabel; anchors.centerIn: parent
                                                    text: modelData.connected ? "Disconnect" : netRow.isConnecting ? "…" : "Connect"
                                                    color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium
                                                }
                                                MouseArea {
                                                    id: connHov; anchors.fill: parent; hoverEnabled: true
                                                    enabled: modelData.connected || NetworkService.connectingNetworkKey === ""
                                                    onClicked: {
                                                        if (modelData.connected) {
                                                            NetworkService.disconnect(modelData)
                                                        } else if (NetworkService.security(modelData) === "Open" || modelData.known) {
                                                            NetworkService.connect(modelData)
                                                        } else {
                                                            wifiView.openPw(modelData)  // ← direct id, no parent chains
                                                        }
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                implicitWidth: Theme.dimensionSize(30); implicitHeight: Theme.dimensionSize(30); radius: Theme.radiusSize(15)
                                                color: netInfoHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                                Text { anchors.centerIn: parent; text: "i"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightBold }
                                                MouseArea { id: netInfoHov; anchors.fill: parent; hoverEnabled: true; onClicked: wifiView.toggleDetails(modelData) }
                                            }
                                            Rectangle {
                                                visible: !!modelData.known
                                                implicitWidth: forgetWifiLabel.implicitWidth + 18; implicitHeight: Theme.dimensionSize(30); radius: Theme.radiusSize(10)
                                                color: forgetWifiHov.containsMouse ? Qt.rgba(1, 0.42, 0.37, Theme.opacityValue(0.20)) : Theme.surfaceRaised
                                                Text { id: forgetWifiLabel; anchors.centerIn: parent; text: "Forget"; color: Theme.error; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                                                MouseArea { id: forgetWifiHov; anchors.fill: parent; hoverEnabled: true; onClicked: NetworkService.forget(modelData) }
                                            }
                                        }

                                        Rectangle {
                                            visible: netRow.isDetailsRow
                                            Layout.fillWidth: true
                                            implicitHeight: detailsCardCol.implicitHeight + 18
                                            Layout.preferredHeight: detailsCardCol.implicitHeight + 18
                                            radius: Theme.radiusSize(12)
                                            color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.045))
                                            border.width: Theme.dimensionSize(1); border.color: Theme.line
                                            ColumnLayout {
                                                id: detailsCardCol
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                anchors.margins: Theme.marginSize(9); spacing: Theme.spacingSize(5)
                                                RowLayout {
                                                    Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                                                    Text { text: "NETWORK DETAILS"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; font.letterSpacing: Theme.letterSpacingValue(0.7); Layout.fillWidth: true }
                                                    Rectangle {
                                                        implicitWidth: detailsStatusText.implicitWidth + 12; implicitHeight: Theme.dimensionSize(20); radius: Theme.radiusSize(10)
                                                        color: modelData.connected ? Qt.rgba(0.35, 0.85, 0.55, Theme.opacityValue(0.16)) : Qt.rgba(1, 1, 1, Theme.opacityValue(0.08))
                                                        Text { id: detailsStatusText; anchors.centerIn: parent; text: modelData.connected ? "Connected" : modelData.known ? "Saved" : "Available"; color: modelData.connected ? Theme.success : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightMedium }
                                                    }
                                                }
                                                Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.line; opacity: Theme.opacityValue(0.7)}
                                                RowLayout {
                                                    Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                                                    Text { text: "SSID:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: modelData.ssid || modelData.name || "—"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightSemibold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                    Text { text: NetworkService.security(modelData); color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightMedium }
                                                }
                                                RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                                    Text { text: "Signal:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: NetworkService.signalPercentage(modelData) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true }
                                                }
                                                RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                                    Text { text: "Band:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: NetworkService.bandChannel(modelData).replace("Band unavailable", "Unknown"); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                                }
                                                RowLayout {
                                                    visible: !!modelData.bssid; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                                    Text { text: "BSSID:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: modelData.bssid || "—"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                RowLayout {
                                                    visible: !!modelData.connected; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                                    Text { text: "IP:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: NetworkService.ipAddress; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                                }
                                                RowLayout {
                                                    visible: !!modelData.connected; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                                    Text { text: "Gateway:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: NetworkService.gateway; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                                }
                                                RowLayout {
                                                    visible: !!modelData.connected; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                                    Text { text: "DNS:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text { text: NetworkService.dnsServer; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                                }
                                                RowLayout {
                                                    visible: !!modelData.known
                                                    Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                                                    Text { text: "Password:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: NetworkService.passwordLookupBusy ? "loading…"
                                                            : NetworkService.revealedPasswordKey === netRow.thisKey
                                                                ? (wifiView.detailsPasswordVisible ? (NetworkService.revealedPassword || "Unavailable") : "••••••••")
                                                                : "Unavailable"
                                                        color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight
                                                    }
                                                    Rectangle {
                                                        visible: NetworkService.revealedPasswordKey === netRow.thisKey && !!NetworkService.revealedPassword
                                                        implicitWidth: detailsPasswordAction.implicitWidth + 18; implicitHeight: Theme.dimensionSize(24); radius: Theme.radiusSize(8)
                                                        color: detailsPasswordHov.containsMouse ? Theme.surfaceHover : Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.12))
                                                        Text { id: detailsPasswordAction; anchors.centerIn: parent; text: wifiView.detailsPasswordVisible ? "Hide" : "Show"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightMedium }
                                                        MouseArea { id: detailsPasswordHov; anchors.fill: parent; hoverEnabled: true; onClicked: wifiView.detailsPasswordVisible = !wifiView.detailsPasswordVisible }
                                                    }
                                                }
                                            }
                                        }

                                        // ── Password entry (shown when isPwRow) ───────────
                                        ColumnLayout {
                                            visible:          netRow.isPwRow
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSize(6)

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: Theme.spacingSize(6)

                                                TextField {
                                                    id: pwInput
                                                    Layout.fillWidth:    true
                                                    focus:              netRow.isPwRow
                                                    activeFocusOnPress: true
                                                    selectByMouse:      true
                                                    placeholderText:     "Password for " + (modelData.name || "network")
                                                    echoMode:            wifiView.pwVisible ? TextInput.Normal : TextInput.Password
                                                    color:               Theme.fg
                                                    placeholderTextColor: Theme.muted
                                                    font.family:         Theme.uiFont
                                                    font.pixelSize:      Theme.fontSize(12)
                                                    background: Rectangle {
                                                        radius: Theme.radiusSize(10); color: Theme.surfaceRaised
                                                        border.width: Theme.dimensionSize(1)
                                                        border.color: pwInput.activeFocus ? Theme.acc : Theme.line
                                                    }
                                                    // Focus automatically when the row appears
                                                    onVisibleChanged: if (visible) pwFocusTimer.restart()
                                                    Timer { id: pwFocusTimer; interval: 0; repeat: false; onTriggered: if (pwInput.visible) pwInput.forceActiveFocus() }
                                                    // Enter key submits
                                                    onAccepted: {
                                                        if (text.length >= 8) {
                                                            NetworkService.connect(modelData, text)
                                                            wifiView.clearPw()
                                                        }
                                                    }
                                                }

                                                // show / hide toggle
                                                Rectangle {
                                                    implicitWidth: pwTogLabel.implicitWidth + 18; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                                                    color: pwTogHov.containsMouse ? Theme.surfaceRaised : "transparent"
                                                    Text { id: pwTogLabel; anchors.centerIn: parent; text: wifiView.pwVisible ? "hide" : "show"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                                    MouseArea { id: pwTogHov; anchors.fill: parent; hoverEnabled: true; onClicked: wifiView.pwVisible = !wifiView.pwVisible }
                                                }

                                                // Join button
                                                Rectangle {
                                                    id: joinBtn
                                                    implicitWidth: joinLabel.implicitWidth + 20; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                                                    color: joinHov.containsMouse && pwInput.length >= 8 ? Theme.acc : Theme.surfaceRaised
                                                    opacity: pwInput.text.length >= 8 ? Theme.opacityValue(1) : Theme.opacityValue(0.45)
                                                    Text { id: joinLabel; anchors.centerIn: parent; text: "Join"; color: joinHov.containsMouse && pwInput.text.length >= 8 ? Theme.islandBg : Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightSemibold }
                                                    MouseArea {
                                                        id: joinHov; anchors.fill: parent; hoverEnabled: true
                                                        enabled: pwInput.text.length >= 8
                                                        onClicked: {
                                                            NetworkService.connect(modelData, pwInput.text)
                                                            wifiView.clearPw()
                                                        }
                                                    }
                                                }

                                                // Cancel button
                                                Rectangle {
                                                    implicitWidth: Theme.dimensionSize(60); implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                                                    color: cancelHov.containsMouse ? Theme.surfaceRaised : "transparent"
                                                    Text { id: cancelLabel; anchors.centerIn: parent; text: "Cancel"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
                                                    MouseArea { id: cancelHov; anchors.fill: parent; hoverEnabled: true; onClicked: wifiView.clearPw() }
                                                }
                                            }

                                            Text {
                                                visible: NetworkService.connectionErrorKey === netRow.thisKey && NetworkService.connectionError !== ""
                                                Layout.fillWidth: true
                                                text: NetworkService.connectionError
                                                color: Theme.error; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); wrapMode: Text.Wrap
                                            }

                                        }

                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ────────────────────────────────────────────────────────────
            // V-BT
            // ────────────────────────────────────────────────────────────
            BluetoothView { visible: ShellState.activeView === "bt"; anchors.fill: parent }

            // ────────────────────────────────────────────────────────────
            // V-SOUND
            // ────────────────────────────────────────────────────────────
            SoundView { visible: ShellState.activeView === "sound"; anchors.fill: parent }

            // ────────────────────────────────────────────────────────────
            // V-BATT
            // ────────────────────────────────────────────────────────────
            BatteryView { visible: ShellState.activeView === "batt"; anchors.fill: parent }

            // ────────────────────────────────────────────────────────────
            // V-CAL
            // ────────────────────────────────────────────────────────────
            CalendarView { visible: ShellState.activeView === "cal"; anchors.fill: parent }

            // ────────────────────────────────────────────────────────────
            // V-ALERTS
            // ────────────────────────────────────────────────────────────
            AlertsView { visible: ShellState.activeView === "alerts"; anchors.fill: parent }

            // ────────────────────────────────────────────────────────────
            // V-UPDATE
            // ────────────────────────────────────────────────────────────
            UpdateView {
                visible:        ShellState.activeView === "update"
                anchors.fill:   parent
                pendingUpdates: root.pendingUpdates
                updateTooltip:  root.updateTooltip
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // INLINE VIEW COMPONENTS
    // ════════════════════════════════════════════════════════════════════════

    // ── Scan sweep line ──────────────────────────────────────────────────
    // Matches .scan + .scan.busy::after from the CSS.
    component ScanBar: Item {
        property bool scanning: false
        Layout.fillWidth: true
        implicitHeight:   Theme.dimensionSize(4)

        Rectangle { anchors.fill: parent; radius: Theme.radiusSize(2); color: Theme.line }
        Rectangle {
            id: sweeper
            height: parent.height; width: parent.width * 0.30; radius: Theme.radiusSize(2)
            color: Theme.fg; opacity: scanning ? Theme.opacityValue(0.9) : Theme.opacityValue(0)
            NumberAnimation on x {
                from: -sweeper.width; to: sweeper.parent.width
                duration: Theme.duration(1000); loops: Animation.Infinite; running: scanning
                easing.type: Easing.InOutSine
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // V-BT VIEW
    // ════════════════════════════════════════════════════════════════════════
    // Reusable scan indicator: rounded track, bar bounces inside it.
    // Fixed height so lists below never jump; fades in/out with `active`.
    component ScanSweep: Item {
        id: sweepRoot
        property bool active: false
        implicitHeight: Theme.dimensionSize(6)
        opacity: active ? Theme.opacityValue(1) : Theme.opacityValue(0)
        Behavior on opacity { NumberAnimation { duration: Theme.duration(250); easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.line
        }
        Rectangle {
            id: sweepBar
            height: parent.height
            width: parent.width * 0.3
            radius: height / 2
            color: Theme.acc

            SequentialAnimation on x {
                loops: Animation.Infinite
                // keep running until the fade-out has finished
                running: sweepRoot.active || sweepRoot.opacity > 0.01
                NumberAnimation {
                    from: 0; to: sweepRoot.width - sweepBar.width
                    duration: Theme.duration(900); easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: sweepRoot.width - sweepBar.width; to: 0
                    duration: Theme.duration(900); easing.type: Easing.InOutSine
                }
            }
        }
    }

    component BluetoothView: Item {
        id: btViewRoot
        property string detailsAddress: ""
        function toggleDetails(device): void {
            const address = String(BluetoothService.value(device, "address") || "")
            detailsAddress = detailsAddress === address ? "" : address
        }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(10)

            // Header
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    implicitHeight: Theme.dimensionSize(40); implicitWidth: bbtRow.implicitWidth + 20; radius: Theme.radiusSize(12)
                    color: bbtBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    RowLayout { id: bbtRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                        SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                        Text { text: "Bluetooth"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                    }
                    MouseArea { id: bbtBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitHeight: Theme.dimensionSize(34); implicitWidth: btScanTxt.implicitWidth + 24; radius: Theme.radiusSize(10)
                    color: btScanHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    Text { id: btScanTxt; anchors.centerIn: parent; text: BluetoothService.scanning ? "Stop" : "Scan"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                    MouseArea { id: btScanHov; anchors.fill: parent; hoverEnabled: true; enabled: BluetoothService.enabled || BluetoothService.scanning
                        onClicked: BluetoothService.scanning ? BluetoothService.stopScan() : BluetoothService.scan() }
                }
                ToggleSwitch { checked: BluetoothService.enabled; enabled: BluetoothService.available; onToggled: BluetoothService.toggle() }
            }

            ScanSweep {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.marginSize(8); Layout.rightMargin: Theme.marginSize(8)
                active: BluetoothService.scanning
            }

            Text { visible: !BluetoothService.enabled; text: "Turn Bluetooth on to discover devices."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }

            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: btDevCol.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: btDevCol; width: parent.width; spacing: Theme.spacingSize(6)

                    Repeater {
                        model: BluetoothService.devices
                        delegate: Rectangle {
                            required property var modelData
                            readonly property string deviceAddress: String(BluetoothService.value(modelData, "address") || "")
                            readonly property bool detailsOpen: btViewRoot.detailsAddress === deviceAddress
                            readonly property string devStatus: BluetoothService.deviceStatus(modelData)
                            readonly property bool busy: devStatus.endsWith("…")
                            Layout.fillWidth: true; implicitHeight: btDevRow.implicitHeight + 20 + (detailsOpen ? btDetailsCol.implicitHeight + 8 : 0); radius: Theme.radiusCard
                            color: BluetoothService.value(modelData, "connected") ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.10)) : Theme.surfaceRaised
                            border.width: BluetoothService.value(modelData, "connected") ? 1 : 0
                            border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.25))

                            RowLayout {
                                id: btDevRow
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.margins: Theme.marginSize(10); spacing: Theme.spacingSize(8)

                                Rectangle {
                                    width: Theme.dimensionSize(9); height: Theme.dimensionSize(9); radius: Theme.radiusSize(5)
                                    color: BluetoothService.value(modelData, "connected") ? Theme.success
                                        : BluetoothService.value(modelData, "paired") ? Theme.acc : Theme.muted
                                }
                                ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                    Text { text: BluetoothService.displayName(modelData) || "Bluetooth device"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightSemibold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: BluetoothService.deviceStatus(modelData) + (BluetoothService.value(modelData, "batteryAvailable") ? " · " + Math.round(BluetoothService.value(modelData, "battery") * 100) + "%" : ""); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Rectangle {
                                    implicitWidth: btActTxt.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: btActHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                    Text { id: btActTxt; anchors.centerIn: parent; text: busy ? devStatus : !BluetoothService.value(modelData, "paired") ? "Pair" : BluetoothService.value(modelData, "connected") ? "Disconnect" : "Connect"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                    MouseArea { id: btActHov; anchors.fill: parent; hoverEnabled: true; enabled: !busy; onClicked: BluetoothService.activate(modelData) }
                                }
                                Rectangle {
                                    implicitWidth: Theme.dimensionSize(30); implicitHeight: Theme.dimensionSize(30); radius: Theme.radiusSize(15)
                                    color: btInfoHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                    Text { anchors.centerIn: parent; text: "i"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightBold }
                                    MouseArea { id: btInfoHov; anchors.fill: parent; hoverEnabled: true; onClicked: btViewRoot.toggleDetails(modelData) }
                                }
                                Rectangle {
                                    visible: BluetoothService.value(modelData, "paired")
                                    implicitWidth: Theme.dimensionSize(60); implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: btForgetHov.containsMouse ? Qt.rgba(1, 0.42, 0.37, Theme.opacityValue(0.20)) : Theme.surfaceRaised
                                    Text { anchors.centerIn: parent; text: "Forget"; color: Theme.error; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                    MouseArea { id: btForgetHov; anchors.fill: parent; hoverEnabled: true; onClicked: BluetoothService.forget(modelData) }
                                }
                            }
                            ColumnLayout {
                                id: btDetailsCol
                                visible: detailsOpen
                                anchors { left: parent.left; right: parent.right; top: btDevRow.bottom; leftMargin: Theme.marginSize(10); rightMargin: Theme.marginSize(10); bottomMargin: Theme.marginSize(10) }
                                spacing: Theme.spacingSize(2)
                                Text { Layout.fillWidth: true; text: "Address: " + deviceAddress; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                                Text { Layout.fillWidth: true; text: "Status: " + BluetoothService.deviceStatus(modelData); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                                Text { visible: BluetoothService.value(modelData, "batteryAvailable"); Layout.fillWidth: true; text: "Battery: " + Math.round(BluetoothService.value(modelData, "battery") * 100) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10) }
                            }
                        }
                    }

                    Text { visible: BluetoothService.devices.length === 0 && !BluetoothService.scanning; text: "No devices found. Tap Scan."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // V-SOUND VIEW
    // ════════════════════════════════════════════════════════════════════════
    component SoundView: Item {
        Flickable {
            anchors.fill: parent; contentWidth: width; contentHeight: sndCol.implicitHeight + 36; clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: sndCol; width: parent.width
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
                spacing: Theme.spacingSize(12)

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: sndBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: sndBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                        RowLayout { id: sndBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6); SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" } Text { text: "Sound"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont } }
                        MouseArea { id: sndBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch { checked: !AudioService.muted; onClicked: AudioService.setMuted(!checked) }
                }

                // Volume slider
                RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(12)
                    SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: AudioService.muted ? "volume-x" : "volume-2"; tone: "muted" }
                    LevelSlider { Layout.fillWidth: true; value: AudioService.outputMaster; onValueEdited: function(v) { AudioService.setVolume(v) } }
                    Text { text: Math.round(AudioService.outputMaster * 100) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.features: ({ "tnum": 1 }) }
                }
                ChannelBalance {
                    Layout.fillWidth: true
                    value: AudioService.outputBalance
                    supported: AudioService.outputBalanceSupported
                    onValueEdited: function(v) { AudioService.setOutputBalance(v) }
                }

                // Outputs label
                Text { text: "Output"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }

                // Output device list
                Repeater {
                    model: AudioService.outputChoices
                    delegate: Rectangle {
                        required property var modelData; required property int index
                        Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(44); radius: Theme.radiusCard
                        color: modelData.active ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.12)) : outDevHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                        border.width: modelData.active ? 1 : 0; border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.30))
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(10)
                            // Speaker / output icon
                            SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "volume-2"; tone: modelData.active ? "accent" : "muted" }
                            ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                Text { Layout.fillWidth: true; text: modelData.description || modelData.name || "Output"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                                Text { Layout.fillWidth: true; text: (modelData.active ? "Active · " : "") + (modelData.detail || ""); color: modelData.active ? Theme.success : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                            }
                        }
                        MouseArea { id: outDevHov; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.selectOutput(modelData) }
                    }
                }

                // Input devices label
                Text { text: "Input"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }

                // Input device list
                Repeater {
                    model: AudioService.inputChoices
                    delegate: Rectangle {
                        required property var modelData; required property int index
                        Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(44); radius: Theme.radiusCard
                        color: modelData.active ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.12)) : inDevHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                        border.width: modelData.active ? 1 : 0; border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.30))
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(10)
                            // Microphone / input icon
                            SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "mic"; tone: modelData.active ? "accent" : "muted" }
                            ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                Text { Layout.fillWidth: true; text: modelData.description || modelData.name || "Input"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                                Text { Layout.fillWidth: true; text: (modelData.active ? "Active · " : "") + (modelData.detail || ""); color: modelData.active ? Theme.success : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                            }
                        }
                        MouseArea { id: inDevHov; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.selectInput(modelData) }
                    }
                }
                Text {
                    visible: AudioService.inputChoices.length === 0
                    text: "No input devices detected"
                    color: Theme.muted
                    font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.italic: true
                    Layout.leftMargin: Theme.marginSize(4)
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // V-BATT VIEW
    // ════════════════════════════════════════════════════════════════════════
    component BatteryView: Item {
        id: battViewRoot
        readonly property var   battery:        UPower.displayDevice
        readonly property real  battPct:        SystemService.batteryAvailable
            ? SystemService.batteryPercent
            : battery && Number.isFinite(Number(battery.percentage))
                ? Math.max(0, Math.min(100, Number(battery.percentage) * 100)) : 0
        readonly property bool  battCharging:   SystemService.batteryAvailable
            ? SystemService.batteryCharging : battery && battery.state === 1
        readonly property color battColor:
            battCharging ? Theme.success
            : battPct <= 20 ? Theme.error
            : battPct <= 40 ? Theme.warning
            : Theme.fg

        Flickable {
            anchors.fill: parent; contentWidth: width; contentHeight: battCol.implicitHeight + 36; clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: battCol; width: parent.width
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
                spacing: Theme.spacingSize(12)

                // Header (back button)
                Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: battBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: battBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    RowLayout { id: battBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6); SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" } Text { text: "Battery"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont } }
                    MouseArea { id: battBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                }

                // Hero: ring + side stats (.bhero)
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(16)

                    // Big circular battery gauge (132×132)
                    Gauge {
                        hero:      true
                        value:     battViewRoot.battPct / 100
                        valueText: Math.round(battViewRoot.battPct) + "%"
                        accent:    battViewRoot.battColor
                    }

                    // Side stats (.bside)
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Theme.spacingSize(10)

                        // Status chip (.bchip)
                        Rectangle {
                            implicitWidth:  bChipRow.implicitWidth + 20
                            implicitHeight: Theme.dimensionSize(24); radius: Theme.radiusSize(99)
                            color: Qt.rgba(battViewRoot.battColor.r, battViewRoot.battColor.g, battViewRoot.battColor.b, Theme.opacityValue(0.14))
                            RowLayout { id: bChipRow; anchors.centerIn: parent; spacing: Theme.spacingSize(5)
                                SvgIcon {
                                    width: Theme.dimensionSize(14); height: Theme.dimensionSize(14)
                                    iconName: battViewRoot.battCharging ? "battery-charging"
                                        : battViewRoot.battPct <= 20 ? "battery-low"
                                        : battViewRoot.battPct <= 40 ? "battery-medium" : "battery-full"
                                    tone: battViewRoot.battCharging ? "success"
                                        : battViewRoot.battPct <= 20 ? "error"
                                        : battViewRoot.battPct <= 40 ? "warning" : "fg"
                                }
                                Text {
                                    text: battViewRoot.battCharging ? "Charging"
                                        : battViewRoot.battPct <= 20 ? "Low battery" : "On battery"
                                    color: battViewRoot.battColor
                                    font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium
                                }
                            }
                        }

                        // Stats rows (.bstats)
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: Theme.spacingSize(0)
                            Repeater {
                                model: [
                                    { k: SystemService.batteryCharging ? "To full" : "Remaining", v: SystemService.batteryStatus.split("\n")[1] || "—" },
                                    { k: "Power",    v: SystemService.batteryPower    || "—" },
                                    { k: "Energy",   v: SystemService.batteryEnergy   || "—" },
                                    { k: "Health",   v: SystemService.batteryHealth   || "—" },
                                    { k: "Voltage",  v: SystemService.batteryVoltage  || "—" },
                                ]
                                delegate: ColumnLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; spacing: Theme.spacingSize(0)
                                    Rectangle { visible: index > 0; Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.line }
                                    RowLayout { Layout.fillWidth: true
                                        Text { text: modelData.k; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); Layout.fillWidth: true }
                                        Text { text: String(modelData.v || "—"); color: Theme.fg;   font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightSemibold; font.features: ({ "tnum": 1 }) }
                                    }
                                }
                            }
                        }
                    }
                }

                // Memory & storage heading
                Text { text: "Memory & storage"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.dimensionSize(102)
                        radius: Theme.radiusCard
                        color: Theme.surfaceRaised
                        border.width: Theme.dimensionSize(1)
                        border.color: Theme.line
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.marginSize(12)
                            spacing: Theme.spacingSize(5)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "RAM"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                                Text { text: SystemService.memoryPercent.toFixed(0) + "%"; color: Theme.success; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line
                                Rectangle {
                                    width: parent.width * SystemService.memoryPercent / 100
                                    height: parent.height; radius: Theme.radiusSize(4)
                                    color: SystemService.memoryPercent >= 85 ? Theme.error : SystemService.memoryPercent >= 65 ? Theme.warning : Theme.success
                                }
                            }
                            Text { text: SystemService.memoryLabel; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.dimensionSize(102)
                        radius: Theme.radiusCard
                        color: Theme.surfaceRaised
                        border.width: Theme.dimensionSize(1)
                        border.color: Theme.line
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.marginSize(12)
                            spacing: Theme.spacingSize(5)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "CPU"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                                Text { text: SystemService.cpuPercent.toFixed(0) + "%"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line
                                Rectangle { width: parent.width * SystemService.cpuPercent / 100; height: parent.height; radius: Theme.radiusSize(4); color: Theme.acc }
                            }
                            Text { text: SystemService.cpuModel; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }

                    Repeater {
                        model: SystemService.gpuStats
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: Theme.dimensionSize(102)
                            radius: Theme.radiusCard
                            color: Theme.surfaceRaised
                            border.width: Theme.dimensionSize(1)
                            border.color: Theme.line
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.marginSize(12)
                                spacing: Theme.spacingSize(5)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: modelData.kind === "Discrete" ? "dGPU" : modelData.kind === "Integrated" ? "iGPU" : "GPU"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                                    Text { text: modelData.sleeping ? "—" : Math.round(modelData.load || 0) + "%"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line
                                    Rectangle { width: parent.width * Math.max(0, Math.min(100, Number(modelData.load || 0))) / 100; height: parent.height; radius: Theme.radiusSize(4); color: Theme.acc }
                                }
                                Text { text: modelData.name || "GPU"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }

                    Rectangle {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        implicitHeight: Theme.dimensionSize(86)
                        radius: Theme.radiusCard
                        color: Theme.surfaceRaised
                        border.width: Theme.dimensionSize(1)
                        border.color: Theme.line
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.marginSize(12)
                            spacing: Theme.spacingSize(5)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "SSD"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                                Text { text: SystemService.storageAvailable ? SystemService.storagePercent.toFixed(0) + "%" : "—"; color: Theme.success; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line
                                Rectangle { width: parent.width * SystemService.storagePercent / 100; height: parent.height; radius: Theme.radiusSize(4); color: Theme.success }
                            }
                            Text { text: SystemService.storageLabel; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                }

                // Fan section
                Text { text: "Cooling fan"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(12)

                    // Spinning fan icon
                    Rectangle {
                        implicitWidth: Theme.dimensionSize(52); implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusSize(26)
                        border.width: Theme.dimensionSize(2); border.color: Theme.line; color: "transparent"
                        SvgIcon {
                            anchors.centerIn: parent; width: Theme.dimensionSize(30); height: Theme.dimensionSize(30)
                            iconName: "fan"; tone: "accent"
                            RotationAnimation on rotation {
                                running: SystemService.fanAvailable && SystemService.fanRpm > 0
                                loops: Animation.Infinite; from: 0; to: 360
                                duration: SystemService.fanRpm > Theme.duration(0) ? Math.round(Theme.duration(60000) / SystemService.fanRpm * Theme.duration(4)) : Theme.duration(2000)
                            }
                        }
                    }

                    ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(2)
                        Text {
                            text: SystemService.fanAvailable ? Math.round(SystemService.fanRpm) + " RPM" : "—"
                            color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(22); font.weight: Theme.fontWeightSemibold; font.features: ({ "tnum": 1 })
                        }
                        Text {
                            text: SystemService.cpuTemperatureText ? "Auto · " + SystemService.cpuTemperatureText : "Auto"
                            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                    Item { Layout.fillWidth: true }
                    Rectangle { implicitWidth: Theme.dimensionSize(58); implicitHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9); color: Theme.surfaceRaised; border.width: Theme.dimensionSize(1); border.color: Theme.line
                        Text { anchors.centerIn: parent; text: "Max"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); font.weight: Theme.fontWeightMedium }
                        MouseArea { anchors.fill: parent; onClicked: { } }
                    }
                    Rectangle { implicitWidth: Theme.dimensionSize(58); implicitHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9); color: Theme.acc; border.width: Theme.dimensionSize(1); border.color: Theme.acc
                        Text { anchors.centerIn: parent; text: "Auto"; color: Theme.background; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); font.weight: Theme.fontWeightMedium }
                        MouseArea { anchors.fill: parent; onClicked: { } }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // V-CAL VIEW
    // ════════════════════════════════════════════════════════════════════════
    component CalendarView: Item {
        id: calViewRoot
        property date   calMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
        property date   today:    new Date()

        function monthOffset(d): int { return (d.getDay() + 6) % 7 }
        function daysInMonth(d): int { return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate() }
        function isToday(y, m, day): bool {
            return today.getFullYear() === y && today.getMonth() === m && today.getDate() === day
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(12)

            // Header (back)
            Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: calBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: calBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                RowLayout { id: calBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6); SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" } Text { text: "Calendar"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont } }
                MouseArea { id: calBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
            }

            // Big time + date
            ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(2)
                Text { text: Qt.formatTime(ShellState.now, "HH:mm:ss"); color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(40); font.weight: Theme.fontWeightLight; font.letterSpacing: Theme.letterSpacingValue(-1) }
                Text { text: Qt.formatDate(ShellState.now, "dddd, MMMM d, yyyy"); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
            }

            // Month nav row
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Qt.formatDate(calViewRoot.calMonth, "MMMM yyyy")
                    color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightSemibold
                    Layout.fillWidth: true
                }
                Rectangle { implicitWidth: Theme.dimensionSize(36); implicitHeight: Theme.dimensionSize(36); radius: Theme.radiusSize(10); color: prevMonHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                    MouseArea { id: prevMonHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: calViewRoot.calMonth = new Date(calViewRoot.calMonth.getFullYear(), calViewRoot.calMonth.getMonth() - 1, 1)
                    }
                }
                Rectangle { implicitWidth: Theme.dimensionSize(36); implicitHeight: Theme.dimensionSize(36); radius: Theme.radiusSize(10); color: nextMonHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "fg" }
                    MouseArea { id: nextMonHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: calViewRoot.calMonth = new Date(calViewRoot.calMonth.getFullYear(), calViewRoot.calMonth.getMonth() + 1, 1)
                    }
                }
            }

            // Calendar grid (.cg) — 7 columns
            Grid {
                Layout.fillWidth: true
                columns: 7; spacing: Theme.spacingSize(2)
                property int cellSize: Math.floor((parent.width - 12) / 7)

                // Weekday headers
                Repeater {
                    model: ["M","T","W","T","F","S","S"]
                    delegate: Item {
                        required property string modelData
                        width: parent.cellSize; height: Theme.dimensionSize(24)
                        Text { anchors.centerIn: parent; text: modelData; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }
                    }
                }

                // Offset blank cells
                Repeater {
                    model: calViewRoot.monthOffset(calViewRoot.calMonth)
                    delegate: Item { width: parent.cellSize; height: Theme.dimensionSize(36) }
                }

                // Day cells
                Repeater {
                    model: calViewRoot.daysInMonth(calViewRoot.calMonth)
                    delegate: Item {
                        required property int index
                        property bool itIsToday: calViewRoot.isToday(calViewRoot.calMonth.getFullYear(), calViewRoot.calMonth.getMonth(), index + 1)
                        width: parent.cellSize; height: Theme.dimensionSize(36)

                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.dimensionSize(32); height: Theme.dimensionSize(32); radius: Theme.radiusSize(16)
                            color: itIsToday ? Theme.acc : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: String(index + 1)
                            color: itIsToday ? Theme.islandBg : Theme.fg
                            font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: itIsToday ? Theme.fontWeightSemibold : Theme.fontWeightRegular
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // V-ALERTS VIEW
    // ════════════════════════════════════════════════════════════════════════
    component AlertsView: Item {
        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(10)

            // Header: back + Clear all
            RowLayout {
                Layout.fillWidth: true
                Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: alBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: alBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    RowLayout { id: alBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6); SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" } Text { text: "Notifications"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont } }
                    MouseArea { id: alBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: NotificationService.count > 0
                    implicitWidth: clrTxt.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                    color: clrHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    Text { id: clrTxt; anchors.centerIn: parent; text: "Clear all"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                    MouseArea { id: clrHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotificationService.clearAll() }
                }
            }

            // Notification list — reuse NotificationPanel component
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: notifContent.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                NotificationPanel { id: notifContent; width: parent.width }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // V-UPDATE VIEW
    // ════════════════════════════════════════════════════════════════════════
    component UpdateView: Item {
        id: updViewRoot
        property int    pendingUpdates: 0
        property string updateTooltip:  ""

        Flickable {
            anchors.fill: parent; contentWidth: width; contentHeight: updCol.implicitHeight + 36; clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: updCol; width: parent.width
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
                spacing: Theme.spacingSize(10)

                // Header: back + Install all
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: updBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: updBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                        RowLayout { id: updBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6); SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" } Text { text: "Updates"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont } }
                        MouseArea { id: updBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: updViewRoot.pendingUpdates > 0
                        implicitWidth: instTxt.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: instHov.containsMouse ? Theme.surfaceRaised : "transparent"
                        Text { id: instTxt; anchors.centerIn: parent; text: "Install all"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                        MouseArea { id: instHov; anchors.fill: parent; hoverEnabled: true; onClicked: { /* wire to shell launchSystemUpdater */ } }
                    }
                }

                // Package count summary
                Text {
                    text: updViewRoot.pendingUpdates + " packages available"
                    color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12)
                }
                Text {
                    text: updViewRoot.updateTooltip
                    color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // Placeholder rows proportional to count
                Repeater {
                    model: Math.min(updViewRoot.pendingUpdates, 20)
                    delegate: Rectangle {
                        required property int index
                        Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(48); radius: Theme.radiusCard; color: Theme.surfaceRaised
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(10)
                            SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: "download"; tone: "accent" }
                            ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(2)
                                Text { Layout.fillWidth: true; text: "Package " + (index + 1); color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                                Text { Layout.fillWidth: true; text: "Pending update"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }
                            }
                        }
                    }
                }

                // Empty state
                ColumnLayout {
                    visible: updViewRoot.pendingUpdates === 0
                    Layout.fillWidth: true; Layout.topMargin: Theme.marginSize(24); spacing: Theme.spacingSize(8)
                    SvgIcon { Layout.alignment: Qt.AlignHCenter; width: Theme.dimensionSize(32); height: Theme.dimensionSize(32); iconName: "check"; tone: "muted"; opacity: Theme.opacityValue(0.4)}
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Your system is up to date"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13) }
                }
            }
        }
    }
}
