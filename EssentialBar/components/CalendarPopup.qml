// CalendarPopup.qml
// Standalone calendar / media hover-card popup surface.
// Previously inlined in shell.qml inside the calendarOverlay PanelWindow.
//
// Drop this Rectangle into a PanelWindow and position it:
//   CalendarPopup {
//       x:      Math.max(8, Math.min(barWidth - width - 8, (barWidth - width) / 2))
//       y:      -2
//       width:  rootScope.clockPopupWidth
//       height: rootScope.clockPopupHeight
//       barWidth: bar.width
//       ...
//   }
import QtQuick
import QtQuick.Layouts
import "../../EssentialBar/core"   // resolved at runtime via import path; caller's shell sets up the path
import "../core"
import "../services"

Rectangle {
    id: root

    // ── Props injected from shell.qml ────────────────────────────────────
    property real barWidth:         800

    // Calendar state
    property date  calendarMonthStart: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property bool  calendarOpen:       false

    // Media hover-card state (legacy island.* flags)
    property bool  mediaInfoVisible: false
    property bool  mediaPanelOpen:   false

    // ── Signals ───────────────────────────────────────────────────────────
    signal prevMonthRequested()
    signal nextMonthRequested()

    // ── Appearance ────────────────────────────────────────────────────────
    radius:       Theme.radiusSize(16)
    color:        Theme.background
    border.width: Theme.dimensionSize(1)
    border.color: Theme.outline

    // Helper: format µs → m:ss
    function formatMediaTime(us): string {
        const s = Math.max(0, Math.floor((Number(us) || 0) / 1000000))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    // ── Content ───────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill:    parent
        anchors.margins: Theme.marginSize(16)
        spacing:         Theme.spacingSize(16)

        // ────────────────────────────────────────────────────────────────
        // LEFT: calendar column
        // ────────────────────────────────────────────────────────────────
        ColumnLayout {
            id: calendarColumn
            visible: root.calendarOpen || root.mediaPanelOpen
            Layout.preferredWidth: root.mediaPanelOpen ? 260 : root.width - 32
            Layout.fillHeight: true
            spacing: Theme.spacingSize(8)

            // Time + date header
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSize(10)
                ColumnLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(1)
                    Label {
                        text: ShellState.time
                        color: Theme.text
                        font.family:    Theme.uiFont
                        font.pixelSize: Theme.fontSize(21)
                        font.weight:    Theme.fontWeightSemibold
                    }
                    Label {
                        text: Qt.formatDateTime(ShellState.now, "dddd, MMMM d")
                        color: Theme.muted
                        font.family:    Theme.uiFont
                        font.pixelSize: Theme.fontSize(10)
                    }
                }
                Item { width: Theme.dimensionSize(26); height: Theme.dimensionSize(26) }
            }

            Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.outline }

            // Month nav
            RowLayout {
                Layout.fillWidth: true

                Rectangle {
                    width: Theme.dimensionSize(28); height: Theme.dimensionSize(26); radius: Theme.radiusSize(8)
                    color: prevMonthMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg" }
                    MouseArea { id: prevMonthMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.prevMonthRequested() }
                }
                Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(root.calendarMonthStart, "MMMM yyyy")
                    color: Theme.text
                    font.family:    Theme.uiFont
                    font.pixelSize: Theme.fontSize(12)
                    font.weight:    Theme.fontWeightSemibold
                }
                Rectangle {
                    width: Theme.dimensionSize(28); height: Theme.dimensionSize(26); radius: Theme.radiusSize(8)
                    color: nextMonthMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "fg" }
                    MouseArea { id: nextMonthMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.nextMonthRequested() }
                }
            }

            // 7-column calendar grid
            Grid {
                id: calendarGrid
                Layout.fillWidth: true
                columns: 7
                spacing: Theme.spacingSize(3)
                property real cellWidth: (width - 18) / 7

                // Weekday headers
                Repeater {
                    model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                    delegate: Label {
                        required property string modelData
                        width:  calendarGrid.cellWidth
                        height: Theme.dimensionSize(20)
                        text:   modelData
                        color:  Theme.muted
                        font.family:    Theme.uiFont
                        font.pixelSize: Theme.fontSize(9)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                }

                // 42 day cells (6 weeks × 7)
                Repeater {
                    model: 42
                    delegate: Rectangle {
                        required property int index
                        readonly property var dateValue: _calDate(index)
                        readonly property bool isToday:   _isToday(dateValue)
                        readonly property bool inMonth:   _inMonth(dateValue)

                        width:  calendarGrid.cellWidth
                        height: Theme.dimensionSize(29)
                        radius: Theme.radiusSize(8)
                        color:  isToday ? Theme.primary
                            : inMonth ? Theme.surfaceRaised : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text:  dateValue.getDate()
                            color: isToday ? Theme.background
                                : inMonth  ? Theme.text : Theme.mutedDim
                            font.family:    Theme.uiFont
                            font.pixelSize: Theme.fontSize(10)
                            font.weight:    isToday ? Theme.fontWeightBold : Theme.fontWeightRegular
                        }
                    }
                }
            }
        }

        // ── Divider between calendar and media panel ──────────────────────
        Rectangle {
            visible: root.mediaPanelOpen
            Layout.fillHeight: true
            width: Theme.dimensionSize(1)
            color: Theme.outline
        }

        // ────────────────────────────────────────────────────────────────
        // RIGHT: media hover card (compact, shown on track-change hover)
        // ────────────────────────────────────────────────────────────────
        ColumnLayout {
            id: hoverMediaCard
            visible: MediaService.hasTrack && root.mediaInfoVisible && !root.mediaPanelOpen
            Layout.fillWidth:  true
            Layout.fillHeight: true
            spacing: Theme.spacingSize(9)

            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacingSize(10)
                Rectangle {
                    width: Theme.dimensionSize(38); height: Theme.dimensionSize(38); radius: Theme.radiusSize(11); color: Theme.surfaceRaised
                    SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(20); height: Theme.dimensionSize(20); iconName: "music-2"; tone: "accent" }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(2)
                    Label { Layout.fillWidth: true; text: MediaService.title || "Unknown track"; color: Theme.text; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightBold; elide: Text.ElideRight }
                    Label { Layout.fillWidth: true; text: MediaService.artist || MediaService.playerName; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); elide: Text.ElideRight }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacingSize(14)
                Repeater {
                    model: [
                        { action: "previous", iconName: "skip-back",                             size: 30 },
                        { action: "toggle",   iconName: MediaService.playing ? "pause" : "play", size: 38 },
                        { action: "next",     iconName: "skip-forward",                          size: 30 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: modelData.size; height: modelData.size; radius: width / 2
                        color: mediaHoverControl.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                        SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: modelData.iconName; tone: "fg" }
                        MouseArea {
                            id: mediaHoverControl; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                m.accepted = true
                                if      (modelData.action === "previous") MediaService.previous()
                                else if (modelData.action === "next")     MediaService.next()
                                else                                      MediaService.toggle()
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacingSize(4)
                RowLayout { Layout.fillWidth: true
                    Label { text: root.formatMediaTime(MediaService.displayPosition); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9) }
                    Item { Layout.fillWidth: true }
                    Label { text: root.formatMediaTime(MediaService.length); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9) }
                }
                Rectangle {
                    property real progress: MediaService.length > 0
                        ? Math.max(0, Math.min(1, MediaService.displayPosition / MediaService.length)) : 0
                    Layout.fillWidth: true; height: Theme.dimensionSize(6); radius: Theme.radiusSize(3); color: Theme.surfaceRaised
                    Rectangle {
                        id: hoverProgressFill
                        width: parent.width * parent.progress; height: parent.height; radius: parent.radius; color: Theme.islandAccent
                        Behavior on width { NumberAnimation { duration: Theme.duration(90); easing.type: Easing.Linear } }
                        Rectangle {
                            visible: MediaService.playing && hoverProgressFill.width > 4
                            width: Theme.dimensionSize(8); height: Theme.dimensionSize(8); radius: Theme.radiusSize(4)
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primaryStrong; opacity: Theme.opacityValue(0.9)
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; MediaService.seekToRatio(e.x / width) } }
                }
            }
        }
    }

    // ── Private calendar helpers ──────────────────────────────────────────
    function _calDate(index): date {
        const firstDay = root.calendarMonthStart.getDay()
        return new Date(root.calendarMonthStart.getFullYear(),
                        root.calendarMonthStart.getMonth(),
                        index - firstDay + 1)
    }
    function _inMonth(date): bool {
        return date.getMonth()    === root.calendarMonthStart.getMonth()
            && date.getFullYear() === root.calendarMonthStart.getFullYear()
    }
    function _isToday(date): bool {
        const t = new Date()
        return date.getDate()    === t.getDate()
            && date.getMonth()   === t.getMonth()
            && date.getFullYear() === t.getFullYear()
    }
}
