// ShellState.qml — global UI routing + panel state singleton.
// Mirrors the JS state in Section 1 / Section 2 of the HTML prototype.
pragma Singleton
import QtQuick

QtObject {
    // ── Panel open / close ───────────────────────────────────────────────
    property bool   popupOpen:  false

    // ── View routing ─────────────────────────────────────────────────────
    // "main" | "wifi" | "bt" | "sound" | "batt" | "cal" | "alerts" | "update"
    // Maps directly to the HTML data-go attribute values.
    property string activeView: "main"

    // ── Legacy tab alias (kept for backward compat with ControlPanel) ─────
    // Some existing code references ShellState.activeTab; keep it in sync.
    readonly property string activeTab: activeView

    // ── Tile toggle states (HTML #tFocus / #tNight) ───────────────────────
    property bool focusEnabled:     false
    property bool nightLightActive: false   // mirrors NightLightService.enabled but with local UI latch
    property bool locationEnabled: false
    property bool screencastEnabled: false

    // ── Clock ─────────────────────────────────────────────────────────────
    property date now: new Date()
    readonly property string time: Qt.formatDateTime(now, "h:mm AP")

    // ── Public actions ─────────────────────────────────────────────────────
    // Normalise legacy tab IDs used by shell.qml to the new HTML-prototype view IDs.
    function normalise(view: string): string {
        const map = {
            "notifications": "alerts",
            "system":        "batt",
            "brightness":    "main",
            "bluetooth":     "bt",
        }
        return map[view] ?? view
    }

    // Navigate to a view and open the panel.
    // Mirrors: view(id); setOpen(true) in Section 2 of the prototype.
    function open(view: string): void {
        activeView  = normalise(view)
        popupOpen   = true
        now         = new Date()
    }

    // Open or close without changing view (used by top-level pill click).
    function toggle(): void {
        if (popupOpen) {
            popupOpen = false
        } else {
            open(activeView === "" ? "main" : activeView)
        }
    }

    // Navigate inside an already-open panel (e.g. row → detail view).
    function goTo(view: string): void {
        activeView = normalise(view)
        if (!popupOpen) popupOpen = true
        now = new Date()
    }

    // Back: return to the main view from any sub-view.
    function back(): void {
        activeView = "main"
    }

    // Close the panel completely.
    function close(): void {
        popupOpen = false
    }

    // ── Clock timer ────────────────────────────────────────────────────────
    property Timer clockTimer: Timer {
        interval:         1000
        repeat:           true
        running:          true
        onTriggered:      ShellState.now = new Date()
    }
}
