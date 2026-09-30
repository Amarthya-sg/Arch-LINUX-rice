pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // CSS is authoritative. Typed properties below preserve the established
    // Theme.<name> API; arbitrary/new CSS tokens are available through
    // Theme.tokens.<camelCaseName> because QML object properties are fixed at load.
    property var tokens: ({})
    property string loadError: ""

    // Palette tokens (fallbacks keep the shell usable if Python/CSS loading fails).
    property color background: tokens.background !== undefined ? tokens.background : "#0b111b"
    property color surface: tokens.surface !== undefined ? tokens.surface : "#111a27"
    property color surfaceRaised: tokens.surfaceRaised !== undefined ? tokens.surfaceRaised : "#192638"
    property color surfaceHover: tokens.surfaceHover !== undefined ? tokens.surfaceHover : "#22344a"
    property color outline: tokens.outline !== undefined ? tokens.outline : "#24ffffff"
    property color text: tokens.text !== undefined ? tokens.text : "#eaf2fb"
    property color textMuted: tokens.textMuted !== undefined ? tokens.textMuted : "#a0afc1"
    property color primary: tokens.primary !== undefined ? tokens.primary : "#5bd6e8"
    property color primaryStrong: tokens.primaryStrong !== undefined ? tokens.primaryStrong : "#8ce9f3"
    property color success: tokens.success !== undefined ? tokens.success : "#57d7a4"
    property color warning: tokens.warning !== undefined ? tokens.warning : "#f2c66d"
    property color error: tokens.error !== undefined ? tokens.error : "#ff7c8c"
    property color islandBg: tokens.islandBg !== undefined ? tokens.islandBg : "#060b12"
    property color islandAccent: tokens.islandAccent !== undefined ? tokens.islandAccent : "#5bd6e8"
    property color islandAccentStrong: tokens.islandAccentStrong !== undefined ? tokens.islandAccentStrong : "#9beef3"
    property color islandMuted: tokens.islandMuted !== undefined ? tokens.islandMuted : "#a9b7c8"
    property color islandMutedDim: tokens.islandMutedDim !== undefined ? tokens.islandMutedDim : "#687c94"

    // Layout and typography tokens.
    property int radiusPanel: tokens.radiusPanel !== undefined ? tokens.radiusPanel : 22
    property int radiusCard: tokens.radiusCard !== undefined ? tokens.radiusCard : 14
    property int radiusControl: tokens.radiusControl !== undefined ? tokens.radiusControl : 10
    property int spaceXs: tokens.spaceXs !== undefined ? tokens.spaceXs : 6
    property int spaceSm: tokens.spaceSm !== undefined ? tokens.spaceSm : 10
    property int spaceMd: tokens.spaceMd !== undefined ? tokens.spaceMd : 14
    property int spaceLg: tokens.spaceLg !== undefined ? tokens.spaceLg : 18
    property int spaceXl: tokens.spaceXl !== undefined ? tokens.spaceXl : 24
    property int textTitle: tokens.textTitle !== undefined ? tokens.textTitle : 22
    property int textSection: tokens.textSection !== undefined ? tokens.textSection : 15
    property int textBody: tokens.textBody !== undefined ? tokens.textBody : 13
    property int textCaption: tokens.textCaption !== undefined ? tokens.textCaption : 11
    property int controlHeight: tokens.controlHeight !== undefined ? tokens.controlHeight : 40
    property int statusIconSize: tokens.statusIconSize !== undefined ? tokens.statusIconSize : 18
    property int statusIconButtonSize: tokens.statusIconButtonSize !== undefined ? tokens.statusIconButtonSize : 28
    property int fontWeightLight: tokens.fontWeightLight !== undefined ? Number(tokens.fontWeightLight) : Font.Light
    property int fontWeightRegular: tokens.fontWeightRegular !== undefined ? Number(tokens.fontWeightRegular) : Font.Normal
    property int fontWeightMedium: tokens.fontWeightMedium !== undefined ? Number(tokens.fontWeightMedium) : Font.Medium
    property int fontWeightSemibold: tokens.fontWeightSemibold !== undefined ? Number(tokens.fontWeightSemibold) : Font.DemiBold
    property int fontWeightBold: tokens.fontWeightBold !== undefined ? Number(tokens.fontWeightBold) : Font.Bold
    property real scrollTitleRate: tokens.scrollTitleRate !== undefined ? Number(tokens.scrollTitleRate) : 45
    property real scrollAppRate: tokens.scrollAppRate !== undefined ? Number(tokens.scrollAppRate) : 35

    // Non-token compatibility values retained for existing components.
    readonly property color surfaceHigh: surfaceRaised
    readonly property color outlineSoft: "#0dffffff"
    readonly property color mutedDim: islandMutedDim
    readonly property color primaryColor: primary
    readonly property color islandAccentColor: islandAccent
    readonly property string uiFont: tokens.fontFamily !== undefined ? String(tokens.fontFamily) : "Inter"
    readonly property int smallRadius: 8
    readonly property int radiusPill: 19

    // Legacy aliases used throughout the existing UI.
    readonly property color bg: background
    readonly property color fg: text
    readonly property color acc: primary
    readonly property color s: surface
    readonly property color s2: surfaceRaised
    readonly property color mut: textMuted
    readonly property color muted: textMuted
    readonly property color line: outline
    readonly property int radius: radiusCard
    readonly property int radiusButton: radiusControl
    readonly property int controlRadius: radiusControl
    readonly property int panelRadius: radiusPanel
    readonly property int space: spaceSm

    // Look up per-baseline CSS values while preserving safe defaults during startup.
    // Numeric suffixes use their digits only; negative values use the "Neg" prefix.
    function numericStyleValue(group: string, baseline: real): real {
        const numeric = Number(baseline)
        const suffix = (numeric < 0 ? "Neg" : "") + String(Math.abs(numeric)).replace(".", "")
        const candidate = root.tokens[group + suffix]
        if (candidate === undefined || candidate === null || candidate === "")
            return numeric
        const resolved = Number(candidate)
        return isNaN(resolved) ? numeric : resolved
    }

    function fontSize(value: real): real { return numericStyleValue("fontSize", value) }
    function spacingSize(value: real): real { return numericStyleValue("spacing", value) }
    function radiusSize(value: real): real { return numericStyleValue("radius", value) }
    function dimensionSize(value: real): real { return numericStyleValue("size", value) }
    function marginSize(value: real): real { return numericStyleValue("margin", value) }
    function paddingSize(value: real): real { return numericStyleValue("padding", value) }
    function duration(value: real): real { return numericStyleValue("duration", value) }
    function opacityValue(value: real): real { return numericStyleValue("opacity", value) }
    function letterSpacingValue(value: real): real { return numericStyleValue("letterSpacing", value) }

    function reloadCssTokens(): void {
        cssParser.exec([
            "python3",
            Quickshell.shellPath("core/parse_css_tokens.py"),
            Quickshell.shellPath("style.css")
        ])
    }

    function applyCssTokens(output: string): void {
        try {
            const parsed = JSON.parse(output.trim())
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)
                    || Object.keys(parsed).length === 0)
                throw new Error("parser returned no token object")
            tokens = parsed
            loadError = ""
        } catch (error) {
            loadError = String(error)
            console.warn("[Theme] CSS token output was invalid:", loadError)
        }
    }

    property FileView cssWatcher: FileView {
        id: cssWatcher
        path: Quickshell.shellPath("style.css")
        watchChanges: true
        onLoaded: root.reloadCssTokens()
        onFileChanged: cssWatcher.reload()
    }

    property Process cssParser: Process {
        id: cssParser
        command: []
        stdout: StdioCollector {
            onStreamFinished: root.applyCssTokens(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) console.warn("[Theme] parser stderr:", text.trim())
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.loadError = "CSS token parser exited with code " + code
                console.warn("[Theme]", root.loadError)
            }
        }
    }
}
