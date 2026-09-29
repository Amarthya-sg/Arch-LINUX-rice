import QtQuick
import Quickshell.Widgets

IconImage {
    id: root

    property string iconName: ""
    property string tone: "muted"

    source: iconName === "" ? ""
        : Qt.resolvedUrl("../icons/" + iconName + "-" + tone + ".svg")
}
