import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "core"
import "components"
import "panels"
import "services"

Scope {
    id: rootScope
    // ── Workspace / client state (polled via hyprctl) ────────────────────
    property var workspaceData:      []   // all workspaces incl. scratchpad — used by popup
    property var numberedWorkspaces: []   // id > 0 only — used by pill numbers
    property var allClients:         []   // flat list every running client
    property int activeWorkspaceId:  1
    property string activeAddress:   ""
    property var rawWorkspaces:      []
    property var rawClients:         []
    readonly property var batteryDevice: UPower.displayDevice
    readonly property int batteryPercent: batteryDevice
        ? Math.max(0, Math.min(100, Math.round((Number(batteryDevice.percentage) || 0) * 100))) : -1
    readonly property bool batteryCharging: batteryDevice && batteryDevice.state === 1

    function batteryIconName(percent, charging): string {
        if (charging) return "battery-charging"
        if (percent <= 15) return "battery-low"
        if (percent < 40) return "battery-medium"
        return "battery-full"
    }
    function batteryIconTone(percent, charging): string {
        if (charging) return "success"
        if (percent <= 15) return "error"
        if (percent < 40) return "warning"
        return "muted"
    }

    // ── Icon resolution (port of illogical-impulse's guessIcon cascade) ─
    property var iconSubstitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code":             "visual-studio-code",
        "code":             "visual-studio-code",
        "gnome-tweaks":     "org.gnome.tweaks",
        "pavucontrol-qt":   "pavucontrol",
        "footclient":       "foot",
        "kiro":             "kiro",
        "Kiro":             "kiro"
    })
    property var iconRegexSubstitutions: [
        { regex: /^steam_app_(\d+)$/, replace: "steam_icon_$1" },
        { regex: /Minecraft.*/,       replace: "minecraft"      },
        { regex: /.*polkit.*/,        replace: "system-lock-screen" },
        { regex: /gcr.prompter/,      replace: "system-lock-screen" }
    ]

    function iconExists(name) {
        if (!name || name.length === 0) return false
        var p = Quickshell.iconPath(name, true)
        return p.length > 0 && !p.includes("image-missing")
    }
    function reverseDomainAppName(s) { return s.split(".").slice(-1)[0] }
    function kebabNorm(s)            { return s.toLowerCase().replace(/\s+/g, "-") }
    function underscoreKebab(s)      { return s.toLowerCase().replace(/_/g, "-") }

    function guessIconName(cls) {
        if (!cls || cls.length === 0) return "application-x-executable"
        var entry = DesktopEntries.byId(cls)
        if (entry) return entry.icon
        if (iconSubstitutions[cls])               return iconSubstitutions[cls]
        if (iconSubstitutions[cls.toLowerCase()]) return iconSubstitutions[cls.toLowerCase()]
        for (var i = 0; i < iconRegexSubstitutions.length; i++) {
            var sub = iconRegexSubstitutions[i]
            var r = cls.replace(sub.regex, sub.replace)
            if (r !== cls) return r
        }
        if (iconExists(cls))                           return cls
        var lower = cls.toLowerCase()
        if (iconExists(lower))                         return lower
        var dn = reverseDomainAppName(cls)
        if (iconExists(dn))                            return dn
        var ldn = dn.toLowerCase()
        if (iconExists(ldn))                           return ldn
        if (iconExists(kebabNorm(cls)))                return kebabNorm(cls)
        if (iconExists(underscoreKebab(cls)))          return underscoreKebab(cls)
        var h = DesktopEntries.heuristicLookup(cls)
        if (h) return h.icon
        return "application-x-executable"
    }
    function iconPathForClass(cls) {
        return Quickshell.iconPath(guessIconName(cls), true)
    }

    // ── hyprctl polling chain ────────────────────────────────────────────
    function refresh() { if (!activeWindowProc.running) activeWindowProc.running = true }

    Process {
        id: activeWindowProc
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { activeAddress = JSON.parse(text).address || "" } catch(e) { activeAddress = "" }
                if (!activeWsProc.running) activeWsProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                activeAddress = ""
                if (!activeWsProc.running) activeWsProc.running = true
            }
        }
    }
    Process {
        id: activeWsProc
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { activeWorkspaceId = JSON.parse(text).id } catch(e) {}
                if (!workspacesProc.running) workspacesProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !workspacesProc.running) workspacesProc.running = true
        }
    }
    Process {
        id: workspacesProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { rawWorkspaces = JSON.parse(text) } catch(e) { rawWorkspaces = [] }
                if (!clientsProc.running) clientsProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                rawWorkspaces = []
                if (!clientsProc.running) clientsProc.running = true
            }
        }
    }
    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { rawClients = JSON.parse(text) } catch(e) { rawClients = [] }
                rebuild()
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                rawClients = []
                rebuild()
            }
        }
    }

    function rebuild() {
        var byWs = {}
        for (var i = 0; i < rawWorkspaces.length; i++) {
            var w = rawWorkspaces[i]
            byWs[w.id] = { id: w.id, name: w.name, clients: [] }
        }
        var flat = []
        for (var j = 0; j < rawClients.length; j++) {
            var c = rawClients[j]
            var wsId = (c.workspace && c.workspace.id !== undefined) ? c.workspace.id : -9999
            if (!byWs[wsId]) byWs[wsId] = { id: wsId, name: c.workspace ? c.workspace.name : "?", clients: [] }
            var cls = c["class"] || c.initialClass || "unknown"
            var entry = {
                appClass:  cls,
                title:     c.title || c.initialTitle || "",
                pid:       c.pid,
                address:   c.address || "",
                iconPath:  iconPathForClass(cls)
            }
            byWs[wsId].clients.push(entry)
            flat.push(entry)
        }
        var list = Object.keys(byWs).map(function(k) { return byWs[k] })
        list.sort(function(a, b) { return a.id - b.id })
        workspaceData      = list
        numberedWorkspaces = list.filter(function(w) { return w.id > 0 })
        allClients         = flat
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: refresh()
    }

    // ── Dispatch (handles both legacy and Lua-style Hyprland IPC) ───────
    Process {
        id: dispatchProc
        property string pendingLuaExpr: ""
        property bool   triedLua:       false
        onExited: (code, status) => {
            // Do not depend on a particular Hyprland error string. If the
            // legacy dispatcher is rejected, retry once with the Lua form.
            if (code !== 0 && !dispatchProc.triedLua) {
                dispatchProc.triedLua = true
                dispatchProc.command  = ["hyprctl", "dispatch", dispatchProc.pendingLuaExpr]
                dispatchProc.running  = true
            } else {
                refresh()
            }
        }
    }
    function hyprDispatch(legacyArgs, luaExpr) {
        dispatchProc.pendingLuaExpr = luaExpr
        dispatchProc.triedLua       = false
        dispatchProc.command        = ["hyprctl", "dispatch"].concat(legacyArgs)
        dispatchProc.running        = true
    }
    function killClient(address) {
        if (!address) return
        hyprDispatch(["closewindow", "address:" + address],
                     "hl.dsp.window.close({ window = \"address:" + address + "\" })")
    }
    function switchWorkspace(id) {
        hyprDispatch(["workspace", String(id)],
                     "hl.dsp.focus({ workspace = \"" + id + "\" })")
    }

    // ── Tooltip state ────────────────────────────────────────────────────
    property bool   tooltipVisible:  false
    property string tooltipText:     ""
    property real   tooltipAnchorX:  0

    // ── Clock/calendar popup state ──────────────────────────────────────
    property bool calendarPopupOpen: false
    property var calendarMonthStart: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    readonly property int calendarPopupWidth: island.mediaPanelOpen
        ? Math.min(660, Math.max(304, bar.width - 16)) : 304
    readonly property int calendarPopupHeight: island.mediaPanelOpen ? 360 : 336
    readonly property int mediaHoverCardWidth: Math.min(460, Math.max(0, bar.width - 16))
    readonly property int clockPopupWidth: island.mediaPanelOpen ? calendarPopupWidth
        : island.mediaInfoVisible && MediaService.hasTrack ? mediaHoverCardWidth : calendarPopupWidth
    readonly property int clockPopupHeight: island.mediaPanelOpen ? calendarPopupHeight
        : island.mediaInfoVisible && MediaService.hasTrack ? 148 : 336

    function toggleCalendar() {
        if (!calendarPopupOpen) {
            const now = new Date()
            calendarMonthStart = new Date(now.getFullYear(), now.getMonth(), 1)
        }
        calendarPopupOpen = !calendarPopupOpen
    }
    function shiftCalendarMonth(delta) {
        calendarMonthStart = new Date(calendarMonthStart.getFullYear(),
                                       calendarMonthStart.getMonth() + delta, 1)
    }
    function calendarDateAt(index) {
        const firstDay = calendarMonthStart.getDay()
        return new Date(calendarMonthStart.getFullYear(), calendarMonthStart.getMonth(),
                        index - firstDay + 1)
    }
    function isCalendarMonthDate(date) {
        return date.getMonth() === calendarMonthStart.getMonth()
            && date.getFullYear() === calendarMonthStart.getFullYear()
    }
    function isCalendarToday(date) {
        const today = new Date()
        return date.getDate() === today.getDate()
            && date.getMonth() === today.getMonth()
            && date.getFullYear() === today.getFullYear()
    }
    function formatMediaTime(microseconds) {
        const totalSeconds = Math.floor(Math.max(0, Number(microseconds) || 0) / 1000000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    // ── activateQuick (status icons → open their control-panel tab) ──────
    function activateQuick(tab) {
        if (tab === "caffeine") { CaffeineService.toggle(); return }
        ShellState.open(tab)
    }

    function launchPowerMenu() {
        powerMenuProcess.command = ["bash", "-c", "helper=\"$HOME/.local/lib/hyde/logoutlaunch.sh\"; if [ -x \"$helper\" ]; then exec bash \"$helper\"; elif command -v wlogout >/dev/null 2>&1; then exec wlogout; else echo 'No power-menu helper found (install wlogout or HyDE logout scripts).' >&2; exit 127; fi"]
        powerMenuProcess.running = true
    }
    Process {
        id: powerMenuProcess
        running: false
    }

    property int pendingUpdates: 0
    property string updateTooltip: "Checking for package updates…"
    property real quickPopupAnchorX: 0
    function openQuickAction(tab, sourceItem) {
        const point = sourceItem.mapToItem(bar.contentItem,
                                           sourceItem.width / 2, sourceItem.height)
        quickPopupAnchorX = point.x
        ShellState.open(tab)
    }
    function refreshUpdateStatus() {
        if (!updateStatusProcess.running) updateStatusProcess.running = true
    }
    function launchSystemUpdater() {
        updateActionProcess.command = ["bash", "-c", "helper=\"$HOME/.local/lib/hyde/system.update.py\"; if [ -f \"$helper\" ]; then exec python3 \"$helper\" up; else echo 'HyDE system update helper is not installed.' >&2; exit 127; fi"]
        updateActionProcess.running = true
    }
    Process {
        id: updateStatusProcess
        property int lastExitCode: 1
        command: ["bash", "-c", "helper=\"$HOME/.local/lib/hyde/system.update.py\"; if [ -f \"$helper\" ]; then exec python3 \"$helper\" status; else printf '{\"text\":\"\",\"tooltip\":\"System updater unavailable (HyDE update helper not installed)\"}'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    const match = String(data.text || "").match(/[0-9]+/)
                    rootScope.pendingUpdates = match ? Number(match[0]) : 0
                    rootScope.updateTooltip = data.tooltip || "System update status unavailable"
                } catch (error) {
                    rootScope.updateTooltip = "Could not read system update status"
                }
            }
        }
        onExited: (code, status) => {
            lastExitCode = code
            if (code !== 0) rootScope.updateTooltip = "System update helper failed or is unavailable"
        }
    }
    Process {
        id: updateActionProcess
        running: false
        onExited: (code, status) => {
            if (code !== 0) rootScope.updateTooltip = "Update integration unavailable (expected HyDE helper)"
            rootScope.refreshUpdateStatus()
        }
    }
    Timer {
        interval: 600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: rootScope.refreshUpdateStatus()
    }

    // ════════════════════════════════════════════════════════════════════
    // BAR
    // ════════════════════════════════════════════════════════════════════
    PanelWindow {
        id: bar
        anchors.top: true
        anchors.left: true
        anchors.right: true
        // The media/notification takeover expands inside this layer-shell
        // window. The surface may grow, but applications reserve only the
        // compact 44px bar zone, so the expanded part overlays them.
        implicitHeight: Math.max(44, unifiedPill.implicitHeight)
        exclusiveZone: 44
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        // The Wi-Fi password editor is hosted inside this layer surface.
        // Request on-demand keyboard focus while the control center is open;
        // without this, the TextField can focus visually but never receives
        // keyboard events from the compositor.
        WlrLayershell.keyboardFocus: unifiedPill.controlPopupVisible
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // HyprlandFocusGrab only sees clicks outside the whole bar window.
        // While media is expanded, catch clicks in the bar's empty space so
        // the media surface behaves like a true pill-level popover.
        MouseArea {
            id: mediaBarDismissArea
            anchors.fill: parent
            visible: unifiedPill.mediaPopupVisible || unifiedPill.controlPopupVisible
                || unifiedPill.windowListOpen
            z: 0
            onClicked: {
                unifiedPill.mediaExpanded = false
                unifiedPill.mediaAutoPopup = false
                ShellState.popupOpen = false
                unifiedPill.windowListOpen = false
            }
        }

        // Unified ChillPill-style capsule. Workspace state and dispatch stay
        // backed by SAT's existing hyprctl polling implementation.
        UnifiedPill {
            id: unifiedPill
            z: 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            workspaces: rootScope.numberedWorkspaces
            workspaceData: rootScope.workspaceData
            activeAddress: rootScope.activeAddress
            activeWorkspaceId: rootScope.activeWorkspaceId
            pendingUpdates: rootScope.pendingUpdates
            updateTooltip: rootScope.updateTooltip
            onOpenControlCenter: (tab) => {
                const point = unifiedPill.mapToItem(bar.contentItem,
                    unifiedPill.width / 2, unifiedPill.height)
                rootScope.quickPopupAnchorX = point.x
                ShellState.open(tab)
            }
            onWorkspaceClicked: (workspaceId) => rootScope.switchWorkspace(workspaceId)
            onHamburgerClicked: {
                ShellState.popupOpen = false
                unifiedPill.windowListOpen = !unifiedPill.windowListOpen
            }
            onTimeClicked: rootScope.toggleCalendar()
            onPowerClicked: rootScope.launchPowerMenu()
            onUpdatesClicked: rootScope.launchSystemUpdater()
            onClientCloseRequested: (address) => rootScope.killClient(address)
        }

        // Treat the expanded media surface as a transient popover. The
        // focus grab keeps the pill interactive but clears it when the user
        // clicks or focuses anything outside the bar.
        HyprlandFocusGrab {
            windows: [bar]
            active: unifiedPill.mediaPopupVisible || unifiedPill.controlPopupVisible
                || unifiedPill.windowListOpen
            onCleared: {
                unifiedPill.mediaExpanded = false
                unifiedPill.mediaAutoPopup = false
                ShellState.popupOpen = false
                unifiedPill.windowListOpen = false
            }
        }

        // ── Workspace pill — far left ─────────────────────────────────
        Rectangle {
            id: workspacePill
            visible: false
            height: 34
            width: pillRow.implicitWidth + 18
            anchors.left:           parent.left
            anchors.leftMargin:     8
            anchors.verticalCenter: parent.verticalCenter
            radius: height / 2
            color: "#181825"
            border.width: 1
            border.color: "#313244"

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 8

                // ── Hamburger → opens window-list popup ──────────────
                Item {
                    id: hamburgerBtn
                    width: 20; height: 20
                    Layout.alignment: Qt.AlignVCenter

                    SvgIcon {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        iconName: "menu"
                        tone: hamburgerMA.containsMouse ? "accent" : "muted"
                    }
                    MouseArea {
                        id: hamburgerMA
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => { m.accepted = true; windowPopupOpen = !windowPopupOpen }
                    }
                }

                // Separator
                Rectangle {
                    width: 1; height: 14
                    color: "#313244"
                    Layout.alignment: Qt.AlignVCenter
                    visible: numberedWorkspaces.length > 0
                }

                // ── Workspace number badges ───────────────────────────
                Row {
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: numberedWorkspaces
                        delegate: Item {
                            required property var modelData
                            width: 20; height: 20

                            Rectangle {
                                anchors.centerIn: parent
                                visible: modelData.id === activeWorkspaceId
                                width: 20; height: 20; radius: 6
                                color: Theme.islandAccent
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.id
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                font.weight: 600
                                color: modelData.id === activeWorkspaceId ? "#181825" : "#9399b2"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: false
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (m) => { m.accepted = true; switchWorkspace(modelData.id) }
                            }
                        }
                    }
                }

                // Separator
                Rectangle {
                    width: 1; height: 14
                    color: "#313244"
                    Layout.alignment: Qt.AlignVCenter
                    visible: allClients.length > 0
                }

                // ── App icons (active-workspace clients only) ─────────
                Row {
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        id: appIconRepeater
                        model: allClients.filter(c => {
                            return c.address !== "" &&
                                   // find what workspace this client is on
                                   rawClients.find(rc => rc.address === c.address)
                                       ?.workspace?.id === activeWorkspaceId
                        }).slice(0, 6)

                        delegate: Item {
                            required property var modelData
                            width: 22; height: 22
                            property bool isFocused: modelData.address === activeAddress

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                visible: isFocused
                                color: "#313244"
                                border.color: "#89b4fa"
                                border.width: 1
                            }

                            Image {
                                anchors.centerIn: parent
                                width: 16; height: 16
                                source: modelData.iconPath
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                asynchronous: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: false
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    tooltipText    = modelData.appClass + " — " + modelData.title
                                    var pos        = parent.mapToItem(bar.contentItem, parent.width / 2, 0)
                                    tooltipAnchorX = pos.x
                                    tooltipVisible = true
                                }
                                onExited:  tooltipVisible = false
                                onClicked: (m) => {
                                    m.accepted = true
                                    hyprDispatch(
                                        ["focuswindow", "address:" + modelData.address],
                                        "hl.dsp.window.focus({ window = \"address:" + modelData.address + "\" })"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Center clock pill ────────────────────────────────────────────
        Rectangle {
            id: island
            visible: false
            property bool mediaInfoVisible: false
            property bool mediaPanelOpen: false
            width: clockRow.implicitWidth + 26
            height: 34
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 17
            color: "#000000"
            border.width: 1
            border.color: clockHover.hovered
                ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.09)
            scale: clockHover.hovered ? 1.035 : 1
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                gradient: Gradient {
                    GradientStop { position: 0;    color: Qt.rgba(1, 1, 1, 0.045) }
                    GradientStop { position: 0.45; color: "transparent" }
                }
            }

            Row {
                id: clockRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: ShellState.time
                    color: Theme.text
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                    font.weight: 600
                    anchors.verticalCenter: parent.verticalCenter
                }
                Row {
                    visible: MediaService.playing
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 2
                            height: 5
                            radius: 1
                            color: Theme.islandAccent
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on height {
                                loops: Animation.Infinite
                                running: MediaService.playing
                                PauseAnimation { duration: index * 55 }
                                NumberAnimation {
                                    to: 12 - (index % 2) * 3
                                    duration: 210 + index * 30
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 4 + (index % 2) * 2
                                    duration: 190 + (3 - index) * 25
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }
            }

            Connections {
                target: MediaService
                function onHasTrackChanged() {
                    if (!MediaService.hasTrack) {
                        island.mediaInfoVisible = false
                        island.mediaPanelOpen = false
                        mediaCardCloseTimer.stop()
                    } else if (clockHover.hovered) {
                        island.mediaInfoVisible = true
                    }
                }
            }

            HoverHandler {
                id: clockHover
                onHoveredChanged: {
                    if (hovered && MediaService.hasTrack) {
                        island.mediaInfoVisible = true
                        mediaCardCloseTimer.stop()
                    } else if (!hovered) {
                        mediaCardCloseTimer.restart()
                    }
                }
            }
            TapHandler {
                onTapped: {
                    if (MediaService.hasTrack) {
                        island.mediaPanelOpen = !island.mediaPanelOpen
                        island.mediaInfoVisible = true
                        calendarPopupOpen = false
                        if (!island.mediaPanelOpen) mediaCardCloseTimer.restart()
                    } else {
                        island.mediaInfoVisible = false
                        island.mediaPanelOpen = false
                        rootScope.toggleCalendar()
                    }
                }
            }
            Timer {
                id: mediaCardCloseTimer
                interval: 220
                repeat: false
                onTriggered: {
                    if (!clockHover.hovered && !mediaCardHover.hovered
                            && !island.mediaPanelOpen)
                        island.mediaInfoVisible = false
                }
            }
            Behavior on scale {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack }
            }
        }

        // ── Right-side status and quick-action pill ──────────────────────
        Rectangle {
            id: actionPill
            visible: false
            width: actionRow.implicitWidth + 20
            height: 34
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            radius: 17
            color: "#000000"
            border.width: 1
            border.color: actionHover.hovered
                ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.09)
            scale: actionHover.hovered ? 1.035 : 1
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                gradient: Gradient {
                    GradientStop { position: 0;    color: Qt.rgba(1, 1, 1, 0.045) }
                    GradientStop { position: 0.45; color: "transparent" }
                }
            }

            Row {
                id: actionRow
                anchors.centerIn: parent
                spacing: 6

                Row {
                    spacing: 5
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [
                            { id: "bluetooth" },
                            { id: "wifi" },
                            { id: "sound" },
                            { id: "notifications" },
                            { id: "updates" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            property bool active: modelData.id === "updates" ? pendingUpdates > 0
                                : modelData.id === "wifi" ? NetworkService.wifiEnabled
                                : modelData.id === "bluetooth" ? BluetoothService.enabled
                                : modelData.id === "sound" ? AudioService.muted
                                : NotificationService.doNotDisturb
                            property string iconName: modelData.id === "updates" ? "download"
                                : modelData.id === "wifi" ? "wifi"
                                : modelData.id === "bluetooth" ? "bluetooth"
                                : modelData.id === "sound"
                                    ? (AudioService.muted ? "volume-x" : "volume-2")
                                    : (NotificationService.doNotDisturb ? "bell-off" : "bell")
                            property string iconTone: modelData.id === "updates"
                                ? (pendingUpdates > 0 ? "accent" : "muted")
                                : modelData.id === "wifi" ? (NetworkService.wifiEnabled ? "accent" : "muted")
                                : modelData.id === "bluetooth" ? (BluetoothService.enabled ? "accent" : "muted")
                                : modelData.id === "sound" ? (AudioService.muted ? "error" : "muted")
                                : NotificationService.doNotDisturb ? "warning" : "muted"
                            width: 19; height: 19; radius: 7
                            color: active
                                ? (modelData.id === "sound"
                                    ? Qt.rgba(1, 0.42, 0.37, 0.16)
                                    : Qt.rgba(1, 0.62, 0.04, 0.16))
                                : Qt.rgba(1, 1, 1, 0.07)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            SvgIcon {
                                anchors.centerIn: parent
                                width: 13; height: 13
                                iconName: parent.iconName
                                tone: parent.iconTone
                            }
                            Rectangle {
                                visible: modelData.id === "updates" && pendingUpdates > 0
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: -3
                                anchors.topMargin: -4
                                width: Math.max(9, updateCount.implicitWidth + 4)
                                height: 9; radius: 5
                                color: Theme.error
                                Text {
                                    id: updateCount
                                    anchors.centerIn: parent
                                    text: pendingUpdates > 99 ? "99+" : String(pendingUpdates)
                                    color: Theme.background
                                    font.family: Theme.uiFont
                                    font.pixelSize: 6
                                    font.weight: 700
                                }
                            }
                            MouseArea {
                                id: quickActionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: false
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (m) => {
                                    m.accepted = true
                                    if (modelData.id === "updates") launchSystemUpdater()
                                    else openQuickAction(modelData.id, parent)
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: parent.parent.radius
                                    color: parent.containsMouse ? Qt.rgba(1,1,1,0.14) : "transparent"
                                }
                            }
                            Rectangle {
                                visible: quickActionMouse.containsMouse && modelData.id === "updates"
                                z: 1000
                                x: parent.width - width
                                y: -height - 8
                                width: 224
                                height: updateTooltipLabel.implicitHeight + 16
                                radius: 9
                                color: Theme.surface
                                border.width: 1
                                border.color: Theme.outline
                                Text {
                                    id: updateTooltipLabel
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: updateTooltip
                                    color: Theme.text
                                    font.family: Theme.uiFont
                                    font.pixelSize: 9
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: batteryIndicator
                    visible: batteryPercent >= 0
                    width: batteryContent.implicitWidth + 12
                    height: 22
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: batteryPercent <= 15
                        ? Qt.rgba(1, 0.42, 0.37, 0.15)
                        : batteryCharging ? Qt.rgba(0.37, 0.84, 0.46, 0.13)
                                          : Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: batteryPercent <= 15
                        ? Qt.rgba(1, 0.42, 0.37, 0.28)
                        : batteryCharging ? Qt.rgba(0.37, 0.84, 0.46, 0.24)
                                          : Qt.rgba(1, 1, 1, 0.06)
                    Row {
                        id: batteryContent
                        anchors.centerIn: parent
                        spacing: 4
                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14
                            iconName: rootScope.batteryIconName(batteryPercent, batteryCharging)
                            tone: rootScope.batteryIconTone(batteryPercent, batteryCharging)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: batteryPercent + "%"
                            color: batteryPercent <= 15 ? Theme.error : Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                            font.weight: 600
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            mouse.accepted = true
                            rootScope.openQuickAction("system", batteryIndicator)
                        }
                    }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                Rectangle {
                    width: 1; height: 14
                    color: Qt.rgba(1, 1, 1, 0.1)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    id: powerButton
                    width: 22; height: 22; radius: 8
                    color: powerMouse.containsMouse
                        ? Qt.rgba(0.95, 0.42, 0.42, 0.20)
                        : Qt.rgba(1, 1, 1, 0.07)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 130 } }
                    SvgIcon {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        iconName: "power"
                        tone: powerMouse.containsMouse ? "error" : "muted"
                    }
                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => {
                            m.accepted = true
                            rootScope.launchPowerMenu()
                        }
                    }
                }
            }

            HoverHandler { id: actionHover }
            Behavior on scale {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack }
            }
        }
    }

    // ── Clock popup: time and calendar ───────────────────────────────────
    PanelWindow {
        id: calendarOverlay
        visible: calendarPopupOpen || island.mediaInfoVisible || island.mediaPanelOpen
        anchors.top: true; anchors.left: true; anchors.right: true; anchors.bottom: true
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: calendarPopupOpen || island.mediaPanelOpen
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        mask: Region {
            shape: RegionShape.Rect
            x: Math.max(8, Math.min(bar.width - clockPopupWidth - 8,
                                    (bar.width - clockPopupWidth) / 2))
            y: -2
            width: calendarPopupOpen || island.mediaInfoVisible || island.mediaPanelOpen
                ? clockPopupWidth : 0
            height: calendarPopupOpen || island.mediaInfoVisible || island.mediaPanelOpen
                ? clockPopupHeight : 0
        }

        HyprlandFocusGrab {
            windows: [calendarOverlay]
            active: calendarPopupOpen || island.mediaPanelOpen
            onCleared: {
                calendarPopupOpen = false
                island.mediaInfoVisible = false
                island.mediaPanelOpen = false
            }
        }

        Rectangle {
            x: Math.max(8, Math.min(bar.width - width - 8, (bar.width - width) / 2))
            y: -2
            width: clockPopupWidth
            height: clockPopupHeight
            radius: 16
            color: Theme.background
            border.width: 1
            border.color: Theme.outline

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                ColumnLayout {
                    id: calendarColumn
                    visible: calendarPopupOpen || island.mediaPanelOpen
                    Layout.preferredWidth: island.mediaPanelOpen ? 260 : calendarPopupWidth - 32
                    Layout.fillHeight: true
                    spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label {
                            text: ShellState.time
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 21
                            font.weight: 600
                        }
                        Label {
                            text: Qt.formatDateTime(ShellState.now, "dddd, MMMM d")
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                        }
                    }
                    Item { width: 26; height: 26 }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline }

                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        width: 28; height: 26; radius: 8
                        color: prevMonthMouse.containsMouse ? Theme.surfaceHover : "transparent"
                        SvgIcon {
                            anchors.centerIn: parent
                            width: 16; height: 16; iconName: "chevron-left"; tone: "fg"
                        }
                        MouseArea {
                            id: prevMonthMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: rootScope.shiftCalendarMonth(-1)
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(calendarMonthStart, "MMMM yyyy")
                        color: Theme.text
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        font.weight: 600
                    }
                    Rectangle {
                        width: 28; height: 26; radius: 8
                        color: nextMonthMouse.containsMouse ? Theme.surfaceHover : "transparent"
                        SvgIcon {
                            anchors.centerIn: parent
                            width: 16; height: 16; iconName: "chevron-right"; tone: "fg"
                        }
                        MouseArea {
                            id: nextMonthMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: rootScope.shiftCalendarMonth(1)
                        }
                    }
                }

                Grid {
                    id: calendarGrid
                    Layout.fillWidth: true
                    columns: 7
                    spacing: 3
                    property real cellWidth: (width - 18) / 7

                    Repeater {
                        model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                        delegate: Label {
                            required property string modelData
                            width: calendarGrid.cellWidth
                            height: 20
                            text: modelData
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 9
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Repeater {
                        model: 42
                        delegate: Rectangle {
                            required property int index
                            readonly property var dateValue: rootScope.calendarDateAt(index)
                            width: calendarGrid.cellWidth
                            height: 29
                            radius: 8
                            color: rootScope.isCalendarToday(dateValue)
                                ? Theme.primary
                                : rootScope.isCalendarMonthDate(dateValue)
                                    ? Theme.surfaceRaised : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: dateValue.getDate()
                                color: rootScope.isCalendarToday(dateValue)
                                    ? Theme.background
                                    : rootScope.isCalendarMonthDate(dateValue)
                                        ? Theme.text : Theme.mutedDim
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: rootScope.isCalendarToday(dateValue) ? 700 : 400
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: island.mediaPanelOpen
                Layout.fillHeight: true
                width: 1
                color: Theme.outline
            }

            ColumnLayout {
                id: hoverMediaCard
                visible: MediaService.hasTrack && island.mediaInfoVisible
                    && !island.mediaPanelOpen
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 9

                HoverHandler {
                    id: mediaCardHover
                    onHoveredChanged: {
                        if (hovered) mediaCardCloseTimer.stop()
                        else mediaCardCloseTimer.restart()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 38; height: 38; radius: 11
                        color: Theme.surfaceRaised
                        SvgIcon {
                            anchors.centerIn: parent
                            width: 20; height: 20; iconName: "music-2"; tone: "accent"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            Layout.fillWidth: true
                            text: MediaService.title || "Unknown track"
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: 700
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            text: MediaService.artist || MediaService.playerName
                            color: Theme.muted
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    Repeater {
                        model: [
                            { action: "previous", iconName: "skip-back", size: 30 },
                            { action: "toggle", iconName: MediaService.playing ? "pause" : "play", size: 38 },
                            { action: "next", iconName: "skip-forward", size: 30 }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: modelData.size; height: modelData.size
                            radius: width / 2
                            color: mediaHoverControl.containsMouse
                                ? Theme.surfaceHover : Theme.surfaceRaised
                            SvgIcon {
                                anchors.centerIn: parent
                                width: 16; height: 16
                                iconName: modelData.iconName
                                tone: "fg"
                            }
                            MouseArea {
                                id: mediaHoverControl
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    mouse.accepted = true
                                    if (modelData.action === "previous") MediaService.previous()
                                    else if (modelData.action === "next") MediaService.next()
                                    else MediaService.toggle()
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: rootScope.formatMediaTime(MediaService.displayPosition)
                            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 9
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: rootScope.formatMediaTime(MediaService.length)
                            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 9
                        }
                    }
                    Rectangle {
                        id: hoverProgressTrack
                        property real progress: MediaService.length > 0
                            ? Math.max(0, Math.min(1, MediaService.displayPosition / MediaService.length)) : 0
                        Layout.fillWidth: true
                        height: 6; radius: 3
                        color: Theme.surfaceRaised
                        Rectangle {
                            id: hoverProgressFill
                            width: parent.width * parent.progress
                            height: parent.height; radius: parent.radius
                            color: Theme.islandAccent
                            Behavior on width {
                                NumberAnimation { duration: 90; easing.type: Easing.Linear }
                            }
                            Rectangle {
                                visible: MediaService.playing && hoverProgressFill.width > 4
                                width: 8; height: 8; radius: 4
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.primaryStrong
                                opacity: 0.9
                                Behavior on opacity { NumberAnimation { duration: 350 } }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (event) => {
                                event.accepted = true
                                MediaService.seekToRatio(event.x / width)
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: fullMediaPanel
                visible: island.mediaPanelOpen && MediaService.hasTrack
                Layout.preferredWidth: Math.max(220, calendarPopupWidth - 330)
                Layout.fillHeight: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: "NOW PLAYING"
                        color: Theme.islandAccent
                        font.family: Theme.uiFont; font.pixelSize: 10; font.weight: 700
                        font.letterSpacing: 1.2
                    }
                    Label {
                        text: MediaService.playerName
                        color: Theme.muted
                        font.family: Theme.uiFont; font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 92; radius: 16
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 0.62, 0.04, 0.16) }
                        GradientStop { position: 0.55; color: Theme.surface }
                        GradientStop { position: 1; color: Qt.rgba(0.4, 0.34, 0.8, 0.10) }
                    }
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 13
                        Rectangle {
                            width: 64; height: 64; radius: 15
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#f4a340" }
                                GradientStop { position: 0.52; color: "#ad5c57" }
                                GradientStop { position: 1; color: "#524d80" }
                            }
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.18)
                            Rectangle {
                                width: 43; height: 43; radius: 22
                                anchors.centerIn: parent
                                color: Qt.rgba(0.08, 0.08, 0.1, 0.62)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    anchors.centerIn: parent
                                    color: Theme.primaryStrong
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Label {
                                Layout.fillWidth: true
                                text: MediaService.title || "Unknown track"
                                color: Theme.text
                                font.family: Theme.uiFont; font.pixelSize: 14; font.weight: 700
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: MediaService.artist || "Unknown artist"
                                color: Theme.muted
                                font.family: Theme.uiFont; font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    Repeater {
                        model: [
                            { action: "previous", iconName: "skip-back", size: 36 },
                            { action: "toggle", iconName: MediaService.playing ? "pause" : "play", size: 50 },
                            { action: "next", iconName: "skip-forward", size: 36 }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: modelData.size; height: modelData.size
                            radius: width / 2
                            color: modelData.action === "toggle"
                                ? (fullMediaControl.containsMouse ? Theme.primaryStrong : Theme.primary)
                                : (fullMediaControl.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised)
                            Behavior on color { ColorAnimation { duration: 160 } }
                            SvgIcon {
                                anchors.centerIn: parent
                                width: modelData.action === "toggle" ? 22 : 18
                                height: width
                                iconName: modelData.iconName
                                tone: modelData.action === "toggle" ? "ink" : "fg"
                            }
                            MouseArea {
                                id: fullMediaControl
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    mouse.accepted = true
                                    if (modelData.action === "previous") MediaService.previous()
                                    else if (modelData.action === "next") MediaService.next()
                                    else MediaService.toggle()
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: rootScope.formatMediaTime(MediaService.displayPosition)
                            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: rootScope.formatMediaTime(MediaService.length)
                            color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: 10
                        }
                    }
                    Rectangle {
                        id: fullProgressTrack
                        property real progress: MediaService.length > 0
                            ? Math.max(0, Math.min(1, MediaService.displayPosition / MediaService.length)) : 0
                        Layout.fillWidth: true
                        height: 5; radius: 3
                        color: Theme.surfaceRaised
                        Rectangle {
                            id: fullProgressFill
                            width: parent.width * parent.progress
                            height: parent.height; radius: parent.radius
                            color: Theme.islandAccent
                            Behavior on width {
                                NumberAnimation { duration: 90; easing.type: Easing.Linear }
                            }
                            Rectangle {
                                visible: MediaService.playing && fullProgressFill.width > 5
                                width: 10; height: 10; radius: 5
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.primaryStrong
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (event) => {
                                event.accepted = true
                                MediaService.seekToRatio(event.x / width)
                            }
                        }
                    }
                }
            }
        }
    }

    }

    // ── App-icon hover tooltip ───────────────────────────────────────────
    PopupWindow {
        id: iconTooltip
        anchor.window: bar
        anchor.rect.x: Math.max(0, Math.min(bar.width - implicitWidth,
                            tooltipAnchorX - implicitWidth / 2))
        anchor.rect.y: bar.implicitHeight
        implicitWidth:  tooltipLabel.implicitWidth + 16
        implicitHeight: tooltipLabel.implicitHeight + 10
        visible: tooltipVisible
        color: "transparent"

        Rectangle {
            anchors.fill: parent; radius: 6
            color: "#181825"
            border.color: "#313244"; border.width: 1
            Text {
                id: tooltipLabel
                anchors.centerIn: parent
                text: tooltipText
                color: "#cdd6f4"
                font.family: Theme.uiFont
                font.pixelSize: 11
            }
        }
    }

    // ── Window-list popup (hamburger) ────────────────────────────────────
    // Uses a full-screen PanelWindow overlay + HyprlandFocusGrab so that
    // clicking anywhere outside the card reliably closes it.
    property bool windowPopupOpen: false
    readonly property int windowPopupWidth: Math.min(380, Math.max(0, bar.width - 16))

    PanelWindow {
        id: windowPopupOverlay
        visible: false
        anchors.top: true; anchors.left: true; anchors.right: true; anchors.bottom: true
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: windowPopupOpen
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Input mask: only the card area is interactive; everything else
        // is transparent to input, so a click outside falls through to
        // HyprlandFocusGrab which then fires onCleared.
        mask: Region {
            shape: RegionShape.Rect
            x: 8
            y: -2
            width:  windowPopupOpen ? windowPopupWidth : 0
            height: windowPopupOpen ? Math.min(420, popupCol.implicitHeight + 20) : 0
        }

        HyprlandFocusGrab {
            windows: [windowPopupOverlay]
            active:  false
            onCleared: windowPopupOpen = false
        }
        Item {
            anchors.fill: parent
            focus: windowPopupOpen
            enabled: windowPopupOpen
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier
                        && activeAddress !== "") {
                    event.accepted = true
                    killClient(activeAddress)
                }
            }
        }

        // The visible card
        Rectangle {
            x: 8
            y: -2
            width:  windowPopupWidth
            height: Math.min(420, popupCol.implicitHeight + 20)
            radius: 12
            color: "#181825"
            border.color: "#313244"; border.width: 1

            ScrollView {
                anchors.fill: parent; anchors.margins: 10
                clip: true
                contentWidth: availableWidth
                ScrollBar.vertical.policy:   ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    id: popupCol
                    width: windowPopupWidth - 20
                    spacing: 8

                    Repeater {
                        model: workspaceData
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            Layout.topMargin: 6
                            Layout.bottomMargin: 2

                            Rectangle {
                                anchors.fill: parent
                                z: -1
                                radius: 10
                                color: modelData.id === activeWorkspaceId
                                    ? Qt.rgba(1,0.62,0.04,0.055) : Qt.rgba(1,1,1,0.025)
                                border.width: 1
                                border.color: modelData.id === activeWorkspaceId
                                    ? Qt.rgba(1,0.62,0.04,0.24) : Qt.rgba(1,1,1,0.08)
                            }

                            Text {
                                Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 8
                                text: (modelData.id > 0
                                    ? "Workspace " + modelData.id
                                    : "Scratchpad") +
                                    (modelData.id === activeWorkspaceId ? "  •  active" : "")
                                color: modelData.id === activeWorkspaceId
                                    ? Theme.islandAccent : "#cdd6f4"
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.weight: 700
                            }

                            Repeater {
                                model: modelData.clients
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.bottomMargin: 4
                                    spacing: 5
                                    width: Math.max(0, parent.width - 16)
                                    HoverHandler { id: popupAppHover }

                                    Image {
                                        Layout.minimumWidth: 14
                                        Layout.preferredWidth: 14
                                        Layout.maximumWidth: 14
                                        Layout.minimumHeight: 14
                                        Layout.preferredHeight: 14
                                        Layout.maximumHeight: 14
                                        width: 14; height: 14
                                        source: modelData.iconPath
                                        sourceSize: Qt.size(28, 28)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true; asynchronous: true
                                    }
                                    SvgIcon {
                                        visible: !modelData.iconPath
                                        Layout.preferredWidth: 14; Layout.preferredHeight: 14
                                        iconName: "app-window"; tone: "muted"
                                    }
                                    Item {
                                        id: popupAppNameViewport
                                        Layout.preferredWidth: 58; Layout.minimumWidth: 40; Layout.maximumWidth: 58
                                        Layout.alignment: Qt.AlignVCenter
                                        height: 18; clip: true
                                        Text {
                                            id: popupAppNameText
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.appClass
                                            color: modelData.address === activeAddress ? "#89b4fa" : "#f5e0dc"
                                            font.family: Theme.uiFont; font.pixelSize: 9; font.weight: 600
                                            width: Math.max(implicitWidth, popupAppNameViewport.width)
                                            elide: Text.ElideRight
                                        }
                                        SequentialAnimation {
                                            running: popupAppHover.hovered && popupAppNameText.implicitWidth > popupAppNameViewport.width
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: 450 }
                                            NumberAnimation { target: popupAppNameText; property: "x"; from: 0; to: -(popupAppNameText.implicitWidth - popupAppNameViewport.width); duration: Math.max(850, popupAppNameText.implicitWidth * 35); easing.type: Easing.InOutSine }
                                            PauseAnimation { duration: 450 }
                                            NumberAnimation { target: popupAppNameText; property: "x"; to: 0; duration: 300; easing.type: Easing.InOutSine }
                                        }
                                    }
                                    Text {
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        color: "#a6adc8"
                                        font.family: Theme.uiFont
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        Layout.minimumWidth: 16; Layout.preferredWidth: 16; Layout.maximumWidth: 16
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        width: 16; height: 16; radius: 5
                                        color: killMA.containsMouse
                                            ? "#f38ba8" : Qt.rgba(0.95, 0.55, 0.62, 0.12)
                                        SvgIcon {
                                            anchors.centerIn: parent
                                            width: 10; height: 10; iconName: "x"
                                            tone: killMA.containsMouse ? "ink" : "error"
                                        }
                                        MouseArea {
                                            id: killMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            propagateComposedEvents: false
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: (m) => {
                                                m.accepted = true
                                                killClient(modelData.address)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: modelData.clients.length === 0
                                Layout.leftMargin: 8
                                text: "(empty)"
                                color: "#6c7086"
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                font.italic: true
                            }
                        }
                    }
                }
            }
        }
    }

}
