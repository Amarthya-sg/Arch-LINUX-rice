// PillMediaPopover.qml
// Pill display mode 4: compact media popover (112px tall).
// Shows album art thumbnail, title/artist, play/pause, progress bar,
// transport controls, and a volume shortcut.
import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Rectangle {
    id: root

    // ── Signals ───────────────────────────────────────────────────────────
    signal closeRequested()
    signal restartInactivity()

    // ── Appearance ────────────────────────────────────────────────────────
    anchors.fill: parent
    radius:       parent.radius
    color:        Theme.surface
    border.width: Theme.dimensionSize(1)
    border.color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.12))

    // ── Helper: format µs → m:ss ──────────────────────────────────────────
    function formatTime(us): string {
        const s = Math.max(0, Math.floor((Number(us) || 0) / 1000000))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    ColumnLayout {
        anchors.fill:         parent
        anchors.leftMargin:   Theme.marginSize(10)
        anchors.rightMargin:  Theme.marginSize(10)
        anchors.topMargin:    Theme.marginSize(7)
        anchors.bottomMargin: Theme.marginSize(7)
        spacing: Theme.spacingSize(5)

        // ── Top row: art + title/artist + play/pause + close ──────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSize(8)

            // Album art
            Rectangle {
                Layout.preferredWidth:  Theme.dimensionSize(35)
                Layout.preferredHeight: Theme.dimensionSize(35)
                radius: Theme.radiusSize(10)
                color:  Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.18))
                clip:   true

                Image {
                    anchors.fill: parent
                    source:       MediaService.artUrl
                    sourceSize:   Qt.size(128, 128)
                    fillMode:     Image.PreserveAspectCrop
                    visible:      status === Image.Ready
                    smooth:       true
                }
                SvgIcon {
                    anchors.centerIn: parent
                    visible:  MediaService.artUrl === ""
                    width:  Theme.dimensionSize(16); height: Theme.dimensionSize(16)
                    iconName: "music-2"; tone: "accent"
                }
            }

            // Title + artist
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSize(1)
                Text {
                    Layout.fillWidth: true
                    text:  MediaService.title || "Nothing playing"
                    color: Theme.fg
                    font.family:    Theme.uiFont
                    font.pixelSize: Theme.fontSize(11)
                    font.weight:    Theme.fontWeightBold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text:  MediaService.artist || MediaService.playerName
                    color: Theme.muted
                    font.family:    Theme.uiFont
                    font.pixelSize: Theme.fontSize(9)
                    elide: Text.ElideRight
                }
            }

            // Play / pause
            Rectangle {
                Layout.preferredWidth:  Theme.dimensionSize(30)
                Layout.preferredHeight: Theme.dimensionSize(30)
                radius: Theme.radiusSize(15)
                color:  mediaPlayMouse.containsMouse ? Theme.acc : Theme.surfaceRaised
                Behavior on color { ColorAnimation { duration: Theme.duration(120) } }
                SvgIcon {
                    anchors.centerIn: parent
                    width: Theme.dimensionSize(12); height: Theme.dimensionSize(12)
                    iconName: MediaService.playing ? "pause" : "play"
                    tone:     mediaPlayMouse.containsMouse ? "ink" : "fg"
                }
                MouseArea {
                    id: mediaPlayMouse
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: (e) => {
                        e.accepted = true
                        MediaService.toggle()
                        root.restartInactivity()
                    }
                }
            }

            // Close
            SvgIcon {
                width: Theme.dimensionSize(14); height: Theme.dimensionSize(14)
                Layout.alignment: Qt.AlignVCenter
                iconName: "x"; tone: mediaCloseMouse.containsMouse ? "fg" : "muted"
                MouseArea {
                    id: mediaCloseMouse; anchors.fill: parent; hoverEnabled: true
                    onClicked: (e) => { e.accepted = true; root.closeRequested() }
                }
            }
        }

        // ── Progress bar row ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSize(8)

            Text {
                text:  root.formatTime(MediaService.displayPosition)
                color: Theme.muted
                font.family:    Theme.uiFont
                font.pixelSize: Theme.fontSize(8)
            }

            Rectangle {
                id: mediaProgressTrack
                Layout.fillWidth: true; height: Theme.dimensionSize(4)
                radius: Theme.radiusSize(2); color: Theme.surfaceRaised

                Rectangle {
                    width:  parent.width * MediaService.progress
                    height: parent.height
                    radius: Theme.radiusSize(2)
                    color:  Theme.acc
                    Behavior on width { NumberAnimation { duration: Theme.duration(120) } }
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: (e) => {
                        e.accepted = true
                        MediaService.seekToRatio(e.x / width)
                        root.restartInactivity()
                    }
                }
            }

            Text {
                text:  root.formatTime(MediaService.length)
                color: Theme.muted
                font.family:    Theme.uiFont
                font.pixelSize: Theme.fontSize(8)
            }
        }

        // ── Transport controls ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingSize(28)

            SvgIcon {
                width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
                Layout.alignment: Qt.AlignVCenter
                iconName: "skip-back"
                tone: mediaPrevMouse.containsMouse ? "fg" : "muted"
                MouseArea {
                    id: mediaPrevMouse; anchors.fill: parent; hoverEnabled: true
                    onClicked: (e) => { e.accepted = true; MediaService.previous(); root.restartInactivity() }
                }
            }

            SvgIcon {
                width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
                Layout.alignment: Qt.AlignVCenter
                iconName: MediaService.playing ? "pause" : "play"; tone: "fg"
                MouseArea {
                    anchors.fill: parent
                    onClicked: (e) => { e.accepted = true; MediaService.toggle(); root.restartInactivity() }
                }
            }

            SvgIcon {
                width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
                Layout.alignment: Qt.AlignVCenter
                iconName: "skip-forward"
                tone: mediaNextMouse.containsMouse ? "fg" : "muted"
                MouseArea {
                    id: mediaNextMouse; anchors.fill: parent; hoverEnabled: true
                    onClicked: (e) => { e.accepted = true; MediaService.next(); root.restartInactivity() }
                }
            }

            // Volume shortcut → sound tab
            SvgIcon {
                width: Theme.dimensionSize(18); height: Theme.dimensionSize(18)
                Layout.alignment: Qt.AlignVCenter
                iconName: "volume-2"; tone: "muted"
                MouseArea {
                    anchors.fill: parent
                    onClicked: (e) => { e.accepted = true; ShellState.goTo("sound"); root.restartInactivity() }
                }
            }
        }
    }
}
