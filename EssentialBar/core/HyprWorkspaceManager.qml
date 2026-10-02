// HyprWorkspaceManager.qml
// Encapsulates all hyprctl polling logic previously in shell.qml.
//
// Exposes reactive properties:
//   workspaceData      — all workspaces (including scratchpad) with nested clients
//   numberedWorkspaces — workspaceData filtered to id > 0
//   allClients         — flat list of every running client
//   activeWorkspaceId  — id of the currently focused workspace
//   activeAddress      — window address of the currently focused client
//
// Exposes functions:
//   refresh()          — trigger a full hyprctl polling chain immediately
//   switchWorkspace(id) — dispatch workspace focus
//   killClient(addr)    — dispatch window close
//
// Usage (in shell.qml):
//   HyprWorkspaceManager { id: wsManager }
//   // then bind: workspaces: wsManager.numberedWorkspaces  etc.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

    // ── Public reactive state ─────────────────────────────────────────────
    property var    workspaceData:      []
    property var    numberedWorkspaces: []
    property var    allClients:         []
    property int    activeWorkspaceId:  1
    property string activeAddress:      ""

    // ── Change-detection internals ────────────────────────────────────────
    property string _wsText:       ""
    property string _clText:       ""
    property bool   _dirty:        false
    // Rebuild unconditionally for the first N cycles so icons that load late
    // still resolve their paths correctly.
    property int    _settleCycles: 4

    // ── Re-run guard ──────────────────────────────────────────────────────
    // Set to true if a refresh() call arrives while a chain is in flight;
    // the chain replays it when it finishes.
    property bool _again: false

    // ── Public API ────────────────────────────────────────────────────────
    function refresh() {
        if (activeWindowProc.running || activeWsProc.running
                || workspacesProc.running || clientsProc.running) {
            _again = true
            return
        }
        activeWindowProc.running = true
    }

    function switchWorkspace(id) {
        _hyprDispatch(
            ["workspace", String(id)],
            "hl.dsp.focus({ workspace = \"" + id + "\" })"
        )
    }

    function killClient(address) {
        if (!address) return
        _hyprDispatch(
            ["closewindow", "address:" + address],
            "hl.dsp.window.close({ window = \"address:" + address + "\" })"
        )
    }

    // ── Private helpers ───────────────────────────────────────────────────
    function _chainDone() {
        if (_again) { _again = false; hyprEventDebounce.restart() }
    }

    function _hyprDispatch(legacyArgs, luaExpr) {
        dispatchProc.pendingLuaExpr = luaExpr
        dispatchProc.triedLua       = false
        dispatchProc.command        = ["hyprctl", "dispatch"].concat(legacyArgs)
        dispatchProc.running        = true
    }

    function _rebuild() {
        var byWs = {}
        for (var i = 0; i < _rawWorkspaces.length; i++) {
            var w = _rawWorkspaces[i]
            byWs[w.id] = { id: w.id, name: w.name, clients: [] }
        }
        var flat = []
        for (var j = 0; j < _rawClients.length; j++) {
            var c  = _rawClients[j]
            var wsId = (c.workspace && c.workspace.id !== undefined) ? c.workspace.id : -9999
            if (!byWs[wsId])
                byWs[wsId] = { id: wsId, name: c.workspace ? c.workspace.name : "?", clients: [] }
            var cls   = c["class"] || c.initialClass || "unknown"
            var entry = {
                appClass:  cls,
                title:     c.title || c.initialTitle || "",
                pid:       c.pid,
                address:   c.address || "",
                iconPath:  iconResolver.iconPathForClass(cls)
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

    // ── Raw data buffers (private) ────────────────────────────────────────
    property var _rawWorkspaces: []
    property var _rawClients:    []

    // Icon resolver reference — expects IconResolver to be in scope as a
    // sibling singleton named iconResolver in shell.qml.
    // If it isn't present the fallback path "application-x-executable" is
    // returned by the resolver itself, so nothing breaks.
    property var iconResolver: null

    // ── Hyprland event debounce ───────────────────────────────────────────
    property Timer hyprEventDebounce: Timer {
        interval: 120
        onTriggered: root.refresh()
    }

    // ── React to Hyprland compositor events ──────────────────────────────
    property Connections hyprConnections: Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "workspace":      case "workspacev2":
            case "createworkspace": case "createworkspacev2":
            case "destroyworkspace": case "destroyworkspacev2":
            case "moveworkspace":  case "moveworkspacev2": case "renameworkspace":
            case "openwindow":     case "closewindow":
            case "movewindow":     case "movewindowv2":
            case "activewindow":   case "activewindowv2":
            case "focusedmon":     case "focusedmonv2":
                root.hyprEventDebounce.restart()
            }
        }
    }

    // ── Safety-net polling timer ──────────────────────────────────────────
    // Fast during startup icon settling, then every 30 s.
    property Timer pollTimer: Timer {
        interval:        root._settleCycles > 0 ? 2000 : 30000
        running:         true
        repeat:          true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ── hyprctl polling chain ─────────────────────────────────────────────
    property Process activeWindowProc: Process {
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.activeAddress = JSON.parse(text).address || "" } catch (e) { root.activeAddress = "" }
                if (!activeWsProc.running) activeWsProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.activeAddress = ""
                if (!activeWsProc.running) activeWsProc.running = true
            }
        }
    }

    property Process activeWsProc: Process {
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.activeWorkspaceId = JSON.parse(text).id } catch (e) {}
                if (!workspacesProc.running) workspacesProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !workspacesProc.running) workspacesProc.running = true
        }
    }

    property Process workspacesProc: Process {
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text !== root._wsText) {
                    root._wsText = text
                    try { root._rawWorkspaces = JSON.parse(text) } catch (e) { root._rawWorkspaces = [] }
                    root._dirty = true
                }
                if (!clientsProc.running) clientsProc.running = true
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root._wsText = ""
                root._dirty  = true
                root._rawWorkspaces = []
                if (!clientsProc.running) clientsProc.running = true
            }
        }
    }

    property Process clientsProc: Process {
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text !== root._clText) {
                    root._clText = text
                    try { root._rawClients = JSON.parse(text) } catch (e) { root._rawClients = [] }
                    root._dirty = true
                }
                if (root._dirty || root._settleCycles > 0) {
                    root._dirty = false
                    if (root._settleCycles > 0) root._settleCycles--
                    root._rebuild()
                }
                root._chainDone()
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root._clText    = ""
                root._rawClients = []
                root._rebuild()
                root._chainDone()
            }
        }
    }

    // ── Dispatch process (legacy + Lua fallback) ──────────────────────────
    property Process dispatchProc: Process {
        property string pendingLuaExpr: ""
        property bool   triedLua:       false
        onExited: (code, status) => {
            if (code !== 0 && !dispatchProc.triedLua) {
                dispatchProc.triedLua = true
                dispatchProc.command  = ["hyprctl", "dispatch", dispatchProc.pendingLuaExpr]
                dispatchProc.running  = true
            } else {
                root.refresh()
            }
        }
    }
}
