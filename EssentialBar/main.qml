import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Shapes 1.15
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "core"
import "services"
import "components"

// ── Root Scope lets Quickshell singletons (Theme, ShellState, services) load ──
Scope {
    id: rootScope

    // ── Icon resolver (plain QtObject — must be a property, not a free child) ──
    property var iconResolverObj: IconResolver {}

    // ── Workspace manager (replaces the inline hyprctl polling from shell.qml) ──
    property var wsManager: HyprWorkspaceManager {
        iconResolver: iconResolverObj
    }

    // ── Power process and confirm timer (Scope-level so Process type is valid) ──
    property var _powerExec: Process { id: powerExecProc }
    property var _powerTimer: Timer {
        id: powerConfirmTimer
        interval: 4000
        onTriggered: root.pendingPower = ""
    }

    // ── System Panel — local stats poller (raw values for gauges/sparklines) ──
    property var _sysStats: QtObject {
        id: sysStats
        property int    cpuPercent:  0
        property int    cpuCores:    0
        property string cpuModel:    ""
        property real   cpuTemp:     0      // °C
        property real   loadAvg:     0
        property real   ramTotalKb:  0
        property real   ramUsedKb:   0
        property real   swapTotalKb: 0
        property real   swapUsedKb:  0
        property real   diskTotal:   0      // bytes
        property real   diskUsed:    0
        property string gpuName:     ""
        property int    gpuUtil:     -1
        property real   gpuMemUsed:  0      // MiB
        property real   gpuMemTotal: 0
        property real   gpuTemp:     0
        property real   uptimeSec:   0
        property int    procCount:   0
        property var    fanRpmList:  []
        property real   fanMax:      0
        property bool   fanControllable: false
        property string fanMode:     "auto"
        property real   fanSetAt:    0
        property var    cpuHist:     []
        property var    ramHist:     []

        function ramPercent()  { return ramTotalKb > 0 ? Math.round(ramUsedKb * 100 / ramTotalKb) : 0 }
        function gbText(bytes) { return (bytes / 1073741824).toFixed(1) + " GB" }
        function kbText(kb)    { return (kb / 1048576).toFixed(1) + " GB" }
        function mibText(mib)  { return mib >= 1024 ? (mib / 1024).toFixed(1) + " GB" : Math.round(mib) + " MB" }
        function fanText()     { return fanRpmList.length === 0 ? "No sensor" : fanRpmList.join(" / ") + " RPM" }
        function uptimeText()  {
            var m = Math.floor(uptimeSec / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
            if (d > 0) return d + "d " + (h % 24) + "h"
            if (h > 0) return h + "h " + (m % 60) + "m"
            return m + "m"
        }
        function pushHist(arr, v) {
            var a = arr.slice(); a.push(v); if (a.length > 40) a.shift(); return a
        }
        function parse(text) {
            var o = {}, rows = text.split("\n")
            for (var i = 0; i < rows.length; i++) {
                var k = rows[i].indexOf("=")
                if (k > 0) o[rows[i].substring(0, k)] = rows[i].substring(k + 1).trim()
            }
            var n = function(v) { var x = parseFloat(v); return isNaN(x) ? 0 : x }
            if (o.cpu      !== undefined) cpuPercent  = n(o.cpu)
            if (o.cores    !== undefined) cpuCores    = n(o.cores)
            if (o.cpumodel !== undefined) cpuModel    = o.cpumodel
            if (o.cputemp  !== undefined) cpuTemp     = n(o.cputemp) / 1000
            if (o.load     !== undefined) loadAvg     = n(o.load)
            if (o.ramtotal !== undefined) {
                ramTotalKb = n(o.ramtotal); ramUsedKb  = n(o.ramused)
                swapTotalKb = n(o.swaptotal); swapUsedKb = n(o.swapused)
            }
            if (o.disk !== undefined) { var d = o.disk.split(/\s+/); diskTotal = n(d[0]); diskUsed = n(d[1]) }
            if (o.uptime !== undefined) uptimeSec = n(o.uptime)
            if (o.procs  !== undefined) procCount = n(o.procs)
            gpuName    = o.gpuname  !== undefined ? o.gpuname : ""
            gpuUtil    = (o.gpuutil !== undefined && o.gpuutil !== "") ? n(o.gpuutil) : -1
            gpuMemUsed = n(o.gpumemused); gpuMemTotal = n(o.gpumemtotal); gpuTemp = n(o.gputemp)
            fanRpmList = (o.fans !== undefined && o.fans !== "")
                ? o.fans.split(",").map(function(x) { return Math.round(n(x)) }) : []
            fanMax = n(o.fanmax); fanControllable = o.fanctl === "1"
            if (o.fanmode !== undefined && !fanProc2.running && Date.now() - fanSetAt > 3000)
                fanMode = o.fanmode
            if (o.cpu !== undefined) {
                cpuHist = pushHist(cpuHist, cpuPercent)
                ramHist = pushHist(ramHist, ramPercent())
            }
        }
        function setFanMode(mode) {
            if (!fanControllable || fanProc2.running || mode === fanMode) return
            fanMode = mode; fanSetAt = Date.now()
            fanProc2.command = ["sh", "-c", [
                'M="$1"',
                'body=\'for h in /sys/class/hwmon/hwmon*; do',
                '  [ -e "$h/pwm1_enable" ] || continue',
                '  if [ "$M" = max ]; then echo 1 > "$h/pwm1_enable" && echo 255 > "$h/pwm1"; else echo 2 > "$h/pwm1_enable"; fi',
                'done\'',
                'f=$(ls /sys/class/hwmon/hwmon*/pwm1_enable 2>/dev/null | head -1)',
                'if [ -w "$f" ]; then M="$M" sh -c "$body"; else pkexec env M="$M" sh -c "$body"; fi'
            ].join("\n"), "sh", mode]
            fanProc2.running = true
        }
    }

    property var _fanProc2:   Process { id: fanProc2;  onExited: if (!statProc2.running) statProc2.running = true }
    property var _statProc2:  Process {
        id: statProc2
        command: ["sh", "-c", [
            "s1=$(head -1 /proc/stat); sleep 0.4; s2=$(head -1 /proc/stat)",
            "echo \"cpu=$(echo \"$s1 $s2\" | awk '{t1=$2+$3+$4+$5+$6+$7+$8+$9; i1=$5+$6; t2=$13+$14+$15+$16+$17+$18+$19+$20; i2=$16+$17; d=t2-t1; if (d>0) printf \"%d\", (d-(i2-i1))*100/d; else print 0}')\"",
            "echo \"cores=$(nproc)\"",
            "echo \"cpumodel=$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ *//')\"",
            "t=0; for h in /sys/class/hwmon/hwmon*; do case \"$(cat \"$h/name\" 2>/dev/null)\" in coretemp|k10temp|zenpower|cpu_thermal) t=$(cat \"$h/temp1_input\" 2>/dev/null); break;; esac; done",
            "echo \"cputemp=$t\"",
            "echo \"load=$(cut -d' ' -f1 /proc/loadavg)\"",
            "awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} /^SwapTotal/{st=$2} /^SwapFree/{sf=$2} END{print \"ramtotal=\"t; print \"ramused=\"t-a; print \"swaptotal=\"st; print \"swapused=\"st-sf}' /proc/meminfo",
            "echo \"disk=$(df -B1 --output=size,used / | tail -1)\"",
            "echo \"uptime=$(cut -d. -f1 /proc/uptime)\"",
            "echo \"procs=$(ls /proc | grep -c '^[0-9]')\"",
            "echo \"fans=$(cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null | tr '\\n' ',' | sed 's/,$//')\"",
            "echo \"fanmax=$(cat /sys/class/hwmon/hwmon*/fan*_max 2>/dev/null | sort -n | tail -1)\"",
            "f=$(ls /sys/class/hwmon/hwmon*/pwm1_enable 2>/dev/null | head -1)",
            "if [ -n \"$f\" ]; then echo fanctl=1; e=$(cat \"$f\"); p=$(cat \"$(dirname \"$f\")/pwm1\" 2>/dev/null || echo 0); if [ \"$e\" = 1 ] && [ \"$p\" -ge 250 ]; then echo fanmode=max; else echo fanmode=auto; fi; else echo fanctl=0; fi",
            "if command -v nvidia-smi >/dev/null 2>&1; then",
            "  nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | awk -F', ' '{print \"gpuname=\"$1; print \"gpuutil=\"$2; print \"gpumemused=\"$3; print \"gpumemtotal=\"$4; print \"gputemp=\"$5}'",
            "else",
            "  echo \"gpuname=$(lspci -mm 2>/dev/null | awk -F'\"' '/VGA|3D|Display/{print $6; exit}')\"",
            "  for d in /sys/class/drm/card[0-9]/device; do",
            "    if [ -r \"$d/gpu_busy_percent\" ]; then",
            "      echo \"gpuutil=$(cat \"$d/gpu_busy_percent\")\"",
            "      echo \"gpumemused=$(( $(cat \"$d/mem_info_vram_used\" 2>/dev/null || echo 0) / 1048576 ))\"",
            "      echo \"gpumemtotal=$(( $(cat \"$d/mem_info_vram_total\" 2>/dev/null || echo 0) / 1048576 ))\"",
            "      echo \"gputemp=$(( $(cat $d/hwmon/hwmon*/temp1_input 2>/dev/null | head -1 || echo 0) / 1000 ))\"",
            "      break",
            "    fi",
            "  done",
            "fi"
        ].join("\n")]
        stdout: StdioCollector { onStreamFinished: sysStats.parse(text) }
    }
    property var _statTimer2: Timer {
        id: statPollTimer
        interval: 2500; repeat: true
        // Poll while panel is open (keeps tile subtitle live) or on system page
        running: ShellState.popupOpen
        triggeredOnStart: true
        onTriggered: if (!statProc2.running) statProc2.running = true
    }

    // ── Update checker (polls every 10 min via HyDE helper or pacman) ────
    property var _updateProc: Process {
        id: updateStatusProc
        command: ["bash", "-c", "helper=\"$HOME/.local/lib/hyde/system.update.py\"; if [ -f \"$helper\" ]; then exec python3 \"$helper\" status; else printf '{\"text\":\"\",\"tooltip\":\"System updater unavailable\"}'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    const match = String(data.text || "").match(/[0-9]+/)
                    rootScope._updateCount   = match ? Number(match[0]) : 0
                    rootScope._updateTooltip = data.tooltip || "System update status unavailable"
                } catch (e) {
                    rootScope._updateTooltip = "Could not read system update status"
                }
            }
        }
    }
    property int    _updateCount:   0
    property string _updateTooltip: "Checking for package updates…"
    property var _updateTimer: Timer {
        interval: 600000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: if (!updateStatusProc.running) updateStatusProc.running = true
    }

    // ──────────────────────────────────────────────────────────────────────
    // MAIN BAR WINDOW
    // ──────────────────────────────────────────────────────────────────────
    PanelWindow {
        id: root
        visible: true
        anchors {
            top: true
            left: true
            right: true
        }
        // Stay tall until the pill has finished shrinking back.
        implicitHeight: (expanded || island.height > 40) ? 850 : 54
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: expanded
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 54
        mask: Region { item: root.expanded ? outsideCatcher : island }

        // ── Derived state from real services ─────────────────────────────
        // Connectivity
        readonly property bool wifi:          NetworkService.wifiEnabled
        readonly property bool bluetooth:     BluetoothService.enabled
        readonly property bool sound:         !AudioService.muted
        readonly property bool dnd:           NotificationService.dndEnabled
        readonly property bool night:         NightLightService.enabled
        readonly property bool caffeine:      CaffeineService.active
        readonly property bool notifications: !NotificationService.dndEnabled

        // Battery (UPower for collapsed pill; SystemService for detail view)
        readonly property var   _battDevice:  UPower.displayDevice
        readonly property int   battery:      (_battDevice && _battDevice.percentage !== undefined)
            ? Math.max(0, Math.min(100, Math.round((Number(_battDevice.percentage) || 0) * 100))) : -1
        readonly property bool  battCharging: _battDevice && _battDevice.state === 1

        // Audio
        readonly property int volume:     Math.round(AudioService.outputMaster * 100)
        readonly property int brightness: BrightnessService.percent

        // Media
        readonly property bool    playing:   MediaService.playing
        readonly property string  trackTitle: MediaService.title
        readonly property string  trackArtist: MediaService.artist
        readonly property real    trackLength: MediaService.length      // microseconds
        readonly property real    trackPos:    MediaService.displayPosition // microseconds

        // Workspace (from HyprWorkspaceManager)
        readonly property int     workspace:  wsManager.activeWorkspaceId

        // Panel open/close
        property bool expanded: ShellState.popupOpen
        onExpandedChanged: {
            ShellState.popupOpen = expanded
            // Start system stats polling as soon as the panel opens
            // so the tile subtitle isn't 0 before visiting the system page
            if (expanded && !statProc2.running) statProc2.running = true
        }

        // Page routing — mirrors ShellState.activeView
        property string page: ShellState.activeView
        onPageChanged: {
            flick.contentY = 0
            ShellState.activeView = page
        }

        // Power confirm (tap once to arm, again to execute)
        property string pendingPower: ""

        // Workspace apps from HyprWorkspaceManager (for the workspaces page)
        readonly property var workspaceApps: wsManager.workspaceData
        readonly property int workspaceAppTotal: {
            var n = 0
            var list = wsManager.workspaceData
            for (var i = 0; i < list.length; i++) n += (list[i].clients ? list[i].clients.length : 0)
            return n
        }

        // Updates (polled by the update timer in shell.qml logic — default safe values)
        property int    pendingUpdates: rootScope._updateCount
        property string updateTooltip:  rootScope._updateTooltip

        // Bluetooth summary
        readonly property string btSummary: BluetoothService.connectedDevices.length > 0
            ? (BluetoothService.connectedDevices.length === 1
               ? BluetoothService.displayName(BluetoothService.connectedDevices[0])
               : BluetoothService.displayName(BluetoothService.connectedDevices[0])
                 + " +" + (BluetoothService.connectedDevices.length - 1))
            : "Not connected"

        // Wifi SSID
        readonly property string wifiSsid:   NetworkService.ssid || ""
        readonly property bool   wifiScanning: NetworkService.scanning

        // Bluetooth scanning
        readonly property bool   btScanning:  BluetoothService.scanning

        // Notifications
        readonly property int    notifCount:  NotificationService.count

        // DND queued
        readonly property int    queued:      NotificationService.queuedList.length

        // Power profile
        readonly property string powerProfileStr: SystemService.powerProfile  // "power-saver"|"balanced"|"performance"
        readonly property int    powerProfile: {
            var p = systemPowerProfile
            if (p === "performance") return 1
            if (p === "power-saver") return 2
            return 0
        }
        // Local alias for readability
        readonly property string systemPowerProfile: SystemService.powerProfile

        // Sizes
        property int contentW: Math.min(width - 28, 560)
        property real headerH: page === "main" ? 0 : 62
        property real expandedH: Math.max(160, Math.min(800, root.headerH + flick.contentHeight + 10))

        // Balance (from AudioService)
        property real balance: AudioService.outputBalance   // -1..1

        // ── Action functions ─────────────────────────────────────────────

        function toggle(key) {
            if (key === "wifi")          NetworkService.toggleWifi()
            else if (key === "bluetooth") BluetoothService.toggle()
            else if (key === "sound")     AudioService.toggleMute()
        }

        function toggleDnd() {
            NotificationService.toggle()
        }

        // Wifi helpers
        function wifiScan()               { NetworkService.scan() }
        function wifiConnectTo(network, pass) {
            NetworkService.connect(network, pass || "")
        }
        function wifiDisconnect(network)  { NetworkService.disconnect(network) }
        function wifiForget(network)      { NetworkService.forget(network) }

        // Bluetooth helpers
        function btConnectTo(device)      { BluetoothService.activate(device) }
        function btDisconnect(device)     { BluetoothService.activate(device) }   // activate toggles
        function btForget(device)         { BluetoothService.forget(device) }
        function btScan()                 { BluetoothService.toggleScan() }

        // Media helpers
        function currentTrackName()  { return root.trackTitle }
        function currentArtist()     { return root.trackArtist }

        // Time helpers (kept for collapsed pill display)
        function timeText()  {
            var d = ShellState.now
            var h = d.getHours() % 12
            return (h === 0 ? 12 : h) + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
        }
        function ampmText()  { return ShellState.now.getHours() < 12 ? "AM" : "PM" }
        function dateText()  { return Qt.formatDate(ShellState.now, "dddd, MMM d") }
        function pad(n)      { return (n < 10 ? "0" : "") + n }
        function durationText(us) {
            const s = Math.floor(Math.max(0, Number(us) || 0) / 1000000)
            return Math.floor(s / 60) + ":" + pad(s % 60)
        }

        // Power profile cycling
        function cyclePowerProfile() {
            var profiles = ["balanced", "performance", "power-saver"]
            var cur = profiles.indexOf(root.systemPowerProfile)
            if (cur < 0) cur = 0
            SystemService.setPowerProfile(profiles[(cur + 1) % 3])
        }

        // Power actions (tap once to arm, tap again to execute)
        // (powerExecProc and powerConfirmTimer are declared at Scope level below)
        function powerAction(key, command) {
            if (root.pendingPower !== key) {
                root.pendingPower = key
                powerConfirmTimer.restart()
                return
            }
            powerConfirmTimer.stop()
            root.pendingPower = ""
            powerExecProc.command = command
            powerExecProc.running = true
        }

        // Trigger an initial brightness + stats read when the bar loads
        Component.onCompleted: {
            SystemService.refresh()
        }

        // ── Timers ───────────────────────────────────────────────────────
        Timer { id: collapseTimer;  interval: 4200; onTriggered: ShellState.close() }
        Timer { id: toastTimer;     interval: 2600; onTriggered: toast.visible = false }

        // ── Outside-click catcher ────────────────────────────────────────
        MouseArea {
            id: outsideCatcher
            z: 0
            anchors.fill: parent
            enabled: root.expanded
            onClicked: { ShellState.close(); collapseTimer.stop() }
        }

        // ════════════════════════════════════════════════════════════════
        // ISLAND PILL
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            id: island
            z: 10
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            // ── Notification toast state ──────────────────────────────
            readonly property bool showingNotif: NotificationService.toastList.length > 0
                                                 && !root.expanded
            readonly property var  activeToast:  showingNotif
                                                 ? NotificationService.toastList[0] : null

            Timer {
                id:       notifDismissTimer
                interval: Config.notificationToastMs
                running:  island.showingNotif
                repeat:   false
                onTriggered: {
                    if (island.activeToast)
                        NotificationService.removeToast(island.activeToast.notifId)
                }
            }

            onActiveToastChanged: if (activeToast) notifDismissTimer.restart()

            width:  root.expanded        ? root.contentW
                  : island.showingNotif  ? Math.min(root.width - 16, 520)
                  : statusRow.implicitWidth + 28
            height: root.expanded        ? root.expandedH
                  : island.showingNotif  ? notifPreviewItem.implicitHeight + 20
                  : 38

            radius: Math.min(height / 2, 32)
            antialiasing: true
            clip:         true
            color:        Theme.islandBg
            border.color: island.showingNotif
                          ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                          : Theme.outline
            border.width: 1
            Behavior on width  { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 220 } }

            // ── Notification preview (Dynamic Island expand) ──────────
            Item {
                id:            notifPreviewItem
                anchors.fill:  parent
                anchors.margins: 0
                visible:  island.showingNotif && !root.expanded
                opacity:  visible ? 1 : 0
                implicitHeight: notifRow.implicitHeight + 20
                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }

                RowLayout {
                    id:                   notifRow
                    anchors.left:         parent.left
                    anchors.right:        parent.right
                    anchors.top:          parent.top
                    anchors.leftMargin:   12
                    anchors.rightMargin:  10
                    anchors.topMargin:    10
                    anchors.bottomMargin: 10
                    spacing: 10

                    // App icon / avatar
                    Rectangle {
                        Layout.preferredWidth:  44
                        Layout.preferredHeight: 44
                        radius: 12
                        color:  Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        Image {
                            id:              notifAppIcon
                            anchors.fill:    parent
                            anchors.margins: 6
                            source:          island.activeToast ? (island.activeToast.appIcon || "") : ""
                            fillMode:        Image.PreserveAspectFit
                            smooth:          true
                            visible:         status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible:          !notifAppIcon.visible
                            text:             island.activeToast
                                              ? (island.activeToast.appName || "?").charAt(0).toUpperCase()
                                              : "?"
                            color:            Theme.primary
                            font.pixelSize:   20
                            font.weight:      Font.Bold
                        }
                    }

                    // Message text
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text:             island.activeToast ? (island.activeToast.appName || "") : ""
                                color:            Theme.islandMuted
                                font.pixelSize:   10
                                font.weight:      Font.DemiBold
                                font.letterSpacing: 0.4
                                Layout.fillWidth: true
                                elide:            Text.ElideRight
                            }
                            Text {
                                text:           island.activeToast
                                                ? NotificationService.timeAgo(island.activeToast.timestamp)
                                                : ""
                                color:          Theme.islandMutedDim
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            text:             island.activeToast
                                              ? (island.activeToast.summary || "") : ""
                            color:            Theme.islandAccentStrong
                            font.pixelSize:   13
                            font.weight:      Font.DemiBold
                            Layout.fillWidth: true
                            wrapMode:         Text.WordWrap
                            maximumLineCount: 2
                            visible:          island.activeToast
                                              && (island.activeToast.summary || "") !== ""
                        }

                        Text {
                            text:             island.activeToast ? (island.activeToast.body || "") : ""
                            color:            Theme.islandMuted
                            font.pixelSize:   11
                            Layout.fillWidth: true
                            wrapMode:         Text.WordWrap
                            maximumLineCount: 3
                            visible:          island.activeToast
                                              && (island.activeToast.body || "") !== ""
                        }
                    }

                    // Dismiss ×
                    Rectangle {
                        Layout.preferredWidth:  24
                        Layout.preferredHeight: 24
                        Layout.alignment:       Qt.AlignVCenter
                        radius: 12
                        color:  dismissHov.containsMouse ? Theme.surfaceHover : Theme.surface
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "✕"; color: Theme.muted; font.pixelSize: 10 }
                        MouseArea {
                            id:           dismissHov
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                notifDismissTimer.stop()
                                if (island.activeToast)
                                    NotificationService.removeToast(island.activeToast.notifId)
                            }
                        }
                    }
                }

                // Tap body → open alerts panel
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: {
                        notifDismissTimer.stop()
                        if (island.activeToast)
                            NotificationService.removeToast(island.activeToast.notifId)
                        ShellState.open("alerts")
                        root.page = "alerts"
                    }
                }
            }

            // ── Collapsed status row ──────────────────────────────────────
            RowLayout {
                id: statusRow
                anchors.top:         parent.top
                anchors.left:        parent.left
                anchors.right:       parent.right
                height:              38
                anchors.leftMargin:  14
                anchors.rightMargin: 14
                spacing:             6
                opacity: (root.expanded || island.showingNotif) ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 180 } }

                IslandLeftIcon {
                    wifiOn:          root.wifi
                    notificationsOn: root.notifications
                    Layout.preferredWidth:  28
                    Layout.preferredHeight: 29
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 5

                        Text {
                            text:           root.timeText() + " " + root.ampmText()
                            color:          Theme.islandMuted
                            font.pixelSize: 12
                            font.weight:    Font.DemiBold
                        }

                        // ── Media pill (EQ bars + scrolling title) ────────
                        Rectangle {
                            visible:      MediaService.hasTrack
                            height:       22
                            radius:       11
                            antialiasing: true
                            color:        Qt.rgba(
                                Theme.islandAccent.r,
                                Theme.islandAccent.g,
                                Theme.islandAccent.b,
                                0.18)
                            border.width: 1
                            border.color: Qt.rgba(
                                Theme.islandAccent.r,
                                Theme.islandAccent.g,
                                Theme.islandAccent.b,
                                0.42)
                            implicitWidth: eqBarsRow.implicitWidth + titleClip.width + 20

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left:           parent.left
                                anchors.leftMargin:     8
                                spacing:               6

                                // ── 3 tall pill EQ bars ───────────────────
                                Row {
                                    id:      eqBarsRow
                                    spacing: 3
                                    anchors.verticalCenter: parent.verticalCenter

                                    Repeater {
                                        model: 3
                                        Item {
                                            width:  4
                                            height: 14
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                id:           eqPill
                                                width:        4
                                                // resting = 5px tall pill; dancing = up to 14px
                                                height:       5
                                                radius:       2      // pill shape
                                                antialiasing: true
                                                anchors.verticalCenter: parent.verticalCenter
                                                // bright when playing, visible-but-dim when paused
                                                color: root.playing
                                                    ? Theme.islandAccent
                                                    : Theme.islandMuted

                                                Behavior on color {
                                                    ColorAnimation { duration: 200 }
                                                }

                                                SequentialAnimation on height {
                                                    running: root.playing
                                                    loops:   Animation.Infinite
                                                    PauseAnimation  { duration: index * 200 }
                                                    NumberAnimation { from: 5; to: 14; duration: 350 + index * 80; easing.type: Easing.InOutSine }
                                                    NumberAnimation { from: 14; to: 5; duration: 350 + index * 80; easing.type: Easing.InOutSine }
                                                }
                                                // settle gracefully when paused
                                                NumberAnimation on height {
                                                    running: !root.playing
                                                    to:      5; duration: 180; easing.type: Easing.OutSine
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Scrolling title ───────────────────────
                                Item {
                                    id:     titleClip
                                    width:  80
                                    height: parent.height
                                    clip:   true
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id:             scrollingTitle
                                        text:           root.trackTitle
                                        color:          Theme.islandAccentStrong
                                        font.pixelSize: 10
                                        font.italic:    true
                                        font.weight:    Font.Medium
                                        anchors.verticalCenter: parent.verticalCenter

                                        // Scroll only when playing and title overflows
                                        readonly property bool needsScroll:
                                            root.playing && implicitWidth > titleClip.width

                                        // x goes from 0 → -(implicitWidth + 16) then snaps back
                                        NumberAnimation on x {
                                            running:  scrollingTitle.needsScroll
                                            loops:    Animation.Infinite
                                            from:     0
                                            to:       -(scrollingTitle.implicitWidth + 16)
                                            duration: Math.max(2000, scrollingTitle.implicitWidth * 28)
                                            easing.type: Easing.Linear
                                        }
                                        // snap back to start when paused or short title
                                        onNeedsScrollChanged: if (!needsScroll) x = 0
                                    }
                                }
                            }
                        }

                        // Battery — bright, bold, warning color on low
                        Text {
                            text:  root.battery >= 0 ? root.battery + "%" : "—"
                            color: root.battery >= 0 && root.battery <= 20
                                   ? Theme.warning
                                   : root.battery >= 0 && root.battCharging
                                   ? Theme.success
                                   : Theme.batteryText
                            font.pixelSize: 11
                            font.weight:    Font.DemiBold
                        }
                    }

                    // Workspace dots — one dot per real workspace, active dot is wider
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 3
                        Repeater {
                            model: wsManager.numberedWorkspaces
                            Rectangle {
                                required property var modelData
                                readonly property bool isActive: modelData.id === wsManager.activeWorkspaceId
                                width:  isActive ? 14 : 4
                                height: 4
                                radius: 2
                                antialiasing: true
                                color: isActive ? Theme.islandMuted : Theme.islandMutedDim
                                Behavior on width { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                }

                IslandRightIcon {
                    bluetoothOn: root.bluetooth
                    soundOn:     root.sound
                    Layout.preferredWidth:  34
                    Layout.preferredHeight: 24
                }
            }

            // Top strip — toggles the panel
            MouseArea {
                width:  parent.width
                height: 38
                onClicked: {
                    ShellState.toggle()
                    collapseTimer.stop()
                }
            }
        }

        // ════════════════════════════════════════════════════════════════
        // EXPANDED PANEL CONTENT
        // ════════════════════════════════════════════════════════════════
        Item {
            id: panel
            z: 20
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            anchors.top:              island.top
            anchors.topMargin:        38
            anchors.horizontalCenter: parent.horizontalCenter
            width:  island.width
            height: Math.max(0, island.height - 38)
            clip:   true

            // Pinned header: stays at top of every sub-page regardless of scroll position
            PageHeader {
                id: pageHeader
                visible: root.page !== "main"
                z: 5
                anchors.top: parent.top; anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.contentW - 28; height: 40
                title: root.page === "wifi"        ? "Wi-Fi"
                     : root.page === "bluetooth"   ? "Bluetooth"
                     : root.page === "alerts"      ? "Alerts"
                     : root.page === "sound"       ? "Audio"
                     : root.page === "workspaces"  ? "Workspaces"
                     : root.page === "power"       ? "Power"
                     : root.page === "updates"     ? "Updates"
                     : root.page === "system"      ? "System Panel"
                     : "Settings"
                subtitle: root.page === "wifi"
                              ? (!root.wifi ? "Off" : root.wifiSsid !== "" ? "Connected to " + root.wifiSsid : "Not connected")
                        : root.page === "bluetooth"
                              ? (!root.bluetooth ? "Off" : root.btSummary)
                        : root.page === "sound"
                              ? (root.sound ? "Volume " + root.volume + "%" : "Muted")
                        : root.page === "workspaces"
                              ? "Workspace " + wsManager.activeWorkspaceId + " active · " + root.workspaceAppTotal + " apps"
                        : root.page === "power"
                              ? "Tap an action, then tap again to confirm"
                        : root.page === "system"
                              ? (sysStats.uptimeSec > 0 ? "Up " + sysStats.uptimeText() : "Reading system stats…")
                        : ""
                showSwitch: ["wifi", "bluetooth", "sound", "alerts"].indexOf(root.page) >= 0
                showClear:  root.page === "alerts" && NotificationService.count > 0
                checked: root.page === "wifi"      ? root.wifi
                       : root.page === "bluetooth"  ? root.bluetooth
                       : root.page === "sound"      ? root.sound
                       : root.notifications
                onBack: { root.page = "main"; ShellState.back() }
                onCleared: NotificationService.clearAll()
                onToggled: function(v) {
                    if (root.page === "wifi")       { if (v !== root.wifi) NetworkService.toggleWifi() }
                    else if (root.page === "bluetooth") { if (v !== root.bluetooth) BluetoothService.toggle() }
                    else if (root.page === "sound") AudioService.setMuted(!v)
                    else NotificationService.setDnd(!v)
                }
            }

            Flickable {
                id: flick
                width:            root.contentW
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top:      parent.top
                anchors.topMargin: root.headerH
                anchors.bottom:   parent.bottom
                anchors.bottomMargin: 10
                contentWidth:  width
                contentHeight: (root.page === "main"
                    ? contentColumn.height : detailColumn.height) + 16
                clip:           true
                boundsBehavior: Flickable.StopAtBounds

                // ── MAIN VIEW ─────────────────────────────────────────────
                Column {
                    id: contentColumn
                    width:      parent.width
                    topPadding: 6; bottomPadding: 24
                    spacing:    12
                    visible:    root.page === "main"

                    // Time / date + battery + CPU/RAM + power button
                    RowLayout {
                        width: parent.width - 28
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0

                        // Clock + date
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 5
                            Row {
                                spacing: 6
                                Text {
                                    id: bigClock
                                    text:           root.timeText()
                                    color:          Theme.text
                                    font.pixelSize: 38
                                    font.weight:    Font.Light
                                }
                                Text {
                                    text:           root.ampmText()
                                    color:          Theme.muted
                                    font.pixelSize: 15
                                    anchors.baseline: bigClock.baseline
                                }
                            }
                            Text {
                                text:           root.dateText()
                                color:          Theme.muted
                                font.pixelSize: 13
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Battery % large + CPU/RAM inline
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 5
                            Row {
                                spacing: 9
                                Layout.alignment: Qt.AlignHCenter
                                BatteryIcon {
                                    level: root.battery >= 0 ? root.battery : 0
                                    tint:  root.battery >= 0 && root.battery <= 20 ? Theme.warning
                                           : root.battCharging ? Theme.success : Theme.text
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text:           root.battery >= 0 ? root.battery + "%" : "—"
                                    color:          root.battery >= 0 && root.battery <= 20 ? Theme.warning
                                                    : root.battCharging ? Theme.success : Theme.text
                                    font.pixelSize: 22
                                    font.weight:    Font.Medium
                                }
                            }
                            Row {
                                spacing: 10
                                Layout.alignment: Qt.AlignHCenter
                                Text {
                                    textFormat: Text.StyledText
                                    font.pixelSize: 11
                                    text: "<font color='" + Theme.muted + "'>CPU</font> <font color='" + Theme.primary + "'>" + Math.round(SystemService.cpuPercent) + "%</font>"
                                }
                                Text {
                                    textFormat: Text.StyledText
                                    font.pixelSize: 11
                                    text: "<font color='" + Theme.muted + "'>RAM</font> <font color='" + Theme.success + "'>" + Math.round(SystemService.memoryPercent) + "%</font>"
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Power button — goes to power page
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 40; Layout.preferredHeight: 40
                            radius: 20; antialiasing: true
                            color: pwrArea.pressed ? Theme.surfaceHover : Theme.surfaceRaised
                            Behavior on color { ColorAnimation { duration: 110 } }
                            Text { anchors.centerIn: parent; text: "⏻"; color: Theme.muted; font.pixelSize: 18 }
                            MouseArea { id: pwrArea; anchors.fill: parent; onClicked: root.page = "power" }
                        }
                    }

                    // Now-playing card (only if a track is playing)
                    Rectangle {
                        visible: root.playing || MediaService.hasTrack
                        width:  parent.width - 28
                        height: 176
                        radius: 26
                        antialiasing: true
                        color:  Theme.surfaceRaised
                        anchors.horizontalCenter: parent.horizontalCenter

                        ColumnLayout {
                            anchors.fill:    parent
                            anchors.margins: 14
                            spacing: 7

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Rectangle {
                                    width: 48; height: 48; radius: 14
                                    color: Theme.surface

                                    Image {
                                        anchors.fill:   parent
                                        source:         MediaService.artUrl || ""
                                        fillMode:       Image.PreserveAspectCrop
                                        visible:        MediaService.artUrl !== ""
                                        layer.enabled:  true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible:          MediaService.artUrl === ""
                                        text:             "♫"
                                        color:            Theme.primary
                                        font.pixelSize:   24
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    // Scrolling title
                                    Item {
                                        Layout.fillWidth: true
                                        height: 20
                                        clip:   true

                                        Text {
                                            id:             panelScrollTitle
                                            text:           root.trackTitle || "Unknown track"
                                            color:          Theme.text
                                            font.pixelSize: 14
                                            font.weight:    Font.DemiBold
                                            y:              (parent.height - implicitHeight) / 2

                                            readonly property bool needsScroll:
                                                root.playing && implicitWidth > parent.width

                                            NumberAnimation on x {
                                                running:  panelScrollTitle.needsScroll
                                                loops:    Animation.Infinite
                                                from:     0
                                                to:       -(panelScrollTitle.implicitWidth + 20)
                                                duration: Math.max(2500, panelScrollTitle.implicitWidth * 30)
                                                easing.type: Easing.Linear
                                            }
                                            onNeedsScrollChanged: if (!needsScroll) x = 0
                                        }
                                    }

                                    Text {
                                        text:            root.trackArtist || ""
                                        color:           Theme.muted
                                        font.pixelSize:  12
                                        elide:           Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Progress bar
                            PillProgress {
                                from:  0
                                to:    Math.max(1, root.trackLength)
                                value: root.trackPos
                                Layout.fillWidth:    true
                                Layout.preferredHeight: 6
                                MouseArea {
                                    anchors.fill:  parent
                                    onClicked: (mouse) => {
                                        MediaService.seekToRatio(mouse.x / width)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text:           root.durationText(root.trackPos)
                                    color:          Theme.muted
                                    font.pixelSize: 10
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text:           root.durationText(root.trackLength)
                                    color:          Theme.muted
                                    font.pixelSize: 10
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 14
                                PillButton {
                                    label: "◀"
                                    onClicked: MediaService.previous()
                                }
                                PillButton {
                                    label:   root.playing ? "Ⅱ" : "▶"
                                    primary: true
                                    onClicked: MediaService.toggle()
                                }
                                PillButton {
                                    label: "▶"
                                    onClicked: MediaService.next()
                                }
                            }
                        }
                    }

                    // ── Toggle tiles ──────────────────────────────────────
                    GridLayout {
                        id: tileGrid
                        columns:      3
                        columnSpacing: 8
                        rowSpacing:    8
                        width: parent.width - 28
                        anchors.horizontalCenter: parent.horizontalCenter

                        Tile {
                            title:    "Wi-Fi"
                            subtitle: root.wifi
                                ? (root.wifiSsid !== "" ? root.wifiSsid : "Not connected") : "Off"
                            icon:   "wifi"
                            active: root.wifi
                            onTapped: NetworkService.toggleWifi()
                            onOpened: { ShellState.goTo("wifi"); root.page = "wifi" }
                        }
                        Tile {
                            title:    "Bluetooth"
                            subtitle: root.bluetooth ? root.btSummary : "Off"
                            icon:   "bluetooth"
                            active: root.bluetooth
                            onTapped: BluetoothService.toggle()
                            onOpened: { ShellState.goTo("bt"); root.page = "bluetooth" }
                        }
                        Tile {
                            title:    "Audio"
                            subtitle: root.sound ? root.volume + "%" : "Muted"
                            icon:     "speaker"
                            iconMuted: !root.sound
                            iconLevel: root.volume
                            active:   root.sound
                            onTapped: AudioService.toggleMute()
                            onOpened: { ShellState.goTo("sound"); root.page = "sound" }
                        }
                        Tile {
                            title:    "Caffeine"
                            subtitle: root.caffeine ? "Awake" : "Normal"
                            icon:     "caffeine"
                            active:   root.caffeine
                            onTapped: CaffeineService.toggle()
                        }
                        Tile {
                            title:    "Do Not Disturb"
                            subtitle: root.dnd
                                ? (root.queued > 0 ? "On · " + root.queued + " queued" : "On") : "Off"
                            glyph:  "☾"
                            active: root.dnd
                            onTapped: NotificationService.toggle()
                            onOpened: { ShellState.goTo("alerts"); root.page = "alerts" }
                        }
                        Tile {
                            title:    "Night Light"
                            subtitle: NightLightService.detail
                            glyph:  "☼"
                            active: root.night
                            onTapped: NightLightService.toggle()
                        }
                        Tile {
                            title:    "System Panel"
                            subtitle: "CPU " + Math.round(sysStats.cpuPercent) + "% · RAM " + sysStats.ramPercent() + "%"
                            glyph:    "▤"
                            active:   false
                            onTapped: root.page = "system"
                            onOpened: root.page = "system"
                        }
                        Tile {
                            title:    "Workspaces"
                            subtitle: "Workspace " + wsManager.activeWorkspaceId + " · " + root.workspaceAppTotal + " apps"
                            glyph:    "▦"
                            active:   false
                            onTapped: root.page = "workspaces"
                            onOpened: root.page = "workspaces"
                        }
                        Tile {
                            title:    "Updates"
                            subtitle: root.pendingUpdates > 0 ? root.pendingUpdates + " available" : "Up to date"
                            glyph:    "⇩"
                            active:   root.pendingUpdates > 0
                            onTapped: root.page = "updates"
                            onOpened: root.page = "updates"
                        }
                    }

                    // ── Volume slider ────────────────────────────────────
                    RowLayout {
                        width: parent.width - 28
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10

                        SpeakerIcon {
                            muted:  !root.sound
                            level:  root.volume
                            tint:   (!root.sound || root.volume < 12)
                                    ? Theme.textMuted : Theme.primary
                            Layout.preferredWidth:  22
                            Layout.preferredHeight: 22
                        }
                        PillSlider {
                            from:  0; to: 100
                            value: root.sound ? root.volume : 0
                            Layout.fillWidth: true
                            onMoved: {
                                AudioService.setVolume(value / 100)
                                if (value > 0 && AudioService.muted)
                                    AudioService.setMuted(false)
                            }
                        }
                    }

                    // ── Brightness slider ────────────────────────────────
                    RowLayout {
                        width: parent.width - 28
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10

                        Text {
                            text:           "☼"
                            color:          root.brightness < 16 ? Theme.muted : Theme.primary
                            font.pixelSize: 18
                        }
                        PillSlider {
                            from:  5; to: 100
                            value: root.brightness
                            Layout.fillWidth: true
                            onMoved: BrightnessService.set(value)
                        }
                    }

                    // ── Notifications ────────────────────────────────────
                    Column {
                        width: parent.width - 28
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        RowLayout {
                            width: parent.width
                            Text {
                                text: "Notifications"
                                      + (NotificationService.count > 0
                                         ? "  " + NotificationService.count : "")
                                color:           Theme.text
                                font.pixelSize:  14
                                Layout.fillWidth: true
                            }
                            PillButton {
                                label:   "Clear all"
                                visible: NotificationService.count > 0 || root.queued > 0
                                onClicked: NotificationService.clearAll()
                            }
                        }

                        Text {
                            visible:            NotificationService.count === 0
                            width:              parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text:               "You're all caught up"
                            color:              Theme.muted
                            font.pixelSize:     12
                            topPadding:         8; bottomPadding: 8
                        }

                        Repeater {
                            model: NotificationService.notifList
                            NotificationCard {
                                name:      modelData.appName
                                body:      modelData.summary || modelData.body
                                age:       NotificationService.timeAgo(modelData.timestamp)
                                timestamp: modelData.timestamp
                                onDismissed: NotificationService.removeNotification(modelData.notifId)
                            }
                        }
                    }

                    // Toast banner
                    Rectangle {
                        id: toast
                        property string text: ""
                        visible:         false
                        width:           parent.width - 28
                        height:          42
                        radius:          21
                        antialiasing:    true
                        color:           Theme.surfaceRaised
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            anchors.fill:    parent
                            anchors.margins: 12
                            text:            toast.text
                            color:           Theme.text
                            font.pixelSize:  12
                            verticalAlignment: Text.AlignVCenter
                            elide:           Text.ElideRight
                        }
                    }
                }  // end contentColumn

                // ── DETAIL VIEWS ─────────────────────────────────────────
                Column {
                    id: detailColumn
                    visible:     root.page !== "main"
                    width:       parent.width - 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding:  4; bottomPadding: 24; spacing: 12

                    // ──── Wi-Fi view ──────────────────────────────────────
                    EmptyState {
                        visible: root.page === "wifi" && !root.wifi
                        iconName: "wifi"
                        title: "Wi-Fi is off"
                        body:  "Turn on Wi-Fi to see and join nearby networks."
                    }

                    Column {
                        visible: root.page === "wifi" && root.wifi
                        width: parent.width; spacing: 8

                        RowLayout {
                            width: parent.width
                            Text {
                                text:            "Networks"
                                color:           Theme.text
                                font.pixelSize:  14
                                Layout.fillWidth: true
                            }
                            PillButton {
                                label:    root.wifiScanning ? "Scanning…" : "Scan"
                                onClicked: root.wifiScan()
                            }
                        }
                        ScanBar { width: parent.width; active: root.wifiScanning }

                        Text {
                            visible:        NetworkService.savedNetworks.length > 0
                            text:           "SAVED"
                            color:          Theme.muted
                            font.pixelSize: 11
                            font.letterSpacing: 1
                        }
                        Repeater {
                            model: NetworkService.networks
                            NetworkRow {
                                visible:  modelData.known
                                name:     String(modelData.ssid || modelData.name || "")
                                level:    Math.round(NetworkService.signalPercentage(modelData) / 25)
                                security: NetworkService.security(modelData)
                                band:     NetworkService.bandChannel(modelData)
                                saved:    !!modelData.known
                                status:   NetworkService.networkKey(modelData) === NetworkService.connectingNetworkKey
                                          ? "connecting"
                                          : (NetworkService.activeNetwork
                                             && NetworkService.networkKey(NetworkService.activeNetwork) === NetworkService.networkKey(modelData))
                                             ? "connected" : "idle"
                                password: NetworkService.revealedPasswordKey === NetworkService.networkKey(modelData)
                                          ? NetworkService.revealedPassword : ""
                                _networkObject: modelData
                                onConnectRequested: function(pass) {
                                    root.wifiConnectTo(modelData, pass)
                                }
                                onDisconnectRequested: root.wifiDisconnect(modelData)
                                onForgetRequested:     root.wifiForget(modelData)
                            }
                        }

                        Text {
                            visible: NetworkService.networks.filter(n => !n.known).length > 0
                            text:           "AVAILABLE"
                            color:          Theme.muted
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            topPadding:     6
                        }
                        Repeater {
                            model: NetworkService.networks
                            NetworkRow {
                                visible:  !modelData.known
                                name:     String(modelData.ssid || modelData.name || "")
                                level:    Math.round(NetworkService.signalPercentage(modelData) / 25)
                                security: NetworkService.security(modelData)
                                band:     NetworkService.bandChannel(modelData)
                                saved:    !!modelData.known
                                status:   NetworkService.networkKey(modelData) === NetworkService.connectingNetworkKey
                                          ? "connecting"
                                          : (NetworkService.activeNetwork
                                             && NetworkService.networkKey(NetworkService.activeNetwork) === NetworkService.networkKey(modelData))
                                             ? "connected" : "idle"
                                password: ""
                                _networkObject: modelData
                                onConnectRequested: function(pass) {
                                    root.wifiConnectTo(modelData, pass)
                                }
                                onDisconnectRequested: root.wifiDisconnect(modelData)
                                onForgetRequested:     root.wifiForget(modelData)
                            }
                        }
                    }

                    // ──── Bluetooth view ──────────────────────────────────
                    EmptyState {
                        visible: root.page === "bluetooth" && !root.bluetooth
                        iconName: "bluetooth"
                        title: "Bluetooth is off"
                        body:  "Turn on Bluetooth to connect headphones, keyboards and more."
                    }

                    Column {
                        visible: root.page === "bluetooth" && root.bluetooth
                        width: parent.width; spacing: 8

                        RowLayout {
                            width: parent.width
                            Text {
                                text:            "Devices"
                                color:           Theme.text
                                font.pixelSize:  14
                                Layout.fillWidth: true
                            }
                            PillButton {
                                label:    root.btScanning ? "Scanning…" : "Scan"
                                onClicked: root.btScan()
                            }
                        }
                        ScanBar { width: parent.width; active: root.btScanning }
                        BluetoothPairPrompt { width: parent.width; height: implicitHeight }

                        Text {
                            visible:        BluetoothService.connectedDevices.length > 0
                                            || BluetoothService.devices.filter(d => BluetoothService.value(d, "paired")).length > 0
                            text:           "MY DEVICES"
                            color:          Theme.muted
                            font.pixelSize: 11
                            font.letterSpacing: 1
                        }
                        Repeater {
                            model: BluetoothService.devices
                            DeviceRow {
                                visible:  BluetoothService.value(modelData, "paired")
                                name:     BluetoothService.displayName(modelData)
                                kind:     String(BluetoothService.value(modelData, "icon") || "other")
                                battery:  BluetoothService.value(modelData, "batteryAvailable")
                                          ? Math.round(BluetoothService.value(modelData, "battery") * 100)
                                          : -1
                                paired:   BluetoothService.value(modelData, "paired")
                                status:   BluetoothService.deviceStatus(modelData).toLowerCase()
                                         .indexOf("connect") >= 0
                                          ? (BluetoothService.deviceStatus(modelData) === "Connected" ? "connected" : "connecting")
                                          : "idle"
                                onConnectRequested:    root.btConnectTo(modelData)
                                onDisconnectRequested: root.btDisconnect(modelData)
                                onForgetRequested:     root.btForget(modelData)
                            }
                        }

                        Text {
                            visible: BluetoothService.devices.filter(d => !BluetoothService.value(d, "paired")).length > 0
                            text:           "NEARBY"
                            color:          Theme.muted
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            topPadding:     6
                        }
                        Repeater {
                            model: BluetoothService.devices
                            DeviceRow {
                                visible:  !BluetoothService.value(modelData, "paired")
                                name:     BluetoothService.displayName(modelData)
                                kind:     String(BluetoothService.value(modelData, "icon") || "other")
                                battery:  -1
                                paired:   false
                                status:   "idle"
                                onConnectRequested:    root.btConnectTo(modelData)
                                onDisconnectRequested: root.btDisconnect(modelData)
                                onForgetRequested:     root.btForget(modelData)
                            }
                        }
                    }

                    // ──── Alerts view ─────────────────────────────────────
                    DetailRow {
                        visible:  root.page === "alerts"
                        title:    "Queued notifications"
                        subtitle: root.dnd
                                  ? root.queued + " waiting" : "Showing banners normally"
                    }
                    Repeater {
                        model: root.page === "alerts" ? NotificationService.notifList : []
                        NotificationCard {
                            name:     modelData.appName
                            body:     modelData.summary || modelData.body
                            age:      NotificationService.timeAgo(modelData.timestamp)
                            timestamp: modelData.timestamp
                            onDismissed: NotificationService.removeNotification(modelData.notifId)
                        }
                    }

                    // ──── Sound view ──────────────────────────────────────
                    Column {
                        visible: root.page === "sound"
                        width:   parent.width
                        spacing: 8

                        // ── Volume slider ─────────────────────────────────
                        Text {
                            text:               "VOLUME"
                            color:              Theme.muted
                            font.pixelSize:     11
                            font.letterSpacing: 1
                        }

                        Rectangle {
                            width:  parent.width
                            height: volRow.implicitHeight + 28
                            radius: Theme.radiusCard
                            color:  Theme.surfaceRaised

                            RowLayout {
                                id:              volRow
                                anchors.fill:    parent
                                anchors.margins: 14
                                spacing:         12

                                // mute toggle icon
                                Rectangle {
                                    width: 36; height: 36; radius: 18
                                    color: AudioService.muted ? Theme.error : Theme.surface
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    SpeakerIcon {
                                        anchors.centerIn: parent
                                        muted: AudioService.muted
                                        level: root.volume
                                        tint:  AudioService.muted ? Theme.background : Theme.primary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked:    AudioService.toggleMute()
                                    }
                                }

                                PillSlider {
                                    Layout.fillWidth: true
                                    from:  0; to: 100
                                    value: root.sound ? root.volume : 0
                                    onMoved: {
                                        AudioService.setVolume(value / 100)
                                        if (value > 0 && AudioService.muted)
                                            AudioService.setMuted(false)
                                    }
                                }

                                Text {
                                    text:           root.volume + "%"
                                    color:          Theme.text
                                    font.pixelSize: 13
                                    font.weight:    Font.Medium
                                    Layout.preferredWidth: 36
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        Text {
                            text:               "BALANCE"
                            color:              Theme.muted
                            font.pixelSize:     11
                            font.letterSpacing: 1
                        }

                        Rectangle {
                            width:  parent.width
                            height: balCol.implicitHeight + 28
                            radius: 22
                            antialiasing: true
                            color:  Theme.surfaceRaised

                            ColumnLayout {
                                id: balCol
                                anchors.left:    parent.left
                                anchors.right:   parent.right
                                anchors.top:     parent.top
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text:            "Left / right"
                                        color:           Theme.text
                                        font.pixelSize:  13
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        // balance is -1..1 internally; display as -100..+100%
                                        readonly property int pct: Math.round(root.balance * 100)
                                        text:  pct === 0 ? "Center"
                                             : pct < 0   ? "Left "  + (-pct) + "%"
                                             :              "Right " + pct    + "%"
                                        color:          Theme.primary
                                        font.pixelSize: 12
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text { text: "L"; color: Theme.muted; font.pixelSize: 13; font.weight: Font.Medium }
                                    BalanceSlider {
                                        Layout.fillWidth: true
                                        // slider uses -100..100; service uses -1..1
                                        value: Math.round(root.balance * 100)
                                        onMoved: AudioService.setOutputBalance(value / 100)
                                    }
                                    Text { text: "R"; color: Theme.muted; font.pixelSize: 13; font.weight: Font.Medium }
                                }

                                // Left / right level meters
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text { text: "L"; color: Theme.muted; font.pixelSize: 11; Layout.preferredWidth: 10 }
                                    PillProgress {
                                        from:  0; to: 100
                                        value: {
                                            var m = AudioService.outputMaster * 100
                                            var b = root.balance
                                            return Math.round(m * (b > 0 ? (1 - b) : 1))
                                        }
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                    }
                                    Text {
                                        text: {
                                            var m = AudioService.outputMaster * 100
                                            var b = root.balance
                                            return Math.round(m * (b > 0 ? (1 - b) : 1)) + "%"
                                        }
                                        color: Theme.muted; font.pixelSize: 11
                                        Layout.preferredWidth: 32
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text { text: "R"; color: Theme.muted; font.pixelSize: 11; Layout.preferredWidth: 10 }
                                    PillProgress {
                                        from:  0; to: 100
                                        value: {
                                            var m = AudioService.outputMaster * 100
                                            var b = root.balance
                                            return Math.round(m * (b < 0 ? (1 + b) : 1))
                                        }
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                    }
                                    Text {
                                        text: {
                                            var m = AudioService.outputMaster * 100
                                            var b = root.balance
                                            return Math.round(m * (b < 0 ? (1 + b) : 1)) + "%"
                                        }
                                        color: Theme.muted; font.pixelSize: 11
                                        Layout.preferredWidth: 32
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                PillButton {
                                    visible:           root.balance !== 0
                                    label:             "Center"
                                    Layout.alignment:  Qt.AlignRight
                                    onClicked:         AudioService.setOutputBalance(0)
                                }
                            }
                        }

                        Text {
                            text:               "OUTPUT"
                            color:              Theme.muted
                            font.pixelSize:     11
                            font.letterSpacing: 1
                            topPadding:         8
                        }
                        Repeater {
                            // Built-in (non-BT) first, then Bluetooth
                            model: AudioService.outputChoices.slice().sort(
                                (a, b) => Number(a.isBluetooth) - Number(b.isBluetooth)
                            )
                            AudioDeviceRow {
                                title:    modelData.description
                                subtitle: modelData.detail
                                glyph:    modelData.isBluetooth ? "♫" : "♪"
                                selected: modelData.active
                                onChosen: AudioService.selectOutput(modelData)
                            }
                        }

                        Text {
                            text:               "INPUT"
                            color:              Theme.muted
                            font.pixelSize:     11
                            font.letterSpacing: 1
                            topPadding:         8
                        }
                        Repeater {
                            // Built-in (non-BT) first, then Bluetooth
                            model: AudioService.inputChoices.slice().sort(
                                (a, b) => Number(a.isBluetooth) - Number(b.isBluetooth)
                            )
                            AudioDeviceRow {
                                title:    modelData.description
                                subtitle: modelData.detail
                                glyph:    modelData.isBluetooth ? "♫" : "◉"
                                selected: modelData.active
                                onChosen: AudioService.selectInput(modelData)
                            }
                        }
                    }

                    // ──── System Panel view ───────────────────────────────
                    Column {
                        visible: root.page === "system"
                        width:   parent.width
                        spacing: 8

                        // 4 gauge cards in a 2×2 grid
                        GridLayout {
                            width: parent.width; columns: 2; columnSpacing: 8; rowSpacing: 8
                            GaugeCard {
                                title: "CPU"
                                value: sysStats.cpuPercent / 100
                                label: sysStats.cpuPercent + "%"
                                sub:   (sysStats.cpuTemp > 0 ? Math.round(sysStats.cpuTemp) + "°C · " : "")
                                       + (sysStats.cpuCores > 0 ? sysStats.cpuCores + " cores" : "")
                            }
                            GaugeCard {
                                title: "Memory"
                                value: sysStats.ramTotalKb > 0 ? sysStats.ramUsedKb / sysStats.ramTotalKb : 0
                                label: sysStats.ramPercent() + "%"
                                sub:   sysStats.kbText(sysStats.ramUsedKb) + " of " + sysStats.kbText(sysStats.ramTotalKb)
                            }
                            GaugeCard {
                                title:     "Storage"
                                available: sysStats.diskTotal > 0
                                value:     sysStats.diskTotal > 0 ? sysStats.diskUsed / sysStats.diskTotal : 0
                                label:     sysStats.diskTotal > 0 ? Math.round(sysStats.diskUsed * 100 / sysStats.diskTotal) + "%" : "–"
                                sub:       sysStats.diskTotal > 0 ? sysStats.gbText(sysStats.diskTotal - sysStats.diskUsed) + " free" : ""
                            }
                            GaugeCard {
                                title:     "GPU"
                                available: sysStats.gpuUtil >= 0
                                value:     sysStats.gpuUtil >= 0 ? sysStats.gpuUtil / 100 : 0
                                label:     sysStats.gpuUtil >= 0 ? sysStats.gpuUtil + "%" : "–"
                                sub:       sysStats.gpuUtil < 0 ? "Not available"
                                           : (sysStats.gpuTemp > 0 ? Math.round(sysStats.gpuTemp) + "°C" : "")
                                             + (sysStats.gpuMemTotal > 0
                                                ? (sysStats.gpuTemp > 0 ? " · " : "") + sysStats.mibText(sysStats.gpuMemUsed) + " / " + sysStats.mibText(sysStats.gpuMemTotal)
                                                : "")
                            }
                        }

                        // Sparkline activity chart
                        Rectangle {
                            width: parent.width; height: 96; radius: Theme.radiusCard; color: Theme.surfaceRaised
                            Row {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12; spacing: 12
                                Row { spacing: 5
                                    Rectangle { width: 7; height: 7; radius: 3.5; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "CPU " + sysStats.cpuPercent + "%"; color: Theme.muted; font.pixelSize: 10 }
                                }
                                Row { spacing: 5
                                    Rectangle { width: 7; height: 7; radius: 3.5; color: Theme.success; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "RAM " + sysStats.ramPercent() + "%"; color: Theme.muted; font.pixelSize: 10 }
                                }
                            }
                            Sparkline {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.bottomMargin: 10
                                height: 58
                                lines: [
                                    { data: sysStats.ramHist, color: Theme.success  },
                                    { data: sysStats.cpuHist, color: Theme.primary  }
                                ]
                            }
                        }

                        // Fan card
                        Rectangle {
                            width: parent.width; height: fanCardCol.implicitHeight + 20; radius: Theme.radiusCard; color: Theme.surfaceRaised
                            Column {
                                id: fanCardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; topMargin: 10 }
                                spacing: 8
                                RowLayout {
                                    width: parent.width; spacing: 10
                                    FanIcon { rpm: sysStats.fanRpmList.length > 0 ? sysStats.fanRpmList[0] : 0; tint: sysStats.fanMode === "max" ? Theme.warning : Theme.primary; Layout.alignment: Qt.AlignVCenter }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                                        Text { text: "Fan"; color: Theme.text; font.pixelSize: 13 }
                                        Text { text: sysStats.fanControllable ? (sysStats.fanMode === "max" ? "Max speed" : "Automatic") : (sysStats.fanRpmList.length > 0 ? "Read-only" : "No sensor"); color: Theme.muted; font.pixelSize: 10 }
                                    }
                                    Text { text: sysStats.fanText(); color: sysStats.fanMode === "max" ? Theme.warning : Theme.primary; font.pixelSize: 15; font.weight: Font.Medium }
                                }
                                Segmented {
                                    width: parent.width
                                    options: [["auto", "Auto"], ["max", "Max"]]
                                    current: sysStats.fanMode
                                    interactive: sysStats.fanControllable
                                    onPicked: function(k) { sysStats.setFanMode(k) }
                                }
                            }
                        }

                        // Info cells grid
                        GridLayout {
                            width: parent.width; columns: 3; columnSpacing: 8; rowSpacing: 8
                            InfoCell { label: "Uptime";    value: sysStats.uptimeSec > 0 ? sysStats.uptimeText() : "–" }
                            InfoCell { label: "Processes"; value: sysStats.procCount > 0 ? sysStats.procCount : "–" }
                            InfoCell { label: "Load";      value: sysStats.loadAvg.toFixed(2) }
                            InfoCell { Layout.columnSpan: 2; label: "Swap"; value: sysStats.swapTotalKb > 0 ? sysStats.kbText(sysStats.swapUsedKb) + " of " + sysStats.kbText(sysStats.swapTotalKb) : "None" }
                            InfoCell { label: "Battery";   value: root.battery >= 0 ? root.battery + "%" : "–" }
                        }

                        // Hardware strings
                        Rectangle {
                            width: parent.width; height: hwStrCol.implicitHeight + 16; radius: Theme.radiusControl; color: Theme.surfaceRaised
                            Column {
                                id: hwStrCol
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                                spacing: 3
                                Text { text: "CPU   " + (sysStats.cpuModel !== "" ? sysStats.cpuModel : "Unknown"); width: parent.width; color: Theme.muted; font.pixelSize: 10; elide: Text.ElideRight }
                                Text { text: "GPU   " + (sysStats.gpuName  !== "" ? sysStats.gpuName  : "Not detected"); width: parent.width; color: Theme.muted; font.pixelSize: 10; elide: Text.ElideRight }
                            }
                        }

                        // Power profile segmented picker
                        Segmented {
                            width: parent.width
                            options: [["power-saver", "Saver"], ["balanced", "Balanced"], ["performance", "Performance"]]
                            current: root.systemPowerProfile
                            onPicked: function(k) { SystemService.setPowerProfile(k) }
                        }
                    }

                    // ──── Workspaces view ─────────────────────────────────
                    Column {
                        visible: root.page === "workspaces"
                        width:   parent.width; spacing: 10

                        Repeater {
                            model: wsManager.workspaceData
                            Rectangle {
                                id:              wsCard
                                required property var modelData
                                readonly property int    wsId:    modelData.id
                                readonly property var    apps:    modelData.clients || []
                                readonly property bool   current: wsId === wsManager.activeWorkspaceId
                                width:  parent.width
                                height: wsCol.implicitHeight + 24
                                radius: 22; antialiasing: true
                                color:  Theme.surfaceRaised
                                border.width: current ? 2 : 0
                                border.color: Theme.primary

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked:    wsManager.switchWorkspace(wsCard.wsId)
                                }

                                Column {
                                    id:      wsCol
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: 12; anchors.topMargin: 12
                                    spacing: 8

                                    RowLayout {
                                        width: parent.width; spacing: 10
                                        Rectangle {
                                            Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 15
                                            color: wsCard.current ? Theme.primary : Theme.surface
                                            Text { anchors.centerIn: parent; text: wsCard.wsId; font.pixelSize: 14; font.weight: Font.DemiBold; color: wsCard.current ? Theme.background : Theme.muted }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 1
                                            Text { text: "Workspace " + wsCard.wsId; color: Theme.text; font.pixelSize: 14 }
                                            Text { text: wsCard.apps.length === 0 ? "Empty" : wsCard.apps.length + (wsCard.apps.length === 1 ? " app" : " apps"); color: Theme.muted; font.pixelSize: 11 }
                                        }
                                        Rectangle {
                                            visible: wsCard.current
                                            Layout.preferredWidth: curLbl.implicitWidth + 18; Layout.preferredHeight: 22; radius: 11
                                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                            Text { id: curLbl; anchors.centerIn: parent; text: "Current"; color: Theme.primary; font.pixelSize: 11 }
                                        }
                                    }

                                    Repeater {
                                        model: wsCard.apps
                                        Rectangle {
                                            required property var modelData
                                            width: wsCol.width; height: 44; radius: 16; antialiasing: true
                                            color: Theme.surface
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12; spacing: 10

                                                // App icon — real icon if available, letter fallback otherwise
                                                Rectangle {
                                                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                                                    radius: 8; color: Theme.surfaceRaised

                                                    Image {
                                                        id:             appIcon
                                                        anchors.fill:   parent
                                                        anchors.margins: 3
                                                        source:          modelData.iconPath || ""
                                                        fillMode:        Image.PreserveAspectFit
                                                        smooth:          true
                                                        visible:         status === Image.Ready
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible:          !appIcon.visible
                                                        text:             (modelData.appClass || "?").charAt(0).toUpperCase()
                                                        color:            Theme.primary
                                                        font.pixelSize:   14; font.weight: Font.DemiBold
                                                    }
                                                }

                                                Text { text: modelData.appClass || "Unknown"; color: Theme.text; font.pixelSize: 13 }
                                                Text { text: modelData.title || ""; color: Theme.muted; font.pixelSize: 11; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true }
                                                Rectangle {
                                                    Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14; antialiasing: true
                                                    color: closeArea.pressed ? Theme.error : closeArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.3) : Theme.surfaceRaised
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                    Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 12; color: closeArea.containsMouse ? Theme.text : Theme.muted }
                                                    MouseArea {
                                                        id:           closeArea
                                                        anchors.fill: parent; anchors.margins: -4
                                                        hoverEnabled: true
                                                        onClicked:    wsManager.killClient(modelData.address)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ──── Power page ──────────────────────────────────────
                    Column {
                        visible: root.page === "power"
                        width:   parent.width; spacing: 8

                        Repeater {
                            model: [
                                { key: "sleep",    title: "Sleep",     sub: "Suspend to RAM",          cmd: ["systemctl", "suspend"]  },
                                { key: "logout",   title: "Log out",   sub: "End this session",        cmd: ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""] },
                                { key: "restart",  title: "Restart",   sub: "Reboot the computer",     cmd: ["systemctl", "reboot"]   },
                                { key: "poweroff", title: "Power off", sub: "Shut down the computer",  cmd: ["systemctl", "poweroff"] }
                            ]
                            Rectangle {
                                required property var modelData
                                readonly property bool armed: root.pendingPower === modelData.key
                                width: parent.width; height: 56; radius: 22; antialiasing: true
                                color: armed ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.22)
                                             : rowPressArea.pressed ? Theme.surfaceHover : Theme.surfaceRaised
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { text: modelData.title; color: Theme.text; font.pixelSize: 13 }
                                        Text { text: armed ? "Tap again to confirm" : modelData.sub; color: armed ? Theme.error : Theme.muted; font.pixelSize: 11 }
                                    }
                                }
                                MouseArea { id: rowPressArea; anchors.fill: parent; onClicked: root.powerAction(modelData.key, modelData.cmd) }
                            }
                        }
                    }

                    // ──── Updates page ────────────────────────────────────
                    Column {
                        visible: root.page === "updates"
                        width:   parent.width; spacing: 10

                        Rectangle {
                            width: parent.width; height: 72; radius: 22; antialiasing: true
                            color: Theme.surfaceRaised
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14; spacing: 12
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text {
                                        text:           root.pendingUpdates > 0 ? root.pendingUpdates : "✓"
                                        color:          root.pendingUpdates > 0 ? Theme.primary : Theme.success
                                        font.pixelSize: 28; font.weight: Font.Medium
                                    }
                                    Text { text: "pending updates"; color: Theme.muted; font.pixelSize: 11 }
                                }
                                Text {
                                    text:           root.updateTooltip
                                    color:          Theme.muted; font.pixelSize: 11
                                    wrapMode:       Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        EmptyState {
                            visible: root.pendingUpdates === 0
                            glyph: "✓"; title: "You're up to date"; body: "No package updates are waiting."
                        }
                    }

                }  // end detailColumn
            }  // end Flickable
        }  // end panel Item

        // ════════════════════════════════════════════════════════════════
        // INLINE COMPONENT DEFINITIONS (kept inside PanelWindow so they
        // can reference the root PanelWindow's properties directly)
        // ════════════════════════════════════════════════════════════════

        component IslandLeftIcon: Item {
            id: leftIcon
            property bool wifiOn:          true
            property bool notificationsOn: true
            width: 28; height: 29
            layer.enabled: true; layer.samples: 4; layer.smooth: true

            Shape {
                anchors.fill: parent; antialiasing: true
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: leftIcon.wifiOn ? Theme.islandMuted : Theme.islandMutedDim
                    strokeWidth: 2.2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M2.4 8.2A15.2 15.2 0 0 1 25.6 8.2 M6.2 11.4A10.2 10.2 0 0 1 21.8 11.4" }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: leftIcon.notificationsOn ? Theme.islandMuted : Theme.islandMutedDim
                    strokeWidth: 2.2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M6.6 24.2 8 22.2C8.6 21 8.8 19.2 8.8 17.2A5.2 5.2 0 0 1 19.2 17.2C19.2 19.2 19.4 21 20 22.2L21.4 24.2Z M11.8 27h4.4" }
                }
            }
            Rectangle { x: 12.1; y: 16.1; width: 3.8; height: 3.8; radius: 1.9; antialiasing: true
                color: leftIcon.wifiOn ? Theme.islandMuted : Theme.islandMutedDim }
            Rectangle { x: 19.6; y: 13.0; width: 5.2; height: 5.2; radius: 2.6; antialiasing: true
                color: Theme.islandAccent
                visible: NotificationService.count > 0 && !NotificationService.dndEnabled }
        }

        component IslandRightIcon: Item {
            id: rightIcon
            property bool bluetoothOn: true
            property bool soundOn:     true
            width: 34; height: 24
            layer.enabled: true; layer.samples: 4; layer.smooth: true

            Shape {
                anchors.fill: parent; antialiasing: true
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: rightIcon.bluetoothOn ? Theme.islandMuted : Theme.islandMutedDim
                    strokeWidth: 2.2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M5 7.6 13.6 14.9A1.8 1.8 0 0 1 13.6 17.6L11.2 19.9A1.1 1.1 0 0 1 10 19V5A1.1 1.1 0 0 1 11.2 4.1L13.6 6.4A1.8 1.8 0 0 1 13.6 9.1L5 16.4" }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: rightIcon.soundOn ? Theme.islandMuted : Theme.islandMutedDim
                    strokeWidth: 2.2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M19.8 8.3a5.4 5.4 0 0 1 0 7.4 M23.6 5.2a10 10 0 0 1 0 13.6 M27.4 2.2a14.6 14.6 0 0 1 0 19.6" }
                }
            }
        }

        component Tile: Rectangle {
            id: tile
            property string title:    "Tile"
            property string subtitle: "Off"
            property string glyph:    "•"
            property string icon:     ""
            property bool   iconMuted: false
            property int    iconLevel: 100
            property string tag:      ""
            property bool   active:   false
            property bool   unavailable: false
            signal tapped()
            signal opened()
            Layout.fillWidth: true
            height: 64; radius: 32; antialiasing: true
            color:   unavailable ? Qt.rgba(0.12, 0.13, 0.14, 1)
                   : active      ? Theme.primary : Theme.surfaceRaised
            opacity: unavailable ? 0.42 : 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 9

                Rectangle {
                    width: 36; height: 36; radius: 18
                    color: tile.active ? Theme.background : Theme.surface

                    Text {
                        visible:           tile.icon === ""
                        anchors.centerIn:  parent
                        text:              tile.glyph
                        color:             tile.active ? Theme.primary : Theme.muted
                        font.pixelSize:    18
                    }
                    SpeakerIcon {
                        visible:          tile.icon === "speaker"
                        anchors.centerIn: parent
                        muted:            tile.iconMuted
                        level:            tile.iconLevel
                        tint:             tile.active ? Theme.primary : Theme.muted
                    }
                    WifiIcon {
                        visible:          tile.icon === "wifi"
                        anchors.centerIn: parent
                        tint:             tile.active ? Theme.primary : Theme.muted
                    }
                    BluetoothIcon {
                        visible:          tile.icon === "bluetooth"
                        anchors.centerIn: parent
                        tint:             tile.active ? Theme.primary : Theme.muted
                    }
                    CaffeineIcon {
                        visible:          tile.icon === "caffeine"
                        anchors.centerIn: parent
                        tint:             tile.active ? Theme.primary : Theme.muted
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text {
                        text:             tile.title + (tile.tag ? "  " + tile.tag : "")
                        color:            tile.active ? Theme.background : Theme.text
                        font.pixelSize:   12
                        wrapMode:         Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        text:             tile.subtitle
                        color:            tile.active ? Theme.surface : Theme.muted
                        font.pixelSize:   11
                        elide:            Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Text {
                    text:           "›"
                    color:          tile.active ? Theme.background : Theme.muted
                    font.pixelSize: 20
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: !tile.unavailable
                onClicked: tile.tapped()
                onPressAndHold: tile.opened()
            }
            MouseArea {
                anchors.right:  parent.right
                width:  42; height: parent.height
                enabled: !tile.unavailable
                onClicked: tile.opened()
            }
        }

        component NotificationCard: Rectangle {
            property string name:      "Name"
            property string body:      "Message"
            property string age:       "now"
            property real   timestamp: 0
            signal dismissed()
            width: parent ? parent.width : 0
            height: notifCardCol.implicitHeight + 20
            radius: 22; antialiasing: true
            color:  Theme.surfaceRaised

            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 10
                Rectangle {
                    width: 32; height: 32; radius: 16
                    color: Theme.surface
                    Layout.alignment: Qt.AlignTop; Layout.topMargin: 2
                    Text { anchors.centerIn: parent; text: "◌"; color: Theme.primary; font.pixelSize: 16 }
                }
                ColumnLayout {
                    id: notifCardCol
                    Layout.fillWidth: true; spacing: 3
                    // App name row with clock time on the right
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: name; color: Theme.text; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text {
                            text: timestamp > 0
                                  ? Qt.formatTime(new Date(timestamp), "h:mm AP")
                                  : age
                            color: Theme.muted; font.pixelSize: 10
                        }
                    }
                    // Relative age
                    Text { text: age; color: Theme.muted; font.pixelSize: 10 }
                    // Body
                    Text {
                        text:             body
                        color:            Theme.muted
                        font.pixelSize:   11
                        wrapMode:         Text.WordWrap
                        maximumLineCount: 2
                        Layout.fillWidth: true
                    }
                }
                PillButton { label: "×"; onClicked: dismissed() }
            }
        }

        component DetailRow: Rectangle {
            id: detailRowRoot
            property string title:    "Item"
            property string subtitle: "Available"
            property bool   checked:  false
            width:  parent ? parent.width : 0
            height: 56; radius: 22; antialiasing: true
            color:  Theme.surfaceRaised

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18; anchors.rightMargin: 18
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: detailRowRoot.title;    color: Theme.text;  font.pixelSize: 13 }
                    Text { text: detailRowRoot.subtitle; color: Theme.muted; font.pixelSize: 11 }
                }
                Text {
                    visible:        detailRowRoot.checked
                    text:           "✓"
                    color:          Theme.primary
                    font.pixelSize: 18
                }
            }
        }

        component PillButton: Rectangle {
            id: pb
            property string label:   ""
            property bool   primary: false
            signal clicked()
            implicitWidth:  Math.max(pbText.implicitWidth + 28, 40)
            implicitHeight: 34
            radius: height / 2; antialiasing: true
            color:   primary ? Theme.primary : Theme.surfaceRaised
            opacity: pbMouse.pressed ? 0.7 : 1
            Behavior on opacity { NumberAnimation { duration: 80 } }
            Text {
                id: pbText; anchors.centerIn: parent
                text:           pb.label
                color:          pb.primary ? Theme.background : Theme.text
                font.pixelSize: 12; font.weight: Font.Medium
            }
            MouseArea { id: pbMouse; anchors.fill: parent; onClicked: pb.clicked() }
        }

        component ToggleSwitch: Rectangle {
            id: sw
            property bool checked: false
            signal toggled(bool value)
            // Optimistic: flips immediately on tap, syncs back when service confirms
            property bool _optimistic: checked
            onCheckedChanged: _optimistic = checked
            implicitWidth: 52; implicitHeight: 30
            radius: height / 2; antialiasing: true
            color: sw._optimistic ? Theme.primary : Theme.surface
            Behavior on color { ColorAnimation { duration: 80 } }
            Rectangle {
                width:  sw._optimistic ? 22 : 16; height: width; radius: width / 2; antialiasing: true
                anchors.verticalCenter: parent.verticalCenter
                x: sw._optimistic ? sw.width - width - 4 : 7
                color: sw._optimistic ? Theme.background : Theme.muted
                Behavior on x     { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 100 } }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    sw._optimistic = !sw._optimistic   // instant visual flip
                    sw.toggled(!sw.checked)             // fire the real toggle
                }
            }
        }

        component PageHeader: RowLayout {
            id: ph
            property string title:      ""
            property string subtitle:   ""
            property bool   showSwitch: false
            property bool   checked:    false
            property bool   showClear:  false
            signal back()
            signal toggled(bool value)
            signal cleared()
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 38; Layout.preferredHeight: 38
                radius: 19; antialiasing: true; color: Theme.surfaceRaised
                Text {
                    anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                    text: "‹"; color: Theme.text; font.pixelSize: 24
                }
                MouseArea { anchors.fill: parent; onClicked: ph.back() }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Text { text: ph.title;    color: Theme.text;  font.pixelSize: 20 }
                Text {
                    visible:          ph.subtitle !== ""
                    text:             ph.subtitle
                    color:            Theme.muted
                    font.pixelSize:   12
                    elide:            Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            // Clear all button — shown on alerts page
            Rectangle {
                visible: ph.showClear
                Layout.preferredHeight: 30
                implicitWidth: clearTxt.implicitWidth + 20
                radius: 15; antialiasing: true
                color: clearHov.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    id: clearTxt
                    anchors.centerIn: parent
                    text:           "Clear all"
                    color:          Theme.muted
                    font.pixelSize: 12
                }
                MouseArea {
                    id:           clearHov
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked:    ph.cleared()
                }
            }
            Item { Layout.preferredWidth: 8; visible: ph.showSwitch }
            // DND toggle — rightmost
            ToggleSwitch {
                visible: ph.showSwitch
                Layout.preferredWidth: 52; Layout.preferredHeight: 30
                checked:   ph.checked
                onToggled: function(v) { ph.toggled(v) }
            }
        }

        component ScanBar: Rectangle {
            id: sb
            property bool active: false
            implicitHeight: 3; radius: 1.5
            color: active ? Theme.surface : "transparent"
            clip:  true
            Rectangle {
                id: seg
                visible: sb.active
                width: sb.width * 0.3; height: parent.height; radius: 1.5; antialiasing: true
                color: Theme.primary
                SequentialAnimation {
                    running: sb.active; loops: Animation.Infinite
                    NumberAnimation {
                        target: seg; property: "x"
                        from: -seg.width; to: sb.width
                        duration: 1100; easing.type: Easing.InOutQuad
                    }
                }
            }
        }

        component EmptyState: Rectangle {
            property string glyph:    ""
            property string iconName: ""
            property string title:    ""
            property string body:     ""
            width:  parent ? parent.width : 0
            height: 164; radius: 22; antialiasing: true; color: Theme.surfaceRaised

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 48; spacing: 8
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 52; Layout.preferredHeight: 52
                    radius: 26; antialiasing: true; color: Theme.surface

                    // SVG icon if iconName provided, text glyph fallback
                    SvgIcon {
                        anchors.centerIn: parent
                        width: 28; height: 28
                        iconName: parent.parent.parent.iconName
                        tone: "muted"
                        visible: parent.parent.parent.iconName !== ""
                    }
                    Text {
                        anchors.centerIn: parent
                        text:    glyph
                        color:   Theme.muted
                        font.pixelSize: 24
                        visible: iconName === ""
                    }
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: title; color: Theme.text;  font.pixelSize: 15 }
                Text {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    text: body; wrapMode: Text.WordWrap
                    color: Theme.muted; font.pixelSize: 12
                }
            }
        }

        component InfoLine: RowLayout {
            property string label: ""
            property string value: ""
            Text { text: label; color: Theme.muted;  font.pixelSize: 12; Layout.fillWidth: true }
            Text { text: value; color: Theme.text; font.pixelSize: 12 }
        }

        component SignalBars: Row {
            id: bars
            property int   level: 0
            property color tint:  Theme.text
            spacing: 2.5
            Repeater {
                model: 4
                Item {
                    width: 4; height: 18
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: 4; height: 6 + index * 4; radius: 2; antialiasing: true
                        color: index < bars.level ? bars.tint : Theme.surface
                    }
                }
            }
        }

        component InfoButton: Rectangle {
            id: ib
            property bool active: false
            signal clicked()
            implicitWidth: 32; implicitHeight: 32; radius: 16; antialiasing: true
            color: ib.active ? Theme.primary : Theme.surfaceRaised
            opacity: ibMouse.pressed ? 0.7 : 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Rectangle { x: 14.7; y: 9.4; width: 2.6; height: 2.6; radius: 1.3; antialiasing: true
                color: ib.active ? Theme.background : Theme.text }
            Rectangle { x: 14.8; y: 13.8; width: 2.4; height: 8; radius: 1.2; antialiasing: true
                color: ib.active ? Theme.background : Theme.text }
            MouseArea { id: ibMouse; anchors.fill: parent; onClicked: ib.clicked() }
        }

        component NetworkRow: Rectangle {
            id: nr
            property string name:        ""
            property int    level:       0   // 0..4
            property string security:    "Open"
            property string band:        ""
            property bool   saved:       false
            property string status:      "idle"
            property string password:    ""
            property bool   showDetails: false
            property bool   showPassword: false
            property bool   reveal:      false
            readonly property bool secured:    security !== "Open"
            readonly property bool connected:  status === "connected"
            readonly property bool connecting: status === "connecting"
            readonly property string signalText:
                ["No signal", "Weak", "Fair", "Good", "Excellent"][Math.max(0, Math.min(4, level))]
            readonly property int dbm:
                [-95, -82, -70, -60, -48][Math.max(0, Math.min(4, level))]
            signal connectRequested(string password)
            signal disconnectRequested()
            signal forgetRequested()

            onConnectedChanged:  if (connected)     showPassword = false
            onShowDetailsChanged: if (!showDetails) {
                reveal = false
                NetworkService.clearSavedPassword()
            } else if (connected && secured) {
                // kick off nmcli password lookup as soon as details open
                NetworkService.revealSavedPassword(nr._networkObject)
            }

            // hold a reference to the live network object so we can call revealSavedPassword
            property var _networkObject: null

            function activate() {
                if (connected)                          showDetails  = !showDetails
                else if (saved || !secured)             connectRequested("")
                else                                    showPassword = !showPassword
            }
            function join() {
                if (pw.text.length < 8) return
                var typed = pw.text; pw.text = ""; showPassword = false
                connectRequested(typed)
            }

            width:  parent ? parent.width : 0
            height: nrCol.implicitHeight
            radius: 22; antialiasing: true; clip: true
            color:  connected ? Theme.surfaceHover : Theme.surfaceRaised
            border.width: connected ? 1 : 0
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.34)
            Behavior on color  { ColorAnimation  { duration: 160 } }
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { width: parent.width; height: 62; enabled: !nr.connecting; onClicked: nr.activate() }

            ColumnLayout {
                id: nrCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 62
                    Layout.leftMargin: 16; Layout.rightMargin: 12; spacing: 10
                    SignalBars {
                        level: nr.level
                        tint:  nr.connected ? Theme.primary : Theme.muted
                        Layout.alignment: Qt.AlignVCenter
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        Text { text: nr.name; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 11
                            color: nr.connected ? Theme.primary : Theme.muted
                            text:  nr.connected  ? "Connected" + (nr.band && nr.band !== "Band unavailable" ? " · " + nr.band : "") + " · " + nr.signalText
                                 : nr.connecting ? "Connecting…"
                                 : (nr.saved ? "Saved · " : "") + nr.security
                        }
                    }
                    PillButton { visible: nr.connected;                             label: "Disconnect"; onClicked: nr.disconnectRequested() }
                    PillButton { visible: !nr.connected && !nr.connecting;          label: (nr.saved || !nr.secured) ? "Connect" : "Join"; primary: nr.saved || !nr.secured; onClicked: nr.activate() }
                    InfoButton { active: nr.showDetails; Layout.preferredWidth: 32; Layout.preferredHeight: 32; Layout.alignment: Qt.AlignVCenter; onClicked: nr.showDetails = !nr.showDetails }
                }

                ColumnLayout {
                    visible: nr.showPassword || nr.showDetails
                    Layout.fillWidth: true; Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.bottomMargin: 14
                    spacing: 10

                    RowLayout {
                        visible: nr.showPassword && !nr.saved && nr.secured && !nr.connected
                        Layout.fillWidth: true; spacing: 8
                        TextField {
                            id: pw
                            Layout.fillWidth: true; Layout.preferredHeight: 38
                            placeholderText: "Password (8+ characters)"
                            placeholderTextColor: Theme.muted
                            echoMode:       TextInput.Password
                            color:          Theme.text; font.pixelSize: 13
                            leftPadding:    16; rightPadding: 16; selectByMouse: true
                            background: Rectangle {
                                radius: 19; antialiasing: true; color: Theme.surface
                                border.width: pw.activeFocus ? 1 : 0; border.color: Theme.primary
                            }
                            onAccepted: nr.join()
                        }
                        PillButton { label: "Join"; primary: true; opacity: pw.text.length >= 8 ? 1 : 0.45; onClicked: nr.join() }
                    }

                    Rectangle { visible: nr.showDetails; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.outline }

                    ColumnLayout {
                        visible: nr.showDetails
                        Layout.fillWidth: true; spacing: 7
                        InfoLine { Layout.fillWidth: true; label: "Status";    value: nr.connected ? "Connected" : nr.connecting ? "Connecting…" : nr.saved ? "Saved" : "Not connected" }
                        InfoLine { Layout.fillWidth: true; label: "Security";  value: nr.security }

                        // Password row — always show for secured connected networks
                        RowLayout {
                            visible: nr.connected && nr.secured
                            Layout.fillWidth: true; spacing: 8

                            Text { text: "Password"; color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true }

                            // Read directly from NetworkService so the binding stays live
                            readonly property bool _isMyKey: nr._networkObject !== null
                                && NetworkService.revealedPasswordKey === NetworkService.networkKey(nr._networkObject)
                            readonly property string _livePassword: _isMyKey ? NetworkService.revealedPassword : ""

                            Text {
                                text: NetworkService.passwordLookupBusy && parent._isMyKey
                                    ? "Looking up…"
                                    : parent._livePassword !== ""
                                    ? (nr.reveal ? parent._livePassword
                                                 : "•".repeat(Math.min(parent._livePassword.length, 14)))
                                    : NetworkService.passwordLookupError !== "" && parent._isMyKey
                                    ? "Unavailable"
                                    : "Not stored"
                                color: Theme.text; font.pixelSize: 12
                            }
                            PillButton {
                                visible:   parent._livePassword !== "" && !NetworkService.passwordLookupBusy
                                label:     nr.reveal ? "Hide" : "Show"
                                onClicked: nr.reveal = !nr.reveal
                            }
                        }

                        InfoLine { Layout.fillWidth: true; label: "Band";     value: (nr.band && nr.band !== "Band unavailable") ? nr.band : "—" }
                        InfoLine { Layout.fillWidth: true; label: "Signal";   value: nr.signalText + " (" + nr.dbm + " dBm)" }
                        InfoLine { visible: nr.connected; Layout.fillWidth: true; label: "IP address"; value: NetworkService.ipAddress !== "—" ? NetworkService.ipAddress : "—" }
                        InfoLine { visible: nr.connected; Layout.fillWidth: true; label: "Gateway";    value: NetworkService.gateway  !== "—" ? NetworkService.gateway  : "—" }
                    }

                    PillButton {
                        visible:   nr.showDetails && nr.saved
                        label:     "Forget network"
                        onClicked: { nr.showDetails = false; nr.forgetRequested() }
                    }
                }
            }
        }

        component DeviceRow: Rectangle {
            id: dr
            property string name:     ""
            property string kind:     "other"
            property int    battery:  -1
            property bool   paired:   false
            property string status:   "idle"
            property bool   showMore: false
            readonly property bool connected:  status === "connected"
            readonly property bool connecting: status === "connecting" || status === "pairing…"
            readonly property var glyphs:     ({ headphones: "♫", earbuds: "◎", keyboard: "⌨", speaker: "♪", watch: "◷", other: "ᛒ" })
            readonly property var kindNames:  ({ headphones: "Headphones", earbuds: "Earbuds", keyboard: "Keyboard", speaker: "Speaker", watch: "Watch", other: "Device" })
            signal connectRequested()
            signal disconnectRequested()
            signal forgetRequested()

            function activate() {
                if (connected) showMore = !showMore
                else           connectRequested()
            }

            width:  parent ? parent.width : 0
            height: drCol.implicitHeight
            radius: 22; antialiasing: true; clip: true
            color:  connected ? Theme.surfaceHover : Theme.surfaceRaised
            border.width: connected ? 1 : 0
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.34)
            Behavior on color  { ColorAnimation  { duration: 160 } }
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { width: parent.width; height: 64; enabled: !dr.connecting; onClicked: dr.activate() }

            ColumnLayout {
                id: drCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 64
                    Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20; antialiasing: true
                        color: dr.connected ? Theme.primary : Theme.surface
                        SvgIcon {
                            anchors.centerIn: parent
                            width: 20; height: 20
                            iconName: "bluetooth"
                            tone: dr.connected ? "ink" : "muted"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        Text { text: dr.name; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 11
                            color: dr.connected ? Theme.primary : Theme.muted
                            text:  dr.connected  ? "Connected" + (dr.battery >= 0 ? " · " + dr.battery + "%" : "")
                                 : dr.connecting ? (dr.paired ? "Connecting…" : "Pairing…")
                                 : dr.paired     ? "Paired · " + (dr.kindNames[dr.kind] || "Device")
                                 : (dr.kindNames[dr.kind] || "Device") + " · Nearby"
                        }
                    }
                    PillButton { visible: dr.connected;                          label: "Disconnect"; onClicked: dr.disconnectRequested() }
                    PillButton { visible: dr.paired && !dr.connected && !dr.connecting; label: "Connect"; primary: true; onClicked: dr.connectRequested() }
                    PillButton { visible: !dr.paired && !dr.connecting;          label: "Pair";    primary: true; onClicked: dr.connectRequested() }
                    PillButton { visible: dr.paired && !dr.connecting;           label: "⋯";       onClicked: dr.showMore = !dr.showMore }
                }

                ColumnLayout {
                    visible: dr.showMore && dr.paired
                    Layout.fillWidth: true; Layout.leftMargin: 16; Layout.rightMargin: 12; Layout.bottomMargin: 14
                    spacing: 6
                    InfoLine { Layout.fillWidth: true; label: "Type";    value: dr.kindNames[dr.kind] || "Device" }
                    InfoLine { visible: dr.connected && dr.battery >= 0; Layout.fillWidth: true; label: "Battery"; value: dr.battery + "%" }
                    PillButton { Layout.topMargin: 4; label: "Forget device"; onClicked: { dr.showMore = false; dr.forgetRequested() } }
                }
            }
        }

        component PillSlider: Slider {
            id: sl
            implicitHeight: 28
            background: Rectangle {
                x: sl.leftPadding; y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: sl.availableWidth; height: 8; radius: 4; antialiasing: true
                color: Theme.surface
                Rectangle { width: sl.visualPosition * parent.width; height: parent.height; radius: 4; antialiasing: true; color: Theme.primary }
            }
            handle: Rectangle {
                x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: 22; height: 22; radius: 11; antialiasing: true; color: Theme.text
            }
        }

        component PillProgress: ProgressBar {
            id: pg
            implicitHeight: 6
            background: Rectangle { radius: 3; antialiasing: true; color: Theme.surface }
            contentItem: Item {
                Rectangle { width: pg.visualPosition * parent.width; height: parent.height; radius: 3; antialiasing: true; color: Theme.primary }
            }
        }

        component SpeakerIcon: Item {
            id: spk
            property bool   muted: false
            property int    level: 100
            property color  tint:  Theme.muted
            implicitWidth: 22; implicitHeight: 22
            width: 22; height: 22
            layer.enabled: true; layer.samples: 4; layer.smooth: true

            Shape {
                anchors.fill: parent; antialiasing: true
                ShapePath { fillColor: spk.tint; strokeColor: spk.tint; strokeWidth: 1.6; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M2.5 8H6L11 4V18L6 14H2.5Z" } }
                ShapePath { fillColor: "transparent"; strokeColor: !spk.muted && spk.level > 0 ? spk.tint : "transparent"; strokeWidth: 1.8; capStyle: ShapePath.RoundCap
                    PathSvg { path: "M14 8A4 4 0 0 1 14 14" } }
                ShapePath { fillColor: "transparent"; strokeColor: !spk.muted && spk.level >= 45 ? spk.tint : "transparent"; strokeWidth: 1.8; capStyle: ShapePath.RoundCap
                    PathSvg { path: "M16.5 5.5A8 8 0 0 1 16.5 16.5" } }
                ShapePath { fillColor: "transparent"; strokeColor: spk.muted ? spk.tint : "transparent"; strokeWidth: 1.8; capStyle: ShapePath.RoundCap
                    PathSvg { path: "M15 8.2L20 13.8M20 8.2L15 13.8" } }
            }
        }

        component BatteryIcon: Item {
            id: bat
            property int   level: 100
            property color tint:  Theme.muted
            implicitWidth: 27; implicitHeight: 12
            Rectangle {
                width: 23; height: 12; radius: 4; antialiasing: true
                color: "transparent"; border.width: 1.4; border.color: bat.tint
                Rectangle {
                    x: 2.4; y: 2.4
                    width: Math.max(2, (parent.width - 4.8) * Math.max(0, Math.min(100, bat.level)) / 100)
                    height: parent.height - 4.8; radius: 1.8; antialiasing: true
                    color:  bat.level <= 20 ? Theme.warning : bat.tint
                }
            }
            Rectangle { x: 24.2; y: 3.8; width: 2.4; height: 4.4; radius: 1.2; antialiasing: true; color: bat.tint }
        }

        component AudioDeviceRow: Rectangle {
            id: ad
            property string title:       ""
            property string subtitle:    ""
            property string glyph:       "♪"
            property bool   selected:    false
            property bool   unavailable: false
            signal chosen()
            width:  parent ? parent.width : 0
            height: 58; radius: 22; antialiasing: true
            color:  selected ? Theme.surfaceHover : Theme.surfaceRaised
            border.width: selected ? 1 : 0
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.34)
            opacity: unavailable ? 0.42 : 1
            Behavior on color { ColorAnimation { duration: 140 } }

            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 16; spacing: 12
                Rectangle {
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 18; antialiasing: true
                    color: ad.selected ? Theme.primary : Theme.surface
                    Text { anchors.centerIn: parent; text: ad.glyph; color: ad.selected ? Theme.background : Theme.muted; font.pixelSize: 16 }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    Text { text: ad.title;    color: Theme.text;                      font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: ad.subtitle; color: ad.selected ? Theme.primary : Theme.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                Rectangle {
                    Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 10; antialiasing: true
                    color: "transparent"; border.width: 2; border.color: ad.selected ? Theme.primary : Theme.muted
                    Rectangle { visible: ad.selected; anchors.centerIn: parent; width: 10; height: 10; radius: 5; antialiasing: true; color: Theme.primary }
                }
            }
            MouseArea { anchors.fill: parent; enabled: !ad.unavailable; onClicked: ad.chosen() }
        }

        component BalanceSlider: Slider {
            id: bs
            from: -100; to: 100; stepSize: 5
            snapMode: Slider.SnapAlways
            implicitHeight: 28
            background: Rectangle {
                x: bs.leftPadding; y: bs.topPadding + bs.availableHeight / 2 - height / 2
                width: bs.availableWidth; height: 8; radius: 4; antialiasing: true; color: Theme.surface
                Rectangle {
                    readonly property real centerX: parent.width / 2
                    readonly property real handleX: bs.visualPosition * parent.width
                    x: Math.min(centerX, handleX); width: Math.abs(handleX - centerX)
                    height: parent.height; radius: 4; antialiasing: true; color: Theme.primary
                }
                Rectangle { x: parent.width / 2 - 1; y: -3; width: 2; height: parent.height + 6; radius: 1; antialiasing: true; color: Theme.outline }
            }
            handle: Rectangle {
                x: bs.leftPadding + bs.visualPosition * (bs.availableWidth - width)
                y: bs.topPadding + bs.availableHeight / 2 - height / 2
                width: 22; height: 22; radius: 11; antialiasing: true; color: Theme.text
            }
        }

        component WifiIcon: Item {
            id: wf
            property color tint: Theme.muted
            width: 22; height: 22
            layer.enabled: true; layer.samples: 4; layer.smooth: true
            Shape {
                anchors.fill: parent; antialiasing: true
                ShapePath { fillColor: "transparent"; strokeColor: wf.tint; strokeWidth: 1.9; capStyle: ShapePath.RoundCap; PathSvg { path: "M8.11 13.95A4.5 4.5 0 0 1 13.89 13.95" } }
                ShapePath { fillColor: "transparent"; strokeColor: wf.tint; strokeWidth: 1.9; capStyle: ShapePath.RoundCap; PathSvg { path: "M5.53 10.89A8.5 8.5 0 0 1 16.47 10.89" } }
                ShapePath { fillColor: "transparent"; strokeColor: wf.tint; strokeWidth: 1.9; capStyle: ShapePath.RoundCap; PathSvg { path: "M2.96 7.82A12.5 12.5 0 0 1 19.04 7.82" } }
            }
            Rectangle { x: 9.3; y: 15.7; width: 3.4; height: 3.4; radius: 1.7; antialiasing: true; color: wf.tint }
        }

        component BluetoothIcon: Item {
            id: bt
            property color tint: Theme.muted
            width: 22; height: 22
            layer.enabled: true; layer.samples: 4; layer.smooth: true
            Shape {
                anchors.fill: parent; antialiasing: true
                ShapePath { fillColor: "transparent"; strokeColor: bt.tint; strokeWidth: 1.9; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M6 7L16 15L11 19V3L16 7L6 15" } }
            }
        }

        component CaffeineIcon: Item {
            id: cf
            property color tint: Theme.muted
            width: 22; height: 22
            layer.enabled: true; layer.samples: 4; layer.smooth: true
            Shape {
                anchors.fill: parent; antialiasing: true
                ShapePath { fillColor: "transparent"; strokeColor: cf.tint; strokeWidth: 1.8; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M4.5 9H15V13.5A4.5 4.5 0 0 1 10.5 18H9A4.5 4.5 0 0 1 4.5 13.5Z" } }
                ShapePath { fillColor: "transparent"; strokeColor: cf.tint; strokeWidth: 1.8; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M15 10.5H16.2A2.4 2.4 0 0 1 16.2 15.3H14.6" } }
                ShapePath { fillColor: "transparent"; strokeColor: cf.tint; strokeWidth: 1.6; capStyle: ShapePath.RoundCap
                    PathSvg { path: "M8 3.4C7 4.6 9 5.6 8 7M11.6 3.4C10.6 4.6 12.6 5.6 11.6 7" } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        // SYSTEM PANEL HELPER COMPONENTS
        // ════════════════════════════════════════════════════════════════

        component RingGauge: Item {
            id: rg
            property real value:  0       // 0..1
            property bool active: true
            property real shown:  value
            readonly property color ringColor:
                !active ? Theme.muted
                : shown < 0.6  ? Theme.primary
                : shown < 0.85 ? Theme.warning : Theme.error
            Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onShownChanged:    cv.requestPaint()
            onRingColorChanged: cv.requestPaint()
            Canvas {
                id: cv
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var lw = Math.max(5, Math.min(width, height) * 0.11)
                    var r  = (Math.min(width, height) - lw) / 2
                    var cx = width / 2, cy = height / 2
                    ctx.lineWidth = lw; ctx.lineCap = "round"
                    ctx.strokeStyle = "" + Theme.surface
                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
                    if (rg.shown > 0.005) {
                        ctx.strokeStyle = "" + rg.ringColor
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2,
                                -Math.PI / 2 + Math.PI * 2 * Math.min(1, rg.shown))
                        ctx.stroke()
                    }
                }
            }
        }

        component GaugeCard: Rectangle {
            id: gaugeCardRoot
            property string title:     ""
            property string sub:       ""
            property string label:     ""
            property real   value:     0
            property bool   available: true
            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: 72
            radius: Theme.radiusCard; antialiasing: true; color: Theme.surfaceRaised
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 9
                RingGauge {
                    id: gaugeRing
                    Layout.preferredWidth: 52; Layout.preferredHeight: 52
                    value:  gaugeCardRoot.available ? gaugeCardRoot.value : 0
                    active: gaugeCardRoot.available
                    Text { anchors.centerIn: parent; text: gaugeCardRoot.label; color: gaugeRing.ringColor; font.pixelSize: 12; font.weight: Font.Medium }
                }
                ColumnLayout { Layout.fillWidth: true; spacing: 1
                    Text { text: gaugeCardRoot.title; color: Theme.text;  font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: gaugeCardRoot.sub;   color: Theme.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
        }

        component FanIcon: Item {
            id: fi
            property color tint: Theme.primary
            property real  rpm:  0
            width: 26; height: 26
            Item {
                id: rotor; anchors.fill: parent
                RotationAnimator on rotation {
                    from: 0; to: 360; loops: Animation.Infinite
                    duration: Math.max(350, 1800000 / Math.max(1, fi.rpm))
                    running: fi.rpm > 0
                }
                Repeater {
                    model: 3
                    Item {
                        x: 13; y: 13; rotation: index * 120
                        Rectangle { x: -3.5; y: -12; width: 7; height: 11; radius: 3.5; antialiasing: true; color: fi.tint }
                    }
                }
                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.surfaceRaised }
            }
        }

        component Segmented: Rectangle {
            id: segCtrl
            property var  options:     []
            property var  current
            property bool interactive: true
            signal picked(var key)
            implicitHeight: 38; radius: height / 2; antialiasing: true; color: Theme.surface
            Row {
                anchors.fill: parent; anchors.margins: 3; spacing: 0
                Repeater {
                    model: segCtrl.options
                    Rectangle {
                        required property var modelData
                        readonly property bool sel: segCtrl.current === modelData[0]
                        width:  parent.width / segCtrl.options.length
                        height: parent.height; radius: height / 2; antialiasing: true
                        color:  sel ? Theme.primary : "transparent"
                        opacity: segCtrl.interactive ? 1 : 0.45
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: modelData[1]; font.pixelSize: 12; font.weight: sel ? Font.DemiBold : Font.Normal; color: sel ? Theme.background : Theme.muted }
                        MouseArea { anchors.fill: parent; enabled: segCtrl.interactive; onClicked: segCtrl.picked(modelData[0]) }
                    }
                }
            }
        }

        component Sparkline: Canvas {
            id: sp
            property var lines:     []
            property int maxPoints: 40
            antialiasing: true
            onLinesChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                // grid lines
                ctx.lineWidth = 1; ctx.strokeStyle = "" + Theme.outline
                for (var g = 0; g < 5; g++) {
                    var gy = Math.round((height - 1) * g / 4) + 0.5
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
                }
                var step = width / (maxPoints - 1)
                for (var li = 0; li < lines.length; li++) {
                    var d = lines[li].data, n = d.length
                    if (n < 2) continue
                    var col  = "" + lines[li].color
                    var x0   = width - (n - 1) * step
                    ctx.beginPath()
                    for (var i = 0; i < n; i++) {
                        var x = x0 + i * step
                        var y = height - 2 - (height - 4) * Math.max(0, Math.min(100, d[i])) / 100
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.lineJoin = "round"; ctx.lineWidth = 2; ctx.strokeStyle = col; ctx.stroke()
                    ctx.lineTo(width, height); ctx.lineTo(x0, height); ctx.closePath()
                    ctx.globalAlpha = 0.16; ctx.fillStyle = col; ctx.fill(); ctx.globalAlpha = 1
                }
            }
        }

        component InfoCell: Rectangle {
            property string label: ""
            property var    value: ""
            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: 44
            radius: Theme.radiusControl; antialiasing: true; color: Theme.surfaceRaised
            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 12; anchors.rightMargin: 8
                spacing: 1
                Text { text: label;        color: Theme.muted; font.pixelSize: 10 }
                Text { text: "" + value;   color: Theme.text;  font.pixelSize: 13; width: parent.width; elide: Text.ElideRight }
            }
        }

    }  // end PanelWindow
}  // end Scope
