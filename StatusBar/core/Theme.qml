pragma Singleton
import QtQuick

// Runtime bridge for the design tokens in ../style.css.
QtObject {
    // HTML prototype tokens: --bg, --fg, --acc, --s, --s2, --mut, --line.
    readonly property color background: "#0e0e10"
    readonly property color surface: "#18181b"
    readonly property color surfaceRaised: "#232327"
    readonly property color surfaceHigh: surfaceRaised
    readonly property color surfaceHover: "#2d2d32"
    readonly property color outline: "#14ffffff"
    readonly property color outlineSoft: "#0dffffff"
    readonly property color text: "#eeeeee"
    readonly property color muted: "#8f8f96"
    readonly property color mutedDim: "#6b6b73"
    readonly property color primary: "#ff9f0a"
    readonly property color primaryStrong: "#ffb020"
    readonly property color success: "#5fd576"
    readonly property color warning: "#ffcf4d"
    readonly property color error: "#ff6b5f"
    readonly property color islandAccent: primary
    readonly property color islandAccentStrong: primaryStrong
    readonly property color islandMuted: muted
    readonly property color islandMutedDim: mutedDim
    readonly property int panelRadius: 22
    readonly property int radius: 14
    readonly property int controlRadius: 10
    readonly property int smallRadius: 8
    readonly property int spaceXs: 6
    readonly property int space: 10
    readonly property int spaceMd: 14
    readonly property int spaceLg: 18
    readonly property int spaceXl: 20
    readonly property int controlHeight: 40
    readonly property string uiFont: "Inter"

    // Explicit prototype names used by ported components.
    readonly property color bg: background
    readonly property color fg: text
    readonly property color acc: primary
    readonly property color s: surface
    readonly property color s2: surfaceRaised
    readonly property color mut: muted
    readonly property color line: outline
    readonly property int radiusPill: 19
    readonly property int radiusPanel: 22
    readonly property int radiusCard: 14
    readonly property int radiusButton: 10
}
