pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

QtObject {
    id: root

    // ── Public state ─────────────────────────────────────────────────────
    property bool dndEnabled:  false
    property var  mutedApps:   []
    property var  notifList:   []          // flat list, newest first
    property var  queuedList:  []          // held during DND
    property var  toastList:   []          // currently visible toasts
    property var  groupedNotifications: [] // rebuilt by rebuildGroups()

    // backward-compat alias used by the bar pill / tab badge
    readonly property bool doNotDisturb: dndEnabled
    // Queued notifications are already part of history; they are merely
    // withheld from toast presentation while DND is enabled.
    readonly property int  count:        notifList.length

    // internal map: id -> Notification object
    property var notifObjects: ({})

    // ── NotificationServer ───────────────────────────────────────────────
    property NotificationServer server: NotificationServer {
        keepOnReload:         true
        actionsSupported:     true
        bodySupported:        true
        bodyMarkupSupported:  true
        imageSupported:       true

        onNotification: (n) => {
            n.tracked = true
            if (root.mutedApps.indexOf(n.appName) !== -1) {
                root.dismissNotificationObject(n)
                return
            }
            root.notifObjects[n.id] = n
            const entry = {
                notifId:      n.id,
                appName:      n.appName   || "Unknown",
                appIcon:      n.appIcon   || "",
                summary:      n.summary   || "",
                body:         n.body      || "",
                urgency:      n.urgency,
                timestamp:    Date.now(),
                resident:     !!n.resident,
                transient:    !!n.transient,
                fullyExpanded: false,
                actionsJson:  JSON.stringify(
                    (n.actions || []).map(a => ({ id: a.identifier, text: a.text }))
                )
            }
            if (root.dndEnabled) {
                root.queuedList = [entry].concat(root.queuedList)
                root.notifList = [entry].concat(root.notifList)
                root.rebuildGroups()
            } else {
                root._addEntry(entry, n)
            }
        }
    }

    // ── Internal helpers ─────────────────────────────────────────────────
    function dismissNotificationObject(n) {
        if (!n) return
        try {
            // Setting tracked to false is the documented dismissal operation.
            // A notification may already have closed before the user clears history.
            n.tracked = false
        } catch (e) {
            // Always allow local history cleanup to proceed for stale objects.
        }
    }

    function dismissAndForget(id) {
        dismissNotificationObject(root.notifObjects[id])
        delete root.notifObjects[id]
    }

    function _addEntry(entry, n) {
        root.notifList = [entry].concat(root.notifList)
        root.rebuildGroups()
        root.showToast(entry)
    }

    

    // ── Public API ───────────────────────────────────────────────────────
    function removeNotification(id) {
        root.notifList = root.notifList.filter(e => e.notifId !== id)
        root.queuedList = root.queuedList.filter(e => e.notifId !== id)
        root.dismissAndForget(id)
        root.removeToast(id)
        root.rebuildGroups()
    }

    function clearAll() {
        Object.keys(root.notifObjects).forEach(id => root.dismissAndForget(id))
        root.notifList    = []
        root.queuedList   = []
        root.notifObjects = {}
        root.toastList    = []
        root.rebuildGroups()
    }

    function clearApp(appName) {
        const toRemove = root.notifList.filter(e => e.appName === appName)
        for (const e of toRemove) {
            root.dismissAndForget(e.notifId)
        }
        root.notifList = root.notifList.filter(e => e.appName !== appName)
        root.queuedList = root.queuedList.filter(e => e.appName !== appName)
        root.toastList = root.toastList.filter(e => e.appName !== appName)
        root.rebuildGroups()
    }

    function toggleMuteApp(appName) {
        const idx  = mutedApps.indexOf(appName)
        const copy = mutedApps.slice()
        if (idx === -1) copy.push(appName)
        else copy.splice(idx, 1)
        mutedApps = copy
        root.rebuildGroups()
    }

    function setDnd(enabled) {
        dndEnabled = enabled
        if (!enabled) {
            const toFlush  = root.queuedList
            root.queuedList = []
            for (const e of toFlush) {
                // The entry was stored in history when it arrived. Only
                // release its toast now; adding it again would duplicate it.
                if (root.mutedApps.indexOf(e.appName) === -1)
                    root.showToast(e)
            }
        }
    }

    // backward-compat: toggles DND
    function toggle() { setDnd(!dndEnabled) }

    function invokeAction(notifId, actionId) {
        const n = root.notifObjects[notifId]
        if (n) n.invokeAction(actionId)
    }

    function showToast(entry) {
        if (root.dndEnabled) return
        root.toastList = [entry].concat(root.toastList)
        // Toasts time out in shell.qml; panel history stays until explicitly cleared.
    }

    function removeToast(id) {
        root.toastList = root.toastList.filter(e => e.notifId !== id)
    }

    // ── Time formatting ──────────────────────────────────────────────────
    function timeAgo(ts) {
        const diff = Math.floor((Date.now() - ts) / 1000)
        if (diff < 60)    return "Just now"
        if (diff < 3600)  return Math.floor(diff / 60)   + "m ago"
        if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
        return Math.floor(diff / 86400) + "d ago"
    }

    function isToday(ts) {
        const d   = new Date(ts)
        const now = new Date()
        return d.toDateString() === now.toDateString()
    }

    // ── Group rebuilder ──────────────────────────────────────────────────
    function rebuildGroups() {
        const today   = []
        const earlier = []
        for (const e of root.notifList) {
            (isToday(e.timestamp) ? today : earlier).push(e)
        }
        function group(list) {
            const byApp = {}
            const order = []
            for (const e of list) {
                if (!byApp[e.appName]) { byApp[e.appName] = []; order.push(e.appName) }
                byApp[e.appName].push(e)
            }
            return order.map(name => ({
                appName: name,
                appIcon: byApp[name][0].appIcon,
                muted:   root.mutedApps.indexOf(name) !== -1,
                items:   byApp[name]
            }))
        }
        const out = []
        if (today.length)   out.push({ label: "Today",   apps: group(today)   })
        if (earlier.length) out.push({ label: "Earlier", apps: group(earlier) })
        root.groupedNotifications = out
    }
}
