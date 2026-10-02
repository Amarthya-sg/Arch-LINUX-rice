// BattView.qml
// Battery & system stats panel view (v-batt).
// Hero battery ring, CPU/RAM/GPU/SSD compact cards, fan RPM, power profile.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../core"
import "../../components"
import "../../services"

Item {
    id: root

    // ── Derived battery state ─────────────────────────────────────────────
    readonly property var   battery:     UPower.displayDevice
    readonly property real  battPct:     SystemService.batteryAvailable
        ? SystemService.batteryPercent
        : battery && Number.isFinite(Number(battery.percentage))
            ? Math.max(0, Math.min(100, Number(battery.percentage) * 100)) : 0
    readonly property bool  battCharging: SystemService.batteryAvailable
        ? SystemService.batteryCharging : battery && battery.state === 1
    readonly property color battColor:
        battCharging ? Theme.success
        : battPct <= 20 ? Theme.error
        : battPct <= 40 ? Theme.warning
        : Theme.fg

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: battCol.implicitHeight + 36
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: battCol; width: parent.width
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
            spacing: Theme.spacingSize(12)

            // ── Header ────────────────────────────────────────────────────
            Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: battBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: battBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                RowLayout { id: battBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                    SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                    Text { text: "Battery"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                }
                MouseArea { id: battBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
            }

            // ── Hero ring + side stats ─────────────────────────────────────
            RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(16)

                Gauge { hero: true; value: root.battPct / 100; valueText: Math.round(root.battPct) + "%"; accent: root.battColor }

                ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(10)
                    // Status chip
                    Rectangle {
                        implicitWidth: bChipRow.implicitWidth + 20; implicitHeight: Theme.dimensionSize(24); radius: Theme.radiusSize(99)
                        color: Qt.rgba(root.battColor.r, root.battColor.g, root.battColor.b, Theme.opacityValue(0.14))
                        RowLayout { id: bChipRow; anchors.centerIn: parent; spacing: Theme.spacingSize(5)
                            SvgIcon { width: Theme.dimensionSize(14); height: Theme.dimensionSize(14)
                                iconName: root.battCharging ? "battery-charging" : root.battPct <= 20 ? "battery-low" : root.battPct <= 40 ? "battery-medium" : "battery-full"
                                tone:     root.battCharging ? "success" : root.battPct <= 20 ? "error" : root.battPct <= 40 ? "warning" : "fg"
                            }
                            Text { text: root.battCharging ? "Charging" : root.battPct <= 20 ? "Low battery" : "On battery"; color: root.battColor; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium }
                        }
                    }
                    // Stat rows
                    ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(0)
                        Repeater {
                            model: [
                                { k: SystemService.batteryCharging ? "To full" : "Remaining", v: SystemService.batteryStatus.split("\n")[1] || "—" },
                                { k: "Power",   v: SystemService.batteryPower   || "—" },
                                { k: "Energy",  v: SystemService.batteryEnergy  || "—" },
                                { k: "Health",  v: SystemService.batteryHealth  || "—" },
                                { k: "Voltage", v: SystemService.batteryVoltage || "—" },
                            ]
                            delegate: ColumnLayout {
                                required property var modelData; required property int index
                                Layout.fillWidth: true; spacing: Theme.spacingSize(0)
                                Rectangle { visible: index > 0; Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.line }
                                RowLayout { Layout.fillWidth: true
                                    Text { text: modelData.k; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); Layout.fillWidth: true }
                                    Text { text: String(modelData.v || "—"); color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightSemibold; font.features: ({ "tnum": 1 }) }
                                }
                            }
                        }
                    }
                }
            }

            // ── Memory & storage heading ──────────────────────────────────
            Text { text: "Memory & storage"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }

            GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8

                // RAM
                Rectangle { Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(102); radius: Theme.radiusCard; color: Theme.surfaceRaised; border.width: Theme.dimensionSize(1); border.color: Theme.line
                    ColumnLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(5)
                        RowLayout { Layout.fillWidth: true; Text { text: "RAM"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true } Text { text: SystemService.memoryPercent.toFixed(0) + "%"; color: Theme.success; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold } }
                        Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line; Rectangle { width: parent.width * SystemService.memoryPercent / 100; height: parent.height; radius: Theme.radiusSize(4); color: SystemService.memoryPercent >= 85 ? Theme.error : SystemService.memoryPercent >= 65 ? Theme.warning : Theme.success } }
                        Text { text: SystemService.memoryLabel; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }

                // CPU
                Rectangle { Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(102); radius: Theme.radiusCard; color: Theme.surfaceRaised; border.width: Theme.dimensionSize(1); border.color: Theme.line
                    ColumnLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(5)
                        RowLayout { Layout.fillWidth: true; Text { text: "CPU"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true } Text { text: SystemService.cpuPercent.toFixed(0) + "%"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold } }
                        Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line; Rectangle { width: parent.width * SystemService.cpuPercent / 100; height: parent.height; radius: Theme.radiusSize(4); color: Theme.acc } }
                        Text { text: SystemService.cpuModel; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }

                // GPU cards
                Repeater {
                    model: SystemService.gpuStats
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(102); radius: Theme.radiusCard; color: Theme.surfaceRaised; border.width: Theme.dimensionSize(1); border.color: Theme.line
                        ColumnLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(5)
                            RowLayout { Layout.fillWidth: true; Text { text: modelData.kind === "Discrete" ? "dGPU" : modelData.kind === "Integrated" ? "iGPU" : "GPU"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true } Text { text: modelData.sleeping ? "—" : Math.round(modelData.load || 0) + "%"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold } }
                            Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line; Rectangle { width: parent.width * Math.max(0, Math.min(100, Number(modelData.load || 0))) / 100; height: parent.height; radius: Theme.radiusSize(4); color: Theme.acc } }
                            Text { text: modelData.name || "GPU"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                }

                // SSD
                Rectangle { Layout.columnSpan: 2; Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(86); radius: Theme.radiusCard; color: Theme.surfaceRaised; border.width: Theme.dimensionSize(1); border.color: Theme.line
                    ColumnLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(5)
                        RowLayout { Layout.fillWidth: true; Text { text: "SSD"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightMedium; Layout.fillWidth: true } Text { text: SystemService.storageAvailable ? SystemService.storagePercent.toFixed(0) + "%" : "—"; color: Theme.success; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(18); font.weight: Theme.fontWeightSemibold } }
                        Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(7); radius: Theme.radiusSize(4); color: Theme.line; Rectangle { width: parent.width * SystemService.storagePercent / 100; height: parent.height; radius: Theme.radiusSize(4); color: Theme.success } }
                        Text { text: SystemService.storageLabel; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }

            // ── Fan ───────────────────────────────────────────────────────
            Text { text: "Cooling fan"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }
            RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(12)
                Rectangle { implicitWidth: Theme.dimensionSize(52); implicitHeight: Theme.dimensionSize(52); radius: Theme.radiusSize(26); border.width: Theme.dimensionSize(2); border.color: Theme.line; color: "transparent"
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(30); height: Theme.dimensionSize(30); iconName: "fan"; tone: "accent"
                        RotationAnimation on rotation { running: SystemService.fanAvailable && SystemService.fanRpm > 0; loops: Animation.Infinite; from: 0; to: 360; duration: SystemService.fanRpm > 0 ? Math.round(60000 / SystemService.fanRpm * 4) : 2000 }
                    }
                }
                ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(2)
                    Text { text: SystemService.fanAvailable ? Math.round(SystemService.fanRpm) + " RPM" : "—"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(22); font.weight: Theme.fontWeightSemibold; font.features: ({ "tnum": 1 }) }
                    Text { text: SystemService.cpuTemperatureText ? "Auto · " + SystemService.cpuTemperatureText : "Auto"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }
                }
            }
        }
    }
}
