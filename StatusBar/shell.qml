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
    // Change detection for the hyprctl poll (avoids rebuilding models and
    // recreating every icon delegate when nothing changed).
    property string _wsText:  ""
    property string _clText:  ""
    property bool   _dirty:   false
    property int    _settleCycles: 4   // always rebuild the first few cycles so late-loading icons resolve
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
    // Re-run requested while a chain is already in flight; replayed at the end.
    property bool _again: false
    function refresh() {
        if (activeWindowProc.running || activeWsProc.running
            || workspacesProc.running || clientsProc.running) {
            _again = true
            return
        }
        activeWindowProc.running = true
    }
    function _chainDone() {
        if (_again) { _again = false; hyprEventDebounce.restart() }
    }
    Timer { id: hyprEventDebounce; interval: 120; onTriggered: rootScope.refresh() }
    // Refresh on Hyprland events instead of spawning 4x hyprctl every 2 s.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "workspace": case "workspacev2":
            case "createworkspace": case "createworkspacev2":
            case "destroyworkspace": case "destroyworkspacev2":
            case "moveworkspace": case "moveworkspacev2": case "renameworkspace":
            case "openwindow": case "closewindow":
            case "movewindow": case "movewindowv2":
            case "activewindow": case "activewindowv2":
            case "focusedmon": case "focusedmonv2":
                hyprEventDebounce.restart()
            }
        }
    }
    // Window titles are not tracked by events; refresh when the list opens.
    Connections {
        target: unifiedPill
        function onWindowListOpenChanged() { if (unifiedPill.windowListOpen) rootScope.refresh() }
    }

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
                if (text !== rootScope._wsText) {
                    rootScope._wsText = text
                    try { rawWorkspaces = JSON.parse(text) } catch(e) { rawWorkspaces = [] }
                    rootScope._dirty = true
                }
                if (!clientsProc.running) clientsProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                rootScope._wsText = ""
                rootScope._dirty = true
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
                if (text !== rootScope._clText) {
                    rootScope._clText = text
                    try { rawClients = JSON.parse(text) } catch(e) { rawClients = [] }
                    rootScope._dirty = true
                }
                if (rootScope._dirty || rootScope._settleCycles > 0) {
                    rootScope._dirty = false
                    if (rootScope._settleCycles > 0) rootScope._settleCycles--
                    rebuild()
                }
                rootScope._chainDone()
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                rootScope._clText = ""
                rawClients = []
                rebuild()
                rootScope._chainDone()
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

    // Fast while icons are still settling at startup, then a 30 s safety net.
    Timer {
        interval: rootScope._settleCycles > 0 ? 2000 : 30000
        running: true; repeat: true; triggeredOnStart: true
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

    // Media-takeover state read by the calendar overlay below. It used to
    // live on a permanently hidden "island" pill (dead code, now removed);
    // the values were never set, so behaviour is unchanged.
    QtObject {
        id: island
        property bool mediaInfoVisible: false
        property bool mediaPanelOpen:   false
    }
    // Mirrors the hover state of the media card, which lives in the lazily
    // created overlay window (it may not exist when this timer fires).
    property bool mediaCardHovered: false
    Timer {
        id: mediaCardCloseTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!rootScope.mediaCardHovered && !island.mediaPanelOpen)
                island.mediaInfoVisible = false
        }
    }
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

    }

    // ── Clock popup: time and calendar ───────────────────────────────────
    // Created only while the clock/media popup is open (a hidden full-screen
    // layer-shell window still costs a surface and buffers).
    LazyLoader {
        active: calendarPopupOpen || island.mediaInfoVisible || island.mediaPanelOpen

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
                radius: Theme.radiusSize(16)
                color: Theme.background
                border.width: Theme.dimensionSize(1)
                border.color: Theme.outline

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.marginSize(16)
                    spacing: Theme.spacingSize(16)

                    ColumnLayout {
                        id: calendarColumn
                        visible: calendarPopupOpen || island.mediaPanelOpen
                        Layout.preferredWidth: island.mediaPanelOpen ? 260 : calendarPopupWidth - 32
                        Layout.fillHeight: true
                        spacing: Theme.spacingSize(8)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSize(10)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSize(1)
                            Label {
                                text: ShellState.time
                                color: Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.fontSize(21)
                                font.weight: Theme.fontWeightSemibold
                            }
                            Label {
                                text: Qt.formatDateTime(ShellState.now, "dddd, MMMM d")
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.fontSize(10)
                            }
                        }
                        Item { width: Theme.dimensionSize(26); height: Theme.dimensionSize(26) }
                    }

                    Rectangle { Layout.fillWidth: true; height: Theme.dimensionSize(1); color: Theme.outline }

                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: Theme.dimensionSize(28); height: Theme.dimensionSize(26); radius: Theme.radiusSize(8)
                            color: prevMonthMouse.containsMouse ? Theme.surfaceHover : "transparent"
                            SvgIcon {
                                anchors.centerIn: parent
                                width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-left"; tone: "fg"
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
                            font.pixelSize: Theme.fontSize(12)
                            font.weight: Theme.fontWeightSemibold
                        }
                        Rectangle {
                            width: Theme.dimensionSize(28); height: Theme.dimensionSize(26); radius: Theme.radiusSize(8)
                            color: nextMonthMouse.containsMouse ? Theme.surfaceHover : "transparent"
                            SvgIcon {
                                anchors.centerIn: parent
                                width: Theme.dimensionSize(16); height: Theme.dimensionSize(16); iconName: "chevron-right"; tone: "fg"
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
                        spacing: Theme.spacingSize(3)
                        property real cellWidth: (width - 18) / 7

                        Repeater {
                            model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                            delegate: Label {
                                required property string modelData
                                width: calendarGrid.cellWidth
                                height: Theme.dimensionSize(20)
                                text: modelData
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.fontSize(9)
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
                                height: Theme.dimensionSize(29)
                                radius: Theme.radiusSize(8)
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
                                    font.pixelSize: Theme.fontSize(10)
                                    font.weight: rootScope.isCalendarToday(dateValue) ? Theme.fontWeightBold : Theme.fontWeightRegular
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: island.mediaPanelOpen
                    Layout.fillHeight: true
                    width: Theme.dimensionSize(1)
                    color: Theme.outline
                }

                ColumnLayout {
                    id: hoverMediaCard
                    visible: MediaService.hasTrack && island.mediaInfoVisible
                        && !island.mediaPanelOpen
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingSize(9)

                    HoverHandler {
                        id: mediaCardHover
                        Component.onDestruction: rootScope.mediaCardHovered = false
                        onHoveredChanged: {
                            rootScope.mediaCardHovered = hovered
                            if (hovered) mediaCardCloseTimer.stop()
                            else mediaCardCloseTimer.restart()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSize(10)
                        Rectangle {
                            width: Theme.dimensionSize(38); height: Theme.dimensionSize(38); radius: Theme.radiusSize(11)
                            color: Theme.surfaceRaised
                            SvgIcon {
                                anchors.centerIn: parent
                                width: Theme.dimensionSize(20); height: Theme.dimensionSize(20); iconName: "music-2"; tone: "accent"
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSize(2)
                            Label {
                                Layout.fillWidth: true
                                text: MediaService.title || "Unknown track"
                                color: Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.fontSize(12)
                                font.weight: Theme.fontWeightBold
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: MediaService.artist || MediaService.playerName
                                color: Theme.muted
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spacingSize(14)
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
                                    width: Theme.dimensionSize(16); height: Theme.dimensionSize(16)
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
                        spacing: Theme.spacingSize(4)
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: rootScope.formatMediaTime(MediaService.displayPosition)
                                color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9)
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: rootScope.formatMediaTime(MediaService.length)
                                color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9)
                            }
                        }
                        Rectangle {
                            id: hoverProgressTrack
                            property real progress: MediaService.length > 0
                                ? Math.max(0, Math.min(1, MediaService.displayPosition / MediaService.length)) : 0
                            Layout.fillWidth: true
                            height: Theme.dimensionSize(6); radius: Theme.radiusSize(3)
                            color: Theme.surfaceRaised
                            Rectangle {
                                id: hoverProgressFill
                                width: parent.width * parent.progress
                                height: parent.height; radius: parent.radius
                                color: Theme.islandAccent
                                Behavior on width {
                                    NumberAnimation { duration: Theme.duration(90); easing.type: Easing.Linear }
                                }
                                Rectangle {
                                    visible: MediaService.playing && hoverProgressFill.width > 4
                                    width: Theme.dimensionSize(8); height: Theme.dimensionSize(8); radius: Theme.radiusSize(4)
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.primaryStrong
                                    opacity: Theme.opacityValue(0.9)
                                    Behavior on opacity { NumberAnimation { duration: Theme.duration(350) } }
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
                    spacing: Theme.spacingSize(10)

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: "NOW PLAYING"
                            color: Theme.islandAccent
                            font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10); font.weight: Theme.fontWeightBold
                            font.letterSpacing: Theme.letterSpacingValue(1.2)
                        }
                        Label {
                            text: MediaService.playerName
                            color: Theme.muted
                            font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(9)
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.dimensionSize(92); radius: Theme.radiusSize(16)
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 0.62, 0.04, Theme.opacityValue(0.16)) }
                            GradientStop { position: 0.55; color: Theme.surface }
                            GradientStop { position: 1; color: Qt.rgba(0.4, 0.34, 0.8, Theme.opacityValue(0.10)) }
                        }
                        border.width: Theme.dimensionSize(1)
                        border.color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.06))
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.marginSize(14)
                            spacing: Theme.spacingSize(13)
                            Rectangle {
                                width: Theme.dimensionSize(64); height: Theme.dimensionSize(64); radius: Theme.radiusSize(15)
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Theme.primaryStrong }
                                    GradientStop { position: 0.52; color: Theme.primary }
                                    GradientStop { position: 1; color: Theme.islandMutedDim }
                                }
                                border.width: Theme.dimensionSize(1)
                                border.color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.18))
                                Rectangle {
                                    width: Theme.dimensionSize(43); height: Theme.dimensionSize(43); radius: Theme.radiusSize(22)
                                    anchors.centerIn: parent
                                    color: Qt.rgba(0.08, 0.08, 0.1, Theme.opacityValue(0.62))
                                    border.width: Theme.dimensionSize(1)
                                    border.color: Qt.rgba(1, 1, 1, Theme.opacityValue(0.22))
                                    Rectangle {
                                        width: Theme.dimensionSize(10); height: Theme.dimensionSize(10); radius: Theme.radiusSize(5)
                                        anchors.centerIn: parent
                                        color: Theme.primaryStrong
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSize(5)
                                Label {
                                    Layout.fillWidth: true
                                    text: MediaService.title || "Unknown track"
                                    color: Theme.text
                                    font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(14); font.weight: Theme.fontWeightBold
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: MediaService.artist || "Unknown artist"
                                    color: Theme.muted
                                    font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10)
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spacingSize(14)
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
                                Behavior on color { ColorAnimation { duration: Theme.duration(160) } }
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
                        spacing: Theme.spacingSize(5)
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: rootScope.formatMediaTime(MediaService.displayPosition)
                                color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10)
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: rootScope.formatMediaTime(MediaService.length)
                                color: Theme.muted; font.family: Theme.uiFont; font.pixelSize: Theme.fontSize(10)
                            }
                        }
                        Rectangle {
                            id: fullProgressTrack
                            property real progress: MediaService.length > 0
                                ? Math.max(0, Math.min(1, MediaService.displayPosition / MediaService.length)) : 0
                            Layout.fillWidth: true
                            height: Theme.dimensionSize(5); radius: Theme.radiusSize(3)
                            color: Theme.surfaceRaised
                            Rectangle {
                                id: fullProgressFill
                                width: parent.width * parent.progress
                                height: parent.height; radius: parent.radius
                                color: Theme.islandAccent
                                Behavior on width {
                                    NumberAnimation { duration: Theme.duration(90); easing.type: Easing.Linear }
                                }
                                Rectangle {
                                    visible: MediaService.playing && fullProgressFill.width > 5
                                    width: Theme.dimensionSize(10); height: Theme.dimensionSize(10); radius: Theme.radiusSize(5)
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
    }

    // ── Window-list popup (hamburger) ────────────────────────────────────
    // Uses a full-screen PanelWindow overlay + HyprlandFocusGrab so that
    // clicking anywhere outside the card reliably closes it.
    property bool windowPopupOpen: false
    readonly property int windowPopupWidth: Math.min(380, Math.max(0, bar.width - 16))

}
