// Wallpaper selector - Quickshell overlay backed by ~/DATABASE/wallpaper
// Run with: qs -p WallpaperSelector.qml
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "wallpaper-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Image that reports its own load lifecycle (start / ready / cached / error / cancel + ms taken).
    // Everything that loads pixels goes through this so the debug log sees every load.
    component TImage: Image {
        id: ti
        property string tag: ""
        property double loadT0: 0
        property bool inFlight: false
        signal loadEvent(string who, string what, url src, int ms, string info)
        onStatusChanged: {
            if (status === Image.Loading) {
                if (!inFlight) { inFlight = true; loadT0 = Date.now(); loadEvent(tag, "start", source, 0, "") }
            } else {
                var was = inFlight
                var ms = was ? Date.now() - loadT0 : 0
                inFlight = false
                if (status === Image.Ready) loadEvent(tag, was ? "ready" : "cached", source, ms, implicitWidth + "x" + implicitHeight)
                else if (status === Image.Error) loadEvent(tag, "error", source, ms, "")
                else if (was) loadEvent(tag, "cancel", source, ms, "")
            }
        }
    }

    // Image with rounded corners / circle crop (radius = width/2 for a circle).
    // decodeWidth is in device pixels (caller multiplies by devicePixelRatio).
    component RoundImage: Item {
        id: ri
        property url source
        property real radius: 0
        property int decodeWidth: 640
        property string tag: ""
        signal loadEvent(string who, string what, url src, int ms, string info)
        Rectangle { anchors.fill: parent; radius: ri.radius; color: Qt.rgba(.5, .5, .5, .35); antialiasing: true }
        TImage {
            id: img
            tag: ri.tag
            onLoadEvent: (who, what, src, ms, info) => ri.loadEvent(who, what, src, ms, info)
            anchors.fill: parent
            source: ri.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            mipmap: true
            sourceSize.width: ri.decodeWidth
            visible: false
        }
        Item {
            id: msk                       // only the small mask is supersampled
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.max(1, ri.width * 2), Math.max(1, ri.height * 2))
            Rectangle { anchors.fill: parent; radius: ri.radius; color: "black"; antialiasing: true }
        }
        MultiEffect {
            anchors.fill: parent
            source: img
            maskEnabled: true
            maskSource: msk
            opacity: img.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
    }

    // Full-screen blurred background layer; fades in once its image has loaded
    component BgLayer: Item {
        id: bl
        property url src
        property bool pending: false
        property string tag: ""
        signal loadEvent(string who, string what, url src, int ms, string info)
        opacity: 0
        function show() {
            pending = true
            opacity = 0
            if (bgImg.status === Image.Ready) go()
        }
        function go() { pending = false; loadEvent(tag, "fade-start", src, 0, ""); fade.restart() }
        TImage {
            id: bgImg
            tag: bl.tag
            onLoadEvent: (who, what, src, ms, info) => bl.loadEvent(who, what, src, ms, info)
            anchors.fill: parent
            source: bl.src
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 320                // it gets blurred anyway: tiny decode = fast
            smooth: true
            visible: false
        }
        Connections {
            target: bgImg
            function onStatusChanged() { if (bgImg.status === Image.Ready && bl.pending) bl.go() }
        }
        MultiEffect {
            anchors.fill: parent
            scale: 1.08                          // hide the soft edges the blur creates
            source: bgImg
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 32
            blur: 1.0                            // 0..1, strength of the blur
            brightness: -0.05
        }
        ParallelAnimation {
            id: fade
            onFinished: bl.loadEvent(bl.tag, "fade-end", bl.src, 0, "")
            NumberAnimation { target: bl; property: "opacity"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: bl; property: "scale"; from: 1.05; to: 1; duration: 700; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true

        // ---------- debug ----------
        // Timestamped log of everything: open, loads, inputs, state changes, selections, close.
        //   WS_DEBUG=0   silence the log (warnings/errors still print)
        //   WS_HUD=0     start without the on-screen panel (F12 toggles it at runtime)
        //   WS_VERBOSE=1 also log instant cache-hit image loads (noisy)
        // Line format:  [wall-clock | T+ seconds since open | +ms since previous event] #n TAG message
        readonly property bool debug: Quickshell.env("WS_DEBUG") !== "0"
        readonly property bool verbose: Quickshell.env("WS_VERBOSE") === "1"
        property bool hud: debug && Quickshell.env("WS_HUD") !== "0"
        property int heartbeatSec: 5          // console heartbeat period, 0 = off
        readonly property double t0: Date.now()   // the counter starts here (window open)
        property double nowMs: t0
        property double tLast: t0
        property double listT0: t0
        property double genT0: 0
        property int tick: 0
        property int evCount: 0
        property int loadingCount: 0
        property int loadsDone: 0
        property int loadErrors: 0
        property int cacheHits: 0
        property int wheelDropped: 0
        property bool firstThemes: false
        property bool firstWall: false
        property bool firstBg: false
        property var logTail: []
        property var urlNames: ({})           // url -> "theme/file.jpg" (readable names for the log)

        function pad0(n, w) { var s = String(n); while (s.length < w) s = "0" + s; return s }
        function padL(n, w) { var s = String(n); while (s.length < w) s = " " + s; return s }
        function padR(n, w) { var s = String(n); while (s.length < w) s += " "; return s }
        function stamp() {
            var d = new Date()
            return pad0(d.getHours(), 2) + ":" + pad0(d.getMinutes(), 2) + ":" + pad0(d.getSeconds(), 2) + "." + pad0(d.getMilliseconds(), 3)
        }
        function dbg(tag, msg, warn) {
            if (!debug && !warn) return
            var now = Date.now()
            var line = "[" + stamp() + " | T+" + padL(((now - t0) / 1000).toFixed(3), 8) + "s | +" + padL(now - tLast, 5) + "ms] #"
                     + pad0(++evCount, 3) + " " + padR(tag, 9) + " " + msg
            tLast = now
            if (warn) console.warn(line); else console.log(line)
            logTail = logTail.concat([((now - t0) / 1000).toFixed(1) + "s " + padR(tag, 9) + " " + msg]).slice(-9)
        }
        function srcInfo(u) {
            var s = String(u)
            if (!s) return "(none)"
            var n = urlNames[s]
            return (n ? n : decodeURIComponent(s.split("/").pop())) + " [" + (s.indexOf("/wallpaper-selector/") >= 0 ? "thumb" : "orig") + "]"
        }
        function btnName(b) { return b === Qt.LeftButton ? "left" : b === Qt.RightButton ? "right" : b === Qt.MiddleButton ? "middle" : String(b) }
        function keyName(k, txt) {
            switch (k) {
            case Qt.Key_Right: return "Right"
            case Qt.Key_Left: return "Left"
            case Qt.Key_Up: return "Up"
            case Qt.Key_Down: return "Down"
            case Qt.Key_Return: return "Return"
            case Qt.Key_Enter: return "Enter"
            case Qt.Key_Escape: return "Escape"
            case Qt.Key_Tab: return "Tab"
            case Qt.Key_Space: return "Space"
            case Qt.Key_F12: return "F12"
            }
            return txt ? "'" + txt + "'" : "0x" + k.toString(16)
        }
        // every image load in the UI reports here (see TImage)
        function imgEvt(who, what, src, ms, info) {
            var done = false
            if (what === "start") loadingCount++
            else if (what === "ready" || what === "error" || what === "cancel") {
                loadingCount = Math.max(0, loadingCount - 1)
                done = true
                if (what === "ready") loadsDone++
                if (what === "error") loadErrors++
            }
            var ok = what === "ready" || what === "cached"
            if (ok && who === "wall[2]" && !firstWall) {
                firstWall = true
                dbg("MILESTONE", "first centre wallpaper visible at T+" + (Date.now() - t0) + "ms")
            }
            if (ok && who.indexOf("bg") === 0 && !firstBg) {
                firstBg = true
                dbg("MILESTONE", "first blurred background loaded at T+" + (Date.now() - t0) + "ms")
            }
            if (what === "cached") { cacheHits++; if (!verbose) return }
            dbg(what === "error" ? "ERROR" : "LOAD",
                padR(who, 8) + " " + padR(what, 10) + " " + srcInfo(src) + (ms ? "  " + ms + "ms" : "") + (info ? "  " + info : "")
                + "  (in-flight=" + loadingCount + ")", what === "error")
            if (done && loadingCount === 0)
                dbg("MILESTONE", "all image loads settled: done=" + loadsDone + " errors=" + loadErrors + " cache-hits=" + cacheHits)
        }
        function runList(why) { listT0 = Date.now(); dbg("LIST", "scanning library (" + why + ")"); lister.running = true }
        function runGen() { genT0 = Date.now(); dbg("GEN", "thumbnail builder started (background, nice 19)"); thumbGen.running = true }
        function quit() {
            dbg("CLOSE", "quit after " + ((Date.now() - t0) / 1000).toFixed(2) + "s | events=" + evCount + " loads=" + loadsDone
                + " errors=" + loadErrors + " cache-hits=" + cacheHits)
            Qt.quit()
        }

        Component.onCompleted: {
            dbg("OPEN", "selector opened | screen " + Screen.name + " " + Screen.width + "x" + Screen.height + " @" + Screen.devicePixelRatio + "x")
            dbg("OPEN", "library=" + libraryPath + " | heartbeat=" + heartbeatSec + "s | F12 toggles HUD")
        }
        Timer {                                   // the open-time counter + periodic heartbeat
            interval: 100; repeat: true; running: root.debug
            onTriggered: {
                root.nowMs = Date.now()
                root.tick++
                if (root.heartbeatSec > 0 && root.tick % (root.heartbeatSec * 10) === 0)
                    root.dbg("BEAT", "up=" + Math.round((root.nowMs - root.t0) / 1000) + "s mode=" + root.mode + " theme=#" + root.active
                             + " wi=" + root.wi + " in-flight=" + root.loadingCount + " events=" + root.evCount)
            }
        }
        Timer { id: resizeT; interval: 60; onTriggered: root.dbg("WINDOW", "size " + root.width + "x" + root.height) }
        onWidthChanged: resizeT.restart()
        onHeightChanged: resizeT.restart()
        onActiveFocusChanged: dbg("WINDOW", "keyboard focus " + (activeFocus ? "gained" : "LOST"))

        // ---------- library ----------
        readonly property string libraryPath: Quickshell.env("HOME") + "/DATABASE/wallpaper"
        property var themes: []     // [{n, desc, images:[file:// urls]}]
        readonly property bool ready: themes.length > 0
        readonly property int nThemes: themes.length
        readonly property real stepDeg: 360 / Math.max(1, nThemes) * 0.8
        readonly property var cur: ready ? themes[active] : null
        readonly property int imgCount: cur ? cur.images.length : 1

        // One script, two modes:
        //   list -> JSON of themes/images; uses the cached thumbnail URL when it exists, else the original
        //   gen  -> (background, low priority) builds the missing thumbnails, theme preview images first
        readonly property string pyScript: `
import os, sys, json, pathlib, hashlib, time
root, mode = sys.argv[1], sys.argv[2]
cache = os.path.join(os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')), 'wallpaper-selector')
ext = ('.jpg', '.jpeg', '.png', '.gif', '.webp')
W = 1400

def thumb_path(p):
    st = os.stat(p)
    key = p + '|' + str(st.st_mtime_ns) + '|' + str(st.st_size) + '|' + str(W)
    return os.path.join(cache, hashlib.sha1(key.encode()).hexdigest() + '.jpg')

themes = []
for t in sorted(os.listdir(root)):
    d = os.path.join(root, t)
    if not os.path.isdir(d):
        continue
    name, desc = t, ''
    try:
        m = json.load(open(os.path.join(d, '.metatag'), encoding='utf-8'))
        name = m.get('name', t); desc = m.get('description', '')
    except Exception:
        pass
    imgs = sorted(f for f in os.listdir(d) if not f.startswith('.') and f.lower().endswith(ext))
    if imgs:
        themes.append((name, desc, [os.path.join(d, f) for f in imgs]))

if mode == 'list':
    out = []
    for name, desc, paths in themes:
        urls = []
        names = []
        for p in paths:
            tp = thumb_path(p)
            urls.append(pathlib.Path(tp if os.path.exists(tp) else p).as_uri())
            names.append(os.path.basename(os.path.dirname(p)) + '/' + os.path.basename(p))
        out.append({'n': name, 'desc': desc, 'images': urls, 'names': names})
    print(json.dumps(out))
else:
    os.nice(19)
    os.makedirs(cache, exist_ok=True)
    try:
        from PIL import Image, ImageOps
    except ImportError:
        Image = None
    import subprocess
    from concurrent.futures import ThreadPoolExecutor

    def make(p):
        out = thumb_path(p)
        if os.path.exists(out):
            return
        tmp = out + '.part'
        t0 = time.time()
        try:
            if Image is not None:
                im = Image.open(p)
                if p.lower().endswith(('.jpg', '.jpeg')):
                    im.draft('RGB', (W, W))
                im = ImageOps.exif_transpose(im)
                im.seek(0)
                im = im.convert('RGB')
                im.thumbnail((W, W), Image.LANCZOS)
                im.save(tmp, 'JPEG', quality=88)
            else:
                subprocess.run(['magick', p + '[0]', '-background', 'black', '-flatten',
                                '-resize', str(W) + 'x' + str(W) + '>', '-quality', '88', 'JPEG:' + tmp],
                               check=True)
            os.replace(tmp, out)
            sys.stderr.write('thumb ok: ' + os.path.basename(os.path.dirname(p)) + '/' + os.path.basename(p) + ' ' + str(int((time.time() - t0) * 1000)) + 'ms' + chr(10))
        except Exception as e:
            sys.stderr.write('thumb failed: ' + p + ': ' + str(e) + chr(10))

    first = [paths[0] for _, _, paths in themes]
    rest = [p for _, _, paths in themes for p in paths[1:]]
    allp = first + rest
    todo = len([p for p in allp if not os.path.exists(thumb_path(p))])
    print('gen: ' + str(todo) + ' to build, ' + str(len(allp) - todo) + ' already cached', file=sys.stderr)
    with ThreadPoolExecutor(max_workers=4) as ex:
        list(ex.map(make, allp))
`
        property bool refreshing: false
        property bool genStarted: false
        Process {
            id: lister
            running: true
            command: ["python3", "-c", root.pyScript, root.libraryPath, "list"]
            stdout: StdioCollector {
                onStreamFinished: {
                    var ms = Date.now() - root.listT0
                    try {
                        var th = JSON.parse(text)
                        var map = {}, nImg = 0, nThumb = 0
                        for (var i = 0; i < th.length; i++) {
                            for (var j = 0; j < th[i].images.length; j++) {
                                var u = th[i].images[j]
                                map[u] = th[i].names ? th[i].names[j] : ""
                                nImg++
                                if (u.indexOf("/wallpaper-selector/") >= 0) nThumb++
                            }
                        }
                        root.urlNames = map            // names first, so the load logs are readable
                        root.themes = th
                        root.dbg("LIST", "done in " + ms + "ms: " + th.length + " themes, " + nImg + " images ("
                                 + nThumb + " thumbs, " + (nImg - nThumb) + " originals)")
                        if (!root.firstThemes) { root.firstThemes = true; root.dbg("MILESTONE", "library ready at T+" + (Date.now() - root.t0) + "ms") }
                    } catch (e) { root.dbg("LIST", "library parse failed after " + ms + "ms: " + e, true) }
                    root.refreshing = false
                    if (!root.genStarted) { root.genStarted = true; root.runGen() }
                }
            }
            stderr: StdioCollector { onStreamFinished: if (text.length) root.dbg("LIST", "stderr: " + text.trim(), true) }
        }
        Process {
            id: thumbGen
            running: false
            command: ["python3", "-c", root.pyScript, root.libraryPath, "gen"]
            // thumbnails are ready: re-list so the UI switches from originals to thumbs without a restart
            onExited: (code, status) => {
                root.dbg("GEN", "builder exited code=" + code + " after " + (Date.now() - root.genT0) + "ms -> re-listing")
                root.refreshing = true
                root.runList("after thumbnails")
            }
            // live, line by line: "gen: N to build", "thumb ok: ... Xms", "thumb failed: ...", python warnings
            stderr: SplitParser {
                onRead: (line) => root.dbg("GEN", line, line.indexOf("failed") >= 0 || line.indexOf("Warning") >= 0)
            }
        }
        onThemesChanged: {
            dbg("STATE", "themes updated: " + nThemes + " (refresh=" + refreshing + ")")
            if (ready && !refreshing) { wi = 0; showBg() }
        }

        // Prefetch: decode the 5 visible images of the active theme and its two neighbours
        // (same sourceSize as the cards, so the pixmap cache hits when the theme changes)
        Repeater {
            model: root.ready ? 15 : 0
            delegate: TImage {
                required property int index
                tag: "pre[" + index + "]"
                onLoadEvent: (who, what, src, ms, info) => root.imgEvt(who, what, src, ms, info)
                readonly property var th: root.themes[root.mod(root.active + Math.floor(index / 5) - 1, root.nThemes)]
                source: th && th.images.length ? th.images[root.mod(index % 5 - 2, th.images.length)] : ""
                asynchronous: true
                cache: true
                visible: false
                sourceSize.width: root.wallDecode
            }
        }

        // ---------- state ----------
        property real target: 0
        property real rot: target
        Behavior on rot { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        readonly property int active: ready ? mod(Math.round(target), nThemes) : 0
        onActiveChanged: {
            wi = 0
            dbg("STATE", "theme -> #" + active + " " + (cur ? cur.n : "-") + " (" + imgCount + " images)")
        }
        property int wi: 0
        onWiChanged: dbg("STATE", "image wi=" + wi + "/" + imgCount + "  " + srcInfo(wallUrl(2)))
        property string mode: "dial"
        onModeChanged: dbg("STATE", "mode -> " + mode)
        property real lock: 0
        property bool flip: false
        property int zc: 0

        readonly property bool dark: Qt.styleHints.colorScheme === Qt.Dark
        readonly property bool narrow: width < 560
        readonly property color ink: dark ? "#f4f4f7" : "#14151a"
        readonly property color muted: dark ? "#c0c3ce" : "#40434e"
        readonly property color glass: dark ? Qt.rgba(16/255, 17/255, 21/255, .78) : Qt.rgba(1, 1, 1, .84)
        readonly property color line: dark ? Qt.rgba(1, 1, 1, .38) : Qt.rgba(20/255, 21/255, 26/255, .30)
        readonly property real tileSize: narrow ? 62 : 84
        // decode wide enough that PreserveAspectCrop never has to upscale (assumes sources up to ~2:1)
        readonly property int wallDecode: Math.ceil(Math.max(wallsArea.centerW, wallsArea.wallH * 2) * Screen.devicePixelRatio)
        readonly property int tileDecode: Math.ceil(tileSize * 1.3 * 2 * Screen.devicePixelRatio)

        function mod(a, n) { return ((a % n) + n) % n }
        function wallUrl(s) {
            return cur && cur.images.length ? cur.images[mod(wi + s - 2, cur.images.length)] : ""
        }
        // blurred preview: always follows the wallpaper in the centre slot
        readonly property string centerUrl: wallUrl(2)
        onCenterUrlChanged: bgTimer.restart()
        Timer { id: bgTimer; interval: 120; onTriggered: root.showBg() }
        function showBg() {
            var url = wallUrl(2)
            if (!url) return
            var l = flip ? bg1 : bg0
            flip = !flip
            l.src = url
            l.z = ++zc
            dbg("BG", "blur " + l.tag + " <- " + srcInfo(url))
            l.show()
        }
        // explicit selection (Enter / click): this is where the real "set wallpaper" hook goes
        function applyBg() {
            if (!cur) { dbg("ACTION", "apply ignored: no theme loaded"); return }
            dbg("ACTION", "SELECTED " + cur.n + "  " + srcInfo(wallUrl(2)) + "  (wi=" + wi + ")")
            console.log("SELECTED", cur.n, wallUrl(2))
        }
        function slide(d) { for (var i = 0; i < 5; i++) walls.itemAt(i).kick(d) }
        function browse(d) { dbg("ACTION", "browse " + d); wi = mod(wi + d, imgCount); slide(d) }
        function step(d) {
            if (!ready) { dbg("INPUT", "step " + d + " ignored: library not loaded yet"); return }
            dbg("ACTION", "step " + d + " (" + mode + ")")
            if (mode === "dial") target += d; else browse(d)
        }
        function wallClicked(s) {
            dbg("ACTION", "wallClicked slot=" + s + (s === 2 ? " (centre)" : " (side)"))
            mode = "walls"
            wi = mod(wi + s - 2, imgCount)
            applyBg()
            slide(Math.sign(s - 2))
        }

        // ---------- input ----------
        WheelHandler {
            onWheel: (e) => {
                var now = Date.now()
                if (now - root.lock < 140) { root.wheelDropped++; return }
                root.lock = now
                var d = -Math.sign(e.angleDelta.y || e.angleDelta.x)
                root.dbg("INPUT", "wheel dy=" + e.angleDelta.y + " dx=" + e.angleDelta.x + " -> " + d
                         + (root.wheelDropped ? "  (+" + root.wheelDropped + " throttled)" : ""))
                root.wheelDropped = 0
                if (d) root.step(d)
            }
        }
        Keys.onPressed: (e) => {
            root.dbg("INPUT", "key " + root.keyName(e.key, e.text) + (e.isAutoRepeat ? " (repeat)" : "") + "  mode=" + root.mode)
            if (e.key === Qt.Key_F12) root.hud = !root.hud
            else if (e.key === Qt.Key_Right) root.step(1)
            else if (e.key === Qt.Key_Left) root.step(-1)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (root.mode === "dial") root.mode = "walls"; else root.applyBg()
            } else if (e.key === Qt.Key_Escape) {
                if (root.mode === "walls") root.mode = "dial"; else root.quit()
            }
        }

        // ---------- background ----------
        Rectangle { anchors.fill: parent; color: root.dark ? "#101114" : "#d9dbe0" }
        Item {
            id: bgStack          // keeps the layers' z-values local so they never cover the UI
            anchors.fill: parent
            clip: true
            BgLayer { id: bg0; tag: "bg0"; anchors.fill: parent; onLoadEvent: (who, what, src, ms, info) => root.imgEvt(who, what, src, ms, info) }
            BgLayer { id: bg1; tag: "bg1"; anchors.fill: parent; onLoadEvent: (who, what, src, ms, info) => root.imgEvt(who, what, src, ms, info) }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0;  color: root.dark ? Qt.rgba(0, 0, 0, .25) : Qt.rgba(1, 1, 1, .10) }
                GradientStop { position: .4; color: root.dark ? Qt.rgba(0, 0, 0, .05) : Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 1;  color: root.dark ? Qt.rgba(0, 0, 0, .45) : Qt.rgba(1, 1, 1, .30) }
            }
        }

        // ---------- dial (one tile per theme folder) ----------
        Item {
            id: dial
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(900, parent.width)
            height: root.narrow ? 270 : 300
            clip: true
            opacity: root.mode === "walls" ? .5 : 1
            Behavior on opacity { NumberAnimation { duration: 300 } }

            readonly property real ringRadius: Math.min(width * .42, 320)
            readonly property real cx: width / 2
            readonly property real cy: height + ringRadius * .42

            Rectangle {
                x: dial.cx - dial.ringRadius; y: dial.cy - dial.ringRadius
                width: 2 * dial.ringRadius; height: width; radius: dial.ringRadius
                color: "transparent"; border.width: 1; border.color: root.line
            }

            Repeater {
                model: root.nThemes
                delegate: Item {
                    id: t
                    required property int index
                    readonly property real d: root.mod(index - root.rot + root.nThemes / 2, root.nThemes) - root.nThemes / 2
                    readonly property real deg: d * root.stepDeg
                    readonly property bool hidden: Math.abs(deg) > 110
                    readonly property bool act: root.active === index
                    width: root.tileSize; height: width
                    x: dial.cx + dial.ringRadius * Math.sin(deg * Math.PI / 180) - width / 2
                    y: dial.cy - dial.ringRadius * Math.cos(deg * Math.PI / 180) - height / 2
                    rotation: deg
                    scale: 1 + .3 * Math.max(0, 1 - Math.abs(d))
                    z: scale > 1.15 ? 2 : 1
                    opacity: hidden ? 0 : 1
                    enabled: !hidden

                    RoundImage {
                        anchors.fill: parent
                        radius: width / 2
                        decodeWidth: root.tileDecode
                        source: root.themes[t.index].images[0]
                        tag: "tile[" + t.index + "]"
                        onLoadEvent: (who, what, src, ms, info) => root.imgEvt(who, what, src, ms, info)
                    }
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: "transparent"; border.width: 2; border.color: Qt.rgba(1, 1, 1, .92)
                    }
                    Rectangle {
                        visible: t.act
                        anchors.centerIn: parent
                        width: parent.width + 12; height: width; radius: width / 2
                        color: "transparent"
                        border.width: root.mode === "walls" ? 1 : 3
                        border.color: root.mode === "walls" ? root.line : root.ink
                    }
                    TapHandler {
                        onTapped: (pt, btn) => {
                            root.dbg("INPUT", "click tile[" + t.index + "] " + root.themes[t.index].n + " btn=" + root.btnName(btn)
                                     + " @" + Math.round(pt.position.x) + "," + Math.round(pt.position.y))
                            root.target += root.mod(t.index - root.active + root.nThemes / 2, root.nThemes) - root.nThemes / 2
                            root.mode = "walls"
                        }
                    }
                }
            }
        }

        // ---------- debug HUD (F12 toggles; never takes input) ----------
        Rectangle {
            visible: root.debug && root.hud
            z: 100
            x: 12; y: 12
            width: hudCol.width + 20; height: hudCol.height + 16
            radius: 8
            color: Qt.rgba(0, 0, 0, .74)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, .2)
            Column {
                id: hudCol
                x: 10; y: 8
                spacing: 2
                Text {
                    color: "#ffd166"; font.family: "monospace"; font.pixelSize: 13; font.bold: true
                    text: "DEBUG   up " + ((root.nowMs - root.t0) / 1000).toFixed(1) + "s"
                }
                Text {
                    color: "#e8e8ee"; font.family: "monospace"; font.pixelSize: 12
                    text: "mode " + root.mode + "   theme " + (root.ready ? root.active + 1 : 0) + "/" + root.nThemes + "   img " + (root.wi + 1) + "/" + root.imgCount
                }
                Text {
                    color: "#e8e8ee"; font.family: "monospace"; font.pixelSize: 12
                    text: "in-flight " + root.loadingCount + "   done " + root.loadsDone + "   err " + root.loadErrors
                          + "   cached " + root.cacheHits + "   events " + root.evCount
                }
                Repeater {
                    model: root.logTail
                    delegate: Text {
                        required property string modelData
                        width: Math.min(560, root.width - 60)
                        elide: Text.ElideRight
                        color: "#9aa0b4"; font.family: "monospace"; font.pixelSize: 11
                        text: modelData
                    }
                }
            }
        }

        // ---------- name + description pill (from .metatag) ----------
        Rectangle {
            id: bar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: dial.top
            anchors.bottomMargin: 10
            width: col.width + 52
            height: col.height + 22
            radius: Math.min(height / 2, 28)
            color: root.glass
            Column {
                id: col
                anchors.centerIn: parent
                spacing: 2
                property real dy: 0
                transform: Translate { y: col.dy }
                Text {
                    id: nameText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.cur ? root.cur.n : ""
                    color: root.ink
                    font.family: "Space Grotesk"; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    id: descText
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text.length > 0
                    text: root.cur ? root.cur.desc : ""
                    color: root.muted
                    font.family: "Space Grotesk"; font.pixelSize: 12
                    width: Math.min(implicitWidth, Math.min(root.width * .8, 560))
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Connections {
                    target: root
                    function onActiveChanged() { nameAnim.restart() }
                }
                ParallelAnimation {
                    id: nameAnim
                    NumberAnimation { target: col; property: "dy"; from: 8; to: 0; duration: 300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: col; property: "opacity"; from: 0; to: 1; duration: 300 }
                }
            }
        }

        // ---------- wallpaper parallelograms (images of the active theme) ----------
        Item {
            id: wallsArea
            anchors.top: parent.top
            anchors.topMargin: parent.height * .06
            anchors.bottom: bar.top
            anchors.bottomMargin: 22
            anchors.left: parent.left; anchors.right: parent.right

            readonly property real gap: root.narrow ? 6 : 10
            readonly property real pad: Math.max(16, Math.min(width * .05, 40))
            readonly property real avail: Math.min(980, width) - 2 * pad
            readonly property real unit: (avail - 4 * gap) / 11
            readonly property real sideW: Math.min(root.narrow ? 46 : 104, unit)
            readonly property real centerW: Math.min(660, unit * 7)
            readonly property real wallH: Math.min(root.height * .38, 320)

            Row {
                anchors.centerIn: parent
                spacing: wallsArea.gap
                Repeater {
                    id: walls
                    model: 5
                    delegate: Item {
                        id: slot
                        required property int index
                        readonly property bool isC: index === 2
                        width: isC ? wallsArea.centerW : wallsArea.sideW
                        height: wallsArea.wallH
                        property real off: 0
                        property real kop: 1

                        function kick(d) {
                            if (isC) sheenAnim.restart()
                            if (d === 0) return
                            offAnim.from = d * 46
                            kickAnim.restart()
                        }
                        ParallelAnimation {
                            id: kickAnim
                            NumberAnimation { id: offAnim; target: slot; property: "off"; to: 0; duration: 340; easing.type: Easing.OutCubic }
                            NumberAnimation { target: slot; property: "kop"; from: .3; to: 1; duration: 340; easing.type: Easing.OutCubic }
                        }

                        Item {
                            id: card
                            width: parent.width; height: parent.height
                            x: slot.off
                            y: hov.hovered ? -4 : 0
                            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            opacity: (root.mode === "dial" ? .55 : (slot.isC ? 1 : .85)) * slot.kop
                            transform: Matrix4x4 {   // skewX(-12deg) about the centre
                                matrix: Qt.matrix4x4(1, -0.2126, 0, 0.2126 * card.height / 2,
                                                     0, 1, 0, 0,
                                                     0, 0, 1, 0,
                                                     0, 0, 0, 1)
                            }

                            RoundImage {
                                anchors.fill: parent
                                radius: slot.isC ? 16 : 12
                                decodeWidth: root.wallDecode
                                source: root.wallUrl(slot.index)
                                tag: "wall[" + slot.index + "]"
                                onLoadEvent: (who, what, src, ms, info) => root.imgEvt(who, what, src, ms, info)
                            }
                            Item {   // sheen sweep (centre only)
                                anchors.fill: parent; clip: true; visible: slot.isC
                                Rectangle {
                                    id: sheen
                                    width: parent.width * .4; height: parent.height
                                    x: -width * 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0;  color: Qt.rgba(1, 1, 1, 0) }
                                        GradientStop { position: .5; color: Qt.rgba(1, 1, 1, .45) }
                                        GradientStop { position: 1;  color: Qt.rgba(1, 1, 1, 0) }
                                    }
                                }
                                NumberAnimation {
                                    id: sheenAnim; target: sheen; property: "x"
                                    from: -sheen.width; to: card.width + sheen.width
                                    duration: 800; easing.type: Easing.OutQuad
                                }
                            }
                            Rectangle {   // focus outline on the centre wallpaper
                                visible: slot.isC && root.mode === "walls"
                                x: -5; y: -5
                                width: card.width + 10; height: card.height + 10
                                radius: 21; color: "transparent"
                                border.width: 3; border.color: root.ink
                            }
                            HoverHandler {
                                id: hov
                                onHoveredChanged: if (hovered) root.dbg("INPUT", "hover wall[" + slot.index + "]")
                            }
                            TapHandler {
                                onTapped: (pt, btn) => {
                                    root.dbg("INPUT", "click wall[" + slot.index + "] btn=" + root.btnName(btn)
                                             + " @" + Math.round(pt.position.x) + "," + Math.round(pt.position.y))
                                    root.wallClicked(slot.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
  }
}
