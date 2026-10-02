// AlertsView.qml
// Notifications panel view (v-alerts).
// Header with back/clear-all, then delegates to NotificationPanel for the list.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../components"
import "../../services"
import ".."

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(10)

        // ── Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: alBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: alBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
                RowLayout { id: alBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                    SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                    Text { text: "Notifications"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
                }
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

        // ── Notification list ─────────────────────────────────────────────
        Flickable {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: width; contentHeight: notifContent.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            NotificationPanel { id: notifContent; width: parent.width }
        }
    }
}
