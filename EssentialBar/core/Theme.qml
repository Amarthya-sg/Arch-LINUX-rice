pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Anchor CSS paths to the shell directory instead of the process working
    // directory. This also keeps parser arguments valid for desktop launches.
    readonly property string cssPath: Quickshell.shellPath("style.css")
    readonly property string cssParserPath: Quickshell.shellPath("core/parse_css_tokens.py")

    // CSS is authoritative. Typed properties below preserve the established
    // Theme.<name> API; arbitrary/new CSS tokens are available through
    // Theme.tokens.<camelCaseName> because QML object properties are fixed at load.
    property var tokens: ({})
    property string loadError: ""

    // Palette tokens (fallbacks keep the shell usable if Python/CSS loading fails).
    property color background:       tokens.background       !== undefined ? tokens.background       : "#0f0d0e"
    property color surface:          tokens.surface          !== undefined ? tokens.surface          : "#171415"
    property color surfaceRaised:    tokens.surfaceRaised    !== undefined ? tokens.surfaceRaised    : "#211c1e"
    property color surfaceHover:     tokens.surfaceHover     !== undefined ? tokens.surfaceHover     : "#2d2629"
    property color surfaceDisabled:  tokens.surfaceDisabled  !== undefined ? tokens.surfaceDisabled  : "#1a1617"
    property color outline:          tokens.outline          !== undefined ? tokens.outline          : "#ffffff1a"
    property color text:             tokens.text             !== undefined ? tokens.text             : "#f4eeee"
    property color textMuted:        tokens.textMuted        !== undefined ? tokens.textMuted        : "#a09598"
    property color primary:          tokens.primary          !== undefined ? tokens.primary          : "#e5334b"
    property color primaryStrong:    tokens.primaryStrong    !== undefined ? tokens.primaryStrong    : "#ff5a6e"
    property color success:          tokens.success          !== undefined ? tokens.success          : "#34c17b"
    property color warning:          tokens.warning          !== undefined ? tokens.warning          : "#e8ac3a"
    property color error:            tokens.error            !== undefined ? tokens.error            : "#f0505f"
    property color islandBg:         tokens.islandBg         !== undefined ? tokens.islandBg         : "#060505"
    property color islandAccent:     tokens.islandAccent     !== undefined ? tokens.islandAccent     : "#ee3a52"
    property color islandAccentStrong: tokens.islandAccentStrong !== undefined ? tokens.islandAccentStrong : "#ff8896"
    property color islandMuted:      tokens.islandMuted      !== undefined ? tokens.islandMuted      : "#b3a8ab"
    property color islandMutedDim:   tokens.islandMutedDim   !== undefined ? tokens.islandMutedDim   : "#6a5f62"
    property color workspaceActive:  tokens.workspaceActive  !== undefined ? tokens.workspaceActive  : "#e8384f"
    property color workspaceInactive: tokens.workspaceInactive !== undefined ? tokens.workspaceInactive : "#736869"
    property color batteryText:      tokens.batteryText      !== undefined ? tokens.batteryText      : "#cfc6c8"

    // Layout and typography tokens.
    property int radiusPanel:    tokens.radiusPanel    !== undefined ? tokens.radiusPanel    : 22
    property int radiusCard:     tokens.radiusCard     !== undefined ? tokens.radiusCard     : 14
    property int radiusControl:  tokens.radiusControl  !== undefined ? tokens.radiusControl  : 10
    property int radiusPillLg:   tokens.radiusPillLg   !== undefined ? tokens.radiusPillLg   : 32
    property int spaceXxs:       tokens.spaceXxs       !== undefined ? tokens.spaceXxs       : 3
    property int spaceXs:        tokens.spaceXs        !== undefined ? tokens.spaceXs        : 6
    property int spaceSm:        tokens.spaceSm        !== undefined ? tokens.spaceSm        : 10
    property int spaceMd:        tokens.spaceMd        !== undefined ? tokens.spaceMd        : 14
    property int spaceLg:        tokens.spaceLg        !== undefined ? tokens.spaceLg        : 18
    property int spaceXl:        tokens.spaceXl        !== undefined ? tokens.spaceXl        : 24
    property int textHero:       tokens.textHero       !== undefined ? tokens.textHero       : 38
    property int textDisplay:    tokens.textDisplay    !== undefined ? tokens.textDisplay    : 28
    property int textLarge:      tokens.textLarge      !== undefined ? tokens.textLarge      : 22
    property int textIcon:       tokens.textIcon       !== undefined ? tokens.textIcon       : 24
    property int textTitle:      tokens.textTitle      !== undefined ? tokens.textTitle      : 20
    property int textSection:    tokens.textSection    !== undefined ? tokens.textSection    : 15
    property int textBody:       tokens.textBody       !== undefined ? tokens.textBody       : 13
    property int textSmall:      tokens.textSmall      !== undefined ? tokens.textSmall      : 12
    property int textCaption:    tokens.textCaption    !== undefined ? tokens.textCaption    : 11
    property int textMicro:      tokens.textMicro      !== undefined ? tokens.textMicro      : 10
    property int controlHeight:       tokens.controlHeight       !== undefined ? tokens.controlHeight       : 40
    property int statusIconSize:      tokens.statusIconSize      !== undefined ? tokens.statusIconSize      : 18
    property int statusIconButtonSize: tokens.statusIconButtonSize !== undefined ? tokens.statusIconButtonSize : 28
    property int fontWeightLight:    tokens.fontWeightLight    !== undefined ? Number(tokens.fontWeightLight)    : Font.Light
    property int fontWeightRegular:  tokens.fontWeightRegular  !== undefined ? Number(tokens.fontWeightRegular)  : Font.Normal
    property int fontWeightMedium:   tokens.fontWeightMedium   !== undefined ? Number(tokens.fontWeightMedium)   : Font.Medium
    property int fontWeightSemibold: tokens.fontWeightSemibold !== undefined ? Number(tokens.fontWeightSemibold) : Font.DemiBold
    property int fontWeightBold:     tokens.fontWeightBold     !== undefined ? Number(tokens.fontWeightBold)     : Font.Bold
    property real scrollTitleRate: tokens.scrollTitleRate !== undefined ? Number(tokens.scrollTitleRate) : 45
    property real scrollAppRate:   tokens.scrollAppRate   !== undefined ? Number(tokens.scrollAppRate)   : 35

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

    property bool cssReloadPending: false

    function startCssReloadIfIdle(): void {
        if (!root.cssReloadPending || cssParser.running)
            return
        root.cssReloadPending = false
        cssParser.exec([
            "python3",
            root.cssParserPath,
            root.cssPath
        ])
    }

    // FileView.loaded and Component.completed can both occur during startup,
    // and file saves can arrive while parsing is still in progress. Queue one
    // follow-up parse instead of calling Process.exec() over an active parser.
    function scheduleCssReload(): void {
        root.cssReloadPending = true
        cssReloadDebounce.restart()
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
        path: root.cssPath
        watchChanges: true
        onLoaded: root.scheduleCssReload()
        onFileChanged: cssWatcher.reload()
        onLoadFailed: (error) => {
            root.loadError = "Unable to load " + root.cssPath
            console.warn("[Theme] CSS stylesheet load failed:", error)
        }
    }
    property Timer cssReloadDebounce: Timer {
        interval: 50
        repeat: false
        onTriggered: root.startCssReloadIfIdle()
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
            if (root.cssReloadPending)
                root.cssReloadDebounce.restart()
        }
    }

    // Do not rely solely on FileView's asynchronous loaded signal. A shell
    // started during a config reload can otherwise miss that first callback.
    Component.onCompleted: root.scheduleCssReload()
}
