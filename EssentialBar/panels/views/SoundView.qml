// SoundView.qml
// Sound panel view (v-sound).
// Output/input volume sliders, stereo balance, and device picker lists.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../components"
import "../../services"

Item {
    id: root

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: sndCol.implicitHeight + 36
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: sndCol; width: parent.width
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
            spacing: Theme.spacingSize(12)

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: sndBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: sndBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    RowLayout { id: sndBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                        SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                        Text { text: "Sound"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                    }
                    MouseArea { id: sndBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                }
                Item { Layout.fillWidth: true }
                ToggleSwitch { checked: !AudioService.muted; onClicked: AudioService.setMuted(!checked) }
            }

            // ── Output volume ─────────────────────────────────────────────
            RowLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(12)
                SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); iconName: AudioService.muted ? "volume-x" : "volume-2"; tone: "muted" }
                LevelSlider { Layout.fillWidth: true; value: AudioService.outputMaster; onValueEdited: function(v) { AudioService.setVolume(v) } }
                Text { text: Math.round(AudioService.outputMaster * 100) + "%"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.features: ({ "tnum": 1 }) }
            }

            // ── Stereo balance ────────────────────────────────────────────
            ChannelBalance {
                Layout.fillWidth: true
                value:     AudioService.outputBalance
                supported: AudioService.outputBalanceSupported
                onValueEdited: function(v) { AudioService.setOutputBalance(v) }
            }

            // ── Output devices ─────────────────────────────────────────────
            Text { text: "Output"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }

            Repeater {
                model: AudioService.outputChoices
                delegate: Rectangle {
                    required property var modelData; required property int index
                    Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(44); radius: Theme.radiusCard
                    color: modelData.active ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.12)) : outDevHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                    border.width: modelData.active ? 1 : 0; border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.30))
                    RowLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(10)
                        SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "volume-2"; tone: modelData.active ? "accent" : "muted" }
                        ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                            Text { Layout.fillWidth: true; text: modelData.description || modelData.name || "Output"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: (modelData.active ? "Active · " : "") + (modelData.detail || ""); color: modelData.active ? Theme.success : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                        }
                    }
                    MouseArea { id: outDevHov; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.selectOutput(modelData) }
                }
            }

            // ── Input devices ──────────────────────────────────────────────
            Text { text: "Input"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }

            Repeater {
                model: AudioService.inputChoices
                delegate: Rectangle {
                    required property var modelData; required property int index
                    Layout.fillWidth: true; implicitHeight: Theme.dimensionSize(44); radius: Theme.radiusCard
                    color: modelData.active ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.12)) : inDevHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                    border.width: modelData.active ? 1 : 0; border.color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.30))
                    RowLayout { anchors.fill: parent; anchors.margins: Theme.marginSize(12); spacing: Theme.spacingSize(10)
                        SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "mic"; tone: modelData.active ? "accent" : "muted" }
                        ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                            Text { Layout.fillWidth: true; text: modelData.description || modelData.name || "Input"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: (modelData.active ? "Active · " : "") + (modelData.detail || ""); color: modelData.active ? Theme.success : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                        }
                    }
                    MouseArea { id: inDevHov; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.selectInput(modelData) }
                }
            }

            Text { visible: AudioService.inputChoices.length === 0; text: "No input devices detected"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.italic: true; Layout.leftMargin: Theme.marginSize(4) }
        }
    }
}
