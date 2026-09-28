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

    // Expand/collapse state per app. Group objects are rebuilt on every
    // notification event (which recreates the delegates), so the state
    // must live here, keyed by app name, to survive rebuilds.
    property var expandedApps: ({})
    function setAppExpanded(appName, value) {
        const copy = Object.assign({}, expandedApps)
        copy[appName] = value
        expandedApps = copy
    }

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

            Text {
                text: "!"
                color: NotificationService.dndEnabled ? Theme.warning : Theme.islandAccent
                font.family: Theme.iconFont
                font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: 180 } }
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

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "✓"
            color: Theme.muted
            font.family: Theme.iconFont; font.pixelSize: 28
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
                    expandedOverride: root.expandedApps.hasOwnProperty(modelData.appName)
                        ? root.expandedApps[modelData.appName] : undefined
                    onExpandRequested: (value) => root.setAppExpanded(modelData.appName, value)
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // AppGroupCard — groups notifications from one app sender
    // ══════════════════════════════════════════════════════════════════════
    component AppGroupCard: Rectangle {
        id: card
        property var  appData
        property var expandedOverride: undefined
        signal expandRequested(bool value)
        readonly property bool expanded: expandedOverride !== undefined
            ? expandedOverride : appData.items.length === 1

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
                Text {
                    text: "•"
                    visible: (card.appData.appIcon || "") === ""
                    color: Theme.muted
                    font.family: Theme.iconFont; font.pixelSize: 14
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
                    Text {
                        anchors.centerIn: parent
                        text: card.appData.muted ? "×" : "♪"
                        color: card.appData.muted ? Theme.warning : Theme.muted
                        font.family: Theme.iconFont; font.pixelSize: 12
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
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: clearHov.containsMouse ? Theme.error : Theme.muted
                        font.family: Theme.iconFont; font.pixelSize: 12
                    }
                    MouseArea {
                        id: clearHov; anchors.fill: parent; hoverEnabled: true
                        propagateComposedEvents: false
                        onClicked: (m) => { m.accepted = true; NotificationService.clearApp(card.appData.appName) }
                    }
                }

                // Expand/collapse (only when > 1)
                Rectangle {
                    visible: card.appData.items.length > 1
                    width: 26; height: 26; radius: 6
                    color: expandHov.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                    Text {
                        anchors.centerIn: parent
                        text: card.expanded ? "⌃" : "⌄"
                        color: Theme.muted
                        font.family: Theme.iconFont; font.pixelSize: 12
                    }
                    MouseArea {
                        id: expandHov; anchors.fill: parent; hoverEnabled: true
                        propagateComposedEvents: false
                        onClicked: (m) => { m.accepted = true; card.expandRequested(!card.expanded) }
                    }
                }
            }

            // Notification rows
            Repeater {
                model: card.expanded ? card.appData.items : [card.appData.items[0]]
                delegate: NotificationRow {
                    Layout.fillWidth: true
                    entry: modelData
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // NotificationRow — single notification entry
    // ══════════════════════════════════════════════════════════════════════
    component NotificationRow: Rectangle {
        id: row
        property var entry

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
            Text {
                anchors.centerIn: parent
                text: "×"; color: "#fff"
                font.family: Theme.iconFont; font.pixelSize: 14
            }
        }

        MouseArea {
            id: dragMA; anchors.fill: parent
            drag.target: row; drag.axis: Drag.XAxis
            drag.minimumX: -row.width; drag.maximumX: row.width
            onReleased: {
                if (Math.abs(row.x) > row.width * 0.35)
                    NotificationService.removeNotification(row.entry.notifId)
                else {
                    // drag.target writes x directly and detaches the x: dragX
                    // binding, so reset x itself (Behavior animates the snap-back).
                    row.dragX = 0
                    row.x = 0
                }
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
                    Text {
                        anchors.centerIn: parent; text: "✕"
                        font.pixelSize: 9; font.weight: 700
                        color: dismissHov.containsMouse ? Theme.error : Theme.muted
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

            // Summary — full width, wraps up to 2 lines
            Text {
                visible: row.entry.summary !== ""
                text: row.entry.summary
                color: Theme.text
                font.family: Theme.uiFont; font.pixelSize: 12; font.weight: 600
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Body — first 2 lines visible, click anywhere to expand
            // Body — always fully visible in panel
            Text {
                visible: row.entry.body !== ""
                text: row.entry.body
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: 11
                wrapMode: Text.Wrap; Layout.fillWidth: true
                // No line limit – always show full body
                maximumLineCount: 999
                elide: Text.ElideRight
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
