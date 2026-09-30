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

    // Palette tokens — defaults are the style.css fallback values.
    // applyCssTokens() overwrites each property directly after the parser runs,
    // which is the only reliable way to trigger QML property-change notifications.
    property color background:         "#0b111b"
    property color surface:            "#111a27"
    property color surfaceRaised:      "#192638"
    property color surfaceHover:       "#22344a"
    property color outline:            "#24ffffff"
    property color text:               "#eaf2fb"
    property color textMuted:          "#a0afc1"
    property color primary:            "#5bd6e8"
    property color primaryStrong:      "#8ce9f3"
    property color success:            "#57d7a4"
    property color warning:            "#f2c66d"
    property color error:              "#ff7c8c"
    property color islandBg:           "#060b12"
    property color islandAccent:       "#5bd6e8"
    property color islandAccentStrong: "#9beef3"
    property color islandMuted:        "#a9b7c8"
    property color islandMutedDim:     "#687c94"

    // Layout and typography tokens.
    property int  radiusPanel:         22
    property int  radiusCard:          14
    property int  radiusControl:       10
    property int  spaceXs:             6
    property int  spaceSm:             10
    property int  spaceMd:             14
    property int  spaceLg:             18
    property int  spaceXl:             24
    property int  textTitle:           22
    property int  textSection:         15
    property int  textBody:            13
    property int  textCaption:         11
    property int  controlHeight:       40
    property int  statusIconSize:      18
    property int  statusIconButtonSize: 28
    property int  fontWeightLight:     Font.Light
    property int  fontWeightRegular:   Font.Normal
    property int  fontWeightMedium:    Font.Medium
    property int  fontWeightSemibold:  Font.DemiBold
    property int  fontWeightBold:      Font.Bold
    property real scrollTitleRate:     45
    property real scrollAppRate:       35

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

            // Store the raw map for Theme.tokens.<name> and numericStyleValue().
            tokens = parsed

            // Explicitly assign each typed property so QML propagates the change
            // to all bindings. A plain `tokens = parsed` replacement breaks the
            // property color bindings that evaluated when tokens was still empty.
            if (parsed.background      !== undefined) background      = parsed.background
            if (parsed.surface         !== undefined) surface         = parsed.surface
            if (parsed.surfaceRaised   !== undefined) surfaceRaised   = parsed.surfaceRaised
            if (parsed.surfaceHover    !== undefined) surfaceHover    = parsed.surfaceHover
            if (parsed.outline         !== undefined) outline         = parsed.outline
            if (parsed.text            !== undefined) text            = parsed.text
            if (parsed.textMuted       !== undefined) textMuted       = parsed.textMuted
            if (parsed.primary         !== undefined) primary         = parsed.primary
            if (parsed.primaryStrong   !== undefined) primaryStrong   = parsed.primaryStrong
            if (parsed.success         !== undefined) success         = parsed.success
            if (parsed.warning         !== undefined) warning         = parsed.warning
            if (parsed.error           !== undefined) error           = parsed.error
            if (parsed.islandBg        !== undefined) islandBg        = parsed.islandBg
            if (parsed.islandAccent    !== undefined) islandAccent    = parsed.islandAccent
            if (parsed.islandAccentStrong !== undefined) islandAccentStrong = parsed.islandAccentStrong
            if (parsed.islandMuted     !== undefined) islandMuted     = parsed.islandMuted
            if (parsed.islandMutedDim  !== undefined) islandMutedDim  = parsed.islandMutedDim

            if (parsed.radiusPanel     !== undefined) radiusPanel     = parsed.radiusPanel
            if (parsed.radiusCard      !== undefined) radiusCard      = parsed.radiusCard
            if (parsed.radiusControl   !== undefined) radiusControl   = parsed.radiusControl
            if (parsed.spaceXs         !== undefined) spaceXs         = parsed.spaceXs
            if (parsed.spaceSm         !== undefined) spaceSm         = parsed.spaceSm
            if (parsed.spaceMd         !== undefined) spaceMd         = parsed.spaceMd
            if (parsed.spaceLg         !== undefined) spaceLg         = parsed.spaceLg
            if (parsed.spaceXl         !== undefined) spaceXl         = parsed.spaceXl
            if (parsed.textTitle       !== undefined) textTitle       = parsed.textTitle
            if (parsed.textSection     !== undefined) textSection     = parsed.textSection
            if (parsed.textBody        !== undefined) textBody        = parsed.textBody
            if (parsed.textCaption     !== undefined) textCaption     = parsed.textCaption
            if (parsed.controlHeight   !== undefined) controlHeight   = parsed.controlHeight
            if (parsed.statusIconSize  !== undefined) statusIconSize  = parsed.statusIconSize
            if (parsed.statusIconButtonSize !== undefined) statusIconButtonSize = parsed.statusIconButtonSize
            if (parsed.fontWeightLight    !== undefined) fontWeightLight    = Number(parsed.fontWeightLight)
            if (parsed.fontWeightRegular  !== undefined) fontWeightRegular  = Number(parsed.fontWeightRegular)
            if (parsed.fontWeightMedium   !== undefined) fontWeightMedium   = Number(parsed.fontWeightMedium)
            if (parsed.fontWeightSemibold !== undefined) fontWeightSemibold = Number(parsed.fontWeightSemibold)
            if (parsed.fontWeightBold     !== undefined) fontWeightBold     = Number(parsed.fontWeightBold)
            if (parsed.scrollTitleRate !== undefined) scrollTitleRate = Number(parsed.scrollTitleRate)
            if (parsed.scrollAppRate   !== undefined) scrollAppRate   = Number(parsed.scrollAppRate)

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
