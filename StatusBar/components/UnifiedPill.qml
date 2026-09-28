import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../core"
import "../panels"
import "../services"

Rectangle {
    id: root

    property var workspaces: []
    property var workspaceData: []
    property string activeAddress: ""
    property int activeWorkspaceId: 1
    property int pendingUpdates: 0
    property string updateTooltip: "Checking for package updates…"

    signal openControlCenter(string tab)
    signal workspaceClicked(int workspaceId)
    signal hamburgerClicked()
    signal timeClicked()
    signal powerClicked()
    signal updatesClicked()
    signal clientCloseRequested(string address)

    readonly property var battery: UPower.displayDevice
    readonly property int batteryPercent: battery
        ? Math.max(0, Math.min(100, Math.round((Number(battery.percentage) || 0) * 100))) : -1
    readonly property bool batteryCharging: battery && battery.state === UPowerDeviceState.Charging
    readonly property bool notificationPreviewVisible:
        NotificationService.toastList.length > 0 && !ShellState.popupOpen
    readonly property var previewNotification: notificationPreviewVisible
        ? NotificationService.toastList[0] : null
    readonly property bool mediaPreviewVisible: MediaService.hasTrack
        && !notificationPreviewVisible
    property bool mediaExpanded: false
    property bool mediaAutoPopup: false
    property string lastMediaTitle: ""
    property real mediaBreath: 0
    readonly property bool mediaPopupVisible: mediaPreviewVisible
        && (mediaExpanded || mediaAutoPopup)
    readonly property bool controlPopupVisible: ShellState.popupOpen
    property bool windowListOpen: false

    function formatMediaTime(value): string {
        const seconds = Math.max(0, Math.floor((Number(value) || 0) / 1000000))
        return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + (seconds % 60)
    }

    function restartMediaInactivity(): void {
        if (mediaPopupVisible) mediaInactivity.restart()
    }

    // The pill owns both states: compact at rest, then a single continuous
    // media/notification surface when contextual content takes over.
    implicitWidth: controlPopupVisible ? 520
        : windowListOpen ? 440
        : notificationPreviewVisible || mediaPopupVisible ? 420
        : pillRow.implicitWidth + 28
    implicitHeight: controlPopupVisible ? 704
        : windowListOpen ? 420
        : notificationPreviewVisible ? (previewBody.visible ? 68 : 52)
        : mediaPopupVisible ? 112 : 40
    radius: controlPopupVisible || windowListOpen || notificationPreviewVisible || mediaPopupVisible ? 28 : height / 2
    scale: 1 + (mediaPreviewVisible && MediaService.playing ? mediaBreath * 0.006 : 0)
    color: controlPopupVisible || windowListOpen ? "#151517" : mouse.containsMouse ? "#1b1b1d" : "#111113"
    border.width: 1
    border.color: mouse.containsMouse ? Qt.rgba(1, 0.62, 0.04, 0.42)
                                      : Qt.rgba(1, 1, 1, 0.13)
    layer.enabled: true

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutExpo } }
    Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutExpo } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutSine } }

    SequentialAnimation on mediaBreath {
        running: root.mediaPreviewVisible && MediaService.playing
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutSine }
    }

    onMediaPreviewVisibleChanged: {
        if (!mediaPreviewVisible) {
            mediaExpanded = false
            mediaAutoPopup = false
            mediaInactivity.stop()
        }
    }

    Connections {
        target: MediaService
        function onTitleChanged() {
            if (!MediaService.hasTrack || MediaService.title === root.lastMediaTitle) return
            root.lastMediaTitle = MediaService.title
            root.mediaAutoPopup = true
            mediaAutoHide.restart()
            mediaInactivity.restart()
        }
    }

    Timer {
        id: mediaAutoHide
        interval: 5000
        repeat: false
        onTriggered: if (!root.mediaExpanded) root.mediaAutoPopup = false
    }

    Timer {
        id: mediaInactivity
        interval: 5000
        repeat: false
        onTriggered: {
            root.mediaExpanded = false
            root.mediaAutoPopup = false
        }
    }

    Timer {
        id: notificationHide
        interval: 2000
        running: false
        repeat: false
        onTriggered: {
            if (root.previewNotification)
                NotificationService.removeToast(root.previewNotification.notifId)
        }
    }

    onNotificationPreviewVisibleChanged: {
        if (notificationPreviewVisible) notificationHide.restart()
        else notificationHide.stop()
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.windowListOpen) root.windowListOpen = false
            else if (root.notificationPreviewVisible) root.openControlCenter("notifications")
            else if (root.mediaPreviewVisible) {
                root.mediaExpanded = true
                root.mediaAutoPopup = false
                mediaAutoHide.stop()
                mediaInactivity.restart()
            }
            else root.openControlCenter("wifi")
        }
    }

    Rectangle {
        id: mediaPanel
        visible: root.mediaPopupVisible
        anchors.fill: parent
        radius: parent.radius
        color: "#18181b"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 35
                    Layout.preferredHeight: 35
                    radius: 10
                    color: Qt.rgba(1, 0.62, 0.04, 0.18)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: MediaService.artUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        smooth: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: MediaService.artUrl === ""
                        text: "♫"
                        color: Theme.primaryStrong
                        font.family: Theme.iconFont
                        font.pixelSize: 16
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: MediaService.title || "Nothing playing"
                        color: Theme.text
                        font.family: Theme.uiFont
                        font.pixelSize: 11
                        font.weight: 700
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: MediaService.artist || MediaService.playerName
                        color: Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: mediaPlayMouse.containsMouse ? Theme.islandAccent : Theme.surfaceRaised
                    Text {
                        anchors.centerIn: parent
                        text: MediaService.playing ? "󰏤" : "󰐊"
                        color: mediaPlayMouse.containsMouse ? Theme.background : Theme.text
                        font.family: Theme.iconFont
                        font.pixelSize: 14
                    }
                    MouseArea {
                        id: mediaPlayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: (event) => {
                            event.accepted = true
                            MediaService.toggle()
                            root.restartMediaInactivity()
                        }
                    }
                }
                Text {
                    text: "×"
                    color: mediaCloseMouse.containsMouse ? Theme.text : Theme.muted
                    font.pixelSize: 17
                    MouseArea {
                        id: mediaCloseMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: (event) => {
                            event.accepted = true
                            root.mediaExpanded = false
                            root.mediaAutoPopup = false
                            mediaAutoHide.stop()
                            mediaInactivity.stop()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: root.formatMediaTime(MediaService.displayPosition)
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 8
                }
                Rectangle {
                    id: mediaProgressTrack
                    Layout.fillWidth: true
                    height: 4
                    radius: 2
                    color: Theme.surfaceRaised
                    Rectangle {
                        width: parent.width * MediaService.progress
                        height: parent.height
                        radius: 2
                        color: Theme.islandAccent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (event) => {
                            event.accepted = true
                            MediaService.seekToRatio(event.x / width)
                            root.restartMediaInactivity()
                        }
                    }
                }
                Text {
                    text: root.formatMediaTime(MediaService.length)
                    color: Theme.muted
                    font.family: Theme.uiFont
                    font.pixelSize: 8
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 28
                Text {
                    text: "󰒮"
                    color: mediaPrevMouse.containsMouse ? Theme.text : Theme.muted
                    font.family: Theme.iconFont
                    font.pixelSize: 15
                    MouseArea {
                        id: mediaPrevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: (event) => {
                            event.accepted = true
                            MediaService.previous()
                            root.restartMediaInactivity()
                        }
                    }
                }
                Text {
                    text: MediaService.playing ? "󰏤" : "󰐊"
                    color: Theme.text
                    font.family: Theme.iconFont
                    font.pixelSize: 17
                    MouseArea {
                        anchors.fill: parent
                        onClicked: (event) => {
                            event.accepted = true
                            MediaService.toggle()
                            root.restartMediaInactivity()
                        }
                    }
                }
                Text {
                    text: "󰒭"
                    color: mediaNextMouse.containsMouse ? Theme.text : Theme.muted
                    font.family: Theme.iconFont
                    font.pixelSize: 15
                    MouseArea {
                        id: mediaNextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: (event) => {
                            event.accepted = true
                            MediaService.next()
                            root.restartMediaInactivity()
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        id: notificationPreviewRow
        visible: root.notificationPreviewVisible
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 9

        Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 10
            color: Qt.rgba(1, 0.62, 0.04, 0.14)
            Text {
                anchors.centerIn: parent
                text: "󰂚"
                color: Theme.islandAccent
                font.family: Theme.iconFont
                font.pixelSize: 15
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: root.previewNotification ? root.previewNotification.appName : "Notification"
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 9
                font.weight: 600
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.previewNotification ? root.previewNotification.summary : ""
                color: Theme.text
                font.family: Theme.uiFont
                font.pixelSize: 12
                font.weight: 600
                elide: Text.ElideRight
            }
            Text {
                id: previewBody
                Layout.fillWidth: true
                visible: !!(root.previewNotification && root.previewNotification.body)
                text: root.previewNotification ? root.previewNotification.body : ""
                color: Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
        Text {
            text: root.previewNotification
                ? NotificationService.timeAgo(root.previewNotification.timestamp) : ""
            color: Theme.muted
            font.family: Theme.uiFont
            font.pixelSize: 9
        }
        Text {
            text: "›"
            color: Theme.muted
            font.pixelSize: 18
        }
    }

    RowLayout {
        id: pillRow
        visible: !root.notificationPreviewVisible && !root.mediaPopupVisible
            && !root.controlPopupVisible && !root.windowListOpen
        anchors.centerIn: parent
        spacing: 7

        Row {
            spacing: 3
            Layout.alignment: Qt.AlignVCenter
            Repeater {
                model: root.workspaces
                delegate: Rectangle {
                    required property var modelData
                    width: 22
                    height: 22
                    radius: 8
                    color: modelData.id === root.activeWorkspaceId
                        ? Theme.islandAccent : Qt.rgba(1, 1, 1, 0.075)
                    border.width: modelData.id === root.activeWorkspaceId ? 0 : 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: modelData.id
                        color: modelData.id === root.activeWorkspaceId
                            ? Theme.background : Theme.muted
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: 700
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: (event) => {
                            event.accepted = true
                            root.workspaceClicked(modelData.id)
                        }
                    }
                }
            }
        }

        Rectangle { width: 1; height: 18; color: Qt.rgba(1, 1, 1, 0.12) }

        Rectangle {
            implicitWidth: 24
            implicitHeight: 24
            radius: 8
            color: hamburgerMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14)
                                                 : Qt.rgba(1, 1, 1, 0.075)
            Text {
                anchors.centerIn: parent
                text: "☰"
                color: hamburgerMouse.containsMouse ? Theme.text : Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 14
            }
            MouseArea {
                id: hamburgerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (event) => {
                    event.accepted = true
                    root.windowListOpen = true
                }
            }
        }

        Rectangle { width: 1; height: 18; color: Qt.rgba(1, 1, 1, 0.12) }

        Rectangle {
            implicitWidth: batteryText.implicitWidth + 18
            implicitHeight: 24
            radius: 8
            color: batteryMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14)
                                               : Qt.rgba(1, 1, 1, 0.075)
            Row {
                id: batteryRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.batteryPercent < 0 ? "󰂑"
                        : root.batteryCharging ? "󰂄" : "󰁹"
                    color: root.batteryPercent >= 0 && root.batteryPercent <= 15
                        ? Theme.error : root.batteryCharging ? Theme.success : Theme.muted
                    font.family: Theme.iconFont
                    font.pixelSize: 12
                }
                Text {
                    id: batteryText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.batteryPercent < 0 ? "n/a" : root.batteryPercent + "%"
                    color: Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    font.weight: 600
                }
            }
            MouseArea {
                id: batteryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (event) => {
                    event.accepted = true
                    root.openControlCenter("system")
                }
            }
        }

        Rectangle {
            implicitWidth: timeText.implicitWidth + 16
            implicitHeight: 24
            radius: 8
            color: timeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14)
                                            : Qt.rgba(1, 1, 1, 0.075)
            Text {
                id: timeText
                anchors.centerIn: parent
                text: ShellState.time
                color: timeMouse.containsMouse ? Theme.text : Theme.muted
                font.family: Theme.uiFont
                font.pixelSize: 10
                font.weight: 600
            }
            MouseArea {
                id: timeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (event) => {
                    event.accepted = true
                    root.timeClicked()
                }
            }
        }

        Rectangle {
            visible: root.mediaPreviewVisible && !root.mediaExpanded
            implicitWidth: 124
            implicitHeight: 24
            radius: 8
            color: mediaCompactMouse.containsMouse ? Qt.rgba(1, 0.62, 0.04, 0.18)
                                                    : Qt.rgba(1, 0.62, 0.04, 0.10)
            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 5
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "♫"
                    color: Theme.islandAccent
                    font.family: Theme.iconFont
                    font.pixelSize: 12
                    SequentialAnimation on opacity {
                        running: MediaService.playing
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 360 }
                        NumberAnimation { to: 1; duration: 360 }
                    }
                }
                Text {
                    id: mediaCompactText
                    width: 96
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaService.title || "Media"
                    color: Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 9
                    font.weight: 600
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                id: mediaCompactMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (event) => {
                    event.accepted = true
                    root.mediaExpanded = true
                }
            }
        }

        Rectangle { width: 1; height: 18; color: Qt.rgba(1, 1, 1, 0.12) }

        PillAction {
            icon: NetworkService.wifiEnabled ? "󰖩" : "󰖪"
            active: NetworkService.wifiEnabled
            tooltipText: NetworkService.connected ? NetworkService.ssid : NetworkService.status
            onClicked: root.openControlCenter("wifi")
        }
        PillAction {
            icon: BluetoothService.enabled ? "󰂯" : "󰂲"
            active: BluetoothService.enabled
            tooltipText: BluetoothService.status
            onClicked: root.openControlCenter("bluetooth")
        }
        PillAction {
            icon: AudioService.muted ? "󰝟" : "󰕾"
            active: AudioService.muted
            danger: AudioService.muted
            tooltipText: AudioService.muted ? "Sound muted" : "Sound"
            onClicked: root.openControlCenter("sound")
        }
        PillAction {
            icon: NotificationService.dndEnabled ? "󰂛" : "󰂚"
            active: NotificationService.count > 0 || NotificationService.dndEnabled
            danger: NotificationService.dndEnabled
            badge: NotificationService.count > 0 ? String(NotificationService.count) : ""
            tooltipText: NotificationService.dndEnabled
                ? "Do not disturb" : NotificationService.count + " notifications"
            onClicked: root.openControlCenter("notifications")
        }
        PillAction {
            icon: "󰐥"
            tooltipText: "Power menu"
            onClicked: root.powerClicked()
        }
        PillAction {
            icon: "󰮯"
            active: root.pendingUpdates > 0
            badge: root.pendingUpdates > 0
                ? (root.pendingUpdates > 99 ? "99+" : String(root.pendingUpdates)) : ""
            tooltipText: root.updateTooltip
            onClicked: root.updatesClicked()
        }
    }

    Rectangle {
        id: inlineWindowList
        visible: root.windowListOpen
        anchors.fill: parent
        radius: parent.radius
        color: "#151517"
        border.width: 1
        border.color: Theme.outline
        z: 3

        ScrollView {
            anchors.fill: parent
            anchors.margins: 14
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                width: parent.width
                spacing: 8
                Repeater {
                    model: root.workspaceData
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 3
                        Rectangle {
                            visible: index > 0
                            Layout.fillWidth: true
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.10)
                            Layout.topMargin: index > 0 ? 5 : 0
                            Layout.bottomMargin: 3
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 26
                            radius: 8
                            color: modelData.id === root.activeWorkspaceId
                                ? Qt.rgba(1, 0.62, 0.04, 0.14) : Qt.rgba(1, 1, 1, 0.045)
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.id > 0 ? "Workspace " + modelData.id : "Scratchpad")
                                    + (modelData.id === root.activeWorkspaceId ? "  •  active" : "")
                                color: modelData.id === root.activeWorkspaceId
                                    ? Theme.islandAccent : Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: 700
                            }
                        }
                        Repeater {
                            model: modelData.clients
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 8
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        source: modelData.iconPath
                                        sourceSize: Qt.size(48, 48)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !modelData.iconPath
                                        text: "▣"
                                        color: Theme.muted
                                        font.family: Theme.iconFont
                                        font.pixelSize: 13
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: modelData.appClass
                                        color: modelData.address === root.activeAddress
                                            ? Theme.islandAccent : Theme.text
                                        font.family: Theme.uiFont
                                        font.pixelSize: 9
                                        font.weight: 600
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.title
                                        color: Theme.muted
                                        font.family: Theme.uiFont
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                                Rectangle {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    radius: 8
                                    color: closeClientMouse.containsMouse
                                        ? Qt.rgba(1, 0.25, 0.35, 0.28) : Qt.rgba(1, 0.25, 0.35, 0.12)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        color: Theme.error
                                        font.pixelSize: 17
                                        font.weight: 700
                                    }
                                    MouseArea {
                                        id: closeClientMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.clientCloseRequested(modelData.address)
                                    }
                                }
                            }
                        }
                        Text {
                            visible: modelData.clients.length === 0
                            text: "(empty)"
                            color: Theme.mutedDim
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                            font.italic: true
                            Layout.leftMargin: 8
                        }
                    }
                }
            }
        }
    }

    ControlPanel {
        id: inlineControlPanel
        // Stay visible while the fade-out runs, otherwise the exit animation never shows.
        visible: root.controlPopupVisible || inlineControlPanel.opacity > 0
        anchors.fill: parent
        focus: root.controlPopupVisible
        z: 3
        Keys.onEscapePressed: ShellState.popupOpen = false
    }

    component PillAction: Item {
        id: action
        property string icon: ""
        property string tooltipText: ""
        property string badge: ""
        property bool active: false
        property bool danger: false
        signal clicked()
        implicitWidth: 24
        implicitHeight: 24

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: actionMouse.containsMouse
                ? (action.danger ? Qt.rgba(1, 0.42, 0.37, 0.24)
                                : Qt.rgba(1, 0.62, 0.04, 0.22))
                : action.active ? Qt.rgba(1, 0.62, 0.04, 0.13)
                                 : Qt.rgba(1, 1, 1, 0.075)
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: action.icon
                color: action.danger ? Theme.error
                    : action.active ? Theme.islandAccent : Theme.muted
                font.family: Theme.iconFont
                font.pixelSize: 13
            }
        }
        Rectangle {
            visible: action.badge !== ""
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -5
            anchors.topMargin: -5
            width: Math.max(10, badgeText.implicitWidth + 5)
            height: 11
            radius: 6
            color: Theme.error
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: action.badge
                color: Theme.background
                font.family: Theme.uiFont
                font.pixelSize: 6
                font.weight: 700
            }
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: (event) => {
                event.accepted = true
                action.clicked()
            }
        }
    }
}
