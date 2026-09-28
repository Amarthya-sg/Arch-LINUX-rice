import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../core"
import "../components"
import "../services"

Rectangle {
    id: root
    color: "#151517"
    radius: 28
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)
    clip: true
    opacity: ShellState.popupOpen ? 1 : 0
    scale: ShellState.popupOpen ? 1 : 0.92
    transformOrigin: Item.Top
    gradient: Gradient {
        GradientStop { position: 0; color: "#1c1c1f" }
        GradientStop { position: 0.48; color: "#151517" }
        GradientStop { position: 1; color: "#111113" }
    }
    Behavior on opacity { NumberAnimation { duration: 220 } }
    Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

    property var tabs: [
        { id: "wifi", label: "Wi-Fi" },
        { id: "bluetooth", label: "Bluetooth" },
        { id: "sound", label: "Sound" },
        { id: "brightness", label: "Display" },
        { id: "notifications", label: "Alerts" },
        { id: "system", label: "System" }
    ]
    property var passwordNetwork: null
    property string passwordNetworkKey: ""
    property var infoNetwork: null
    // Scan results are recreated as new JS objects; retain the open row by key.
    property string infoNetworkKey: ""
    property string password: ""
    property bool showPassword: false
    property var savedPasswordNetwork: null
    property string savedPasswordValue: ""
    readonly property var battery: UPower.displayDevice
    readonly property real batteryPercent: battery && Number.isFinite(Number(battery.percentage))
        ? Math.max(0, Math.min(100, Number(battery.percentage) * 100)) : -1
    property date currentDate: new Date()

    onVisibleChanged: {
        if (!visible) {
            clearCredentialState()
        } else {
            if (activeTabIndex === 0 && NetworkService.wifiEnabled) NetworkService.scan()
            if (activeTabIndex === 1 && BluetoothService.enabled) BluetoothService.scan()
            if (activeTabIndex === 2) AudioService.refresh()
        }
    }

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentDate = new Date()
    }

    function clearCredentialState(): void {
        passwordNetwork = null
        passwordNetworkKey = ""
        infoNetwork = null
        infoNetworkKey = ""
        password = ""
        showPassword = false
        savedPasswordNetwork = null
        savedPasswordValue = ""
    }

    function openPassword(network): void {
        clearCredentialState()
        passwordNetwork = network
        passwordNetworkKey = networkKey(network)
    }

    function revealSavedPassword(network): void {
        savedPasswordNetwork = network
        savedPasswordValue = String(network?.password || "")
        NetworkService.revealSavedPassword(network)
    }

    Connections {
        target: NetworkService
        function onRevealedPasswordChanged() {
            if (root.savedPasswordNetwork
                    && NetworkService.revealedPasswordKey === root.networkKey(root.savedPasswordNetwork))
                root.savedPasswordValue = NetworkService.revealedPassword
        }
    }

    function toggleInfo(network): void {
        passwordNetwork = null
        const key = networkKey(network)
        infoNetwork = infoNetworkKey === key ? null : network
        infoNetworkKey = infoNetwork ? key : ""
    }

    function networkKey(network): string {
        return String(network?.bssid || network?.ssid || network?.name || "")
    }

    function syncOutputChoiceModel(): void {
        outputChoiceModel.clear()
        for (const choice of AudioService.outputChoices)
            outputChoiceModel.append({ label: choice.description || choice.name || "Output",
                                       detail: choice.detail || "Output device",
                                       active: !!choice.active })
        Qt.callLater(function() {
            outputSelector.currentIndex = outputChoiceModel.count > 0
                ? Math.max(0, Math.min(AudioService.outputIndex, outputChoiceModel.count - 1)) : -1
        })
    }

    function syncInputChoiceModel(): void {
        inputChoiceModel.clear()
        for (const choice of AudioService.inputChoices)
            inputChoiceModel.append({ label: choice.description || choice.name || "Input",
                                      detail: choice.detail || "Input device",
                                      active: !!choice.active })
        Qt.callLater(function() {
            inputSelector.currentIndex = inputChoiceModel.count > 0
                ? Math.max(0, Math.min(AudioService.inputIndex, inputChoiceModel.count - 1)) : -1
        })
    }

    readonly property int activeTabIndex: {
        const index = tabs.findIndex(tab => tab.id === ShellState.activeTab)
        return index < 0 ? 0 : index
    }
    onActiveTabIndexChanged: {
        if (activeTabIndex !== 0) clearCredentialState()
        if (visible && activeTabIndex === 0 && NetworkService.wifiEnabled) NetworkService.scan()
        if (visible && activeTabIndex === 1 && BluetoothService.enabled) BluetoothService.scan()
        if (visible && activeTabIndex === 2) AudioService.refresh()
    }

    ListModel {
        id: outputChoiceModel
        Component.onCompleted: root.syncOutputChoiceModel()
    }
    ListModel {
        id: inputChoiceModel
        Component.onCompleted: root.syncInputChoiceModel()
    }
    Connections {
        target: AudioService
        function onOutputNamesChanged() { root.syncOutputChoiceModel() }
        function onInputNamesChanged() { root.syncInputChoiceModel() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: Qt.formatTime(root.currentDate, "hh:mm")
                    color: Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 19
                    font.weight: 600
                }
                Label {
                    text: Qt.formatDate(root.currentDate, "dddd, MMMM d")
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
        }

        // At-a-glance status ribbon
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 12
                color: NetworkService.connected ? Qt.rgba(0.37, 0.84, 0.46, 0.10)
                                                : Theme.surfaceRaised
                Text {
                    anchors.centerIn: parent
                    text: NetworkService.connected ? "Wi-Fi · online" : "Wi-Fi · offline"
                    color: NetworkService.connected ? Theme.success : Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 12
                color: AudioService.muted ? Qt.rgba(1, 0.42, 0.37, 0.12)
                                           : Theme.surfaceRaised
                Text {
                    anchors.centerIn: parent
                    text: AudioService.muted ? "Sound · muted" : "Sound · on"
                    color: AudioService.muted ? Theme.error : Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 12
                color: NotificationService.dndEnabled ? Qt.rgba(1, 0.62, 0.04, 0.12)
                                                       : Theme.surfaceRaised
                Text {
                    anchors.centerIn: parent
                    text: NotificationService.dndEnabled
                        ? "DND on" : NotificationService.count + " alerts"
                    color: NotificationService.dndEnabled ? Theme.warning : Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 12
                color: Theme.surfaceRaised
                Text {
                    anchors.centerIn: parent
                    text: batteryPercent >= 0 ? "Battery · " + Math.round(batteryPercent) + "%" : "Battery · n/a"
                    color: batteryPercent >= 0 && batteryPercent <= 15 ? Theme.error : Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 3
            Repeater {
                model: root.tabs
                delegate: ToolButton {
                    id: tabButton
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 42
                    highlighted: ShellState.activeTab === modelData.id
                    onClicked: ShellState.activeTab = modelData.id
                    contentItem: Text {
                        text: modelData.label
                        color: tabButton.highlighted ? Theme.text : Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: tabButton.highlighted ? 600 : 500
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: 14
                        color: tabButton.highlighted ? Theme.surfaceRaised : Theme.surface
                        border.width: tabButton.highlighted ? 1 : 0
                        border.color: Qt.rgba(1, 0.62, 0.04, 0.2)
                    }
                }
            }
        }

        StackLayout {
            id: pageStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.activeTabIndex
            clip: true

            // ── Wi-Fi ────────────────────────────────────────────────────
            Flickable {
                id: wifiFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: Math.max(height, wifiView.implicitHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: wifiView
                    width: parent.width
                    height: implicitHeight
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 58
                        radius: Theme.radius
                        color: Theme.surfaceRaised
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Label { text: "Wi-Fi"
                                    color: Theme.text; font.family: Theme.uiFont
                                    font.pixelSize: 15; font.weight: 600 }
                                Label { text: NetworkService.connected ? "connected: " + NetworkService.ssid : NetworkService.status
                                    color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 10 }
                            }
                            ToggleSwitch { checked: NetworkService.wifiEnabled
                                onToggled: NetworkService.toggleWifi() }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "networks"
                            color: Theme.muted; font.family: Theme.iconFont
                            font.pixelSize: 10; font.weight: 600 }
                        Item { Layout.fillWidth: true }
                        StyledButton {
                            compact: true
                            text: NetworkService.scanning ? "stop" : "scan"
                            enabled: NetworkService.wifiEnabled || NetworkService.scanning
                            onClicked: NetworkService.scanning
                                ? NetworkService.stopScan() : NetworkService.scan()
                        }
                        StyledButton {
                            compact: true
                            text: "forget"
                            visible: !!NetworkService.activeNetwork
                            onClicked: NetworkService.forget()
                        }
                    }

                    Item {
                        visible: NetworkService.scanning
                        Layout.fillWidth: true
                        implicitHeight: 20
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 3; radius: 2
                            color: Theme.outline
                        }
                        Rectangle {
                            id: wifiScanBar
                            anchors.verticalCenter: parent.verticalCenter
                            height: 3; radius: 2; width: parent.width * 0.35
                            color: Theme.islandAccent; opacity: 0.9
                            NumberAnimation on x {
                                from: -wifiScanBar.width; to: wifiScanBar.parent.width
                                duration: 1400; loops: Animation.Infinite
                                running: NetworkService.scanning; easing.type: Easing.InOutSine
                            }
                        }
                        Label {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "scanning…"; color: Theme.islandAccent
                            font.family: Theme.iconFont; font.pixelSize: 9
                        }
                    }

                    Label {
                        visible: !NetworkService.wifiEnabled
                        Layout.fillWidth: true
                        text: "Turn Wi-Fi on to see networks."
                        color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 10
                    }
                    Label {
                        visible: NetworkService.wifiEnabled && NetworkService.networks.length === 0
                        Layout.fillWidth: true
                        text: NetworkService.scanning ? "Scanning for networks…" : "No networks found. Tap Scan."
                        color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 10
                    }

                    Repeater {
                        model: NetworkService.networks
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: infoNetworkKey === networkKey(modelData) ? 232
                                : passwordNetworkKey === networkKey(modelData) ? 94
                                : savedPasswordNetwork === modelData ? 76 : 50
                            radius: 14
                            color: modelData.connected ? Qt.rgba(1, 0.62, 0.04, 0.10) : Theme.surface
                            border.width: modelData.connected ? 1 : 0
                            border.color: Qt.rgba(1, 0.62, 0.04, 0.25)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: Number(modelData.signalStrength || 0) > 0.8 ? "󰤨"
                                            : Number(modelData.signalStrength || 0) > 0.5 ? "󰤥" : "󰤟"
                                        color: modelData.connected ? Theme.islandAccent : Theme.muted
                                        font.family: Theme.iconFont; font.pixelSize: 16
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData.name || "Hidden network"
                                            color: Theme.text; font.family: Theme.uiFont
                                            font.pixelSize: 12; font.weight: 600
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: Math.round(Number(modelData.signalStrength || 0) * 100) + "% · "
                                                + NetworkService.security(modelData)
                                                + (modelData.connected ? " · connected" : modelData.known ? " · saved" : "")
                                            color: Theme.muted; font.family: Theme.iconFont
                                            font.pixelSize: 9; elide: Text.ElideRight
                                        }
                                    }

                                    Row {
                                        Layout.preferredWidth: 114
                                        Layout.maximumWidth: 114
                                        spacing: 4
                                        Layout.alignment: Qt.AlignVCenter

                                        StyledButton {
                                            compact: true; width: 28; height: 28; text: "i"
                                            onClicked: toggleInfo(modelData)
                                        }
                                        StyledButton {
                                            compact: true; width: 82; height: 28
                                            text: modelData.connected ? "disconnect"
                                                : modelData.stateChanging ? "…" : "connect"
                                            highlighted: false
                                            enabled: modelData.connected
                                                || (!modelData.stateChanging)
                                            onClicked: modelData.connected
                                                ? NetworkService.connect(modelData)
                                                : NetworkService.security(modelData) === "Open"
                                                    ? NetworkService.connect(modelData)
                                                    : openPassword(modelData)
                                        }
                                    }
                                }

                                RowLayout {
                                    visible: infoNetworkKey === networkKey(modelData)
                                    Layout.fillWidth: true
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2; rowSpacing: 6; columnSpacing: 12
                                        Label { text: "signal\n" + Math.round(Number(modelData.signalStrength || 0) * 100) + "%"
                                            color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 }
                                        Label { text: "security\n" + NetworkService.security(modelData)
                                            color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 }
                                        Label { text: "status\n" + (modelData.connected ? "connected" : "available")
                                            color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 }
                                        Label { text: "IP address\n" + (modelData.connected ? NetworkService.ipAddress : "—")
                                            color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 }
                                        Label { text: "gateway\n" + (modelData.connected ? NetworkService.gateway : "—")
                                            color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 }
                                        Label { text: "DNS\n" + (modelData.connected ? NetworkService.dnsServer : "—")
                                            color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 }
                                        StyledButton { compact: true
                                            text: savedPasswordNetwork === modelData ? "hide" : "show password"
                                            onClicked: savedPasswordNetwork === modelData
                                                ? clearCredentialState() : revealSavedPassword(modelData) }
                                    }
                                }

                                RowLayout {
                                    visible: passwordNetworkKey === networkKey(modelData)
                                    Layout.fillWidth: true
                                    TextField {
                                        id: wifiPassword
                                        Layout.fillWidth: true
                                        placeholderText: "password for " + (modelData.name || "network")
                                        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                        color: Theme.text; placeholderTextColor: Theme.muted
                                        font.family: Theme.iconFont; font.pixelSize: 10
                                        background: Rectangle { radius: 10; color: Theme.surfaceRaised
                                            border.width: 1
                                            border.color: wifiPassword.activeFocus ? Theme.islandAccent : Theme.outline }
                                        Component.onCompleted: if (visible) forceActiveFocus()
                                        onVisibleChanged: if (visible) forceActiveFocus()
                                        onAccepted: if (text.length >= 8) {
                                            NetworkService.connect(modelData, text)
                                            root.clearCredentialState()
                                        }
                                    }
                                    StyledButton { compact: true
                                        text: root.showPassword ? "hide" : "show"
                                        onClicked: root.showPassword = !root.showPassword }
                                    StyledButton { compact: true; text: "join"; highlighted: true
                                        enabled: wifiPassword.text.length >= 8
                                        onClicked: { NetworkService.connect(modelData, wifiPassword.text)
                                            clearCredentialState() } }
                                    StyledButton { compact: true; text: "cancel"
                                        onClicked: clearCredentialState() }
                                }

                                Label {
                                    visible: savedPasswordNetwork === modelData && passwordNetwork !== modelData
                                    text: savedPasswordValue.length > 0
                                        ? "password: " + savedPasswordValue : "no readable saved password"
                                    color: Theme.islandAccent; font.family: Theme.iconFont
                                    font.pixelSize: 9; elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            // ── Bluetooth ────────────────────────────────────────────────
            Flickable {
                id: bluetoothPage
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width
                contentHeight: Math.max(height, bluetoothView.implicitHeight)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                clip: true; boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: bluetoothView
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 58
                        radius: Theme.radius; color: Theme.surfaceRaised
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                Label { text: "Bluetooth"; color: Theme.text
                                    font.family: Theme.uiFont; font.pixelSize: 15; font.weight: 600 }
                                Label {
                                    text: BluetoothService.enabled
                                        ? (BluetoothService.connectedDevices.length > 0
                                            ? BluetoothService.connectedDevices.length + " connected"
                                            : "on · no devices connected")
                                        : BluetoothService.status
                                    color: BluetoothService.connectedDevices.length > 0 ? Theme.success : Theme.muted
                                    font.family: Theme.iconFont; font.pixelSize: 10 }
                            }
                            ToggleSwitch { checked: BluetoothService.enabled
                                onToggled: BluetoothService.toggle() }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "nearby devices"; color: Theme.muted
                            font.family: Theme.iconFont; font.pixelSize: 10; font.weight: 600 }
                        Item { Layout.fillWidth: true }
                        StyledButton {
                            compact: true
                            text: BluetoothService.scanning ? "stop" : "scan"
                            enabled: BluetoothService.enabled || BluetoothService.scanning
                            onClicked: BluetoothService.scanning
                                ? BluetoothService.stopScan() : BluetoothService.scan()
                        }
                    }

                    Item {
                        visible: BluetoothService.scanning
                        Layout.fillWidth: true; implicitHeight: 20
                        Rectangle { anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 3; radius: 2; color: Theme.outline }
                        Rectangle {
                            id: btScanBar
                            anchors.verticalCenter: parent.verticalCenter
                            height: 3; radius: 2; width: parent.width * 0.35
                            color: Theme.islandAccent; opacity: 0.9
                            NumberAnimation on x {
                                from: -btScanBar.width; to: btScanBar.parent.width
                                duration: 1600; loops: Animation.Infinite
                                running: BluetoothService.scanning; easing.type: Easing.InOutSine
                            }
                        }
                        Label { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "scanning…"; color: Theme.islandAccent
                            font.family: Theme.iconFont; font.pixelSize: 9 }
                    }

                    Label {
                        visible: !BluetoothService.enabled
                        Layout.fillWidth: true
                        text: "Turn Bluetooth on to discover devices."
                        color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 10
                    }
                    Label {
                        visible: BluetoothService.enabled && BluetoothService.devices.length === 0 && !BluetoothService.scanning
                        Layout.fillWidth: true
                        text: "No devices found. Tap Scan."
                        color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 10
                    }
                    Label {
                        visible: BluetoothService.enabled && BluetoothService.scanning
                        Layout.fillWidth: true
                        text: "Scanning for devices..."
                        color: Theme.islandAccent; font.family: Theme.iconFont; font.pixelSize: 10
                    }

                    Repeater {
                        model: BluetoothService.devices
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: btRow.implicitHeight + 20
                            radius: 14
                            color: modelData.connected ? Qt.rgba(1, 0.62, 0.04, 0.10) : Theme.surface
                            border.width: modelData.connected ? 1 : 0
                            border.color: Qt.rgba(1, 0.62, 0.04, 0.25)
                            RowLayout {
                                id: btRow
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                anchors.margins: 10
                                Rectangle {
                                    implicitWidth: 9; implicitHeight: 9; radius: 5
                                    color: modelData.connected ? Theme.success
                                        : modelData.paired ? Theme.islandAccent : Theme.muted
                                }
                                ColumnLayout { Layout.fillWidth: true; spacing: 1
                                    Label { text: modelData.name || modelData.deviceName || "Bluetooth device"
                                        color: Theme.text; font.family: Theme.uiFont; font.pixelSize: 12
                                        font.weight: 600; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Label { text: (modelData.connected ? "connected" : modelData.paired ? "paired" : "available")
                                            + " · " + String(modelData.address || "")
                                        color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9
                                        elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                StyledButton { compact: true
                                    text: modelData.connected ? "disconnect" : modelData.paired ? "connect" : "pair"
                                    onClicked: BluetoothService.activate(modelData) }
                                StyledButton { compact: true; text: "forget"
                                    visible: modelData.paired || modelData.bonded
                                    onClicked: BluetoothService.forget(modelData) }
                            }
                        }
                    }
                }
            }

            // ── Sound ────────────────────────────────────────────────────
            Flickable {
                id: soundPage
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width
                contentHeight: Math.max(height, soundView.implicitHeight)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                clip: true; boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: soundView
                    width: parent.width
                    spacing: 8

                    // Output card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: outputCard.implicitHeight + 28
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout {
                            id: outputCard
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14
                            spacing: 6

                            LevelSlider {
                                Layout.fillWidth: true
                                title: "output volume"
                                value: AudioService.outputMaster
                                valueLabel: Math.round(AudioService.outputMaster * 100) + "%"
                                onValueEdited: function(value) { AudioService.setVolume(value) }
                            }
                            Label {
                                text: AudioService.outputChoices.length > 1
                                    ? "available outputs · " + AudioService.outputChoices.length
                                    : "output device"
                                color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9
                            }
                            ComboBox {
                                id: outputSelector
                                objectName: "audioOutputSelector"
                                Layout.fillWidth: true
                                enabled: outputChoiceModel.count > 0
                                textRole: "label"
                                model: outputChoiceModel
                                onActivated: function(index) {
                                    AudioService.selectOutput(AudioService.outputChoices[index])
                                }
                                contentItem: Text {
                                    leftPadding: 10; rightPadding: 28
                                    text: outputSelector.count > 0 ? outputSelector.displayText : "No audio outputs detected"
                                    color: outputSelector.enabled ? Theme.text : Theme.muted
                                    font.family: Theme.uiFont; font.pixelSize: 10
                                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 9; color: Theme.surfaceRaised; border.width: 1
                                    border.color: outputSelector.popup.visible ? Theme.islandAccent : Theme.outline
                                }
                                indicator: Text {
                                    x: outputSelector.width - width - 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "⌄"; color: Theme.muted; font.pixelSize: 14
                                }
                                popup: Popup {
                                    y: outputSelector.height; width: outputSelector.width; padding: 4
                                    background: Rectangle { radius: 9; color: Theme.surfaceRaised
                                        border.color: Theme.outline; border.width: 1 }
                                    contentItem: ListView {
                                        model: outputSelector.delegateModel
                                        currentIndex: outputSelector.highlightedIndex
                                        clip: true; implicitHeight: Math.min(contentHeight, 180)
                                    }
                                }
                                delegate: ItemDelegate {
                                    required property int index
                                    objectName: "outputChoiceDelegate-" + index
                                    width: outputSelector.width; height: 44
                                    contentItem: ColumnLayout {
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            text: outputChoiceModel.get(index).label
                                            color: Theme.text; font.family: Theme.uiFont
                                            font.pixelSize: 10; elide: Text.ElideRight
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: (outputChoiceModel.get(index).active ? "ACTIVE · " : "")
                                                  + outputChoiceModel.get(index).detail
                                            color: outputChoiceModel.get(index).active ? Theme.success : Theme.muted
                                            font.family: Theme.iconFont; font.pixelSize: 8; elide: Text.ElideRight
                                        }
                                    }
                                    background: Rectangle { radius: 7
                                        color: highlighted ? Theme.surfaceHover : "transparent" }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                StyledButton { compact: true
                                    text: AudioService.muted ? "unmute output" : "mute output"
                                    onClicked: AudioService.toggleMute() }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: AudioService.available ? "pipewire connected" : "pipewire unavailable"
                                    color: AudioService.available ? Theme.success : Theme.muted
                                    font.family: Theme.iconFont; font.pixelSize: 9
                                }
                            }
                            ChannelBalance {
                                Layout.fillWidth: true
                                objectName: "audioOutputBalance"
                                value: AudioService.outputBalance
                                supported: AudioService.outputBalanceSupported
                                onValueEdited: function(value) { AudioService.setOutputBalance(value) }
                            }
                        }
                    }

                    // Input card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: inputCard.implicitHeight + 28
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout {
                            id: inputCard
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14
                            spacing: 6

                            LevelSlider {
                                Layout.fillWidth: true
                                title: "microphone volume"
                                value: AudioService.inputMaster
                                valueLabel: Math.round(AudioService.inputMaster * 100) + "%"
                                onValueEdited: function(value) { AudioService.setInputVolume(value) }
                            }
                            Label {
                                text: AudioService.inputChoices.length > 1
                                    ? "available inputs · " + AudioService.inputChoices.length
                                    : "input device"
                                color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9
                            }
                            ComboBox {
                                id: inputSelector
                                objectName: "audioInputSelector"
                                Layout.fillWidth: true
                                enabled: inputChoiceModel.count > 0
                                textRole: "label"
                                model: inputChoiceModel
                                onActivated: function(index) {
                                    AudioService.selectInput(AudioService.inputChoices[index])
                                }
                                contentItem: Text {
                                    leftPadding: 10; rightPadding: 28
                                    text: inputSelector.count > 0 ? inputSelector.displayText : "No microphones detected"
                                    color: inputSelector.enabled ? Theme.text : Theme.muted
                                    font.family: Theme.uiFont; font.pixelSize: 10
                                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 9; color: Theme.surfaceRaised; border.width: 1
                                    border.color: inputSelector.popup.visible ? Theme.islandAccent : Theme.outline
                                }
                                indicator: Text {
                                    x: inputSelector.width - width - 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "⌄"; color: Theme.muted; font.pixelSize: 14
                                }
                                popup: Popup {
                                    y: inputSelector.height; width: inputSelector.width; padding: 4
                                    background: Rectangle { radius: 9; color: Theme.surfaceRaised
                                        border.color: Theme.outline; border.width: 1 }
                                    contentItem: ListView {
                                        model: inputSelector.delegateModel
                                        currentIndex: inputSelector.highlightedIndex
                                        clip: true; implicitHeight: Math.min(contentHeight, 180)
                                    }
                                }
                                delegate: ItemDelegate {
                                    required property int index
                                    objectName: "inputChoiceDelegate-" + index
                                    width: inputSelector.width; height: 44
                                    contentItem: ColumnLayout {
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            text: inputChoiceModel.get(index).label
                                            color: Theme.text; font.family: Theme.uiFont
                                            font.pixelSize: 10; elide: Text.ElideRight
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: (inputChoiceModel.get(index).active ? "ACTIVE · " : "")
                                                  + inputChoiceModel.get(index).detail
                                            color: inputChoiceModel.get(index).active ? Theme.success : Theme.muted
                                            font.family: Theme.iconFont; font.pixelSize: 8; elide: Text.ElideRight
                                        }
                                    }
                                    background: Rectangle { radius: 7
                                        color: highlighted ? Theme.surfaceHover : "transparent" }
                                }
                            }
                            StyledButton { compact: true
                                text: AudioService.inputMuted ? "unmute microphone" : "mute microphone"
                                onClicked: AudioService.toggleInputMute() }
                            ChannelBalance {
                                Layout.fillWidth: true
                                objectName: "audioInputBalance"
                                value: AudioService.inputBalance
                                supported: AudioService.inputBalanceSupported
                                onValueEdited: function(value) { AudioService.setInputBalance(value) }
                            }
                        }
                    }
                }
            }

            // ── Display ──────────────────────────────────────────────────
            Flickable {
                id: displayPage
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width
                contentHeight: Math.max(height, displayView.implicitHeight)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                clip: true; boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: displayView
                    width: parent.width
                    spacing: 8

                    Rectangle { Layout.fillWidth: true; implicitHeight: 80
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout { anchors.fill: parent; anchors.margins: 14
                            LevelSlider { Layout.fillWidth: true; title: "screen brightness"
                                value: BrightnessService.level
                                valueLabel: Math.round(BrightnessService.level * 100) + "%"
                                onValueEdited: function(value) { BrightnessService.set(value * 100) } } } }

                    Rectangle { Layout.fillWidth: true
                        implicitHeight: NightLightService.enabled ? 130 : 92
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout { anchors.fill: parent; anchors.margins: 14
                            RowLayout { Layout.fillWidth: true
                                Label { text: "Night Light"; color: Theme.text; font.family: Theme.uiFont
                                    font.pixelSize: 14; font.weight: 600 }
                                Item { Layout.fillWidth: true }
                                ToggleSwitch { checked: NightLightService.enabled
                                    enabled: NightLightService.available
                                    onToggled: NightLightService.toggle() } }
                            LevelSlider { visible: NightLightService.enabled; Layout.fillWidth: true
                                title: "color temperature"; value: NightLightService.level
                                valueLabel: NightLightService.temperature + "K"
                                onValueEdited: NightLightService.setTemperature(
                                    NightLightService.minimum + value * (NightLightService.maximum - NightLightService.minimum)) }
                            Label { text: NightLightService.available
                                    ? "hyprsunset available · applying changes smoothly" : "hyprsunset unavailable"
                                color: NightLightService.available ? Theme.muted : Theme.error
                                font.family: Theme.iconFont; font.pixelSize: 9 } } }
                }
            }

            // ── Alerts ───────────────────────────────────────────────────
            Flickable {
                id: notificationsPage
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width
                contentHeight: Math.max(height, notifPanel.implicitHeight)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                clip: true; boundsBehavior: Flickable.StopAtBounds
                NotificationPanel { id: notifPanel; width: parent.width }
            }

            // ── System ───────────────────────────────────────────────────
            Flickable {
                id: systemPage
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width
                contentHeight: Math.max(height, systemView.implicitHeight)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                clip: true; boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: systemView
                    width: parent.width
                    spacing: 8

                    Rectangle { Layout.fillWidth: true; implicitHeight: 66
                        radius: Theme.radius; color: Theme.surface
                        RowLayout { anchors.fill: parent; anchors.margins: 12
                            Rectangle { implicitWidth: 100; implicitHeight: 10; radius: 5; color: Theme.outline
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, root.batteryPercent / 100))
                                    height: parent.height; radius: 5
                                    color: root.battery?.state === 1 ? Theme.success : Theme.islandAccent } }
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                Label { text: root.batteryPercent >= 0 ? Math.round(root.batteryPercent) + "%" : "n/a"
                                    color: Theme.text; font.family: Theme.iconFont
                                    font.pixelSize: 16; font.weight: 600 }
                                Label { text: !root.battery || root.batteryPercent < 0 ? "battery unavailable"
                                        : root.battery.state === 1 ? "charging"
                                        : UPower.onBattery ? "on battery" : "plugged in"
                                    color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 9 } }
                            StyledButton { compact: true; text: "details" } } }

                    RowLayout { Layout.fillWidth: true; spacing: 6
                        Rectangle { Layout.fillWidth: true; implicitHeight: 94
                            radius: Theme.radius; color: Theme.surface
                            Gauge { anchors.centerIn: parent; label: "cpu"
                                value: SystemService.cpuPercent / 100
                                valueText: SystemService.cpuPercent.toFixed(0) + "%"
                                accent: SystemService.cpuPercent > 80 ? Theme.error
                                      : SystemService.cpuPercent > 50 ? Theme.warning : Theme.islandAccent } }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 94
                            radius: Theme.radius; color: Theme.surface
                            Gauge { anchors.centerIn: parent; label: "gpu"
                                value: 0; valueText: "n/a"; accent: Theme.muted } }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 94
                            radius: Theme.radius; color: Theme.surface
                            Gauge { anchors.centerIn: parent; label: "memory"
                                value: SystemService.memoryPercent / 100
                                valueText: SystemService.memoryPercent.toFixed(0) + "%"
                                accent: SystemService.memoryPercent > 80 ? Theme.error
                                      : SystemService.memoryPercent > 60 ? Theme.warning : Theme.islandAccent } }
                    }

                    Rectangle { Layout.fillWidth: true
                        implicitHeight: metricsInner.implicitHeight + 28
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout { id: metricsInner
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14; spacing: 6
                            Label { text: "metrics"; color: Theme.muted
                                font.family: Theme.iconFont; font.pixelSize: 10 }
                            RowLayout { Layout.fillWidth: true
                                Label { Layout.fillWidth: true
                                    text: "cpu usage\n" + SystemService.cpuPercent.toFixed(0) + "%"
                                    color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 10 }
                                Label { Layout.fillWidth: true
                                    text: "memory\n" + SystemService.memoryLabel
                                    color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 10 } }
                            RowLayout { Layout.fillWidth: true
                                Label { Layout.fillWidth: true
                                    text: "cpu temp\n" + (SystemService.temperatureAvailable
                                        ? SystemService.temperature.toFixed(0) + "°c" : "n/a")
                                    color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 10 }
                                Label { Layout.fillWidth: true; text: "gpu\nnot available"
                                    color: Theme.muted; font.family: Theme.iconFont; font.pixelSize: 10 } }
                        }
                    }

                    Rectangle { Layout.fillWidth: true
                        implicitHeight: fanStatus.implicitHeight + 28
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout { id: fanStatus
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14; spacing: 4
                            Label { text: "fan control unavailable"; color: Theme.muted
                                font.family: Theme.iconFont; font.pixelSize: 10 }
                            Label { text: "No supported fan-control backend is configured."
                                color: Theme.mutedDim; font.family: Theme.uiFont; font.pixelSize: 10
                                wrapMode: Text.Wrap; Layout.fillWidth: true }
                        }
                    }

                    Rectangle { Layout.fillWidth: true
                        implicitHeight: powerInner.implicitHeight + 28
                        radius: Theme.radius; color: Theme.surface
                        ColumnLayout { id: powerInner
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14; spacing: 8
                            RowLayout { Layout.fillWidth: true
                                Label { text: "power profile"; color: Theme.muted
                                    font.family: Theme.iconFont; font.pixelSize: 10 }
                                Item { Layout.fillWidth: true }
                                Label { text: SystemService.powerProfile; color: Theme.islandAccent
                                    font.family: Theme.iconFont; font.pixelSize: 9; font.weight: 600 } }
                            RowLayout { Layout.fillWidth: true; spacing: 6
                                Repeater {
                                    model: ["power-saver", "balanced", "performance"]
                                    delegate: StyledButton {
                                        required property string modelData
                                        Layout.fillWidth: true; compact: true; text: modelData
                                        highlighted: SystemService.powerProfile === modelData
                                        onClicked: SystemService.setPowerProfile(modelData)
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
