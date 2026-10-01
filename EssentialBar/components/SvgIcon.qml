import QtQuick
import QtQuick.Effects
import "../core"

Item {
    id: root

    property string iconName: ""
    property string assetName: ""
    property string tone: "muted"
    property bool slash: false
    readonly property bool hasSlash: root.slash || ["wifi-off", "bluetooth-off", "bell-off", "coffee-off", "volume-x"].indexOf(iconName) >= 0
    readonly property string baseIconName: {
        const names = { "wifi-off": "wifi", "bluetooth-off": "bluetooth",
                        "bell-off": "bell", "coffee-off": "coffee", "volume-x": "volume-2" }
        return names[iconName] || iconName
    }
    readonly property string renderedAssetName: root.assetName !== "" ? root.assetName : root.baseIconName
    readonly property string iconTokenName: "icon" + root.renderedAssetName.split("-").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join("")
    readonly property string toneTokenName: "icon" + root.tone.charAt(0).toUpperCase() + root.tone.slice(1)
    readonly property color iconColor: Theme.tokens[root.iconTokenName] !== undefined
        ? Theme.tokens[root.iconTokenName]
        : Theme.tokens[root.toneTokenName] !== undefined ? Theme.tokens[root.toneTokenName]
        : root.tone === "accent" ? Theme.acc
        : root.tone === "fg" ? Theme.fg
        : root.tone === "ink" ? Theme.islandBg
        : root.tone === "success" ? Theme.success
        : root.tone === "warning" ? Theme.warning
        : root.tone === "error" ? Theme.error : Theme.muted
    readonly property color slashColor: {
        const key = root.iconTokenName + "Slash"
        return Theme.tokens[key] !== undefined ? Theme.tokens[key]
            : Theme.tokens.iconSlash !== undefined ? Theme.tokens.iconSlash : root.iconColor
    }
    implicitWidth: 24
    implicitHeight: 24

   // Shader effects don't run on the software backend, so show the SVG directly there.
   readonly property bool useEffect: GraphicsInfo.api !== GraphicsInfo.Software

   Image {
       id: iconSource
       anchors.fill: parent
       visible: !root.useEffect
       source: root.renderedAssetName === "" ? ""
           : Qt.resolvedUrl("../icons/" + (root.assetName !== "" ? root.assetName + ".svg" : root.baseIconName + "-" + root.tone + ".svg"))
       sourceSize: Qt.size(Math.max(1, root.width * 2), Math.max(1, root.height * 2))
       fillMode: Image.PreserveAspectFit
   }
   MultiEffect {
       anchors.fill: parent
       visible: root.useEffect
       source: iconSource
       colorization: 1
       colorizationColor: root.iconColor
   }
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(2, root.width * 0.09)
        height: root.height * 0.92
        radius: width / 2
        rotation: -45
        color: root.slashColor
        visible: root.hasSlash
    }
}
