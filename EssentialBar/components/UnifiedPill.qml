// UnifiedPill.qml
// Collapsed: 38px × auto-width pill — .prow button order matches HTML prototype:
//   Menu | WorkspaceDots | Sep | NowPlaying(EQ+track) | Clock | Sep |
//   QuickSettings | Battery% | WiFi | Bluetooth | Volume | Bell(+badge) |
//   Coffee(keepAwake) | Updates(+badge) | Power
//
// Expanded states (mutually exclusive, highest priority first):
//   1. ControlPanel   (popupOpen)  — full 380×480 panel
//   2. WindowList     (windowListOpen)
//   3. Notification preview
//   4. Media popover
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.UPower
import "../core"
import "../panels"
import "../services"

Rectangle {
    id: root

    // ── External state injected by shell.qml ────────────────────────────
    property var    workspaces:        []
    property var    workspaceData:     []
    property string activeAddress:     ""
    property int    activeWorkspaceId: 1
    property int    pendingUpdates:    0
    property string updateTooltip:     "Checking for package updates…"

    // ── Signals ──────────────────────────────────────────────────────────
    signal openControlCenter(string tab)
    signal workspaceClicked(int workspaceId)
    signal hamburgerClicked()
    signal timeClicked()
    signal powerClicked()
    signal updatesClicked()
    signal clientCloseRequested(string address)

    // ── Battery (UPower) ─────────────────────────────────────────────────
    readonly property var   battery:         UPower.displayDevice
    readonly property int   batteryPercent:  battery
        ? Math.max(0, Math.min(100, Math.round((Number(battery.percentage) || 0) * 100))) : -1
    readonly property bool  batteryCharging: battery && battery.state === 1

    // ── Notification / media preview ─────────────────────────────────────
    readonly property bool notificationPreviewVisible:
        NotificationService.toastList.length > 0 && !ShellState.popupOpen
    readonly property var  previewNotification: notificationPreviewVisible
        ? NotificationService.toastList[0] : null
    readonly property int  notificationPreviewHeight:
        Math.min(176, Math.max(52, notificationPreviewColumn.implicitHeight + 16))
    readonly property bool mediaPreviewVisible:
        MediaService.hasTrack && !notificationPreviewVisible
    property bool mediaExpanded:    false
    property bool mediaAutoPopup:   false
    property string lastMediaTitle: ""
    property real   mediaBreath:    0
    readonly property bool mediaPopupVisible:   mediaPreviewVisible && (mediaExpanded || mediaAutoPopup)
    readonly property bool controlPopupVisible: ShellState.popupOpen
    property bool windowListOpen: false
    // App targeted by the keyboard close shortcut. Hovering an app selects it;
    // when nothing has been hovered, the currently active client is used.
    property string keyboardKillAddress: ""

    // ── Sizing ────────────────────────────────────────────────────────────
    // Collapsed: pill wraps its content row. Expanded: 380×480.
    implicitWidth: controlPopupVisible     ? 380
        : windowListOpen                   ? 380
        : notificationPreviewVisible || mediaPopupVisible ? 380
        : pillRow.implicitWidth + 28   // 14px padding each side
    implicitHeight: controlPopupVisible    ? 480
        : windowListOpen                   ? 420
        : notificationPreviewVisible       ? notificationPreviewHeight
        : mediaPopupVisible                ? 112
        : 38                               // collapsed height per spec

    // ── Appearance ────────────────────────────────────────────────────────
    color:        controlPopupVisible || windowListOpen
                      ? Theme.surface
                      : pillMouse.containsMouse ? Theme.surfaceRaised : Theme.surface
    radius:       Theme.radiusSize(19)   // border-radius: 19px  (.pill spec)
    border.width: Theme.dimensionSize(1)
    border.color: pillMouse.containsMouse
                      ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.42)) : Theme.line
    layer.enabled: true
    clip: true

    Behavior on color        { ColorAnimation  { duration: Theme.duration(140) } }
    Behavior on border.color { ColorAnimation  { duration: Theme.duration(140) } }
    // Keep popup geometry immediate; animated size changes make expandable
    // Wi-Fi details appear to open in two separate steps.
    // Do not tween the shell height while expandable Wi-Fi rows are being
    // measured; that produces a visible lag and clips the details card.

    // ── Media breath pulse ────────────────────────────────────────────────
    SequentialAnimation on mediaBreath {
        running: root.mediaPreviewVisible && MediaService.playing
        loops:   Animation.Infinite
        NumberAnimation { to: 1; duration: Theme.duration(520); easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: Theme.duration(520); easing.type: Easing.InOutSine }
    }
    scale: 1 + (mediaPreviewVisible && MediaService.playing ? mediaBreath * 0.006 : 0)
    Behavior on scale { NumberAnimation { duration: Theme.duration(120); easing.type: Easing.OutSine } }

    onMediaPreviewVisibleChanged: {
        if (!mediaPreviewVisible) {
            mediaExpanded   = false
            mediaAutoPopup  = false
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

    Timer { id: mediaAutoHide;   interval: 5000; repeat: false
        onTriggered: if (!root.mediaExpanded) root.mediaAutoPopup = false }
    Timer { id: mediaInactivity; interval: 5000; repeat: false
        onTriggered: { root.mediaExpanded = false; root.mediaAutoPopup = false } }
    Timer { id: notificationHide; interval: 6000; running: false; repeat: false
        onTriggered: {
            if (root.previewNotification)
                NotificationService.removeToast(root.previewNotification.notifId)
        }
    }

    onNotificationPreviewVisibleChanged: {
        if (notificationPreviewVisible) notificationHide.restart()
        else                            notificationHide.stop()
    }
    onPreviewNotificationChanged: {
        if (notificationPreviewVisible) notificationHide.restart()
    }

    // ── Global click (pill root) ──────────────────────────────────────────
    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked: {
            if (root.windowListOpen)             root.windowListOpen = false
            else if (root.notificationPreviewVisible) root.openControlCenter("notifications")
            else if (root.mediaPreviewVisible) {
                root.mediaExpanded  = true
                root.mediaAutoPopup = false
                mediaAutoHide.stop()
                mediaInactivity.restart()
            }
            else root.openControlCenter("main")
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 1. COLLAPSED STATUS ROW  (.prow)
    //    Visible only when no expanded surface is active.
    // ════════════════════════════════════════════════════════════════════
    RowLayout {
        id: pillRow
        visible:  !root.notificationPreviewVisible && !root.mediaPopupVisible
                  && !root.controlPopupVisible     && !root.windowListOpen
        anchors.centerIn: parent
        spacing: Theme.spacingSize(2)

        // ── Helper: flat icon button (Rectangle + CSS-colored SVG + MouseArea) ──
        // Each button below uses this exact same pattern inline.
        // Width = 28, Height = 28, radius 99, 16×16 SVG centred.

        // ── Hamburger ────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: Theme.dimensionSize(28); implicitHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(99)
            color: menuHov.containsMouse ? Theme.surfaceRaised : "transparent"
            Layout.alignment: Qt.AlignVCenter
            SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); assetName: "menu-muted" }
            MouseArea { id: menuHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.hamburgerClicked() } }
        }

        // ── Workspace dots ───────────────────────────────────────────────
        Row {
            spacing: Theme.spacingSize(5); Layout.leftMargin: Theme.marginSize(4); Layout.rightMargin: Theme.marginSize(4); Layout.alignment: Qt.AlignVCenter
            Repeater {
                model: root.workspaces.length > 0 ? root.workspaces : [{ id: root.activeWorkspaceId }]
                delegate: Rectangle {
                    readonly property int wsId: Number(modelData?.id || (index + 1))
                    width: wsId === root.activeWorkspaceId ? 16 : 8; height: Theme.dimensionSize(8); radius: Theme.radiusSize(99)
                    color: wsId === root.activeWorkspaceId ? Theme.workspaceActive : Theme.workspaceInactive
                    Behavior on width { NumberAnimation { duration: Theme.duration(200); easing.type: Easing.InOutQuad } }
                    MouseArea { anchors.fill: parent; onClicked: (e) => { e.accepted = true; root.workspaceClicked(wsId) } }
                }
            }
        }

        // ── Separator ────────────────────────────────────────────────────
        Rectangle { width: Theme.dimensionSize(1); height: Theme.dimensionSize(14); color: Theme.line; opacity: Theme.opacityValue(0.5); Layout.alignment: Qt.AlignVCenter }

        // ── Now-playing (EQ + track name) ────────────────────────────────
        Item {
            visible: MediaService.hasTrack
            Layout.preferredWidth: visible ? nowRow.implicitWidth + 16 : 0
            Layout.preferredHeight: Theme.dimensionSize(30); Layout.alignment: Qt.AlignVCenter
            Row {
                id: nowRow; anchors.centerIn: parent; spacing: Theme.spacingSize(4)
                Row {
                    spacing: Theme.spacingSize(2); anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: Theme.dimensionSize(2); height: Theme.dimensionSize(12); radius: Theme.radiusSize(2); color: Theme.acc; anchors.bottom: parent.bottom
                            SequentialAnimation on height {
                                loops: Animation.Infinite; running: MediaService.playing
                                PauseAnimation { duration: [Theme.duration(0), Theme.duration(400), Theme.duration(750)][index] }
                                NumberAnimation { to: 12; duration: Theme.duration(500); easing.type: Easing.InOutSine }
                                NumberAnimation { to: 3;  duration: Theme.duration(500); easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
                Item {
                    id: pillTitleViewport
                    width: Theme.dimensionSize(120); height: Theme.dimensionSize(18); clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: pillTitleText
                        y: 1
                        text: MediaService.title
                        color: Theme.fg
                        font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11)
                        width: Math.max(implicitWidth, pillTitleViewport.width)
                        elide: Text.ElideNone
                    }
                    SequentialAnimation {
                        running: MediaService.hasTrack && MediaService.playing && pillTitleText.implicitWidth > pillTitleViewport.width
                        loops: Animation.Infinite
                        PauseAnimation { duration: Theme.duration(800) }
                        NumberAnimation { target: pillTitleText; property: "x"; from: 0; to: -(pillTitleText.implicitWidth - pillTitleViewport.width); duration: Math.max(Theme.duration(1800), pillTitleText.implicitWidth * Theme.scrollTitleRate); easing.type: Easing.Linear }
                        PauseAnimation { duration: Theme.duration(800) }
                        NumberAnimation { target: pillTitleText; property: "x"; to: 0; duration: Theme.duration(450); easing.type: Easing.InOutSine }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: (e) => { e.accepted = true; root.mediaExpanded = true; root.mediaAutoPopup = false; mediaAutoHide.stop(); mediaInactivity.restart() }
            }
        }

        // ── Clock ────────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: clockText.implicitWidth + 16; implicitHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(99)
            color: clockHov.containsMouse ? Theme.surfaceRaised : "transparent"
            Layout.alignment: Qt.AlignVCenter
            Text { id: clockText; anchors.centerIn: parent; text: ShellState.time; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightSemibold; font.features: ({ "tnum": 1 }) }
            MouseArea { id: clockHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.timeClicked() } }
        }

        // ── Separator ────────────────────────────────────────────────────
        Rectangle { width: Theme.dimensionSize(1); height: Theme.dimensionSize(14); color: Theme.line; opacity: Theme.opacityValue(0.5); Layout.alignment: Qt.AlignVCenter }

        // ── Quick Settings ───────────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize; Layout.alignment: Qt.AlignVCenter
            SvgIcon { anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize; assetName: "status-settings" }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("main") } }
        }

        // ── Battery (icon + %) ───────────────────────────────────────────
        Item {
            implicitWidth: battRow.implicitWidth + 16; implicitHeight: Theme.statusIconButtonSize; Layout.alignment: Qt.AlignVCenter
            Row {
                id: battRow; anchors.centerIn: parent; spacing: Theme.spacingSize(4)
                SvgIcon {
                    width: Theme.statusIconSize; height: Theme.statusIconSize; anchors.verticalCenter: parent.verticalCenter
                    assetName: root.batteryCharging ? "status-battery-charging"
                        : root.batteryPercent < 0 ? "status-battery-unknown"
                        : root.batteryPercent <= 15 ? "status-battery-low"
                        : root.batteryPercent < 40 ? "status-battery-medium" : "status-battery-full"
                }
                Text { text: root.batteryPercent < 0 ? "n/a" : root.batteryPercent + "%"; color: Theme.batteryText; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightSemibold; font.features: ({ "tnum": 1 }); anchors.verticalCenter: parent.verticalCenter }
                LockBadge { active: LockKeysService.numLock; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("batt") } }
        }

        // ── Wi-Fi ────────────────────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
            Layout.alignment: Qt.AlignVCenter
            SvgIcon {
                anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
                assetName: "status-wifi-on"
                slash: !NetworkService.wifiEnabled
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("wifi") } }
        }

        // ── Bluetooth ────────────────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
            Layout.alignment: Qt.AlignVCenter
            SvgIcon {
                anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
                assetName: "status-bluetooth-on"
                slash: !BluetoothService.enabled
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("bt") } }
        }

        // ── Volume ───────────────────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
            Layout.alignment: Qt.AlignVCenter
            SvgIcon {
                anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
                assetName: "status-sound-on"
                slash: AudioService.muted
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("sound") } }
        }

        // ── Bell ─────────────────────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize; Layout.alignment: Qt.AlignVCenter
            SvgIcon {
                anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
                property bool dnd_: NotificationService.dndEnabled
                assetName: "status-bell-on"
                slash: dnd_
            }
            // Badge
            Rectangle {
                visible: NotificationService.count > 0
                anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: Theme.marginSize(-3); anchors.topMargin: Theme.marginSize(-3)
                width: Math.max(13, badgeTxt.implicitWidth + 5); height: Theme.dimensionSize(13); radius: Theme.radiusSize(7); color: Theme.acc
                Text { id: badgeTxt; anchors.centerIn: parent; text: NotificationService.count > 99 ? "99+" : String(NotificationService.count); color: Theme.islandBg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(7); font.weight: Theme.fontWeightBold }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("alerts") } }
        }

        // ── Coffee (keep-awake) ──────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize; Layout.alignment: Qt.AlignVCenter
            SvgIcon {
                anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
                assetName: "status-coffee-on"
                slash: !CaffeineService.enabled
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; CaffeineService.toggle() } }
        }

        // ── Updates ──────────────────────────────────────────────────────
        Item {
            visible: root.pendingUpdates > 0
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize; Layout.alignment: Qt.AlignVCenter
            SvgIcon { anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize; assetName: "status-download" }
            Rectangle {
                anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: Theme.marginSize(-3); anchors.topMargin: Theme.marginSize(-3)
                width: Math.max(13, updBadgeTxt.implicitWidth + 5); height: Theme.dimensionSize(13); radius: Theme.radiusSize(7); color: Theme.acc
                Text { id: updBadgeTxt; anchors.centerIn: parent; text: root.pendingUpdates > 99 ? "99+" : String(root.pendingUpdates); color: Theme.islandBg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(7); font.weight: Theme.fontWeightBold }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.updatesClicked() } }
        }

        // ── Power ────────────────────────────────────────────────────────
        Item {
            implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize; Layout.alignment: Qt.AlignVCenter
            SvgIcon { anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize; assetName: "status-power" }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.powerClicked() } }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 2. NOTIFICATION PREVIEW
    // ════════════════════════════════════════════════════════════════════
    RowLayout {
        id: notificationPreviewRow
        visible: root.notificationPreviewVisible
        anchors.fill:        parent
        anchors.leftMargin:  Theme.marginSize(15)
        anchors.rightMargin: Theme.marginSize(15)
        anchors.topMargin:   Theme.marginSize(8)
        anchors.bottomMargin: Theme.marginSize(8)
        spacing: Theme.spacingSize(9)

        Rectangle {
            Layout.preferredWidth:  Theme.dimensionSize(30)
            Layout.preferredHeight: Theme.dimensionSize(30)
            radius: Theme.radiusSize(10)
            color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.14))
            SvgIcon { anchors.centerIn: parent; width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "bell-dot"; tone: "accent" }
        }

        ColumnLayout {
            id: notificationPreviewColumn
            Layout.fillWidth: true
            spacing: Theme.spacingSize(1)
            Text {
                Layout.fillWidth: true
                text:  root.previewNotification ? root.previewNotification.appName : "Notification"
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightSemibold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text:  root.previewNotification ? root.previewNotification.summary : ""
                color: Theme.fg
                font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(12); font.weight: Theme.fontWeightSemibold
                elide: Text.ElideRight
            }
            Text {
                id: previewBody
                objectName: "pillPreviewBody"
                Layout.fillWidth: true
                visible: !!(root.previewNotification && root.previewNotification.body)
                text:  root.previewNotification ? root.previewNotification.body : ""
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9)
                textFormat: Text.AutoText
                wrapMode:   Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
        }

        Text {
            text: root.previewNotification
                ? NotificationService.timeAgo(root.previewNotification.timestamp) : ""
            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9)
        }
        SvgIcon { width: Theme.dimensionSize(14); height: Theme.dimensionSize(14); Layout.alignment: Qt.AlignVCenter; iconName: "chevron-right"; tone: "muted" }
    }

    // ════════════════════════════════════════════════════════════════════
    // 3. MEDIA POPOVER
    // ════════════════════════════════════════════════════════════════════
    Rectangle {
        id: mediaPanel
        visible: root.mediaPopupVisible
        anchors.fill: parent
        radius: parent.radius
        color: Theme.surface
        border.width: Theme.dimensionSize(1)
        border.color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.12))

        ColumnLayout {
            anchors.fill:        parent
            anchors.leftMargin:  Theme.marginSize(10)
            anchors.rightMargin: Theme.marginSize(10)
            anchors.topMargin:   Theme.marginSize(7)
            anchors.bottomMargin: Theme.marginSize(7)
            spacing: Theme.spacingSize(5)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSize(8)

                Rectangle {
                    Layout.preferredWidth:  Theme.dimensionSize(35)
                    Layout.preferredHeight: Theme.dimensionSize(35)
                    radius: Theme.radiusSize(10)
                    color:  Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18))
                    clip:   true
                    Image {
                        anchors.fill: parent
                        source: MediaService.artUrl
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        smooth: true
                    }
                    SvgIcon {
                        anchors.centerIn: parent
                        visible: MediaService.artUrl === ""
                        width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
                        iconName: "music-2"; tone: "accent"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSize(1)
                    Text {
                        Layout.fillWidth: true
                        text:  MediaService.title || "Nothing playing"
                        color: Theme.fg
                        font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text:  MediaService.artist || MediaService.playerName
                        color: Theme.muted
                        font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9)
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: Theme.dimensionSize(30); Layout.preferredHeight: Theme.dimensionSize(30)
                    radius: Theme.radiusSize(15)
                    color:  mediaPlayMouse.containsMouse ? Theme.acc : Theme.surfaceRaised
                    SvgIcon {
                        anchors.centerIn: parent
                        width: Theme.dimensionSize(12); height: Theme.dimensionSize(12)
                        iconName: MediaService.playing ? "pause" : "play"
                        tone: mediaPlayMouse.containsMouse ? "ink" : "fg"
                    }
                    MouseArea {
                        id: mediaPlayMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => { e.accepted = true; MediaService.toggle(); root.restartMediaInactivity() }
                    }
                }

                SvgIcon {
                    width: Theme.dimensionSize(14); height: Theme.dimensionSize(14); Layout.alignment: Qt.AlignVCenter
                    iconName: "x"; tone: mediaCloseMouse.containsMouse ? "fg" : "muted"
                    MouseArea {
                        id: mediaCloseMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => {
                            e.accepted = true
                            root.mediaExpanded = false; root.mediaAutoPopup = false
                            mediaAutoHide.stop(); mediaInactivity.stop()
                        }
                    }
                }
            }

            // Progress bar
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                Text { text: root.formatMediaTime(MediaService.displayPosition); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8) }
                Rectangle {
                    id: mediaProgressTrack; Layout.fillWidth: true; height: Theme.dimensionSize(4); radius: Theme.radiusSize(2); color: Theme.surfaceRaised
                    Rectangle {
                        width: parent.width * MediaService.progress; height: parent.height; radius: Theme.radiusSize(2); color: Theme.acc
                        Behavior on width { NumberAnimation { duration: Theme.duration(120) } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: (e) => { e.accepted = true; MediaService.seekToRatio(e.x / width); root.restartMediaInactivity() }
                    }
                }
                Text { text: root.formatMediaTime(MediaService.length); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8) }
            }

            // Transport controls
            RowLayout {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacingSize(28)
                SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); Layout.alignment: Qt.AlignVCenter
                    iconName: "skip-back"; tone: mediaPrevMouse.containsMouse ? "fg" : "muted"
                    MouseArea { id: mediaPrevMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => { e.accepted = true; MediaService.previous(); root.restartMediaInactivity() } } }
                SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); Layout.alignment: Qt.AlignVCenter
                    iconName: MediaService.playing ? "pause" : "play"; tone: "fg"
                    MouseArea { anchors.fill: parent; onClicked: (e) => { e.accepted = true; MediaService.toggle(); root.restartMediaInactivity() } } }
                SvgIcon { width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); Layout.alignment: Qt.AlignVCenter
                    iconName: "skip-forward"; tone: mediaNextMouse.containsMouse ? "fg" : "muted"
                    MouseArea { id: mediaNextMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => { e.accepted = true; MediaService.next(); root.restartMediaInactivity() } } }
                SvgIcon { width: Theme.dimensionSize(18); height: Theme.dimensionSize(18); Layout.alignment: Qt.AlignVCenter
                    iconName: "volume-2"; tone: "muted"
                    MouseArea { anchors.fill: parent; onClicked: (e) => { e.accepted = true; ShellState.goTo("sound"); root.restartMediaInactivity() } }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 4. WINDOW LIST
    // ════════════════════════════════════════════════════════════════════
    Loader {
        id: inlineWindowList
        anchors.fill: parent
        z: 3
        active: root.windowListOpen
        sourceComponent: windowListComponent
    }
    Component {
      id: windowListComponent
      Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.surface
        border.width: Theme.dimensionSize(1); border.color: Theme.outline
        z: 3

        ScrollView {
            anchors.fill: parent; anchors.margins: Theme.marginSize(14); clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width; spacing: Theme.spacingSize(8)

                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacingSize(8)
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Theme.spacingSize(0)
                        Text { text: "WORKSPACES & APPS"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(11); font.weight: Theme.fontWeightBold; font.letterSpacing: Theme.letterSpacingValue(0.5) }
                        Text { text: "Running applications  •  hover an app and press S to close"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.line; opacity: Theme.opacityValue(0.8)}

                Repeater {
                    model: root.workspaceData
                    delegate: Item {
                        id: wsCard
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.topMargin: index > 0 ? 6 : 0
                        Layout.bottomMargin: Theme.marginSize(2)
                        implicitHeight: wsColumn.implicitHeight

                        Rectangle {
                            anchors.fill: parent
                            z: -1
                            radius: Theme.radiusSize(12)
                            color: modelData.id === root.activeWorkspaceId
                                ? Qt.rgba(1,0.62,0.04, Theme.opacityValue(0.055)) : Qt.rgba(1,1,1, Theme.opacityValue(0.025))
                            border.width: Theme.dimensionSize(1)
                            border.color: modelData.id === root.activeWorkspaceId
                                ? Qt.rgba(1,0.62,0.04, Theme.opacityValue(0.24)) : Qt.rgba(1,1,1, Theme.opacityValue(0.08))
                        }

                        ColumnLayout {
                            id: wsColumn
                            width: parent.width
                            spacing: Theme.spacingSize(3)

                        Rectangle {
                            visible: false; Layout.fillWidth: true; height: Theme.dimensionSize(1)
                            color: Qt.rgba(1,1,1, Theme.opacityValue(0.10))
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.leftMargin: Theme.marginSize(8); Layout.rightMargin: Theme.marginSize(8); Layout.topMargin: Theme.marginSize(8)
                            height: Theme.dimensionSize(26); radius: Theme.radiusSize(8)
                            color: modelData.id === root.activeWorkspaceId ? Qt.rgba(1,0.62,0.04, Theme.opacityValue(0.14)) : Qt.rgba(1,1,1, Theme.opacityValue(0.045))
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: Theme.marginSize(9); anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.id > 0 ? "Workspace " + modelData.id : "Scratchpad")
                                    + (modelData.id === root.activeWorkspaceId ? "  •  active" : "")
                                color: modelData.id === root.activeWorkspaceId ? Theme.islandAccent : Theme.fg
                                font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); font.weight: Theme.fontWeightBold
                            }
                        }
                        Repeater {
                            model: modelData.clients
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true; Layout.minimumWidth: Theme.dimensionSize(0); Layout.leftMargin: Theme.marginSize(8); Layout.rightMargin: Theme.marginSize(8); Layout.bottomMargin: Theme.marginSize(4); spacing: Theme.spacingSize(5)
                                width: Math.max(0, parent.width - 16)
                                HoverHandler {
                                    id: appRowHover
                                    onHoveredChanged: {
                                        if (hovered) root.keyboardKillAddress = modelData.address
                                        else appNameText.x = 0
                                    }
                                }
                                Rectangle {
                                    Layout.minimumWidth: Theme.dimensionSize(28); Layout.preferredWidth: Theme.dimensionSize(28); Layout.maximumWidth: Theme.dimensionSize(28)
                                    Layout.minimumHeight: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); Layout.maximumHeight: Theme.dimensionSize(28)
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    radius: Theme.radiusSize(8)
                                    color: Qt.rgba(1,1,1, Theme.opacityValue(0.08)); clip: true
                                    Image {
                                        anchors.fill: parent; anchors.margins: Theme.marginSize(4)
                                        source: modelData.iconPath; sourceSize: Qt.size(48,48)
                                        fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
                                    }
                                    SvgIcon { anchors.centerIn: parent; visible: !modelData.iconPath; width: Theme.dimensionSize(14); height: Theme.dimensionSize(14); iconName: "app-window"; tone: "muted" }
                                }
                                Item {
                                    id: appNameViewport
                                    Layout.fillWidth: true; Layout.minimumWidth: Theme.dimensionSize(1); Layout.preferredHeight: Theme.dimensionSize(28)
                                    Layout.alignment: Qt.AlignVCenter
                                    clip: true
                                    Text {
                                        id: appNameText
                                        y: 1
                                        text: modelData.appClass
                                        color: modelData.address === root.activeAddress ? Theme.islandAccent : Theme.fg
                                        font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.weight: Theme.fontWeightSemibold
                                        width: Math.max(implicitWidth, appNameViewport.width)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        text: modelData.title; color: Theme.muted
                                        font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(8)
                                        elide: Text.ElideRight
                                    }
                                    SequentialAnimation {
                                        running: appRowHover.hovered && appNameText.implicitWidth > appNameViewport.width
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: Theme.duration(500) }
                                        NumberAnimation { target: appNameText; property: "x"; from: 0; to: -(appNameText.implicitWidth - appNameViewport.width); duration: Math.max(Theme.duration(900), appNameText.implicitWidth * Theme.scrollAppRate); easing.type: Easing.InOutSine }
                                        PauseAnimation { duration: Theme.duration(500) }
                                        NumberAnimation { target: appNameText; property: "x"; to: 0; duration: Theme.duration(350); easing.type: Easing.InOutSine }
                                    }
                                }
                                Rectangle {
                                    Layout.minimumWidth: Theme.dimensionSize(28); Layout.preferredWidth: Theme.dimensionSize(28); Layout.maximumWidth: Theme.dimensionSize(28); Layout.preferredHeight: Theme.dimensionSize(28); radius: Theme.radiusSize(9)
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    color: closeClientMouse.containsMouse ? Qt.rgba(1,0.25,0.35, Theme.opacityValue(0.28)) : Qt.rgba(1,0.25,0.35, Theme.opacityValue(0.12))
                                    Text { anchors.centerIn: parent; text: "×"; color: closeClientMouse.containsMouse ? Theme.error : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(17); font.weight: Theme.fontWeightMedium }
                                    MouseArea {
                                        id: closeClientMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onEntered: root.keyboardKillAddress = modelData.address
                                        onClicked: (e) => {
                                            e.accepted = true
                                            root.keyboardKillAddress = modelData.address
                                            root.clientCloseRequested(modelData.address)
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: modelData.clients.length === 0; text: "(empty)"
                            color: Theme.mutedDim; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9); font.italic: true
                            Layout.leftMargin: Theme.marginSize(8); Layout.topMargin: Theme.marginSize(4); Layout.bottomMargin: Theme.marginSize(8)
                        }
                        }
                    }
                }
            }
        }
      }
    }

    // ════════════════════════════════════════════════════════════════════
    // 5. CONTROL PANEL (embedded, fills the pill when popupOpen)
    // ════════════════════════════════════════════════════════════════════
    // Loaded by file path (not sourceComponent) so the panel's QML is not
    // even compiled until the first time it is opened, and is destroyed when
    // it closes. Frees the ~1500-line panel and the services only it uses.
    Loader {
        id: inlineControlPanel
        anchors.fill: parent
        z: 3
        active: root.controlPopupVisible
        visible: root.controlPopupVisible
        focus: root.controlPopupVisible
        source: Qt.resolvedUrl("../panels/ControlPanel.qml")

        // The panel's own scan-stop handler can't run once it is destroyed,
        // so stop the Wi-Fi scan here when it closes.
        onActiveChanged: if (!active) { NetworkService.stopScan(); panelGcTimer.restart() }
        // Give the destroyed panel a moment to be released, then collect it.
        Timer { id: panelGcTimer; interval: 400; onTriggered: gc() }
        onLoaded: item.focus = true

        // Props previously passed inline.
        Binding { target: inlineControlPanel.item; property: "pendingUpdates"
                  value: root.pendingUpdates; when: inlineControlPanel.item !== null }
        Binding { target: inlineControlPanel.item; property: "updateTooltip"
                  value: root.updateTooltip;  when: inlineControlPanel.item !== null }

        // Key events the panel doesn't consume bubble up to the Loader.
        Keys.onEscapePressed: ShellState.popupOpen = false
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier) {
                const address = root.keyboardKillAddress || root.activeAddress
                if (address) {
                    event.accepted = true
                    root.clientCloseRequested(address)
                    root.keyboardKillAddress = ""
                }
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    function formatMediaTime(value): string {
        const seconds = Math.max(0, Math.floor((Number(value) || 0) / 1000000))
        return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + (seconds % 60)
    }
    function restartMediaInactivity(): void {
        if (mediaPopupVisible) mediaInactivity.restart()
    }

    // ════════════════════════════════════════════════════════════════════
    // ════════════════════════════════════════════════════════════════════
    // PillAction — legacy alias kept for any external code that references it
    // ════════════════════════════════════════════════════════════════════
    component PillAction: Item {
        id: action
        property string icon:        ""
        property string tooltipText: ""
        property string badge:       ""
        property bool   active:      false
        property bool   danger:      false
        signal clicked()
        implicitWidth: Theme.dimensionSize(24); implicitHeight: Theme.dimensionSize(24)

        Rectangle {
            anchors.fill: parent; radius: Theme.radiusSize(8)
            color: actionMouse.containsMouse
                ? (action.danger ? Qt.rgba(1,0.42,0.37, Theme.opacityValue(0.24)) : Qt.rgba(1,0.62,0.04, Theme.opacityValue(0.22)))
                : action.active ? Qt.rgba(1,0.62,0.04, Theme.opacityValue(0.13)) : Qt.rgba(1,1,1, Theme.opacityValue(0.075))
            Behavior on color { ColorAnimation { duration: Theme.duration(120) } }
            Text { anchors.centerIn: parent; text: action.icon; color: action.danger ? Theme.error : action.active ? Theme.islandAccent : Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(13) }
        }
        Rectangle {
            visible: action.badge !== ""
            anchors.right: parent.right; anchors.top: parent.top
            anchors.rightMargin: Theme.marginSize(-5); anchors.topMargin: Theme.marginSize(-5)
            width: Math.max(10, badgeText.implicitWidth + 5); height: Theme.dimensionSize(11); radius: Theme.radiusSize(6); color: Theme.error
            Text { id: badgeText; anchors.centerIn: parent; text: action.badge; color: Theme.background; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(6); font.weight: Theme.fontWeightBold }
        }
        MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; action.clicked() } }
    }
}
