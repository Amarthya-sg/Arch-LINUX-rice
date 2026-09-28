pragma Singleton
import QtQuick

// Runtime bridge for the design tokens in ../style.css.
QtObject {
    readonly property color background: "#0a0a0b"
    readonly property color surface: "#141517"
    readonly property color surfaceRaised: "#1c1e21"
    readonly property color surfaceHigh: surfaceRaised
    readonly property color surfaceHover: "#25272b"
    readonly property color outline: "#2c2e33"
    readonly property color outlineSoft: "#1f2124"
    readonly property color text: "#eceeef"
    readonly property color muted: "#8d9096"
    readonly property color mutedDim: "#5f6268"
    readonly property color primary: "#ff9f0a"
    readonly property color primaryStrong: "#ffb340"
    readonly property color success: "#5fd576"
    readonly property color warning: "#ffcf4d"
    readonly property color error: "#ff6b5f"
    readonly property color islandAccent: primary
    readonly property color islandAccentStrong: primaryStrong
    readonly property color islandMuted: muted
    readonly property color islandMutedDim: mutedDim
    readonly property int panelRadius: 26
    readonly property int radius: 18
    readonly property int controlRadius: 12
    readonly property int smallRadius: 10
    readonly property int spaceXs: 6
    readonly property int space: 10
    readonly property int spaceMd: 14
    readonly property int spaceLg: 18
    readonly property int spaceXl: 20
    readonly property int controlHeight: 32
    readonly property string uiFont: "Noto Sans"
    readonly property string iconFont: "Noto Sans Mono"
}
