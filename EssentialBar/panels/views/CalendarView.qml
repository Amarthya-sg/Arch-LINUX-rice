// CalendarView.qml
// In-panel calendar view (v-cal).
// Big live clock, date, month navigation, and a 7-column day grid.
import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../components"

Item {
    id: root

    // ── Local state ───────────────────────────────────────────────────────
    property date calMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date today:    new Date()

    // ── Helpers ───────────────────────────────────────────────────────────
    // Monday-first offset: Sunday = 6, Monday = 0 … Saturday = 5
    function monthOffset(d): int { return (d.getDay() + 6) % 7 }
    function daysInMonth(d): int { return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate() }
    function isToday(y, m, day): bool {
        return today.getFullYear() === y && today.getMonth() === m && today.getDate() === day
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.marginSize(18); spacing: Theme.spacingSize(12)

        // ── Header (back) ─────────────────────────────────────────────────
        Rectangle { implicitHeight: Theme.dimensionSize(40); implicitWidth: calBackRow.implicitWidth + 20; radius: Theme.radiusSize(12); color: calBackHov.containsMouse ? Theme.surfaceRaised : "transparent"
            RowLayout { id: calBackRow; anchors.centerIn: parent; spacing: Theme.spacingSize(6)
                SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                Text { text: "Calendar"; color: Theme.fg; font.pixelSize: Theme.fontSize(16); font.weight: Theme.fontWeightSemibold; font.family: Theme.uiFont }
            }
            MouseArea { id: calBackHov; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.back() }
        }

        // ── Big live clock ────────────────────────────────────────────────
        ColumnLayout { Layout.fillWidth: true; spacing: Theme.spacingSize(2)
            Text { text: Qt.formatTime(ShellState.now, "HH:mm:ss"); color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(40); font.weight: Theme.fontWeightLight; font.letterSpacing: Theme.letterSpacingValue(-1) }
            Text { text: Qt.formatDate(ShellState.now, "dddd, MMMM d, yyyy"); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12) }
        }

        // ── Month nav ─────────────────────────────────────────────────────
        RowLayout { Layout.fillWidth: true
            Text { text: Qt.formatDate(root.calMonth, "MMMM yyyy"); color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightSemibold; Layout.fillWidth: true }
            Rectangle { implicitWidth: Theme.dimensionSize(36); implicitHeight: Theme.dimensionSize(36); radius: Theme.radiusSize(10); color: prevMonHov.containsMouse ? Theme.surfaceRaised : "transparent"
                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                MouseArea { id: prevMonHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.calMonth = new Date(root.calMonth.getFullYear(), root.calMonth.getMonth() - 1, 1) }
            }
            Rectangle { implicitWidth: Theme.dimensionSize(36); implicitHeight: Theme.dimensionSize(36); radius: Theme.radiusSize(10); color: nextMonHov.containsMouse ? Theme.surfaceRaised : "transparent"
                SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "fg" }
                MouseArea { id: nextMonHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.calMonth = new Date(root.calMonth.getFullYear(), root.calMonth.getMonth() + 1, 1) }
            }
        }

        // ── Calendar grid ─────────────────────────────────────────────────
        Grid {
            Layout.fillWidth: true; columns: 7; spacing: Theme.spacingSize(2)
            property int cellSize: Math.floor((parent.width - 12) / 7)

            // Weekday headers (Mon-first)
            Repeater {
                model: ["M","T","W","T","F","S","S"]
                delegate: Item {
                    required property string modelData
                    width: parent.cellSize; height: Theme.dimensionSize(24)
                    Text { anchors.centerIn: parent; text: modelData; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11) }
                }
            }

            // Blank offset cells
            Repeater {
                model: root.monthOffset(root.calMonth)
                delegate: Item { width: parent.cellSize; height: Theme.dimensionSize(36) }
            }

            // Day cells
            Repeater {
                model: root.daysInMonth(root.calMonth)
                delegate: Item {
                    required property int index
                    property bool itIsToday: root.isToday(root.calMonth.getFullYear(), root.calMonth.getMonth(), index + 1)
                    width: parent.cellSize; height: Theme.dimensionSize(36)

                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.dimensionSize(32); height: Theme.dimensionSize(32); radius: Theme.radiusSize(16)
                        color: itIsToday ? Theme.acc : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text:  String(index + 1)
                        color: itIsToday ? Theme.islandBg : Theme.fg
                        font.family:    Theme.uiFont
                        font.pixelSize: Theme.fontSize(13)
                        font.weight:    itIsToday ? Theme.fontWeightSemibold : Theme.fontWeightRegular
                        font.features:  ({ "tnum": 1 })
                    }
                }
            }
        }
    }
}
