import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: root

    property string enteredValue: ""
    visible: BluetoothService.pairingPrompt !== null
    implicitHeight: visible ? promptCard.implicitHeight : 0

    Connections {
        target: BluetoothService
        function onPairingPromptChanged() { root.enteredValue = "" }
    }

    Rectangle {
        id: promptCard
        anchors.fill: parent
        implicitHeight: promptColumn.implicitHeight + Theme.dimensionSize(20)
        radius: Theme.radiusCard
        color: Theme.surface
        border.width: Theme.dimensionSize(1)
        border.color: Theme.primary

        ColumnLayout {
            id: promptColumn
            anchors.fill: parent
            anchors.margins: Theme.marginSize(10)
            spacing: Theme.spacingSize(6)

            Text {
                Layout.fillWidth: true
                text: BluetoothService.pairingPrompt?.kind === "confirmation"
                    ? "Bluetooth pairing request"
                    : BluetoothService.pairingPrompt?.kind === "authorization"
                        ? "Allow Bluetooth pairing?"
                        : BluetoothService.pairingPrompt?.kind === "service"
                            ? "Allow Bluetooth service?"
                            : BluetoothService.pairingPrompt?.kind === "display"
                                ? "Bluetooth code"
                                : "Enter Bluetooth code"
                color: Theme.text
                font.family: Theme.uiFont
                font.pixelSize: Theme.fontSize(13)
                font.weight: Theme.fontWeightSemibold
            }
            Text {
                Layout.fillWidth: true
                text: BluetoothService.pairingPrompt?.kind === "confirmation"
                    ? "Compare this code with the one shown on " + (BluetoothService.pairingPrompt?.deviceName || "your device") + ". Confirm only if they match."
                    : BluetoothService.pairingPrompt?.kind === "display"
                        ? "Show this code on " + (BluetoothService.pairingPrompt?.deviceName || "your device") + "."
                        : "Pair with " + (BluetoothService.pairingPrompt?.deviceName || "this device") + "?"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.Wrap
            }
            Text {
                visible: !!BluetoothService.pairingPrompt?.passkey
                Layout.alignment: Qt.AlignHCenter
                text: BluetoothService.pairingPrompt?.passkey || ""
                color: Theme.primary
                font.family: Theme.uiFont
                font.pixelSize: Theme.fontSize(22)
                font.weight: Theme.fontWeightBold
                font.letterSpacing: Theme.letterSpacingValue(1)
            }
            TextField {
                visible: ["pin", "passkey"].includes(BluetoothService.pairingPrompt?.kind || "")
                Layout.fillWidth: true
                text: root.enteredValue
                placeholderText: BluetoothService.pairingPrompt?.kind === "pin" ? "Enter PIN" : "Enter passkey"
                onTextChanged: root.enteredValue = text
                inputMethodHints: BluetoothService.pairingPrompt?.kind === "passkey"
                    ? Qt.ImhDigitsOnly : Qt.ImhNone
            }
            RowLayout {
                visible: BluetoothService.pairingPrompt?.requiresDecision === true
                Layout.fillWidth: true
                spacing: Theme.spacingSize(8)

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.dimensionSize(34)
                    radius: Theme.radiusControl
                    color: denyMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                    Text {
                        anchors.centerIn: parent
                        text: "Deny"
                        color: Theme.error
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Theme.fontWeightMedium
                    }
                    MouseArea {
                        id: denyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: BluetoothService.respondToPairingPrompt(false)
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.dimensionSize(34)
                    radius: Theme.radiusControl
                    color: confirmMouse.containsMouse ? Theme.primaryStrong : Theme.primary
                    Text {
                        anchors.centerIn: parent
                        text: ["pin", "passkey"].includes(BluetoothService.pairingPrompt?.kind || "") ? "Submit" : "Confirm"
                        color: Theme.background
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Theme.fontWeightSemibold
                    }
                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !["pin", "passkey"].includes(BluetoothService.pairingPrompt?.kind || "") || root.enteredValue.length > 0
                        onClicked: BluetoothService.respondToPairingPrompt(true, root.enteredValue)
                    }
                }
            }
        }
    }
}
