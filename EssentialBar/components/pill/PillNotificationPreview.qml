// PillNotificationPreview.qml
// Pill display mode 3: transient notification toast preview.
// Shown when NotificationService.toastList is non-empty and the panel is closed.
// Auto-dismisses after Config.notificationToastMs ms (wired by UnifiedPill).
import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

RowLayout {
    id: root

    // ── Props ─────────────────────────────────────────────────────────────
    // The notification to display; may be null while the model is empty.
    property var notification: null

    // ── Layout ────────────────────────────────────────────────────────────
    anchors.leftMargin:   Theme.marginSize(15)
    anchors.rightMargin:  Theme.marginSize(15)
    anchors.topMargin:    Theme.marginSize(8)
    anchors.bottomMargin: Theme.marginSize(8)
    spacing: Theme.spacingSize(9)

    // ── Bell icon badge ───────────────────────────────────────────────────
    Rectangle {
        Layout.preferredWidth:  Theme.dimensionSize(30)
        Layout.preferredHeight: Theme.dimensionSize(30)
        radius: Theme.radiusSize(10)
        color:  Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.14))
        SvgIcon {
            anchors.centerIn: parent
            width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
            iconName: "bell-dot"; tone: "accent"
        }
    }

    // ── Text block ────────────────────────────────────────────────────────
    ColumnLayout {
        id: notificationPreviewColumn
        Layout.fillWidth: true
        spacing: Theme.spacingSize(1)

        Text {
            Layout.fillWidth: true
            text:  root.notification ? root.notification.appName : "Notification"
            color: Theme.muted
            font.family:    Theme.uiFont
            font.pixelSize: Theme.fontSize(9)
            font.weight:    Theme.fontWeightSemibold
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            text:  root.notification ? root.notification.summary : ""
            color: Theme.fg
            font.family:    Theme.uiFont
            font.pixelSize: Theme.fontSize(12)
            font.weight:    Theme.fontWeightSemibold
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: !!(root.notification && root.notification.body)
            text:    root.notification ? root.notification.body : ""
            color:   Theme.muted
            font.family:    Theme.uiFont
            font.pixelSize: Theme.fontSize(9)
            textFormat:  Text.AutoText
            wrapMode:    Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }
    }

    // ── Timestamp ─────────────────────────────────────────────────────────
    Text {
        text:  root.notification
            ? NotificationService.timeAgo(root.notification.timestamp) : ""
        color: Theme.muted
        font.family:    Theme.uiFont
        font.pixelSize: Theme.fontSize(9)
    }

    SvgIcon {
        width: Theme.dimensionSize(14); height: Theme.dimensionSize(14)
        Layout.alignment: Qt.AlignVCenter
        iconName: "chevron-right"; tone: "muted"
    }
}
