import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import "core"

Item {
    id: ti
    required property var modelData
    readonly property var hiddenIds: ["nm-applet", "blueman", "udiskie"]
    visible: !hiddenIds.some(h => String(modelData.id).toLowerCase().includes(h))
    readonly property bool passive: modelData.status === Status.Passive
    implicitWidth: 28; implicitHeight: 28
    opacity: passive ? 0.5 : (trayMouse.pressed ? 0.7 : 1)
    Behavior on opacity { NumberAnimation { duration: 80 } }

    property var  currentMenu: modelData.menu     // swapped when entering a submenu
    readonly property string tipText:
        (modelData.tooltipTitle !== "" ? modelData.tooltipTitle : modelData.title) || ""

    function openMenu() {
        tip.visible = false
        if (menuPopup.visible) { menuPopup.visible = false; return }
        currentMenu = modelData.menu
        menuPopup.visible = true
        leaveTimer.restart()
    }

    Image {
        anchors.centerIn: parent
        width: 18; height: 18
        source: ti.modelData.icon
        sourceSize: Qt.size(36, 36)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Rectangle {
        visible: ti.modelData.status === Status.NeedsAttention
        x: parent.width - 9; y: 3; width: 6; height: 6; radius: 3
        color: Theme.warning; antialiasing: true
    }

    // ── Tooltip ──────────────────────────────────────────────
    Timer {
        id: tipTimer
        interval: 400
        onTriggered: if (trayMouse.containsMouse && !menuPopup.visible && ti.tipText !== "")
                         tip.visible = true
    }

    PopupWindow {
        id: tip
        anchor.window: QsWindow.window
        anchor.item: ti
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        implicitWidth: tipLabel.implicitWidth + 20
        implicitHeight: tipLabel.implicitHeight + 12
        color: "transparent"
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: 10; antialiasing: true
            color: Theme.surfaceRaised
            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: ti.tipText
                color: Theme.text
                font.pixelSize: 12
            }
        }
    }

    // ── Themed menu ──────────────────────────────────────────
    PopupWindow {
        id: menuPopup
        anchor.window: QsWindow.window
        anchor.item: ti
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        implicitWidth: 210
        implicitHeight: menuCol.implicitHeight + 12
        color: "transparent"
        visible: false

        HyprlandFocusGrab {
            id: grab
            windows: [menuPopup]
            active: false
            onCleared: menuPopup.visible = false
        }
        Timer { id: grabTimer; interval: 80; onTriggered: grab.active = menuPopup.visible }
        onVisibleChanged: {
            if (visible) { grabTimer.start(); leaveTimer.stop() }
            else grab.active = false
        }

        // fallback: close if the pointer has been away from the menu for a while
        Timer { id: leaveTimer; interval: 1500; onTriggered: menuPopup.visible = false }
        HoverHandler {
            id: menuHover
            onHoveredChanged: if (hovered) leaveTimer.stop(); else leaveTimer.restart()
        }
        Shortcut { sequence: "Escape"; enabled: menuPopup.visible; onActivated: menuPopup.visible = false }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusPanel; antialiasing: true
            color: Theme.surfaceRaised

            QsMenuOpener { id: opener; menu: ti.currentMenu }

            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                // back row, only inside a submenu
                Rectangle {
                    visible: ti.currentMenu !== ti.modelData.menu
                    width: parent.width; height: visible ? 30 : 0
                    radius: Theme.radiusControl; antialiasing: true
                    color: backMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                        text: "‹  Back"; color: Theme.muted; font.pixelSize: 12
                    }
                    MouseArea {
                        id: backMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: ti.currentMenu = ti.modelData.menu
                    }
                }

                Repeater {
                    model: opener.children
                    Item {
                        id: row
                        required property var modelData
                        width: menuCol.width
                        height: modelData.isSeparator ? 9 : 30

                        Rectangle {          // separator
                            visible: row.modelData.isSeparator
                            anchors.centerIn: parent
                            width: parent.width - 16; height: 1
                            color: Theme.outline
                        }

                        Rectangle {          // entry
                            visible: !row.modelData.isSeparator
                            anchors.fill: parent
                            radius: Theme.radiusControl; antialiasing: true
                            color: rowMouse.containsMouse && row.modelData.enabled
                                   ? Theme.surfaceHover : "transparent"

                            Text {
                                id: check
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                                width: 14
                                text: row.modelData.checkState === Qt.Checked ? "✓" : ""
                                color: Theme.primary; font.pixelSize: 12
                            }
                            Image {
                                id: rowIcon
                                anchors { verticalCenter: parent.verticalCenter; left: check.right; leftMargin: 2 }
                                width: row.modelData.icon !== "" ? 16 : 0; height: 16
                                source: row.modelData.icon
                                sourceSize: Qt.size(32, 32)
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: rowIcon.right; leftMargin: rowIcon.width > 0 ? 8 : 4
                                    right: arrow.left; rightMargin: 6
                                }
                                text: row.modelData.text.replace(/&/g, "")
                                color: row.modelData.enabled ? Theme.text : Theme.muted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                id: arrow
                                anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 10 }
                                text: row.modelData.hasChildren ? "›" : ""
                                color: Theme.muted; font.pixelSize: 14
                            }

                            MouseArea {
                                id: rowMouse; anchors.fill: parent; hoverEnabled: true
                                enabled: row.modelData.enabled
                                onClicked: {
                                    if (row.modelData.hasChildren) {
                                        ti.currentMenu = row.modelData
                                    } else {
                                        row.modelData.triggered()
                                        menuPopup.visible = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Input ────────────────────────────────────────────────
    MouseArea {
        id: trayMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onEntered: tipTimer.restart()
        onExited:  { tipTimer.stop(); tip.visible = false }
        onClicked: function(mouse) {
            tip.visible = false
            if (mouse.button === Qt.LeftButton) {
                if (ti.modelData.hasMenu) ti.openMenu()
                else ti.modelData.activate()
            } else if (mouse.button === Qt.RightButton) {
                if (ti.modelData.hasMenu) ti.openMenu()
                else ti.modelData.secondaryActivate()
            } else {
                ti.modelData.secondaryActivate()
            }
        }
        onWheel: function(wheel) { ti.modelData.scroll(wheel.angleDelta.y, false) }
    }
}
