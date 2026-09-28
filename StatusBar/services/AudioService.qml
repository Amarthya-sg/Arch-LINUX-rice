pragma Singleton
import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Io

QtObject {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: Pipewire.ready && !!sink?.audio
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real inputVolume: source?.audio?.volume ?? 0
    readonly property bool inputMuted: source?.audio?.muted ?? false
    property var outputs: []
    property var inputs: []
    property var cards: []
    property string lastOutputSignature: ""

    function profileKey(name, isOutput): string {
        const value = String(name || "")
        const prefix = isOutput ? "output:" : "input:"
        if (value.indexOf(prefix) >= 0) {
            const parts = value.split("+").filter(part => part.indexOf(prefix) === 0)
            if (parts.length > 0) return parts.sort().join("+")
        }
        if (value.indexOf("a2dp-sink") === 0) return "a2dp-sink"
        if (value.indexOf("headset-head-unit") === 0) return "headset-head-unit"
        return value
    }

    readonly property var outputChoices: {
        const choices = []
        for (const output of outputs) {
            const ports = (output.ports || []).filter(port => port.availability !== "no")
            if (ports.length === 0) {
                choices.push({ kind: "device", name: output.name, sinkName: output.name, portName: "",
                               description: output.description || output.name,
                               detail: output.volumeText || "Output device",
                               volumeText: output.volumeText || "", active: output.name === sink?.name,
                               isBluetooth: output.isBluetooth })
                continue
            }
            for (const port of ports) {
                choices.push({ kind: "device", name: output.name, sinkName: output.name, portName: port.name,
                               description: port.description + " — " + (output.description || output.name),
                               detail: (output.volumeText ? output.volumeText + " · " : "") + (port.type || "Output"),
                               volumeText: output.volumeText || "",
                               active: output.name === sink?.name && output.activePort === port.name,
                               isBluetooth: output.isBluetooth })
            }
        }
        for (const card of cards) {
            const candidates = card.profiles.filter(profile => profile.name !== card.activeProfile
                && profile.sinks > 0 && profile.available !== "no" && !/^pro-audio$/i.test(profile.name))
                .sort((a, b) => b.priority - a.priority)
            const seen = {}
            seen[root.profileKey(card.activeProfile, true)] = true
            for (const profile of candidates) {
                const key = root.profileKey(profile.name, true)
                if (seen[key]) continue
                seen[key] = true
                const label = /speaker/i.test(profile.name) ? "Speakers"
                    : /headphones?/i.test(profile.name) ? "Headphones"
                    : /bluetooth|a2dp/i.test(profile.name) ? "Bluetooth"
                    : profile.description || profile.name
                choices.push({ kind: "profile", cardName: card.name, profileName: profile.name,
                               sinkName: "", portName: "", description: label + " — " + (card.description || card.name),
                               detail: "Switch output profile", volumeText: "", active: false,
                               isBluetooth: card.isBluetooth })
            }
        }
        return choices
    }

    readonly property var inputChoices: {
        const choices = []
        for (const input of inputs) {
            if (input.name.endsWith(".monitor") || input.monitorOfSink) continue
            const ports = (input.ports || []).filter(port => port.availability !== "no")
            if (ports.length === 0) {
                choices.push({ kind: "device", name: input.name, sourceName: input.name, portName: "",
                               description: input.description || input.name,
                               detail: input.volumeText || "Input device", volumeText: input.volumeText || "",
                               active: input.name === source?.name, isBluetooth: input.isBluetooth })
                continue
            }
            for (const port of ports) {
                choices.push({ kind: "device", name: input.name, sourceName: input.name, portName: port.name,
                               description: port.description + " — " + (input.description || input.name),
                               detail: (input.volumeText ? input.volumeText + " · " : "") + (port.type || "Input"),
                               volumeText: input.volumeText || "",
                               active: input.name === source?.name && input.activePort === port.name,
                               isBluetooth: input.isBluetooth })
            }
        }
        for (const card of cards) {
            const active = card.profiles.find(profile => profile.name === card.activeProfile)
            if (active && active.sources > 0) continue
            const candidates = card.profiles.filter(profile => profile.name !== card.activeProfile
                && profile.sources > 0 && profile.available !== "no"
                && !/^pro-audio$/i.test(profile.name) && !/^a2dp-source/i.test(profile.name))
                .sort((a, b) => b.priority - a.priority)
            const seen = {}
            seen[root.profileKey(card.activeProfile, false)] = true
            for (const profile of candidates) {
                const key = root.profileKey(profile.name, false)
                if (seen[key]) continue
                seen[key] = true
                choices.push({ kind: "profile", cardName: card.name, profileName: profile.name,
                               sourceName: "", portName: "",
                               description: (profile.description || profile.name) + " — " + (card.description || card.name),
                               detail: "Switch profile to expose microphone", volumeText: "", active: false,
                               isBluetooth: card.isBluetooth })
            }
        }
        return choices
    }

    readonly property var outputNames: outputChoices.map(n => n.description || n.name || "Output")
    readonly property var inputNames:  inputChoices.map(n => n.description || n.name || "Input")
    readonly property int outputIndex: {
        const index = outputChoices.findIndex(n => n.active)
        return index >= 0 ? index : Math.max(0, outputChoices.findIndex(n => n.sinkName === sink?.name))
    }
    readonly property int inputIndex: {
        const index = inputChoices.findIndex(n => n.active)
        return index >= 0 ? index : Math.max(0, inputChoices.findIndex(n => n.sourceName === source?.name))
    }

    property real outputBalance: 0
    property real inputBalance: 0
    property real outputMasterValue: 0
    property real inputMasterValue: 0
    property bool outputChannelsKnown: false
    property bool inputChannelsKnown: false
    property bool outputBalanceSupported: false
    property bool inputBalanceSupported: false
    property bool outputBalanceDirty: false
    property bool inputBalanceDirty: false
    readonly property real outputMaster: outputChannelsKnown ? outputMasterValue : volume
    readonly property real inputMaster:  inputChannelsKnown  ? inputMasterValue  : inputVolume
    property real pendingOutputVolume: 0
    property real pendingInputVolume: 0
    property bool outputVolumePending: false
    property bool inputVolumePending: false

    function channelVolumeArgs(master, balance, stereo): var {
        const level   = Math.max(0, Math.min(1, Number(master)  || 0))
        const percent = Math.round(level * 100)
        if (!stereo) return [percent + "%"]
        const pan   = Math.max(-1, Math.min(1, Number(balance) || 0))
        const left  = Math.round(level * (pan > 0 ? 1 - pan : 1) * 100)
        const right = Math.round(level * (pan < 0 ? 1 + pan : 1) * 100)
        return [left + "%", right + "%"]
    }

    function parseStereoVolume(text): var {
        const left  = String(text).match(/front-left:\s*(?:[0-9]+(?:\.[0-9]+)?\s*\/\s*)?([0-9]+(?:\.[0-9]+)?)\s*%/i)
        const right = String(text).match(/front-right:\s*(?:[0-9]+(?:\.[0-9]+)?\s*\/\s*)?([0-9]+(?:\.[0-9]+)?)\s*%/i)
        if (!left || !right) return { supported: false, master: 0, balance: 0 }
        const l      = Math.max(0, Number(left[1])  / 100)
        const r      = Math.max(0, Number(right[1]) / 100)
        const master = Math.max(l, r)
        const balance = master > 0 ? Math.max(-1, Math.min(1, (r - l) / master)) : 0
        return { supported: true, master: master, balance: balance }
    }

    function syncStereoVolumes(outputText, inputText): void {
        const out = root.parseStereoVolume(outputText)
        if (!root.outputBalanceDirty && !root.outputVolumePending && !root.outputVolumeProcess.running) {
            root.outputBalanceSupported = out.supported
            root.outputChannelsKnown   = out.supported
            if (out.supported) {
                root.outputMasterValue = out.master
                root.outputBalance     = out.balance
            }
        }
        const input = root.parseStereoVolume(inputText)
        if (!root.inputBalanceDirty && !root.inputVolumePending && !root.inputVolumeProcess.running) {
            root.inputBalanceSupported = input.supported
            root.inputChannelsKnown   = input.supported
            if (input.supported) {
                root.inputMasterValue = input.master
                root.inputBalance     = input.balance
            }
        }
    }

    // Slider changes are debounced and serialized; only the latest pending
    // value is sent when a previous pactl command has finished.
    function setVolume(value): void {
        root.pendingOutputVolume = Math.max(0, Math.min(1, value))
        root.outputVolumePending = true
        root.outputVolumeTimer.restart()
    }
    function setInputVolume(value): void {
        root.pendingInputVolume = Math.max(0, Math.min(1, value))
        root.inputVolumePending = true
        root.inputVolumeTimer.restart()
    }
    function setOutputBalance(value): void {
        if (!root.outputBalanceSupported) return
        root.outputBalance     = Math.max(-1, Math.min(1, value))
        root.outputBalanceDirty = true
        root.pendingOutputVolume = root.outputMaster
        root.outputVolumePending = true
        root.outputVolumeTimer.restart()
    }
    function setInputBalance(value): void {
        if (!root.inputBalanceSupported) return
        root.inputBalance     = Math.max(-1, Math.min(1, value))
        root.inputBalanceDirty = true
        root.pendingInputVolume = root.inputMaster
        root.inputVolumePending = true
        root.inputVolumeTimer.restart()
    }
    function flushOutputVolume(): void {
        if (!root.outputVolumePending || root.outputVolumeProcess.running) return
        const args = root.channelVolumeArgs(root.pendingOutputVolume, root.outputBalance,
                                             root.outputBalanceSupported)
        root.outputVolumePending = false
        root.outputVolumeProcess.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@"].concat(args)
        root.outputVolumeProcess.running = true
    }
    function flushInputVolume(): void {
        if (!root.inputVolumePending || root.inputVolumeProcess.running) return
        const args = root.channelVolumeArgs(root.pendingInputVolume, root.inputBalance,
                                             root.inputBalanceSupported)
        root.inputVolumePending = false
        root.inputVolumeProcess.command = ["pactl", "set-source-volume", "@DEFAULT_SOURCE@"].concat(args)
        root.inputVolumeProcess.running = true
    }
    function toggleMute(): void {
        outputMute.command = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
        outputMute.running = true
    }
    function toggleInputMute(): void {
        inputMute.command = ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"]
        inputMute.running = true
    }

    function routeSinkCommand(sinkName, portName): var {
        const script = [
            "set -e",
            "exec 2>&1",
            'sink="$1"',
            'port="$2"',
            'if [ -n "$port" ]; then pactl set-sink-port "$sink" "$port"; fi',
            'pactl set-default-sink "$sink"',
            "pactl list short sink-inputs 2>/dev/null | awk 'NF { print $1 }' | while read -r input; do",
            '    [ -n "$input" ] || continue',
            '    pactl move-sink-input "$input" "$sink" 2>/dev/null || true',
            "done",
            'default_sink=$(pactl get-default-sink 2>/dev/null || true)',
            'if [ "$default_sink" != "$sink" ]; then echo "Default sink verification failed: expected $sink, got $default_sink" >&2; exit 1; fi',
            'printf "ROUTE_OK sink=%s default=%s port=%s\\n" "$sink" "$default_sink" "$port"'
        ].join("\n")
        return ["sh", "-c", script, "sh", sinkName, portName || ""]
    }

    function routeSourceCommand(sourceName, portName): var {
        const script = [
            "set -e",
            "exec 2>&1",
            'source="$1"',
            'port="$2"',
            'if [ -n "$port" ] && ! pactl set-source-port "$source" "$port"; then echo "Could not activate input port $port on source $source" >&2; exit 1; fi',
            'pactl set-default-source "$source"',
            "pactl list short source-outputs 2>/dev/null | awk 'NF { print $1 }' | while read -r stream; do",
            '    [ -n "$stream" ] || continue',
            '    pactl move-source-output "$stream" "$source" 2>/dev/null || true',
            "done",
            'default_source=$(pactl get-default-source 2>/dev/null || true)',
            'if [ "$default_source" != "$source" ]; then echo "Default source verification failed: expected $source, got $default_source" >&2; exit 1; fi',
            'printf "INPUT_ROUTE_OK source=%s default=%s port=%s\\n" "$source" "$default_source" "$port"'
        ].join("\n")
        return ["sh", "-c", script, "sh", sourceName, portName || ""]
    }

    function profileSwitchCommand(cardName, profileName): var {
        const script = [
            'set -e',
            'exec 2>&1',
            'card=$1',
            'profile="$2"',
            'pactl set-card-profile "$card" "$profile"',
            'sink=""',
            "for attempt in $(seq 1 20); do",
            '    sink=$(pactl list sinks 2>/dev/null | awk -v card="$card" \'',
            '        function emit() { if (matches && name != "") print name }',
            '        /^Sink #[0-9]+/ { emit(); name=""; matches=0; next }',
            '        /^[[:space:]]*Name:/ { name=$2 }',
            '        /^[[:space:]]*device[.]name =/ && index($0, card) > 0 { matches=1 }',
            '        END { emit() }',
            "    ' | sed -n '1p')",
            '    if [ -n "$sink" ]; then break; fi',
            '    sleep 0.1',
            "done",
            'if [ -z "$sink" ]; then echo "No sink appeared for card $card after profile switch" >&2; exit 1; fi',
            'port=$(pactl list sinks 2>/dev/null | awk -v target="$sink" -v profile="$profile" \'',
            '    /^Sink #[0-9]+/ { inTarget=0; inPorts=0; sinkName=""; portIndent=-1 }',
            '    /^[[:space:]]*Name:/ { sinkName=$2; inTarget=(sinkName == target) }',
            '    /^[[:space:]]*Ports:[[:space:]]*$/ && inTarget { inPorts=1; portIndent=-1; next }',
            '    /^[[:space:]]*Active Port:/ && inTarget { inPorts=0; next }',
            '    inTarget && inPorts {',
            '        line=$0; match(line, /^[[:space:]]*/); indent=RLENGTH; sub(/^[[:space:]]*/, "", line)',
            '        if (portIndent < 0) portIndent=indent',
            '        if (indent != portIndent) next',
            '        colon=index(line, ":"); if (!colon) next',
            '        portName=substr(line, 1, colon-1); details=substr(line, colon+1)',
            '        if (tolower(details) ~ /not available/) next',
            '        if (first == "") first=portName',
            '        combined=tolower(portName " " details)',
            '        if ((tolower(profile) ~ /speaker/ && combined ~ /speaker/) || (tolower(profile) ~ /headphones?/ && combined ~ /headphones?/)) { selected=portName; exit }',
            '    }',
            '    END { if (selected != "") print selected; else if (first != "") print first }',
            "' | sed -n '1p')",
            "if [ -z \"$port\" ] && printf '%s' \"$profile\" | grep -Eiq 'speaker|headphone'; then echo \"No output port matched profile $profile on sink $sink\" >&2; exit 1; fi",
            'if [ -n "$port" ] && ! pactl set-sink-port "$sink" "$port"; then echo "Could not activate port $port on sink $sink" >&2; exit 1; fi',
            'pactl set-default-sink "$sink"',
            "pactl list short sink-inputs 2>/dev/null | awk 'NF { print $1 }' | while read -r input; do",
            '    [ -n "$input" ] || continue',
            '    pactl move-sink-input "$input" "$sink" 2>/dev/null || true',
            "done",
            'active_port=$(pactl list sinks 2>/dev/null | awk -v target="$sink" \'',
            '    /^Sink #[0-9]+/ { inTarget=0 }',
            '    /^[[:space:]]*Name:/ { inTarget=($2 == target) }',
            '    /^[[:space:]]*Active Port:/ && inTarget { sub(/^[[:space:]]*Active Port:[[:space:]]*/, ""); print; exit }',
            "' | sed -n '1p')",
            'default_sink=$(pactl get-default-sink 2>/dev/null || true)',
            'if [ "$default_sink" != "$sink" ]; then echo "Default sink verification failed: expected $sink, got $default_sink" >&2; exit 1; fi',
            'if [ -n "$port" ] && [ "$active_port" != "$port" ]; then echo "Active port verification failed: expected $port, got $active_port" >&2; exit 1; fi',
            'mute=$(pactl get-sink-mute "$sink" 2>/dev/null | awk \'{print $2}\')',
            'volume=$(pactl get-sink-volume "$sink" 2>/dev/null | sed -n \'1p\')',
            'printf "ROUTE_OK profile=%s sink=%s default=%s port=%s mute=%s volume=%s\\n" "$profile" "$sink" "$default_sink" "$active_port" "$mute" "$volume"'
        ].join("\n")
        return ["sh", "-c", script, "sh", cardName, profileName]
    }

    function inputProfileSwitchCommand(cardName, profileName): var {
        const script = [
            "set -e",
            "exec 2>&1",
            'card=$1',
            'profile="$2"',
            'pactl set-card-profile "$card" "$profile"',
            'source=""',
            "for attempt in $(seq 1 20); do",
            '    source=$(pactl list sources 2>/dev/null | awk -v card="$card" \'',
            '        function emit() { if (matches && name != "" && name !~ /\\.monitor$/) print name }',
            '        /^Source #[0-9]+/ { emit(); name=""; matches=0; next }',
            '        /^[[:space:]]*Name:/ { name=$2 }',
            '        /^[[:space:]]*device[.]name =/ && index($0, card) > 0 { matches=1 }',
            '        END { emit() }',
            "    ' | sed -n '1p')",
            '    if [ -n "$source" ]; then break; fi',
            '    sleep 0.1',
            "done",
            'if [ -z "$source" ]; then echo "No microphone source appeared for card $card after profile switch" >&2; exit 1; fi',
            'pactl set-default-source "$source"',
            "pactl list short source-outputs 2>/dev/null | awk 'NF { print $1 }' | while read -r stream; do",
            '    [ -n "$stream" ] || continue',
            '    pactl move-source-output "$stream" "$source" 2>/dev/null || true',
            "done",
            'default_source=$(pactl get-default-source 2>/dev/null || true)',
            'if [ "$default_source" != "$source" ]; then echo "Default source verification failed: expected $source, got $default_source" >&2; exit 1; fi',
            'printf "INPUT_PROFILE_OK profile=%s source=%s default=%s\\n" "$profile" "$source" "$default_source"'
        ].join("\n")
        return ["sh", "-c", script, "sh", cardName, profileName]
    }

    function selectOutput(node): void {
        if (!node) return
        console.log("[SAT][Audio] output selected; name=", node.sinkName || node.name || node.cardName,
                    "port=", node.portName || "default", "profile=", node.profileName || "",
                    "description=", node.description || "")
        if (node.kind === "profile") {
            outputSelect.command = root.profileSwitchCommand(node.cardName, node.profileName)
        } else {
            outputSelect.command = root.routeSinkCommand(node.sinkName || node.name, node.portName)
        }
        outputSelect.running = true
    }

    function selectInput(node): void {
        if (!node) return
        console.log("[SAT][Audio] input selected; name=", node.sourceName || node.name || node.cardName,
                    "port=", node.portName || "default", "profile=", node.profileName || "",
                    "description=", node.description || "")
        inputSelect.command = node.kind === "profile"
            ? root.inputProfileSwitchCommand(node.cardName, node.profileName)
            : root.routeSourceCommand(node.sourceName || node.name, node.portName)
        inputSelect.running = true
    }

    function speakerFallbackProfile(output, card): var {
        if (!output || output.isBluetooth || !card || !/headphones?/i.test(card.activeProfile)) return null
        const headphonePort = output.ports.find(port => port.name === output.activePort)
            || output.ports.find(port => /headphones?/i.test(port.name + " " + port.description))
        if (!headphonePort || headphonePort.availability !== "no") return null
        return card.profiles.find(profile => /speaker/i.test(profile.name)
            && profile.sinks > 0 && profile.available !== "no")
            || null
    }

    function maybeAutoSwitchToSpeakers(): void {
        if (root.outputSelect.running || !root.sink?.name) return
        const output = root.outputs.find(item => item.name === root.sink.name)
        if (!output || !output.cardName) return
        const card = root.cards.find(item => item.name === output.cardName)
        const speakerProfile = root.speakerFallbackProfile(output, card)
        if (!speakerProfile || card.activeProfile === speakerProfile.name) return
        console.log("[SAT][Audio] headphone port unavailable; switching to speakers; card=",
                    card.name, "profile=", speakerProfile.name)
        root.selectOutput({ kind: "profile", cardName: card.name,
                            profileName: speakerProfile.name,
                            description: speakerProfile.description })
    }

    function parsePorts(block): var {
        const result = []
        let inPorts = false
        let portIndent = -1
        for (const line of block.split("\n")) {
            if (/^\s*Ports:\s*$/.test(line)) { inPorts = true; continue }
            if (inPorts && /^\s*Active Port:/.test(line)) break
            if (!inPorts) continue
            const match = line.match(/^\s+(.+?):\s*(.*)$/)
            if (!match) continue
            const indent = (line.match(/^[ \t]*/) || [""])[0].length
            if (portIndent < 0) portIndent = indent
            if (indent !== portIndent) continue
            const details     = match[2]
            const portName    = match[1].replace(/^\*\s*/, "").trim()
            const description = details.split(/\s+\(type:/i)[0].trim()
            const type        = (details.match(/\(type:\s*([^,\)]+)/i) || ["", ""])[1].trim()
            const availability = /\bnot available\b/i.test(details) ? "no"
                : /\bavailable\b/i.test(details) ? "yes" : "unknown"
            result.push({ name: portName, description: description || portName,
                          type: type, availability: availability })
        }
        return result
    }

    function parseCards(text): var {
        const result = []
        const blocks = text.split(/\n(?=Card #)/)
        for (const block of blocks) {
            const name          = (block.match(/\n\s*Name:\s*(\S+)/)                          || ["", ""])[1]
            if (!name) continue
            const description   = (block.match(/\n\s*device\.description\s*=\s*"([^"]+)"/)   || ["", name])[1]
            const activeProfile = (block.match(/\n\s*Active Profile:\s*(.+)/)                 || ["", ""])[1].trim()
            const profiles = []
            let inProfiles = false
            for (const line of block.split("\n")) {
                if (/^\s*Profiles:\s*$/.test(line)) { inProfiles = true; continue }
                if (inProfiles && /^\s*Active Profile:/.test(line)) break
                if (!inProfiles) continue
                const match = line.match(/^\s{2,}(.+?):\s*(.*?)\s+\(sinks:\s*(\d+),\s*sources:\s*(\d+),\s*priority:\s*(-?\d+),\s*available:\s*(yes|no|unknown)\)\s*$/)
                if (!match) continue
                profiles.push({ name: match[1].trim(), description: match[2].trim(),
                                sinks: Number(match[3]), sources: Number(match[4]),
                                priority: Number(match[5]), available: match[6] })
            }
            result.push({ name: name, description: description, activeProfile: activeProfile,
                          profiles: profiles, isBluetooth: /bluez|bluetooth/i.test(block) })
        }
        return result
    }

    function parseVolumeSummary(block): string {
        if (/\n\s*Mute:\s*yes\b/i.test(block)) return "Muted"
        const volumeStart = block.search(/\n\s*Volume:/i)
        if (volumeStart < 0) return ""
        const volumeText = block.slice(volumeStart).split(/\n\s*(?:Balance|Base Volume|Mute|Monitor Source|Latency|Flags|Properties|Ports|Active Port):/i)[0]
        const channelPattern = /(?:front-left|front-right|front-center|rear-left|rear-right|side-left|side-right|mono|lfe):\s*[0-9]+\s*\/\s*([0-9]+(?:\.[0-9]+)?)%/gi
        let match
        let highest = -1
        while ((match = channelPattern.exec(volumeText)) !== null)
            highest = Math.max(highest, Number(match[1]))
        if (highest < 0) return ""
        return Math.round(highest) + "%"
    }

    function parseBlocks(text, prefix): var {
        const result = []
        const blocks = text.split(new RegExp("\n(?=" + prefix + " #)"))
        for (const block of blocks) {
            const name          = (block.match(/\n\s*Name:\s*(\S+)/)              || ["", ""])[1]
            if (!name) continue
            const description   = (block.match(/\n\s*Description:\s*(.+)/)        || ["", name])[1].trim()
            const state         = (block.match(/\n\s*State:\s*(\S+)/)             || ["", "UNKNOWN"])[1]
            const port          = (block.match(/\n\s*Active Port:\s*(.+)/)        || ["", ""])[1].trim()
            const cardName      = (block.match(/\n\s*device\.name\s*=\s*"([^"]+)"/) || ["", ""])[1]
            const monitorOfSink = (block.match(/\n\s*Monitor of Sink:\s*(.+)/)    || ["", ""])[1].trim()
            const bluetooth     = /bluez|bluetooth/i.test(block)
            result.push({ name: name, description: description, state: state, activePort: port,
                          cardName: cardName, monitorOfSink: monitorOfSink,
                          muted: /\n\s*Mute:\s*yes\b/i.test(block),
                          volumeText: root.parseVolumeSummary(block),
                          ports: root.parsePorts(block), isBluetooth: bluetooth })
        }
        return result
    }

    function refresh(): void { if (!deviceScan.running) deviceScan.running = true }

    property Process deviceScan: Process {
        id: deviceScan
        command: ["sh", "-c",
            "pactl list sinks 2>/dev/null;" +
            " printf '\\n---SOURCES---\\n';" +
            " pactl list sources 2>/dev/null;" +
            " printf '\\n---CARDS---\\n';" +
            " pactl list cards 2>/dev/null;" +
            " printf '\\n---OUTPUT-VOLUME---\\n';" +
            " pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null;" +
            " printf '\\n---INPUT-VOLUME---\\n';" +
            " pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts          = text.split("\n---SOURCES---\n")
                const sourceAndCards = (parts[1] || "").split("\n---CARDS---\n")
                const cardsAndOutput = (sourceAndCards[1] || "").split("\n---OUTPUT-VOLUME---\n")
                const outputAndInput = (cardsAndOutput[1] || "").split("\n---INPUT-VOLUME---\n")
                root.outputs = root.parseBlocks(parts[0] || "", "Sink")
                root.inputs  = root.parseBlocks(sourceAndCards[0] || "", "Source")
                root.cards   = root.parseCards(cardsAndOutput[0] || "")
                root.syncStereoVolumes(outputAndInput[0] || "", outputAndInput[1] || "")
                const signature = root.outputNames.join(" | ")
                if (signature !== root.lastOutputSignature) {
                    root.lastOutputSignature = signature
                    console.log("[SAT][Audio] output devices detected; count=", root.outputChoices.length,
                                "devices=", signature || "none")
                }
                root.maybeAutoSwitchToSpeakers()
            }
        }
    }

    property Process outputSelect: Process {
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim()
                if (result.length > 0) console.log("[SAT][Audio] route result:", result)
            }
        }
        onExited: (code, status) => {
            console.log("[SAT][Audio] output selection exited; code=", code, "status=", status)
            root.refresh()
        }
    }

    property Process inputSelect: Process {
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim()
                if (result.length > 0) console.log("[SAT][Audio] input route result:", result)
            }
        }
        onExited: (code, status) => {
            console.log("[SAT][Audio] input selection exited; code=", code, "status=", status)
            root.refresh()
        }
    }

    property Process outputMute: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][Audio] output mute exited; code=", code, "status=", status)
            root.refresh()
        }
    }
    property Process inputMute: Process {
        command: []
        onExited: (code, status) => {
            console.log("[SAT][Audio] input mute exited; code=", code, "status=", status)
            root.refresh()
        }
    }

    property Timer outputVolumeTimer: Timer {
        interval: 100; repeat: false
        onTriggered: root.flushOutputVolume()
    }
    property Timer inputVolumeTimer: Timer {
        interval: 100; repeat: false
        onTriggered: root.flushInputVolume()
    }

    property Process outputVolumeProcess: Process {
        command: []
        onExited: (code, status) => {
            if (code !== 0) console.warn("[SAT][Audio] output volume command failed; code=", code, "status=", status)
            if (root.outputVolumePending) root.outputVolumeTimer.restart()
            else { root.outputBalanceDirty = false; root.refresh() }
        }
    }
    property Process inputVolumeProcess: Process {
        command: []
        onExited: (code, status) => {
            if (code !== 0) console.warn("[SAT][Audio] input volume command failed; code=", code, "status=", status)
            if (root.inputVolumePending) root.inputVolumeTimer.restart()
            else { root.inputBalanceDirty = false; root.refresh() }
        }
    }

    property Timer refreshTimer: Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
