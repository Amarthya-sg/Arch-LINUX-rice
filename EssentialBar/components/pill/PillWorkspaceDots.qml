// PillWorkspaceDots.qml
// Workspace indicator dots in the collapsed pill row.
// Active workspace shown as a wide pill; inactive as small circles.
import QtQuick
import QtQuick.Layouts
import "../../core"

Row {
    id: root

    // ── Props injected by UnifiedPill ─────────────────────────────────────
    property var workspaces:       []   // [{id, name, clients}]
    property int activeWorkspaceId: 1

    // ── Signal ────────────────────────────────────────────────────────────
    signal workspaceClicked(int workspaceId)

    spacing: Theme.spacingSize(5)

    Repeater {
        model: root.workspaces.length > 0 ? root.workspaces : [{ id: root.activeWorkspaceId }]
        delegate: Rectangle {
            readonly property int wsId: Number(modelData?.id || (index + 1))

            width:  wsId === root.activeWorkspaceId ? Theme.dimensionSize(16) : Theme.dimensionSize(8)
            height: Theme.dimensionSize(8)
            radius: Theme.radiusSize(99)
            color:  wsId === root.activeWorkspaceId ? Theme.workspaceActive : Theme.workspaceInactive

            Behavior on width { NumberAnimation { duration: Theme.duration(200); easing.type: Easing.InOutQuad } }

            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked: (e) => { e.accepted = true; root.workspaceClicked(wsId) }
            }
        }
    }
}
