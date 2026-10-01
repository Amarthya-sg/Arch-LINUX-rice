pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

QtObject {
    id: root

    property var playersList: Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players
    property var activePlayer: resolveActivePlayer()

    readonly property bool hasTrack: activePlayer !== null
        && String(activePlayer.trackTitle || activePlayer.title || "").length > 0
    readonly property bool playing: activePlayer
        ? activePlayer.playbackState === MprisPlaybackState.Playing : false
    readonly property string title: hasTrack
        ? String(activePlayer.trackTitle || activePlayer.title || "") : ""
    readonly property string artUrl: activePlayer
        ? String(activePlayer.trackArtUrl || activePlayer.artUrl || "") : ""
    readonly property string artist: {
        if (!activePlayer) return ""
        let value = activePlayer.artist
        if (!value && activePlayer.metadata) value = activePlayer.metadata["xesam:artist"]
        if (Array.isArray(value)) return value.join(", ")
        return value ? String(value) : ""
    }
    readonly property string playerName: activePlayer
        ? String(activePlayer.identity || activePlayer.name || activePlayer.dbusName || "") : ""
    readonly property real position: activePlayer ? Math.max(0, Number(activePlayer.position) || 0) * 1000000 : 0
    readonly property real length: activePlayer ? Math.max(0, Number(activePlayer.length) || 0) * 1000000 : 0
    readonly property real progress: length > 0
        ? Math.max(0, Math.min(1, displayPosition / length)) : 0
    property real displayPosition: 0
    property real positionAnchor: 0
    property real lastObservedPosition: 0
    property double positionAnchorTime: 0
    readonly property bool available: hasTrack

    function resolveActivePlayer() {
        if (!playersList || playersList.length === 0) return null
        for (let i = 0; i < playersList.length; i++)
            if (playersList[i].playbackState === MprisPlaybackState.Playing)
                return playersList[i]
        for (let i = 0; i < playersList.length; i++)
            if (playersList[i].playbackState === MprisPlaybackState.Paused)
                return playersList[i]
        return playersList.length > 0 ? playersList[0] : null
    }

    function updateDisplayPosition(): void {
        if (!root.hasTrack) {
            root.displayPosition = 0
            root.positionAnchor = 0
            root.lastObservedPosition = 0
            root.positionAnchorTime = 0
            return
        }
        const observed = root.position
        root.displayPosition = observed
        root.positionAnchor = observed
        root.lastObservedPosition = observed
        root.positionAnchorTime = Date.now()
    }

    // Some MPRIS players expose position but do not emit positionChanged on
    // every tick. Keep the UI live locally and resync whenever the reported
    // position jumps (track changes, seeking, or player-side updates).
    function advanceDisplayPosition(): void {
        if (!root.hasTrack) {
            root.displayPosition = 0
            return
        }
        const observed = root.position
        const now = Date.now()
        if (!root.playing) {
            root.displayPosition = observed
            root.positionAnchor = observed
            root.lastObservedPosition = observed
            root.positionAnchorTime = now
            return
        }

        // A player-side seek or track transition is a real discontinuity.
        // Otherwise use wall-clock time so timer scheduling jitter cannot
        // accumulate into visible drift.
        if (root.positionAnchorTime <= 0
                || Math.abs(observed - root.lastObservedPosition) > 500000) {
            root.positionAnchor = observed
            root.positionAnchorTime = now
            root.lastObservedPosition = observed
        }
        const projected = root.positionAnchor
            + Math.max(0, now - root.positionAnchorTime) * 1000
        root.displayPosition = root.length > 0
            ? Math.min(root.length, projected) : projected
    }

    function toggle(): void {
        if (activePlayer && activePlayer.canTogglePlaying) activePlayer.togglePlaying()
    }
    function next(): void {
        if (activePlayer && activePlayer.canGoNext) activePlayer.next()
    }
    function previous(): void {
        if (activePlayer && activePlayer.canGoPrevious) activePlayer.previous()
    }
    function seekToRatio(ratio): void {
        if (!activePlayer || length <= 0) return
        const target = Math.max(0, Math.min(1, Number(ratio))) * length / 1000000
        if (activePlayer.canSeek !== false) activePlayer.position = target
        root.displayPosition = target * 1000000
    }

    onActivePlayerChanged: updateDisplayPosition()

    property Connections playerConnections: Connections {
        target: root.activePlayer
        function onPositionChanged() { root.updateDisplayPosition() }
        function onLengthChanged() { root.updateDisplayPosition() }
        function onPlaybackStateChanged() { root.updateDisplayPosition() }
        function onTrackTitleChanged() { root.updateDisplayPosition() }
    }

    property Timer progressTimer: Timer {
        interval: 1000
        running: root.hasTrack
        repeat: true
        triggeredOnStart: true
        onTriggered: root.advanceDisplayPosition()
    }
}
