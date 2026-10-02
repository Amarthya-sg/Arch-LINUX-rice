// PillNowPlaying.qml
// Now-playing section of the collapsed pill row.
// Shows animated EQ bars + scrolling track title when media is active.
import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: root

    // ── Sizing ─────────────────────────────────────────────────────────────
    // Visible only when MediaService.hasTrack; caller controls visibility.
    Layout.preferredWidth:  visible ? nowRow.implicitWidth + 16 : 0
    Layout.preferredHeight: Theme.dimensionSize(30)
    Layout.alignment:       Qt.AlignVCenter

    // ── Signal ─────────────────────────────────────────────────────────────
    signal mediaClicked()

    Row {
        id: nowRow
        anchors.centerIn: parent
        spacing: Theme.spacingSize(4)

        // ── Animated EQ bars ──────────────────────────────────────────────
        Row {
            spacing: Theme.spacingSize(2)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width:  Theme.dimensionSize(2)
                    height: Theme.dimensionSize(12)
                    radius: Theme.radiusSize(2)
                    color:  Theme.acc
                    anchors.bottom: parent.bottom

                    SequentialAnimation on height {
                        loops:   Animation.Infinite
                        running: MediaService.playing
                        PauseAnimation  { duration: [Theme.duration(0), Theme.duration(400), Theme.duration(750)][index] }
                        NumberAnimation { to: 12; duration: Theme.duration(500); easing.type: Easing.InOutSine }
                        NumberAnimation { to: 3;  duration: Theme.duration(500); easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        // ── Scrolling track title ─────────────────────────────────────────
        Item {
            id: pillTitleViewport
            width:  Theme.dimensionSize(120)
            height: Theme.dimensionSize(18)
            clip:   true
            anchors.verticalCenter: parent.verticalCenter

            Text {
                id: pillTitleText
                y:    1
                text: MediaService.title
                color: Theme.fg
                font.family:    Theme.uiFont
                font.pixelSize: Theme.fontSize(11)
                width: Math.max(implicitWidth, pillTitleViewport.width)
                elide: Text.ElideNone

                SequentialAnimation {
                    running: MediaService.hasTrack && MediaService.playing
                             && pillTitleText.implicitWidth > pillTitleViewport.width
                    loops:   Animation.Infinite
                    PauseAnimation { duration: Theme.duration(800) }
                    NumberAnimation {
                        target:   pillTitleText
                        property: "x"
                        from:     0
                        to:       -(pillTitleText.implicitWidth - pillTitleViewport.width)
                        duration: Math.max(Theme.duration(1800), pillTitleText.implicitWidth * Theme.scrollTitleRate)
                        easing.type: Easing.Linear
                    }
                    PauseAnimation { duration: Theme.duration(800) }
                    NumberAnimation {
                        target:   pillTitleText
                        property: "x"
                        to:       0
                        duration: Theme.duration(450)
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    // Whole area is clickable to open the media popover.
    MouseArea {
        anchors.fill: parent
        onClicked: (e) => { e.accepted = true; root.mediaClicked() }
    }
}
