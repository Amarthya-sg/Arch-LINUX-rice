// WifiView.qml
// Wi-Fi panel view (v-wifi).
// Scan, network list with signal/security, inline password entry,
// inline details card with IP/gateway/DNS/password reveal, and forget.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../components"
import "../../services"

Item {
    id: root

    // ── Local state ───────────────────────────────────────────────────────
    property string pwNetKey:    ""    // SSID key of the network awaiting a password
    property bool   pwVisible:   false
    property var    pwNetworks:  []    // local copy refreshed from NetworkService
    property string detailsNetKey:         ""
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

    // ── Initialise + react to scan results ───────────────────────────────
    Component.onCompleted: {
        pwNetworks = NetworkService.networks.slice(0)
        if (ShellState.popupOpen && ShellState.activeView === "wifi")
            NetworkService.scan()
    }

    Connections {
        target: NetworkService
        function onNetworkListUpdated() {
            if (!root.detailsNetKey)
                root.pwNetworks = NetworkService.networks.slice(0)
        }
        function onConnectionFinished(success, nk) {
            if (success)    root.clearPw()
            else if (nk)  { root.pwNetKey = nk; root.pwVisible = false }
        }
        function onWifiDeviceChanged() {
            if (NetworkService.wifiEnabled && ShellState.popupOpen && ShellState.activeView === "wifi")
                NetworkService.scan()
        }
        function onWifiEnabledChanged() {
            if (NetworkService.wifiEnabled && ShellState.popupOpen && ShellState.activeView === "wifi")
                NetworkService.scan()
            else if (!NetworkService.wifiEnabled)
                NetworkService.stopScan()
        }
    }
    Connections {
        target: ShellState
        function onActiveViewChanged() {
            if (ShellState.popupOpen && ShellState.activeView === "wifi") NetworkService.scan()
            else NetworkService.stopScan()
        }
        function onPopupOpenChanged() {
            if (ShellState.popupOpen && ShellState.activeView === "wifi") NetworkService.scan()
            else NetworkService.stopScan()
        }
    }

    // Refresh list while scanner is running (once per second).
    Timer {
        interval: 1000; repeat: true; running: NetworkService.scanning
        onTriggered: if (!root.detailsNetKey) root.pwNetworks = NetworkService.networks.slice(0)
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(10)

        // Header: back / scan / toggle
        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                implicitHeight: Theme.dimensionSize(40); implicitWidth: wfBackRow.implicitWidth + 20
                radius: Theme.radiusSize(12); color: wfBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                RowLayout { id: wfBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                    SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                    Text { text: "Wi-Fi"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                }
                MouseArea { id: wfBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitHeight: Theme.dimensionSize(34); implicitWidth: wfScanLabel.implicitWidth + 24
                radius: Theme.radiusSize(10); color: wfScanHov.containsMouse ? Theme.surfaceRaised : "transparent"
                Text { id: wfScanLabel; anchors.centerIn: parent; text: NetworkService.scanning ? "Stop" : "Scan"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                MouseArea { id: wfScanHov; anchors.fill: parent; hoverEnabled: true; enabled: NetworkService.wifiEnabled || NetworkService.scanning
                    onClicked: NetworkService.scanning ? NetworkService.stopScan() : NetworkService.scan() }
            }
            ToggleSwitch { checked: NetworkService.wifiEnabled; onToggled: NetworkService.toggleWifi() }
        }

        // Scan sweep
        ScanSweep { Layout.fillWidth: true; Layout.leftMargin: Theme.marginSize(8); Layout.rightMargin: Theme.marginSize(8); active: NetworkService.scanning }

        // Empty states
        Text { visible: !NetworkService.wifiEnabled; text: "Turn Wi-Fi on to see networks."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
        Text { visible: NetworkService.wifiEnabled && root.pwNetworks.length === 0; text: NetworkService.scanning ? "Scanning…" : "No networks found. Tap Scan."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }

        // Network list
        Flickable {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: width; contentHeight: wfNetCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: wfNetCol; width: parent.width; spacing: Theme.spacingSize(6)

                Repeater {
                    model: root.pwNetworks

                    delegate: Item {
                        id: netRow
                        required property var modelData
                        required property int index

                        readonly property string thisKey:     String(modelData?.ssid || modelData?.name || modelData?.bssid || "")
                        readonly property bool   isPwRow:     root.pwNetKey === thisKey
                        readonly property bool   isDetailsRow: root.detailsNetKey === thisKey
                        readonly property bool   isConnecting: NetworkService.connectingNetworkKey === thisKey

                        Layout.fillWidth: true
                        implicitHeight:   netRowInner.implicitHeight + 20
                        Layout.preferredHeight: netRowInner.implicitHeight + 20

                        Rectangle {
                            anchors.fill: parent; radius: Theme.radiusCard
                            color:  modelData.connected ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.10)) : Theme.surfaceRaised
                            border.width: modelData.connected ? 1 : 0
                            border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.25))
                        }

                        ColumnLayout {
                            id: netRowInner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(10) }
                            spacing: Theme.spacingSize(6)

                            // Network info row
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: "wifi"; tone: "fg" }
                                ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                    Text { Layout.fillWidth: true; text: modelData.name || "Hidden network"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightSemibold; elide: Text.ElideRight }
                                    Text { Layout.fillWidth: true; text: Math.round(Number(modelData.signalStrength || 0) * 100) + "% · " + NetworkService.security(modelData) + (modelData.connected ? " · connected" : modelData.known ? " · saved" : ""); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                                }
                                // Connect/Disconnect
                                Rectangle {
                                    implicitWidth: connLabel.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                                    color: connHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                    Text { id: connLabel; anchors.centerIn: parent; text: modelData.connected ? "Disconnect" : netRow.isConnecting ? "…" : "Connect"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                    MouseArea { id: connHov; anchors.fill: parent; hoverEnabled: true; enabled: modelData.connected || NetworkService.connectingNetworkKey === ""
                                        onClicked: {
                                            if (modelData.connected)                                                         NetworkService.disconnect(modelData)
                                            else if (NetworkService.security(modelData) === "Open" || modelData.known)       NetworkService.connect(modelData)
                                            else                                                                             root.openPw(modelData)
                                        }
                                    }
                                }
                                // Info
                                Rectangle { implicitWidth: Theme.dimensionSize(30); implicitHeight: Theme.dimensionSize(30); radius: Theme.radiusSize(15); color: netInfoHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                    Text { anchors.centerIn: parent; text: "i"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightBold }
                                    MouseArea { id: netInfoHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleDetails(modelData) }
                                }
                                // Forget
                                Rectangle { visible: !!modelData.known; implicitWidth: forgetWifiLabel.implicitWidth + 18; implicitHeight: Theme.dimensionSize(30); radius: Theme.radiusSize(10); color: forgetWifiHov.containsMouse ? Qt.rgba(1, 0.42, 0.37, Theme.opacityValue(0.20)) : Theme.surfaceRaised
                                    Text { id: forgetWifiLabel; anchors.centerIn: parent; text: "Forget"; color: Theme.error; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium }
                                    MouseArea { id: forgetWifiHov; anchors.fill: parent; hoverEnabled: true; onClicked: NetworkService.forget(modelData) }
                                }
                            }

                            // Details card
                            Rectangle {
                                visible: netRow.isDetailsRow
                                Layout.fillWidth: true
                                implicitHeight: detailsCardCol.implicitHeight + 18
                                Layout.preferredHeight: detailsCardCol.implicitHeight + 18
                                radius: Theme.radiusSize(12); color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.045))
                                border.width: Theme.dimensionSize(1); border.color: Theme.line

                                ColumnLayout {
                                    id: detailsCardCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(9) }
                                    spacing: Theme.spacingSize(5)

                                    RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                                        Text { text: "NETWORK DETAILS"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; font.letterSpacing: Theme.letterSpacingValue(0.7); Layout.fillWidth: true }
                                        Rectangle { implicitWidth: detailsStatusText.implicitWidth + 12; implicitHeight: Theme.dimensionSize(20); radius: Theme.radiusSize(10); color: modelData.connected ? Qt.rgba(0.35, 0.85, 0.55, Theme.opacityValue(0.16)) : Qt.rgba(1, 1, 1, Theme.opacityValue(0.08))
                                            Text { id: detailsStatusText; anchors.centerIn: parent; text: modelData.connected ? "Connected" : modelData.known ? "Saved" : "Available"; color: modelData.connected ? Theme.success : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightMedium }
                                        }
                                    }
                                    Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.line; opacity: Theme.opacityValue(0.7) }

                                    RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(6)
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
                                    RowLayout { visible: !!modelData.bssid; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                        Text { text: "BSSID:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                        Text { text: modelData.bssid || "—"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                    RowLayout { visible: !!modelData.connected; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                        Text { text: "IP:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                        Text { text: NetworkService.ipAddress; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                    RowLayout { visible: !!modelData.connected; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                        Text { text: "Gateway:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                        Text { text: NetworkService.gateway; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                    RowLayout { visible: !!modelData.connected; Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                                        Text { text: "DNS:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                        Text { text: NetworkService.dnsServer; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                    RowLayout { visible: !!modelData.known; Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                                        Text { text: "Password:"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightBold; Layout.preferredWidth: Theme.dimensionSize(64) }
                                        Text {
                                            Layout.fillWidth: true
                                            text: NetworkService.passwordLookupBusy ? "loading…"
                                                : NetworkService.revealedPasswordKey === netRow.thisKey
                                                    ? (root.detailsPasswordVisible ? (NetworkService.revealedPassword || "Unavailable") : "••••••••")
                                                    : "Unavailable"
                                            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight
                                        }
                                        Rectangle {
                                            visible: NetworkService.revealedPasswordKey === netRow.thisKey && !!NetworkService.revealedPassword
                                            implicitWidth: detailsPasswordAction.implicitWidth + 18; implicitHeight: Theme.dimensionSize(24); radius: Theme.radiusSize(8)
                                            color: detailsPasswordHov.containsMouse ? Theme.surfaceHover : Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.12))
                                            Text { id: detailsPasswordAction; anchors.centerIn: parent; text: root.detailsPasswordVisible ? "Hide" : "Show"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightMedium }
                                            MouseArea { id: detailsPasswordHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.detailsPasswordVisible = !root.detailsPasswordVisible }
                                        }
                                    }
                                }
                            }

                            // Password entry
                            ColumnLayout {
                                visible: netRow.isPwRow; Layout.fillWidth: true; spacing: Theme.spacingSize(6)

                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.spacingSize(6)
                                    TextField {
                                        id: pwInput
                                        Layout.fillWidth: true; focus: netRow.isPwRow; activeFocusOnPress: true; selectByMouse: true
                                        placeholderText:  "Password for " + (modelData.name || "network")
                                        echoMode:         root.pwVisible ? TextInput.Normal : TextInput.Password
                                        color:            Theme.fg; placeholderTextColor: Theme.muted
                                        font.family:      Theme.uiFont; font.pixelSize: Theme.fontSize(12)
                                        background: Rectangle { radius: Theme.radiusSize(10); color: Theme.surfaceRaised; border.width: Theme.dimensionSize(1); border.color: pwInput.activeFocus ? Theme.acc : Theme.line }
                                        onVisibleChanged: if (visible) pwFocusTimer.restart()
                                        Timer { id: pwFocusTimer; interval: 0; repeat: false; onTriggered: if (pwInput.visible) pwInput.forceActiveFocus() }
                                        onAccepted: { if (text.length >= 8) { NetworkService.connect(modelData, text); root.clearPw() } }
                                    }
                                    Rectangle { implicitWidth: pwTogLabel.implicitWidth + 18; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: pwTogHov.containsMouse ? Theme.surfaceRaised : "transparent"
                                        Text { id: pwTogLabel; anchors.centerIn: parent; text: root.pwVisible ? "hide" : "show"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                        MouseArea { id: pwTogHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.pwVisible = !root.pwVisible }
                                    }
                                    Rectangle { implicitWidth: joinLabel.implicitWidth + 20; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: joinHov.containsMouse && pwInput.length >= 8 ? Theme.acc : Theme.surfaceRaised; opacity: pwInput.text.length >= 8 ? Theme.opacityValue(1) : Theme.opacityValue(0.45)
                                        Text { id: joinLabel; anchors.centerIn: parent; text: "Join"; color: joinHov.containsMouse && pwInput.text.length >= 8 ? Theme.islandBg : Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightSemibold }
                                        MouseArea { id: joinHov; anchors.fill: parent; hoverEnabled: true; enabled: pwInput.text.length >= 8; onClicked: { NetworkService.connect(modelData, pwInput.text); root.clearPw() } }
                                    }
                                    Rectangle { implicitWidth: Theme.dimensionSize(60); implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: cancelHov.containsMouse ? Theme.surfaceRaised : "transparent"
                                        Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
                                        MouseArea { id: cancelHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.clearPw() }
                                    }
                                }
                                Text {
                                    visible: NetworkService.connectionErrorKey === netRow.thisKey && NetworkService.connectionError !== ""
                                    Layout.fillWidth: true; text: NetworkService.connectionError
                                    color: Theme.error; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Shared scan-sweep component used by this view ─────────────────────
    component ScanSweep: Item {
        id: sweepRoot
        property bool active: false
        implicitHeight: Theme.dimensionSize(6)
        opacity: active ? Theme.opacityValue(1) : Theme.opacityValue(0)
        Behavior on opacity { NumberAnimation { duration: Theme.duration(250); easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.line }
        Rectangle {
            id: sweepBar; height: parent.height; width: parent.width * 0.3; radius: height / 2; color: Theme.acc
            SequentialAnimation on x {
                loops: Animation.Infinite; running: sweepRoot.active || sweepRoot.opacity > 0.01
                NumberAnimation { from: 0; to: sweepRoot.width - sweepBar.width; duration: Theme.duration(900); easing.type: Easing.InOutSine }
                NumberAnimation { from: sweepRoot.width - sweepBar.width; to: 0; duration: Theme.duration(900); easing.type: Easing.InOutSine }
            }
        }
    }
}
