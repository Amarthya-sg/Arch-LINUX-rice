// ToggleSwitch.qml — pixel-perfect port of .sw from the HTML prototype.
// CSS spec: width 36px, height 20px, border-radius 99px.
//   OFF: background var(--line), knob var(--fg)
//   ON:  background var(--acc),  dark knob
// Knob translate animation: 0.2s ease-in-out (QML: InOutQuad ≈ CSS ease-in-out).
import QtQuick
import QtQuick.Controls
import "../core"

Switch {
    id: root

    // Allow callers to override the accent colour (default: Theme.acc).
    property color accent: Theme.acc

    implicitWidth:  Theme.dimensionSize(36)
    implicitHeight: Theme.dimensionSize(20)

    // Remove the default Switch indicator/label so we draw our own.
    indicator: Rectangle {
        implicitWidth:  Theme.dimensionSize(36)
        implicitHeight: Theme.dimensionSize(20)
        radius:         Theme.radiusSize(99)          // pill shape
        // OFF → translucent hairline border fill; ON → accent
        color:          root.checked ? root.accent : Theme.line
        // Smooth colour crossfade (matches CSS transition: .2s)
        Behavior on color { ColorAnimation { duration: Theme.duration(200) } }

        Rectangle {
            id: knob
            width:  Theme.dimensionSize(16)
            height: Theme.dimensionSize(16)
            radius: Theme.radiusSize(8)                // circle
            y:      2                // (20 - 16) / 2 = 2
            // OFF: sits at x=2; ON: slides to x=18 (36 - 16 - 2)
            x:      root.checked ? 18 : 2
            color:  root.checked ? Theme.islandBg : Theme.fg
            Behavior on x     { NumberAnimation { duration: Theme.duration(200); easing.type: Easing.InOutQuad } }
            Behavior on color { ColorAnimation   { duration: Theme.duration(200) } }
        }
    }

    // No visible label text.
    contentItem: Item {}

    // No default background chrome.
    background: Item {}
}
