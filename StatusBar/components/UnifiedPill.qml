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
    radius:       19   // border-radius: 19px  (.pill spec)
    border.width: 1
    border.color: pillMouse.containsMouse
                      ? Qt.rgba(1, 0.62, 0.04, 0.42) : Theme.line
    layer.enabled: true
    clip: true

    Behavior on color        { ColorAnimation  { duration: 140 } }
    Behavior on border.color { ColorAnimation  { duration: 140 } }
    // Keep popup geometry immediate; animated size changes make expandable
    // Wi-Fi details appear to open in two separate steps.
    // Do not tween the shell height while expandable Wi-Fi rows are being
    // measured; that produces a visible lag and clips the details card.

    // ── Media breath pulse ────────────────────────────────────────────────
    SequentialAnimation on mediaBreath {
        running: root.mediaPreviewVisible && MediaService.playing
        loops:   Animation.Infinite
        NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutSine }
    }
    scale: 1 + (mediaPreviewVisible && MediaService.playing ? mediaBreath * 0.006 : 0)
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutSine } }

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
        spacing: 2

        // ── Helper: flat icon button (Rectangle + SVG IconImage + MouseArea) ──
        // Each button below uses this exact same pattern inline.
        // Width = 28, Height = 28, radius 99, 16×16 SVG centred.

        // ── Hamburger ────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99
            color: menuHov.containsMouse ? Theme.surfaceRaised : "transparent"
            Layout.alignment: Qt.AlignVCenter
            IconImage { anchors.centerIn: parent; width: 16; height: 16; source: Qt.resolvedUrl("../icons/menu-muted.svg") }
            MouseArea { id: menuHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.hamburgerClicked() } }
        }

        // ── Workspace dots ───────────────────────────────────────────────
        Row {
            spacing: 5; Layout.leftMargin: 4; Layout.rightMargin: 4; Layout.alignment: Qt.AlignVCenter
            Repeater {
                model: root.workspaces.length > 0 ? root.workspaces : [{ id: root.activeWorkspaceId }]
                delegate: Rectangle {
                    readonly property int wsId: Number(modelData?.id || (index + 1))
                    width: wsId === root.activeWorkspaceId ? 16 : 8; height: 8; radius: 99
                    color: wsId === root.activeWorkspaceId ? Theme.fg : Theme.muted
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                    MouseArea { anchors.fill: parent; onClicked: (e) => { e.accepted = true; root.workspaceClicked(wsId) } }
                }
            }
        }

        // ── Separator ────────────────────────────────────────────────────
        Rectangle { width: 1; height: 14; color: Theme.line; opacity: 0.5; Layout.alignment: Qt.AlignVCenter }

        // ── Now-playing (EQ + track name) ────────────────────────────────
        Item {
            visible: MediaService.hasTrack
            Layout.preferredWidth: visible ? nowRow.implicitWidth + 16 : 0
            Layout.preferredHeight: 30; Layout.alignment: Qt.AlignVCenter
            Row {
                id: nowRow; anchors.centerIn: parent; spacing: 4
                Row {
                    spacing: 2; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 2; height: 12; radius: 2; color: Theme.acc; anchors.bottom: parent.bottom
                            SequentialAnimation on height {
                                loops: Animation.Infinite; running: MediaService.playing
                                PauseAnimation { duration: [0, 400, 750][index] }
                                NumberAnimation { to: 12; duration: 500; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 3;  duration: 500; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
                Item {
                    id: pillTitleViewport
                    width: 120; height: 18; clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: pillTitleText
                        y: 1
                        text: MediaService.title
                        color: Theme.fg
                        font.family: Theme.uiFont; font.pixelSize: 11
                        width: Math.max(implicitWidth, pillTitleViewport.width)
                        elide: Text.ElideNone
                    }
                    SequentialAnimation {
                        running: MediaService.hasTrack && MediaService.playing && pillTitleText.implicitWidth > pillTitleViewport.width
                        loops: Animation.Infinite
                        PauseAnimation { duration: 800 }
                        NumberAnimation { target: pillTitleText; property: "x"; from: 0; to: -(pillTitleText.implicitWidth - pillTitleViewport.width); duration: Math.max(1800, pillTitleText.implicitWidth * 45); easing.type: Easing.Linear }
                        PauseAnimation { duration: 800 }
                        NumberAnimation { target: pillTitleText; property: "x"; to: 0; duration: 450; easing.type: Easing.InOutSine }
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
            implicitWidth: clockText.implicitWidth + 16; implicitHeight: 28; radius: 99
            color: clockHov.containsMouse ? Theme.surfaceRaised : "transparent"
            Layout.alignment: Qt.AlignVCenter
            Text { id: clockText; anchors.centerIn: parent; text: ShellState.time; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: 11; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }) }
            MouseArea { id: clockHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.timeClicked() } }
        }

        // ── Separator ────────────────────────────────────────────────────
        Rectangle { width: 1; height: 14; color: Theme.line; opacity: 0.5; Layout.alignment: Qt.AlignVCenter }

        // ── Quick Settings ───────────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99
            color: settHov.containsMouse ? Theme.surfaceRaised : "transparent"; Layout.alignment: Qt.AlignVCenter
            IconImage { anchors.centerIn: parent; width: 16; height: 16; source: Qt.resolvedUrl("../icons/sliders-horizontal-muted.svg") }
            MouseArea { id: settHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("main") } }
        }

        // ── Battery (icon + %) ───────────────────────────────────────────
        Rectangle {
            implicitWidth: battRow.implicitWidth + 16; implicitHeight: 28; radius: 99
            color: battHov.containsMouse ? Theme.surfaceRaised : "transparent"; Layout.alignment: Qt.AlignVCenter
            Row {
                id: battRow; anchors.centerIn: parent; spacing: 4
                IconImage {
                    width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(root.batteryCharging ? "../icons/battery-charging-success.svg"
                        : root.batteryPercent < 0 ? "../icons/battery-muted.svg"
                        : root.batteryPercent <= 15 ? "../icons/battery-low-error.svg"
                        : root.batteryPercent < 40 ? "../icons/battery-medium-muted.svg"
                        : "../icons/battery-full-muted.svg")
                }
                Text { text: root.batteryPercent < 0 ? "n/a" : root.batteryPercent + "%"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: 11; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }); anchors.verticalCenter: parent.verticalCenter }
                LockBadge { active: LockKeysService.numLock; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: battHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("batt") } }
        }

        // ── Wi-Fi ────────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99
            color: wifiHov.containsMouse ? Theme.surfaceRaised : "transparent"; Layout.alignment: Qt.AlignVCenter
            IconImage {
                anchors.centerIn: parent; width: 16; height: 16
                property bool on_: NetworkService.wifiEnabled
                property bool connected_: !!NetworkService.activeNetwork
                source: Qt.resolvedUrl(!on_ ? "../icons/wifi-muted.svg"
                    : connected_ ? "../icons/wifi-accent.svg" : "../icons/wifi-fg.svg")
            }
            MouseArea { id: wifiHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("wifi") } }
        }

        // ── Bluetooth ────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99
            color: btHov.containsMouse ? Theme.surfaceRaised : "transparent"; Layout.alignment: Qt.AlignVCenter
            IconImage {
                anchors.centerIn: parent; width: 16; height: 16
                property bool on_: BluetoothService.enabled
                property bool connected_: BluetoothService.connectedDevices.length > 0
                source: Qt.resolvedUrl(!on_ ? "../icons/bluetooth-muted.svg"
                    : connected_ ? "../icons/bluetooth-accent.svg" : "../icons/bluetooth-fg.svg")
            }
            MouseArea { id: btHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("bt") } }
        }

        // ── Volume ───────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99
            color: volHov.containsMouse ? Theme.surfaceRaised : "transparent"; Layout.alignment: Qt.AlignVCenter
            IconImage {
                anchors.centerIn: parent; width: 16; height: 16
                property bool muted_: AudioService.muted
                source: Qt.resolvedUrl(muted_ ? "../icons/volume-x-error.svg" : "../icons/volume-2-fg.svg")
            }
            MouseArea { id: volHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("sound") } }
        }

        // ── Bell ─────────────────────────────────────────────────────────
        Item {
            implicitWidth: 28; implicitHeight: 28; Layout.alignment: Qt.AlignVCenter
            Rectangle {
                anchors.fill: parent; radius: 99
                color: bellHov.containsMouse ? Theme.surfaceRaised : "transparent"
            }
            IconImage {
                anchors.centerIn: parent; width: 16; height: 16
                property bool dnd_: NotificationService.dndEnabled
                source: Qt.resolvedUrl(dnd_ ? "../icons/bell-off-error.svg"
                    : NotificationService.count > 0 ? "../icons/bell-fg.svg" : "../icons/bell-muted.svg")
            }
            // Badge
            Rectangle {
                visible: NotificationService.count > 0
                anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -3
                width: Math.max(13, badgeTxt.implicitWidth + 5); height: 13; radius: 7; color: Theme.acc
                Text { id: badgeTxt; anchors.centerIn: parent; text: NotificationService.count > 99 ? "99+" : String(NotificationService.count); color: "#111"; font.family: Theme.uiFont; font.pixelSize: 7; font.weight: Font.Bold }
            }
            MouseArea { id: bellHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.openControlCenter("alerts") } }
        }

        // ── Coffee (keep-awake) ──────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99; Layout.alignment: Qt.AlignVCenter
            color: CaffeineService.enabled ? Theme.acc : coffeeHov.containsMouse ? Theme.surfaceRaised : "transparent"
            Behavior on color { ColorAnimation { duration: 200 } }
            IconImage {
                anchors.centerIn: parent; width: 16; height: 16
                property bool on_: CaffeineService.enabled
                source: Qt.resolvedUrl(on_ ? "../icons/coffee-ink.svg" : "../icons/coffee-muted.svg")
            }
            MouseArea { id: coffeeHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; CaffeineService.toggle() } }
        }

        // ── Updates ──────────────────────────────────────────────────────
        Item {
            visible: root.pendingUpdates > 0
            implicitWidth: 28; implicitHeight: 28; Layout.alignment: Qt.AlignVCenter
            Rectangle { anchors.fill: parent; radius: 99; color: updHov.containsMouse ? Theme.surfaceRaised : "transparent" }
            IconImage { anchors.centerIn: parent; width: 16; height: 16; source: Qt.resolvedUrl("../icons/download-fg.svg") }
            Rectangle {
                anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -3
                width: Math.max(13, updBadgeTxt.implicitWidth + 5); height: 13; radius: 7; color: Theme.acc
                Text { id: updBadgeTxt; anchors.centerIn: parent; text: root.pendingUpdates > 99 ? "99+" : String(root.pendingUpdates); color: "#111"; font.family: Theme.uiFont; font.pixelSize: 7; font.weight: Font.Bold }
            }
            MouseArea { id: updHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.updatesClicked() } }
        }

        // ── Power ────────────────────────────────────────────────────────
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 99
            color: pwrHov.containsMouse ? Theme.surfaceRaised : "transparent"; Layout.alignment: Qt.AlignVCenter
            IconImage { anchors.centerIn: parent; width: 16; height: 16; source: Qt.resolvedUrl("../icons/power-muted.svg") }
            MouseArea { id: pwrHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; root.powerClicked() } }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 2. NOTIFICATION PREVIEW
    // ════════════════════════════════════════════════════════════════════
    RowLayout {
        id: notificationPreviewRow
        visible: root.notificationPreviewVisible
        anchors.fill:        parent
        anchors.leftMargin:  15
        anchors.rightMargin: 15
        anchors.topMargin:   8
        anchors.bottomMargin: 8
        spacing: 9

        Rectangle {
            Layout.preferredWidth:  30
            Layout.preferredHeight: 30
            radius: 10
            color: Qt.rgba(1, 0.62, 0.04, 0.14)
            IconImage { anchors.centerIn: parent; width: 16; height: 16; source: Qt.resolvedUrl("../icons/bell-dot-accent.svg") }
        }

        ColumnLayout {
            id: notificationPreviewColumn
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text:  root.previewNotification ? root.previewNotification.appName : "Notification"
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: 9; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text:  root.previewNotification ? root.previewNotification.summary : ""
                color: Theme.fg
                font.family: Theme.uiFont; font.pixelSize: 12; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                id: previewBody
                objectName: "pillPreviewBody"
                Layout.fillWidth: true
                visible: !!(root.previewNotification && root.previewNotification.body)
                text:  root.previewNotification ? root.previewNotification.body : ""
                color: Theme.muted
                font.family: Theme.uiFont; font.pixelSize: 9
                textFormat: Text.AutoText
                wrapMode:   Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
        }

        Text {
            text: root.previewNotification
                ? NotificationService.timeAgo(root.previewNotification.timestamp) : ""
            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 9
        }
        IconImage { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("../icons/chevron-right-muted.svg") }
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
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        ColumnLayout {
            anchors.fill:        parent
            anchors.leftMargin:  10
            anchors.rightMargin: 10
            anchors.topMargin:   7
            anchors.bottomMargin: 7
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth:  35
                    Layout.preferredHeight: 35
                    radius: 10
                    color:  Qt.rgba(1, 0.62, 0.04, 0.18)
                    clip:   true
                    Image {
                        anchors.fill: parent
                        source: MediaService.artUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        smooth: true
                    }
                    IconImage {
                        anchors.centerIn: parent
                        visible: MediaService.artUrl === ""
                        width: 16; height: 16
                        source: Qt.resolvedUrl("../icons/music-2-accent.svg")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text:  MediaService.title || "Nothing playing"
                        color: Theme.fg
                        font.family: Theme.uiFont; font.pixelSize: 11; font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text:  MediaService.artist || MediaService.playerName
                        color: Theme.muted
                        font.family: Theme.uiFont; font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    radius: 15
                    color:  mediaPlayMouse.containsMouse ? Theme.acc : Theme.surfaceRaised
                    IconImage {
                        anchors.centerIn: parent
                        width: 12; height: 12
                        source: Qt.resolvedUrl(MediaService.playing
                            ? mediaPlayMouse.containsMouse ? "../icons/pause-ink.svg" : "../icons/pause-fg.svg"
                            : mediaPlayMouse.containsMouse ? "../icons/play-ink.svg" : "../icons/play-fg.svg")
                    }
                    MouseArea {
                        id: mediaPlayMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => { e.accepted = true; MediaService.toggle(); root.restartMediaInactivity() }
                    }
                }

                IconImage {
                    width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(mediaCloseMouse.containsMouse ? "../icons/x-fg.svg" : "../icons/x-muted.svg")
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
                Layout.fillWidth: true; spacing: 8
                Text { text: root.formatMediaTime(MediaService.displayPosition); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 8 }
                Rectangle {
                    id: mediaProgressTrack; Layout.fillWidth: true; height: 4; radius: 2; color: Theme.surfaceRaised
                    Rectangle {
                        width: parent.width * MediaService.progress; height: parent.height; radius: 2; color: Theme.acc
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: (e) => { e.accepted = true; MediaService.seekToRatio(e.x / width); root.restartMediaInactivity() }
                    }
                }
                Text { text: root.formatMediaTime(MediaService.length); color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 8 }
            }

            // Transport controls
            RowLayout {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 28
                IconImage { width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(mediaPrevMouse.containsMouse ? "../icons/skip-back-fg.svg" : "../icons/skip-back-muted.svg")
                    MouseArea { id: mediaPrevMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => { e.accepted = true; MediaService.previous(); root.restartMediaInactivity() } } }
                IconImage { width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(MediaService.playing ? "../icons/pause-fg.svg" : "../icons/play-fg.svg")
                    MouseArea { anchors.fill: parent; onClicked: (e) => { e.accepted = true; MediaService.toggle(); root.restartMediaInactivity() } } }
                IconImage { width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(mediaNextMouse.containsMouse ? "../icons/skip-forward-fg.svg" : "../icons/skip-forward-muted.svg")
                    MouseArea { id: mediaNextMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: (e) => { e.accepted = true; MediaService.next(); root.restartMediaInactivity() } } }
                IconImage { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl("../icons/volume-2-muted.svg")
                    MouseArea { anchors.fill: parent; onClicked: (e) => { e.accepted = true; ShellState.goTo("sound"); root.restartMediaInactivity() } }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 4. WINDOW LIST
    // ════════════════════════════════════════════════════════════════════
    Rectangle {
        id: inlineWindowList
        visible: root.windowListOpen
        anchors.fill: parent
        radius: parent.radius
        color: "#151517"
        border.width: 1; border.color: Theme.outline
        z: 3

        ScrollView {
            anchors.fill: parent; anchors.margins: 14; clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width; spacing: 8

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text { text: "WORKSPACES & APPS"; color: Theme.fg; font.family: Theme.uiFont; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.5 }
                        Text { text: "Running applications  •  hover an app and press S to close"; color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line; opacity: 0.8 }

                Repeater {
                    model: root.workspaceData
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; spacing: 3
                        Layout.topMargin: index > 0 ? 6 : 0
                        Layout.bottomMargin: 2

                        Rectangle {
                            anchors.fill: parent
                            z: -1
                            radius: 12
                            color: modelData.id === root.activeWorkspaceId
                                ? Qt.rgba(1,0.62,0.04,0.055) : Qt.rgba(1,1,1,0.025)
                            border.width: 1
                            border.color: modelData.id === root.activeWorkspaceId
                                ? Qt.rgba(1,0.62,0.04,0.24) : Qt.rgba(1,1,1,0.08)
                        }

                        Rectangle {
                            visible: false; Layout.fillWidth: true; height: 1
                            color: Qt.rgba(1,1,1,0.10)
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 8
                            height: 26; radius: 8
                            color: modelData.id === root.activeWorkspaceId ? Qt.rgba(1,0.62,0.04,0.14) : Qt.rgba(1,1,1,0.045)
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 9; anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.id > 0 ? "Workspace " + modelData.id : "Scratchpad")
                                    + (modelData.id === root.activeWorkspaceId ? "  •  active" : "")
                                color: modelData.id === root.activeWorkspaceId ? Theme.islandAccent : Theme.fg
                                font.family: Theme.uiFont; font.pixelSize: 10; font.weight: Font.Bold
                            }
                        }
                        Repeater {
                            model: modelData.clients
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.bottomMargin: 4; spacing: 5
                                width: Math.max(0, parent.width - 16)
                                HoverHandler {
                                    id: appRowHover
                                    onHoveredChanged: {
                                        if (hovered) root.keyboardKillAddress = modelData.address
                                        else appNameText.x = 0
                                    }
                                }
                                Rectangle {
                                    Layout.minimumWidth: 28; Layout.preferredWidth: 28; Layout.maximumWidth: 28
                                    Layout.minimumHeight: 28; Layout.preferredHeight: 28; Layout.maximumHeight: 28
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    radius: 8
                                    color: Qt.rgba(1,1,1,0.08); clip: true
                                    Image {
                                        anchors.fill: parent; anchors.margins: 4
                                        source: modelData.iconPath; sourceSize: Qt.size(48,48)
                                        fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
                                    }
                                    IconImage { anchors.centerIn: parent; visible: !modelData.iconPath; width: 14; height: 14; source: Qt.resolvedUrl("../icons/app-window-muted.svg") }
                                }
                                Item {
                                    id: appNameViewport
                                    Layout.fillWidth: true; Layout.minimumWidth: 1; Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter
                                    clip: true
                                    Text {
                                        id: appNameText
                                        y: 1
                                        text: modelData.appClass
                                        color: modelData.address === root.activeAddress ? Theme.islandAccent : Theme.fg
                                        font.family: Theme.uiFont; font.pixelSize: 9; font.weight: Font.DemiBold
                                        width: Math.max(implicitWidth, appNameViewport.width)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        text: modelData.title; color: Theme.muted
                                        font.family: Theme.uiFont; font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }
                                    SequentialAnimation {
                                        running: appRowHover.hovered && appNameText.implicitWidth > appNameViewport.width
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: 500 }
                                        NumberAnimation { target: appNameText; property: "x"; from: 0; to: -(appNameText.implicitWidth - appNameViewport.width); duration: Math.max(900, appNameText.implicitWidth * 35); easing.type: Easing.InOutSine }
                                        PauseAnimation { duration: 500 }
                                        NumberAnimation { target: appNameText; property: "x"; to: 0; duration: 350; easing.type: Easing.InOutSine }
                                    }
                                }
                                Rectangle {
                                    Layout.minimumWidth: 28; Layout.preferredWidth: 28; Layout.maximumWidth: 28; Layout.preferredHeight: 28; radius: 9
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    color: closeClientMouse.containsMouse ? Qt.rgba(1,0.25,0.35,0.28) : Qt.rgba(1,0.25,0.35,0.12)
                                    Text { anchors.centerIn: parent; text: "×"; color: closeClientMouse.containsMouse ? Theme.error : Theme.muted; font.family: Theme.uiFont; font.pixelSize: 17; font.weight: Font.Medium }
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
                            color: Theme.mutedDim; font.family: Theme.uiFont; font.pixelSize: 9; font.italic: true
                            Layout.leftMargin: 8; Layout.topMargin: 4; Layout.bottomMargin: 8
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 5. CONTROL PANEL (embedded, fills the pill when popupOpen)
    // ════════════════════════════════════════════════════════════════════
    ControlPanel {
        id: inlineControlPanel
        visible: root.controlPopupVisible
        anchors.fill: parent
        focus: root.controlPopupVisible
        z: 3
        pendingUpdates: root.pendingUpdates
        updateTooltip:  root.updateTooltip
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
        implicitWidth: 24; implicitHeight: 24

        Rectangle {
            anchors.fill: parent; radius: 8
            color: actionMouse.containsMouse
                ? (action.danger ? Qt.rgba(1,0.42,0.37,0.24) : Qt.rgba(1,0.62,0.04,0.22))
                : action.active ? Qt.rgba(1,0.62,0.04,0.13) : Qt.rgba(1,1,1,0.075)
            Behavior on color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: action.icon; color: action.danger ? Theme.error : action.active ? Theme.islandAccent : Theme.muted; font.family: Theme.uiFont; font.pixelSize: 13 }
        }
        Rectangle {
            visible: action.badge !== ""
            anchors.right: parent.right; anchors.top: parent.top
            anchors.rightMargin: -5; anchors.topMargin: -5
            width: Math.max(10, badgeText.implicitWidth + 5); height: 11; radius: 6; color: Theme.error
            Text { id: badgeText; anchors.centerIn: parent; text: action.badge; color: Theme.background; font.family: Theme.uiFont; font.pixelSize: 6; font.weight: Font.Bold }
        }
        MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: (e) => { e.accepted = true; action.clicked() } }
    }
}
