// BtView.qml
// Bluetooth panel view (v-bt).
// Lists paired/available devices with connect/disconnect/forget/pair actions,
// inline expandable details card, scan sweep, and battery % for supported devices.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../components"
import "../../services"

Item {
    id: root

    property string detailsAddress: ""

    function toggleDetails(device): void {
        const address = String(BluetoothService.value(device, "address") || "")
        detailsAddress = detailsAddress === address ? "" : address
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(10)

        // ── Header ────────────────────────────────────────────────────────
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

        // ── Scan sweep ────────────────────────────────────────────────────
        ScanSweep { Layout.fillWidth: true; Layout.leftMargin: Theme.marginSize(8); Layout.rightMargin: Theme.marginSize(8); active: BluetoothService.scanning }

        Text { visible: !BluetoothService.enabled; text: "Turn Bluetooth on to discover devices."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }

        // ── Device list ───────────────────────────────────────────────────
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
                        readonly property bool   detailsOpen:   root.detailsAddress === deviceAddress
                        readonly property string devStatus:     BluetoothService.deviceStatus(modelData)
                        readonly property bool   busy:          devStatus.endsWith("…")

                        Layout.fillWidth: true
                        implicitHeight: btDevRow.implicitHeight + 20 + (detailsOpen ? btDetailsCol.implicitHeight + 8 : 0)
                        radius: Theme.radiusCard
                        color:  BluetoothService.value(modelData, "connected") ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.10)) : Theme.surfaceRaised
                        border.width: BluetoothService.value(modelData, "connected") ? 1 : 0
                        border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.25))

                        RowLayout {
                            id: btDevRow
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(10) }
                            spacing: Theme.spacingSize(8)

                            // Status dot
                            Rectangle {
                                width: Theme.dimensionSize(9); height: Theme.dimensionSize(9); radius: Theme.radiusSize(5)
                                color: BluetoothService.value(modelData, "connected") ? Theme.success
                                    : BluetoothService.value(modelData, "paired") ? Theme.acc : Theme.muted
                            }

                            ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                                Text { text: BluetoothService.displayName(modelData) || "Bluetooth device"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightSemibold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: devStatus + (BluetoothService.value(modelData, "batteryAvailable") ? " · " + Math.round(BluetoothService.value(modelData, "battery") * 100) + "%" : ""); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            // Action button
                            Rectangle { implicitWidth: btActTxt.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: btActHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                Text { id: btActTxt; anchors.centerIn: parent; text: busy ? devStatus : !BluetoothService.value(modelData, "paired") ? "Pair" : BluetoothService.value(modelData, "connected") ? "Disconnect" : "Connect"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                MouseArea { id: btActHov; anchors.fill: parent; hoverEnabled: true; enabled: !busy; onClicked: BluetoothService.activate(modelData) }
                            }

                            // Info
                            Rectangle { implicitWidth: Theme.dimensionSize(30); implicitHeight: Theme.dimensionSize(30); radius: Theme.radiusSize(15); color: btInfoHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                Text { anchors.centerIn: parent; text: "i"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightBold }
                                MouseArea { id: btInfoHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleDetails(modelData) }
                            }

                            // Forget
                            Rectangle { visible: BluetoothService.value(modelData, "paired"); implicitWidth: Theme.dimensionSize(60); implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10); color: btForgetHov.containsMouse ? Qt.rgba(1, 0.42, 0.37, Theme.opacityValue(0.20)) : Theme.surfaceRaised
                                Text { anchors.centerIn: parent; text: "Forget"; color: Theme.error; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                                MouseArea { id: btForgetHov; anchors.fill: parent; hoverEnabled: true; onClicked: BluetoothService.forget(modelData) }
                            }
                        }

                        // Details card
                        ColumnLayout {
                            id: btDetailsCol
                            visible: detailsOpen
                            anchors { left: parent.left; right: parent.right; top: btDevRow.bottom; leftMargin: Theme.marginSize(10); rightMargin: Theme.marginSize(10); bottomMargin: Theme.marginSize(10) }
                            spacing: Theme.spacingSize(2)
                            Text { Layout.fillWidth: true; text: "Address: " + deviceAddress; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: "Status: " + devStatus; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                            Text { visible: BluetoothService.value(modelData, "batteryAvailable"); Layout.fillWidth: true; text: "Battery: " + Math.round(BluetoothService.value(modelData, "battery") * 100) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10) }
                        }
                    }
                }

                Text { visible: BluetoothService.devices.length === 0 && !BluetoothService.scanning; text: "No devices found. Tap Scan."; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
            }
        }
    }

    // ── Shared scan sweep ─────────────────────────────────────────────────
    component ScanSweep: Item {
        id: sweepRoot; property bool active: false; implicitHeight: Theme.dimensionSize(6)
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
