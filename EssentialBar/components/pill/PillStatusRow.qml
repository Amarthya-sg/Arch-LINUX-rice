// PillStatusRow.qml
// Right-side quick-status icon cluster in the collapsed pill row.
// Contains: Settings, Battery, Wi-Fi, Bluetooth, Volume, Bell, Coffee, Updates, Power.
import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import ".."

RowLayout {
    id: root

    // ── Props injected from UnifiedPill ──────────────────────────────────
    property int    batteryPercent:  -1
    property bool   batteryCharging: false
    property int    pendingUpdates:  0

    // ── Signals ───────────────────────────────────────────────────────────
    signal openControlCenter(string tab)
    signal updatesClicked()
    signal powerClicked()

    spacing: Theme.spacingSize(2)

    // ── Settings ──────────────────────────────────────────────────────────
    Item {
        implicitWidth:  Theme.statusIconButtonSize
        implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon { anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize; assetName: "status-settings" }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.openControlCenter("main") }
        }
    }

    // ── Battery (icon + %) ────────────────────────────────────────────────
    Item {
        implicitWidth:  battRow.implicitWidth + 16
        implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        Row {
            id: battRow
            anchors.centerIn: parent
            spacing: Theme.spacingSize(4)
            SvgIcon {
                width:  Theme.statusIconSize; height: Theme.statusIconSize
                anchors.verticalCenter: parent.verticalCenter
                assetName: root.batteryCharging ? "status-battery-charging"
                    : root.batteryPercent < 0   ? "status-battery-unknown"
                    : root.batteryPercent <= 15  ? "status-battery-low"
                    : root.batteryPercent < 40   ? "status-battery-medium" : "status-battery-full"
            }
            Text {
                text:  root.batteryPercent < 0 ? "n/a" : root.batteryPercent + "%"
                color: Theme.batteryText
                font.family:    Theme.uiFont
                font.pixelSize: Theme.fontSize(11)
                font.weight:    Theme.fontWeightSemibold
                font.features:  ({ "tnum": 1 })
                anchors.verticalCenter: parent.verticalCenter
            }
            LockBadge { active: LockKeysService.numLock; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.openControlCenter("batt") }
        }
    }

    // ── Wi-Fi ─────────────────────────────────────────────────────────────
    Item {
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon {
            anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
            assetName: "status-wifi-on"
            slash: !NetworkService.wifiEnabled
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.openControlCenter("wifi") }
        }
    }

    // ── Bluetooth ─────────────────────────────────────────────────────────
    Item {
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon {
            anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
            assetName: "status-bluetooth-on"
            slash: !BluetoothService.enabled
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.openControlCenter("bt") }
        }
    }

    // ── Volume ────────────────────────────────────────────────────────────
    Item {
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon {
            anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
            assetName: "status-sound-on"
            slash: AudioService.muted
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.openControlCenter("sound") }
        }
    }

    // ── Bell (notifications) ──────────────────────────────────────────────
    Item {
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon {
            anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
            assetName: "status-bell-on"
            slash: NotificationService.dndEnabled
        }
        // Unread count badge
        Rectangle {
            visible: NotificationService.count > 0
            anchors.right:       parent.right; anchors.top: parent.top
            anchors.rightMargin: Theme.marginSize(-3); anchors.topMargin: Theme.marginSize(-3)
            width:  Math.max(13, badgeTxt.implicitWidth + 5); height: Theme.dimensionSize(13)
            radius: Theme.radiusSize(7); color: Theme.acc
            Text {
                id: badgeTxt
                anchors.centerIn: parent
                text:  NotificationService.count > 99 ? "99+" : String(NotificationService.count)
                color: Theme.islandBg
                font.family:    Theme.uiFont; font.pixelSize: Theme.fontSize(7); font.weight: Theme.fontWeightBold
            }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.openControlCenter("alerts") }
        }
    }

    // ── Coffee (keep-awake / Caffeine) ─────────────────────────────────────
    Item {
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon {
            anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize
            assetName: "status-coffee-on"
            slash: !CaffeineService.enabled
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; CaffeineService.toggle() }
        }
    }

    // ── Pending updates ────────────────────────────────────────────────────
    Item {
        visible: root.pendingUpdates > 0
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon { anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize; assetName: "status-download" }
        Rectangle {
            anchors.right:       parent.right; anchors.top: parent.top
            anchors.rightMargin: Theme.marginSize(-3); anchors.topMargin: Theme.marginSize(-3)
            width:  Math.max(13, updBadgeTxt.implicitWidth + 5); height: Theme.dimensionSize(13)
            radius: Theme.radiusSize(7); color: Theme.acc
            Text {
                id: updBadgeTxt
                anchors.centerIn: parent
                text:  root.pendingUpdates > 99 ? "99+" : String(root.pendingUpdates)
                color: Theme.islandBg
                font.family:    Theme.uiFont; font.pixelSize: Theme.fontSize(7); font.weight: Theme.fontWeightBold
            }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.updatesClicked() }
        }
    }

    // ── Power ──────────────────────────────────────────────────────────────
    Item {
        implicitWidth: Theme.statusIconButtonSize; implicitHeight: Theme.statusIconButtonSize
        Layout.alignment: Qt.AlignVCenter
        SvgIcon { anchors.centerIn: parent; width: Theme.statusIconSize; height: Theme.statusIconSize; assetName: "status-power" }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: (e) => { e.accepted = true; root.powerClicked() }
        }
    }
}
