pragma Singleton
import QtQuick
import Quickshell.Io
import "../core"

QtObject {
    id: root
    Component.onCompleted: root.refresh()   // one initial read so the first open has data

    property real cpuPercent: 0
    property string cpuModel: "Unavailable"
    property string cpuClock: ""
    property string cpuMaxClock: ""
    property string cpuThreads: ""
    property string cpuTemperatureText: ""
    property real memoryPercent: 0
    property string memoryLabel: "Unavailable"
    property string memoryAvailableLabel: ""
    property string memoryCacheLabel: ""
    property string swapLabel: ""
    property bool storageAvailable: false
    property real storagePercent: 0
    property string storageLabel: "Unavailable"
    property string powerProfile: "Unavailable"
    property real previousCpuTotal: 0
    property real previousCpuIdle: 0

    property bool batteryAvailable: false
    property real batteryPercent: 0
    property bool batteryCharging: false
    property string batteryStatus: ""
    property string batteryPower: ""
    property string batteryEnergy: ""
    property string batteryHealth: ""
    property string batteryCycles: ""
    property string batteryVoltage: ""
    property string batteryTechnology: ""

    property var gpuStats: []
    property bool fanAvailable: false
    property real fanRpm: 0

    readonly property var gpuIds: ({
        "0x743f": "Radeon RX 6500M",
        "0x1638": "Radeon Vega"
    })

    readonly property string sysScript: `
readv() { cat "$1" 2>/dev/null; }
for b in /sys/class/power_supply/BAT*; do
  [ -d "$b" ] || continue
  for k in capacity status energy_now energy_full energy_full_design charge_now charge_full charge_full_design power_now current_now voltage_now cycle_count technology; do
    v=$(readv "$b/$k"); [ -n "$v" ] && printf 'bat.%s=%s\n' "$k" "$v"
  done
  break
done
for a in /sys/class/power_supply/*; do
  if [ "$(readv "$a/type")" = Mains ]; then printf 'ac=%s\n' "$(readv "$a/online")"; break; fi
done
head -n 1 /proc/stat | sed 's/^cpu */cpu.stat=/'
awk '{s+=$1;n++;if($1>m)m=$1} END{if(n){printf "cpu.clock_khz=%d\n",int(s/n); printf "cpu.max_clock_khz=%d\n",int(m)}}' /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq 2>/dev/null
awk -F: '/model name/{gsub(/^[ \\t]+/,"",$2); print "cpu.model=" $2; exit}' /proc/cpuinfo
printf 'cpu.threads=%s\n' "$(nproc 2>/dev/null || echo 0)"
awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree|Cached|Buffers):/{gsub(":","",$1); print "mem." $1 "=" $2}' /proc/meminfo
rootfs=$(df -P -k / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $3 "|" $2 "|" $5}')
[ -n "$rootfs" ] && printf 'storage=%s\n' "$rootfs"
for h in /sys/class/hwmon/hwmon*; do
  n=$(readv "$h/name")
  case "$n" in
    k10temp|zenpower|coretemp) v=$(readv "$h/temp1_input"); [ -n "$v" ] && printf 'cpu.temp_milli=%s\n' "$v" ;;
  esac
  [ "$n" = amdgpu ] && continue
  for f in "$h"/fan*_input; do
    [ -r "$f" ] || continue
    v=$(readv "$f"); [ -n "$v" ] && printf 'fan.rpm=%s\n' "$v" && break 2
  done
done
for d in /sys/class/drm/card[0-9]/device; do
  [ "$(readv "$d/vendor")" = 0x1002 ] || continue
  id=$(readv "$d/device")
  state=$(readv "$d/power/runtime_status")
  if [ -n "$state" ] && [ "$state" != active ]; then
    printf 'gpu=%s|sleeping|||||||' "$id"; printf '\n'; continue
  fi
  h=$(ls -d "$d"/hwmon/hwmon* 2>/dev/null | head -n 1)
  p=$(readv "$h/power1_average"); [ -z "$p" ] && p=$(readv "$h/power1_input")
  printf 'gpu=%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$state" "$(readv "$d/gpu_busy_percent")" "$(readv "$d/mem_info_vram_used")" "$(readv "$d/mem_info_vram_total")" "$(readv "$h/temp1_input")" "$p" "$(readv "$h/fan1_input")" "$(readv "$h/freq1_input")"
done
`

    function refresh(): void {
        if (!stats.running) stats.running = true
        if (!profileQuery.running) profileQuery.running = true
    }

    function setPowerProfile(profile: string): void {
        if (["power-saver", "balanced", "performance"].indexOf(profile) < 0) return
        profileSet.command = ["powerprofilesctl", "set", profile]
        profileSet.running = true
    }

    function numberValue(value): real {
        const n = Number(value)
        return Number.isFinite(n) ? n : 0
    }

    function fmtKiB(kib): string {
        return (numberValue(kib) / 1048576).toFixed(2) + " GiB"
    }

    function fmtBytes(bytes): string {
        return (numberValue(bytes) / 1073741824).toFixed(2) + " GiB"
    }

    function fmtEta(hours): string {
        if (!Number.isFinite(hours) || hours <= 0 || hours > 48) return ""
        const minutes = Math.round(hours * 60)
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
    }

    function parse(text): void {
        const values = ({})
        const gpuLines = []
        for (const line of String(text || "").split("\n")) {
            const at = line.indexOf("=")
            if (at < 0) continue
            const key = line.slice(0, at)
            const value = line.slice(at + 1)
            if (key === "gpu") gpuLines.push(value)
            else values[key] = value
        }

        const cpu = String(values["cpu.stat"] || "").trim().split(/\s+/).map(Number)
        if (cpu.length >= 5) {
            const total = cpu.slice(0, 8).reduce((sum, value) => sum + (Number(value) || 0), 0)
            const idle = (cpu[3] || 0) + (cpu[4] || 0)
            if (root.previousCpuTotal > 0 && total > root.previousCpuTotal) {
                const dt = total - root.previousCpuTotal
                const di = idle - root.previousCpuIdle
                root.cpuPercent = Math.max(0, Math.min(100, (dt - di) * 100 / dt))
            }
            root.previousCpuTotal = total
            root.previousCpuIdle = idle
        }
        root.cpuModel = values["cpu.model"] || "Unavailable"
        const clockKhz = numberValue(values["cpu.clock_khz"])
        const maxClockKhz = numberValue(values["cpu.max_clock_khz"])
        root.cpuClock = clockKhz > 0 ? Math.round(clockKhz / 1000) + " MHz" : ""
        root.cpuMaxClock = maxClockKhz > 0 ? Math.round(maxClockKhz / 1000) + " MHz" : ""
        root.cpuThreads = values["cpu.threads"] || ""
        const temp = numberValue(values["cpu.temp_milli"]) / 1000
        root.cpuTemperatureText = temp > 0 && temp < 150 ? Math.round(temp) + " °C" : ""

        const memTotal = numberValue(values["mem.MemTotal"])
        const memAvailable = numberValue(values["mem.MemAvailable"])
        if (memTotal > 0) {
            root.memoryPercent = Math.max(0, Math.min(100, (memTotal - memAvailable) * 100 / memTotal))
            root.memoryLabel = fmtKiB(memTotal - memAvailable) + " / " + fmtKiB(memTotal)
            root.memoryAvailableLabel = fmtKiB(memAvailable)
            root.memoryCacheLabel = fmtKiB(numberValue(values["mem.Cached"]) + numberValue(values["mem.Buffers"]))
        }
        const storage = String(values["storage"] || "").split("|")
        if (storage.length >= 3 && numberValue(storage[1]) > 0) {
            root.storageAvailable = true; root.storagePercent = Math.max(0, Math.min(100, numberValue(storage[2])))
            root.storageLabel = fmtKiB(numberValue(storage[0])) + " / " + fmtKiB(numberValue(storage[1]))
        } else { root.storageAvailable = false; root.storagePercent = 0; root.storageLabel = "Unavailable" }

        const swapTotal = numberValue(values["mem.SwapTotal"])
        root.swapLabel = swapTotal > 0
            ? fmtKiB(swapTotal - numberValue(values["mem.SwapFree"])) + " / " + fmtKiB(swapTotal)
            : "none"

        root.batteryAvailable = values["bat.capacity"] !== undefined
        if (root.batteryAvailable) {
            const voltage = numberValue(values["bat.voltage_now"]) / 1e6
            const energy = function (energyKey, chargeKey): real {
                if (values[energyKey] !== undefined) return numberValue(values[energyKey]) / 1e6
                if (values[chargeKey] !== undefined) return numberValue(values[chargeKey]) / 1e6 * voltage
                return 0
            }
            const now = energy("bat.energy_now", "bat.charge_now")
            const full = energy("bat.energy_full", "bat.charge_full")
            const design = energy("bat.energy_full_design", "bat.charge_full_design")
            const watts = values["bat.power_now"] !== undefined
                ? numberValue(values["bat.power_now"]) / 1e6
                : numberValue(values["bat.current_now"]) * numberValue(values["bat.voltage_now"]) / 1e12
            const status = values["bat.status"] || "Unknown"
            let eta = ""
            if (watts > 0.5) {
                if (status === "Discharging") eta = fmtEta(now / watts) + " remaining"
                else if (status === "Charging") eta = fmtEta((full - now) / watts) + " until full"
                if (eta.startsWith(" ")) eta = ""
            }
            root.batteryPercent = Math.max(0, Math.min(100, numberValue(values["bat.capacity"])))
            root.batteryCharging = status === "Charging"
            root.batteryStatus = status + (values.ac === "1" ? " · plugged in" : "") + (eta ? "\n" + eta : "")
            root.batteryPower = watts > 0 ? watts.toFixed(1) + " W"
                + (status === "Charging" ? " in" : status === "Discharging" ? " out" : "") : ""
            root.batteryEnergy = full > 0 ? now.toFixed(1) + " / " + full.toFixed(1) + " Wh" : ""
            root.batteryHealth = full > 0 && design > 0
                ? Math.round(full * 100 / design) + "% (design " + design.toFixed(1) + " Wh)" : ""
            root.batteryCycles = numberValue(values["bat.cycle_count"]) > 0 ? values["bat.cycle_count"] : ""
            root.batteryVoltage = voltage > 0 ? voltage.toFixed(2) + " V" : ""
            root.batteryTechnology = values["bat.technology"] || ""
        } else {
            root.batteryStatus = "Battery unavailable"
            root.batteryPower = ""
            root.batteryEnergy = ""
            root.batteryHealth = ""
            root.batteryCycles = ""
            root.batteryVoltage = ""
            root.batteryTechnology = ""
        }

        const gpus = []
        let gpuFan = null
        for (const line of gpuLines) {
            const fields = line.split("|")
            const id = String(fields[0] || "").toLowerCase()
            const deviceName = root.gpuIds[id] || (id ? "AMD GPU " + id : "AMD GPU")
            const sleeping = fields[1] !== undefined && fields[1] !== "" && fields[1] !== "active"
            const vramTotal = numberValue(fields[4])
            const kind = id === "0x743f" ? "Discrete" : id === "0x1638" ? "Integrated"
                : vramTotal > 2147483648 ? "Discrete" : vramTotal > 0 ? "Integrated" : ""
            const fanValue = numberValue(fields[7])
            gpus.push({
                name: deviceName,
                kind: kind,
                sleeping: sleeping,
                load: sleeping ? 0 : numberValue(fields[2]),
                memory: !sleeping && vramTotal > 0 ? fmtBytes(fields[3]) + " / " + fmtBytes(vramTotal) : "",
                temperature: !sleeping && numberValue(fields[5]) > 0 ? Math.round(numberValue(fields[5]) / 1000) + " °C" : "",
                power: !sleeping && numberValue(fields[6]) > 0 ? (numberValue(fields[6]) / 1e6).toFixed(1) + " W" : "",
                fan: !sleeping && fanValue > 0 ? Math.round(fanValue) + " RPM" : "",
                clock: !sleeping && numberValue(fields[8]) > 0 ? Math.round(numberValue(fields[8]) / 1e6) + " MHz" : ""
            })
            if (!sleeping && fields[7] !== undefined && fields[7] !== "" && gpuFan === null) gpuFan = fanValue
        }
        gpus.sort((a, b) => Number(b.kind === "Discrete") - Number(a.kind === "Discrete"))
        root.gpuStats = gpus
        const boardFan = values["fan.rpm"] !== undefined ? numberValue(values["fan.rpm"]) : null
        root.fanAvailable = boardFan !== null || gpuFan !== null
        root.fanRpm = boardFan !== null ? boardFan : (gpuFan || 0)
    }

    property Process stats: Process {
        id: stats
        command: ["sh", "-c", root.sysScript]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.cpuModel = "Unavailable"
                root.memoryLabel = "Unavailable"
            }
        }
    }
    property Process profileQuery: Process {
        id: profileQuery
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: root.powerProfile = text.trim() || "Unavailable" }
        onExited: (code, status) => { if (code !== 0) root.powerProfile = "Unavailable" }
    }
    property Process profileSet: Process {
        id: profileSet
        onExited: (code, status) => root.refresh()
    }
    property Timer refreshTimer: Timer {
        interval: 3000
        running: ShellState.popupOpen   // only poll while the control panel is open
        repeat: true
        triggeredOnStart: true          // immediate refresh each time it opens
        onTriggered: root.refresh()
    }
}
