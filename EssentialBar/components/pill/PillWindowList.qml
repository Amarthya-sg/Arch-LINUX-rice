// PillWindowList.qml
// Pill display mode 2: workspace + running-app browser (hamburger menu).
// Lists all workspaces with their client windows; supports hover-scroll of long
// class names, keyboard close (S key via parent), and per-app close button.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

Rectangle {
    id: root

    // ── Props injected from UnifiedPill ───────────────────────────────────
    property var    workspaceData:     []
    property int    activeWorkspaceId: 1
    property string activeAddress:     ""

    // ── Signals ───────────────────────────────────────────────────────────
    signal clientCloseRequested(string address)
    // Emitted when hover changes the "keyboard kill" target.
    signal keyboardTargetChanged(string address)

    // ── Appearance ────────────────────────────────────────────────────────
    anchors.fill: parent
    radius:       parent.radius
    color:        Theme.surface
    border.width: Theme.dimensionSize(1)
    border.color: Theme.outline

    ScrollView {
        anchors.fill:    parent
        anchors.margins: Theme.marginSize(14)
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy:   ScrollBar.AlwaysOff
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width:   parent.width
            spacing: Theme.spacingSize(8)

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSize(8)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSize(0)
                    Text {
                        text:  "WORKSPACES & APPS"
                        color: Theme.fg
                        font.family:       Theme.uiFont
                        font.pixelSize:    Theme.fontSize(11)
                        font.weight:       Theme.fontWeightBold
                        font.letterSpacing: Theme.letterSpacingValue(0.5)
                    }
                    Text {
                        text:  "Running applications  •  hover an app and press S to close"
                        color: Theme.muted
                        font.family:    Theme.uiFont
                        font.pixelSize: Theme.fontSize(9)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.line; opacity: Theme.opacityValue(0.8) }

            // ── Workspace cards ────────────────────────────────────────────
            Repeater {
                model: root.workspaceData
                delegate: Item {
                    id: wsCard
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.topMargin:    index > 0 ? 6 : 0
                    Layout.bottomMargin: Theme.marginSize(2)
                    implicitHeight: wsColumn.implicitHeight

                    // Card background
                    Rectangle {
                        anchors.fill: parent; z: -1
                        radius: Theme.radiusSize(12)
                        color: modelData.id === root.activeWorkspaceId
                            ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.055))
                            : Qt.rgba(1, 1, 1, Theme.opacityValue(0.025))
                        border.width: Theme.dimensionSize(1)
                        border.color: modelData.id === root.activeWorkspaceId
                            ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.24))
                            : Qt.rgba(1, 1, 1, Theme.opacityValue(0.08))
                    }

                    ColumnLayout {
                        id: wsColumn
                        width: parent.width
                        spacing: Theme.spacingSize(3)

                        // Workspace label pill
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin:  Theme.marginSize(8)
                            Layout.rightMargin: Theme.marginSize(8)
                            Layout.topMargin:   Theme.marginSize(8)
                            height: Theme.dimensionSize(26); radius: Theme.radiusSize(8)
                            color: modelData.id === root.activeWorkspaceId
                                ? Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.14))
                                : Qt.rgba(1, 1, 1, Theme.opacityValue(0.045))

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin:    Theme.marginSize(9)
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.id > 0 ? "Workspace " + modelData.id : "Scratchpad")
                                    + (modelData.id === root.activeWorkspaceId ? "  •  active" : "")
                                color: modelData.id === root.activeWorkspaceId ? Theme.islandAccent : Theme.fg
                                font.family:    Theme.uiFont
                                font.pixelSize: Theme.fontSize(10)
                                font.weight:    Theme.fontWeightBold
                            }
                        }

                        // Client rows
                        Repeater {
                            model: modelData.clients
                            delegate: RowLayout {
                                required property var modelData

                                Layout.fillWidth:    true
                                Layout.minimumWidth: Theme.dimensionSize(0)
                                Layout.leftMargin:   Theme.marginSize(8)
                                Layout.rightMargin:  Theme.marginSize(8)
                                Layout.bottomMargin: Theme.marginSize(4)
                                spacing: Theme.spacingSize(5)
                                width: Math.max(0, parent.width - 16)

                                HoverHandler {
                                    id: appRowHover
                                    onHoveredChanged: {
                                        if (hovered)
                                            root.keyboardTargetChanged(modelData.address)
                                        else
                                            appNameText.x = 0
                                    }
                                }

                                // App icon
                                Rectangle {
                                    Layout.minimumWidth:  Theme.dimensionSize(28)
                                    Layout.preferredWidth: Theme.dimensionSize(28)
                                    Layout.maximumWidth:  Theme.dimensionSize(28)
                                    Layout.minimumHeight:  Theme.dimensionSize(28)
                                    Layout.preferredHeight: Theme.dimensionSize(28)
                                    Layout.maximumHeight:  Theme.dimensionSize(28)
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    radius: Theme.radiusSize(8)
                                    color:  Qt.rgba(1, 1, 1, Theme.opacityValue(0.08))
                                    clip:   true
                                    Image {
                                        anchors.fill: parent; anchors.margins: Theme.marginSize(4)
                                        source:       modelData.iconPath
                                        sourceSize:   Qt.size(48, 48)
                                        fillMode:     Image.PreserveAspectFit
                                        smooth: true; asynchronous: true
                                    }
                                    SvgIcon {
                                        anchors.centerIn: parent
                                        visible: !modelData.iconPath
                                        width: Theme.dimensionSize(14); height: Theme.dimensionSize(14)
                                        iconName: "app-window"; tone: "muted"
                                    }
                                }

                                // App name + title (scrolling viewport)
                                Item {
                                    id: appNameViewport
                                    Layout.fillWidth:      true
                                    Layout.minimumWidth:   Theme.dimensionSize(1)
                                    Layout.preferredHeight: Theme.dimensionSize(28)
                                    Layout.alignment:      Qt.AlignVCenter
                                    clip: true

                                    Text {
                                        id: appNameText
                                        y:    1
                                        text: modelData.appClass
                                        color: modelData.address === root.activeAddress
                                            ? Theme.islandAccent : Theme.fg
                                        font.family:    Theme.uiFont
                                        font.pixelSize: Theme.fontSize(9)
                                        font.weight:    Theme.fontWeightSemibold
                                        width: Math.max(implicitWidth, appNameViewport.width)
                                        elide: Text.ElideRight

                                        SequentialAnimation {
                                            running: appRowHover.hovered
                                                && appNameText.implicitWidth > appNameViewport.width
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: Theme.duration(500) }
                                            NumberAnimation {
                                                target: appNameText; property: "x"
                                                from: 0
                                                to:   -(appNameText.implicitWidth - appNameViewport.width)
                                                duration: Math.max(Theme.duration(900),
                                                    appNameText.implicitWidth * Theme.scrollAppRate)
                                                easing.type: Easing.InOutSine
                                            }
                                            PauseAnimation { duration: Theme.duration(500) }
                                            NumberAnimation {
                                                target: appNameText; property: "x"
                                                to: 0; duration: Theme.duration(350)
                                                easing.type: Easing.InOutSine
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.left:   parent.left
                                        anchors.right:  parent.right
                                        anchors.bottom: parent.bottom
                                        text:  modelData.title
                                        color: Theme.muted
                                        font.family:    Theme.uiFont
                                        font.pixelSize: Theme.fontSize(8)
                                        elide: Text.ElideRight
                                    }
                                }

                                // Close button
                                Rectangle {
                                    Layout.minimumWidth:   Theme.dimensionSize(28)
                                    Layout.preferredWidth: Theme.dimensionSize(28)
                                    Layout.maximumWidth:   Theme.dimensionSize(28)
                                    Layout.preferredHeight: Theme.dimensionSize(28)
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    radius: Theme.radiusSize(9)
                                    color: closeClientMouse.containsMouse
                                        ? Qt.rgba(1, 0.25, 0.35, Theme.opacityValue(0.28))
                                        : Qt.rgba(1, 0.25, 0.35, Theme.opacityValue(0.12))
                                    Behavior on color { ColorAnimation { duration: Theme.duration(100) } }
                                    Text {
                                        anchors.centerIn: parent
                                        text:  "×"
                                        color: closeClientMouse.containsMouse ? Theme.error : Theme.muted
                                        font.family:    Theme.uiFont
                                        font.pixelSize: Theme.fontSize(17)
                                        font.weight:    Theme.fontWeightMedium
                                    }
                                    MouseArea {
                                        id: closeClientMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.keyboardTargetChanged(modelData.address)
                                        onClicked: (e) => {
                                            e.accepted = true
                                            root.keyboardTargetChanged(modelData.address)
                                            root.clientCloseRequested(modelData.address)
                                        }
                                    }
                                }
                            }
                        }

                        // Empty workspace label
                        Text {
                            visible: modelData.clients.length === 0
                            text:    "(empty)"
                            color:   Theme.mutedDim
                            font.family:    Theme.uiFont
                            font.pixelSize: Theme.fontSize(9)
                            font.italic: true
                            Layout.leftMargin:   Theme.marginSize(8)
                            Layout.topMargin:    Theme.marginSize(4)
                            Layout.bottomMargin: Theme.marginSize(8)
                        }
                    }
                }
            }
        }
    }
}
