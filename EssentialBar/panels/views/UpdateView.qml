// UpdateView.qml
// System updates panel view (v-update).
// Shows pending package count, tooltip detail, and placeholder package rows.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../components"
import "../../services"

Item {
    id: root

    // ── Props from ControlPanel ───────────────────────────────────────────
    property int    pendingUpdates: 0
    property string updateTooltip:  ""

    // ── Signal: "Install all" button pressed ──────────────────────────────
    signal installAllRequested()

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: updCol.implicitHeight + 36
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: updCol; width: parent.width
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.marginSize(18) }
            spacing: Theme.spacingSize(10)

            // ── Header ────────────────────────────────────────────────────
            RowLayout { Layout.fillWidth: true
                Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: updBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: updBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    RowLayout { id: updBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                        SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                        Text { text: "System Updates"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                    }
                    MouseArea { id: updBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: root.pendingUpdates > 0
                    implicitWidth: instTxt.implicitWidth + 24; implicitHeight: Theme.dimensionSize(34); radius: Theme.radiusSize(10)
                    color: instHov.containsMouse ? Theme.surfaceRaised : "transparent"
                    Text { id: instTxt; anchors.centerIn: parent; text: "Install all"; color: Theme.acc; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13); font.weight: Theme.fontWeightMedium }
                    MouseArea { id: instHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.installAllRequested() }
                }
            }

            // ── Summary ───────────────────────────────────────────────────
            Text { text: root.pendingUpdates + " packages available"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
            Text { text: root.updateTooltip; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); wrapMode: Text.Wrap; Layout.fillWidth: true }

            // ── Package rows ──────────────────────────────────────────────
            Repeater {
                model: Math.min(root.pendingUpdates, 20)
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

            // ── Up-to-date state ──────────────────────────────────────────
            ColumnLayout {
                visible: root.pendingUpdates === 0
                Layout.fillWidth: true; Layout.topMargin: Theme.marginSize(24); spacing: Theme.spacingSize(8)
                SvgIcon { Layout.alignment: Qt.AlignHCenter; width: Theme.dimensionSize(32); height: Theme.dimensionSize(32); iconName: "check"; tone: "muted"; opacity: Theme.opacityValue(0.4) }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Your system is up to date"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13) }
            }
        }
    }
}
