import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../core"
import "../components"
import "../services"

// Drop-in replacement for the alerts tab content.
// Parent must provide a ColumnLayout context (it uses Layout.fillWidth).
ColumnLayout {
    id: root
    spacing: 8

    // ── Header card: DND toggle + count ──────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hdrRow.implicitHeight + 24
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: NotificationService.dndEnabled
            ? Qt.rgba(0.96, 0.71, 0.27, 0.40) : Theme.outline
        Behavior on border.color { ColorAnimation { duration: 200 } }

        RowLayout {
            id: hdrRow
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 14
            spacing: 10

            SvgIcon {
                width: 18; height: 18
                iconName: NotificationService.dndEnabled ? "bell-off" : "bell"
                tone: NotificationService.dndEnabled ? "warning" : "accent"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "Notifications"
                    color: Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 14; font.weight: 600
                }
                Text {
                    text: NotificationService.dndEnabled
                        ? "Do not disturb on"
                        : NotificationService.count > 0
                            ? NotificationService.count + " notification"
                              + (NotificationService.count === 1 ? "" : "s")
                            : "All clear"
                    color: NotificationService.dndEnabled
                        ? Theme.warning
                        : NotificationService.count > 0 ? Theme.text : Theme.muted
                    font.family: Theme.uiFont; font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }

            // DND toggle
            ToggleSwitch {
                checked: NotificationService.dndEnabled
                accent:  Theme.islandAccent
                onToggled: NotificationService.setDnd(checked)
            }
        }
    }

    // ── Toolbar: count + Clear all ────────────────────────────────────────
    RowLayout {
        visible: NotificationService.count > 0
        Layout.fillWidth: true

        Text {
            text: NotificationService.count
                  + (NotificationService.count === 1 ? " notification" : " notifications")
            color: Theme.muted
            font.family: Theme.uiFont; font.pixelSize: 11
            Layout.fillWidth: true
        }
        StyledButton {
            compact: true; text: "Clear all"
            onClicked: NotificationService.clearAll()
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────
    ColumnLayout {
        visible: NotificationService.count === 0
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 6

        SvgIcon {
            Layout.alignment: Qt.AlignHCenter
            iconName: "check"; tone: "muted"
            width: 28; height: 28
            opacity: 0.4
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "You're all caught up"
            color: Theme.muted
            font.family: Theme.uiFont; font.pixelSize: 13
        }
    }

    // ── Grouped notification list ─────────────────────────────────────────
    Repeater {
        model: NotificationService.groupedNotifications

        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 6

            // Section label (Today / Earlier)
            Text {
                text: modelData.label
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: 10; font.weight: 600
                topPadding: 4
            }

            // App groups
            Repeater {
                model: modelData.apps
                delegate: AppGroupCard {
                    required property var modelData
                    Layout.fillWidth: true
                    appData: modelData
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // AppGroupCard — groups notifications from one app sender
    // ══════════════════════════════════════════════════════════════════════
    component AppGroupCard: Rectangle {
        id: card
        objectName: "notificationGroupCard"
        property var  appData
        property bool expanded: false
        readonly property bool canExpand: appData.items.length > 1

        radius: Theme.radius
        color:  Theme.surfaceRaised
        border.width: 1; border.color: Theme.outline
        implicitHeight: cardCol.implicitHeight + 24

        ColumnLayout {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 12
            spacing: 8

            // App header row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // App icon
                Image {
                    visible: (card.appData.appIcon || "") !== ""
                    source:  Quickshell.iconPath(card.appData.appIcon || "", true)
                    width: 16; height: 16
                    fillMode: Image.PreserveAspectFit
                    smooth: true; asynchronous: true
                }
                SvgIcon {
                    visible: (card.appData.appIcon || "") === ""
                    width: 14; height: 14
                    iconName: "app-window"; tone: "muted"
                }

                Text {
                    text: card.appData.appName
                    color: Theme.text
                    font.family: Theme.uiFont; font.pixelSize: 13; font.weight: 600
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Count badge when multiple
                Rectangle {
                    visible: card.appData.items.length > 1
                    radius: 8; color: Theme.surfaceHover
                    implicitWidth: cntLbl.implicitWidth + 10; implicitHeight: 18
                    Text {
                        id: cntLbl
                        anchors.centerIn: parent
                        text: card.appData.items.length
                        color: Theme.primary
                        font.family: Theme.uiFont; font.pixelSize: 10; font.weight: 600
                    }
                }

                // Mute toggle
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: muteHov.containsMouse
                        ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                    SvgIcon {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        iconName: card.appData.muted ? "bell-off" : "bell"
                        tone: card.appData.muted ? "warning" : "muted"
                    }
                    MouseArea {
                        id: muteHov; anchors.fill: parent; hoverEnabled: true
                        propagateComposedEvents: false
                        onClicked: (m) => { m.accepted = true; NotificationService.toggleMuteApp(card.appData.appName) }
                    }
                }

                // Clear app
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: clearHov.containsMouse
                        ? Qt.rgba(0.95, 0.44, 0.44, 0.18) : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                    SvgIcon {
                        anchors.centerIn: parent
                        width: 12; height: 12
                        iconName: "x"
                        tone: clearHov.containsMouse ? "error" : "muted"
                    }
                    MouseArea {
                        id: clearHov; anchors.fill: parent; hoverEnabled: true
                        propagateComposedEvents: false
                        onClicked: (m) => { m.accepted = true; NotificationService.clearApp(card.appData.appName) }
                    }
                }

                // Expand the full message, and all messages in a grouped card.
                Rectangle {
                    objectName: "notificationGroupExpand"
                    visible: card.canExpand
                    width: 26; height: 26; radius: 6
                    color: expandHov.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                    SvgIcon {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        iconName: card.expanded ? "chevron-up" : "chevron-down"
                        tone: "muted"
                    }
                    MouseArea {
                        id: expandHov; anchors.fill: parent; hoverEnabled: true
                        propagateComposedEvents: false
                        onClicked: (m) => { m.accepted = true; card.expanded = !card.expanded }
                    }
                }
            }

            // Notification rows
            Repeater {
                model: card.expanded ? card.appData.items : [card.appData.items[0]]
                delegate: NotificationRow {
                    Layout.fillWidth: true
                    entry: modelData
                    groupExpanded: card.expanded
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // NotificationRow — single notification entry
    // ══════════════════════════════════════════════════════════════════════
    component NotificationRow: Rectangle {
        id: row
        objectName: "notificationRow"
        property var entry
        property bool bodyExpanded: false
        property bool groupExpanded: false
        readonly property bool fullContentExpanded: bodyExpanded || groupExpanded

        readonly property color urgencyAccent:
            entry.urgency === NotificationUrgency.Critical ? Theme.error
            : entry.urgency === NotificationUrgency.Low    ? Theme.muted
            :                                                Theme.primary

        radius: Theme.smallRadius
        color:  entry.urgency === NotificationUrgency.Critical
            ? Qt.rgba(0.94, 0.44, 0.44, 0.08) : Theme.surface
        border.width: entry.urgency === NotificationUrgency.Critical ? 1 : 0
        border.color: Theme.error
        implicitHeight: rowCol.implicitHeight + 20
        clip: true

        // Swipe-to-dismiss
        property real dragX: 0
        x: dragX
        Behavior on x {
            enabled: !dragMA.drag.active
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        // Red reveal strip on left
        Rectangle {
            anchors.right: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: parent.height; radius: Theme.smallRadius
            color: Theme.error
            opacity: Math.min(1, Math.abs(row.x) / 50)
            visible: row.x !== 0
            SvgIcon {
                anchors.centerIn: parent
                width: 14; height: 14
                iconName: "x"; tone: "fg"
            }
        }

        MouseArea {
            id: dragMA; anchors.fill: parent
            drag.target: row; drag.axis: Drag.XAxis
            drag.minimumX: -row.width; drag.maximumX: row.width
            onReleased: {
                if (Math.abs(row.x) > row.width * 0.35)
                    NotificationService.removeNotification(row.entry.notifId)
                else
                    row.dragX = 0
            }
            onPositionChanged: row.dragX = row.x
        }

        ColumnLayout {
            id: rowCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 10
            spacing: 4

            // Top meta row: urgency dot · timestamp · dismiss
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: row.urgencyAccent
                    Layout.alignment: Qt.AlignVCenter
                }
                // spacer so timestamp+dismiss sit at the right
                Item { Layout.fillWidth: true }
                Text {
                    text: NotificationService.timeAgo(row.entry.timestamp)
                    color: Theme.muted
                    font.family: Theme.uiFont; font.pixelSize: 10
                }
                // Dismiss ×
                Rectangle {
                    width: 20; height: 20; radius: 5
                    color: dismissHov.containsMouse
                        ? Qt.rgba(0.94, 0.44, 0.44, 0.20) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    SvgIcon {
                        anchors.centerIn: parent; width: 11; height: 11
                        iconName: "x"
                        tone: dismissHov.containsMouse ? "error" : "muted"
                    }
                    MouseArea {
                        id: dismissHov; anchors.fill: parent; hoverEnabled: true
                        propagateComposedEvents: false
                        onClicked: (m) => {
                            m.accepted = true
                            NotificationService.removeNotification(row.entry.notifId)
                        }
                    }
                }
            }

            // Summary preview is concise until the notification is expanded.
            Text {
                visible: row.entry.summary !== ""
                text: row.entry.summary
                color: Theme.text
                font.family: Theme.uiFont; font.pixelSize: 12; font.weight: 600
                wrapMode: Text.Wrap
                maximumLineCount: row.fullContentExpanded ? -1 : 2
                elide: row.fullContentExpanded ? Text.ElideNone : Text.ElideRight
                Layout.fillWidth: true
            }

            // Message bodies are revealed explicitly, or by expanding their app group.
            Text {
                objectName: "notificationMessageBody"
                visible: row.entry.body !== "" && row.fullContentExpanded
                text: row.entry.body
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: 11
                textFormat: Text.AutoText
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            StyledButton {
                objectName: "notificationBodyExpand"
                visible: row.entry.body !== "" && !row.groupExpanded
                compact: true
                text: row.bodyExpanded ? "Show less" : "Show message"
                Layout.alignment: Qt.AlignLeft
                onClicked: row.bodyExpanded = !row.bodyExpanded
            }

            // Action buttons
            Flow {
                visible: JSON.parse(row.entry.actionsJson).length > 0
                Layout.fillWidth: true; spacing: 5

                Repeater {
                    model: JSON.parse(row.entry.actionsJson)
                    delegate: StyledButton {
                        required property var modelData
                        compact: true; text: modelData.text
                        onClicked: NotificationService.invokeAction(row.entry.notifId, modelData.id)
                    }
                }
            }
        }
    }
}
