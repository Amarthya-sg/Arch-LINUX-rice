// Config.qml — Central configuration for all hardcoded behaviour values.
//
// Every tuneable constant that was previously buried in QML files is here.
// Colors, spacing, radii, and animation durations live in style.css (see
// core/Theme.qml for how they are consumed). This file covers everything
// that CSS cannot express: polling intervals, retry counts, timeouts, etc.
//
// Usage: import "core" anywhere in the project, then access Config.<property>.
pragma Singleton
import QtQuick

QtObject {
    id: root

    // ── Bar layout ────────────────────────────────────────────────────────
    // How many pixels the compositor reserves below the bar for windows.
    // Must match the PanelWindow.exclusiveZone value in shell.qml.
    property int barExclusiveZone: 44

    // Collapsed pill height (px). Also drives the bar's minimum height.
    property int pillCollapsedHeight: 38

    // Expanded panel/window-list width.
    property int panelWidth:       380
    property int panelHeight:      480
    property int windowListHeight: 420

    // ── Notification toasts ───────────────────────────────────────────────
    // How long (ms) a toast preview stays visible in the pill before
    // auto-dismissing.
    property int notificationToastMs: 2500

    // ── Media auto-popup ──────────────────────────────────────────────────
    // Duration (ms) the media popover stays open after a track change
    // or after the last interaction. Applies to both the auto-popup and
    // the inactivity timer.
    property int mediaAutoPopupMs: 5000

    // ── Hyprland IPC ─────────────────────────────────────────────────────
    // Debounce (ms) between a Hyprland compositor event and the start of
    // the hyprctl polling chain.
    property int hyprEventDebounceMs: 120

    // Number of early polling cycles where workspace data is always rebuilt
    // even if nothing changed (lets late-loading icons resolve).
    property int hyprSettleCycles: 4

    // ── System update check ───────────────────────────────────────────────
    // How often (ms) to poll for pending package updates. Default: 10 min.
    property int updateCheckIntervalMs: 600000

    // ── Audio ─────────────────────────────────────────────────────────────
    // Debounce (ms) before a volume change is written via pactl.
    // Prevents rapid slider drags from spawning dozens of processes.
    property int audioVolumeDebounceMs: 100

    // ── Bluetooth ─────────────────────────────────────────────────────────
    // How many times to retry a connect attempt before giving up.
    property int bluetoothRetryCount: 3
    // Delay (ms) between retry attempts.
    property int bluetoothRetryIntervalMs: 4000
    // Timeout (s) passed to bluetoothctl for the pair/connect command.
    property int bluetoothConnectTimeoutS: 45

    // ── Brightness & system stats polling ─────────────────────────────────
    // How often (ms) to re-poll brightness and system stats while the
    // control panel is open.
    property int systemPollIntervalMs: 3000

    // ── Night light ───────────────────────────────────────────────────────
    // Debounce (ms) before a temperature change is applied via hyprsunset.
    property int nightLightDebounceMs: 180
    // Minimum and maximum colour temperature values (Kelvin).
    property int nightLightMinTemp: 2500
    property int nightLightMaxTemp: 6500

    // ── Calendar popup dimensions ─────────────────────────────────────────
    // Width when the media panel is not open.
    property int calendarPopupWidth:  304
    // Height when only the calendar is shown (no media hover card).
    property int calendarPopupHeight: 336
    // Height when the compact media hover card is visible.
    property int mediaHoverCardHeight: 148
    // Dimensions when the full media panel is open.
    property int mediaPanelWidth:  660
    property int mediaPanelHeight: 360

    // ── App icon substitutions ────────────────────────────────────────────
    // These are the defaults; IconResolver exposes them as a writable
    // property so you can extend them without touching core code:
    //   iconResolver.iconSubstitutions["myApp"] = "my-icon-name"
    // The map is documented in core/IconResolver.qml.

    // ── Scroll speeds (ms per pixel) ─────────────────────────────────────
    // Lower = faster. These fall back to the CSS --cc-scroll-*-rate tokens
    // if defined; set them here only if you don't use style.css overrides.
    property real scrollTitleRateMsPerPx: 45
    property real scrollAppRateMsPerPx:   35
}
