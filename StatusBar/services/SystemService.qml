pragma Singleton
import QtQuick
import Quickshell.Services.UPower
import Quickshell.Io

QtObject {
    id: root

    property real cpuPercent: 0
    property real memoryPercent: 0
    property string memoryLabel: "Unavailable"
    property real temperature: 0
    property bool temperatureAvailable: false
    property string powerProfile: "Unavailable"
    property real previousCpuTotal: 0
    property real previousCpuIdle: 0

    function refresh(): void {
        if (!stats.running) stats.running = true
        if (!profileQuery.running) profileQuery.running = true
    }
    function setPowerProfile(profile: string): void {
        if (["power-saver", "balanced", "performance"].indexOf(profile) < 0)
            return
        profileSet.command = ["powerprofilesctl", "set", profile]
        profileSet.running = true
    }
    property Process stats: Process {
        id: stats
        command: ["sh", "-c", "head -n 1 /proc/stat; grep -E 'MemTotal|MemAvailable' /proc/meminfo; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const cpu = (lines[0] || "").trim().split(/\s+/).slice(1).map(Number)
                const total = cpu.reduce((sum, value) => sum + value, 0)
                const idle = (cpu[3] || 0) + (cpu[4] || 0)
                if (root.previousCpuTotal > 0 && total > root.previousCpuTotal) {
                    const totalDelta = total - root.previousCpuTotal
                    const idleDelta = idle - root.previousCpuIdle
                    root.cpuPercent = Math.max(0, Math.min(100,
                        (1 - idleDelta / totalDelta) * 100))
                }
                root.previousCpuTotal = total
                root.previousCpuIdle = idle
                const totalMemory = Number((lines[1] || "").split(/\s+/)[1])
                const availableMemory = Number((lines[2] || "").split(/\s+/)[1])
                if (totalMemory > 0 && availableMemory >= 0) {
                    root.memoryPercent = Math.max(0, Math.min(100,
                        (1 - availableMemory / totalMemory) * 100))
                    root.memoryLabel = Math.round((totalMemory - availableMemory) / 1024)
                        + " / " + Math.round(totalMemory / 1024) + " MB"
                }
                const temp = Number(lines[3]) / 1000
                root.temperatureAvailable = Number.isFinite(temp) && temp > -50 && temp < 150
                if (root.temperatureAvailable) root.temperature = temp
            }
        }
    }
    property Process profileQuery: Process {
        id: profileQuery
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: root.powerProfile = text.trim() || "Unavailable" }
        onExited: (code, status) => { if (code !== 0) root.powerProfile = "Unavailable" }
    }
    property Process profileSet: Process { id: profileSet
 onExited: (code, status) => root.refresh() }
    property Timer refreshTimer: Timer { interval: 3000
 running: true
 repeat: true
 triggeredOnStart: true
 onTriggered: root.refresh() }
}
