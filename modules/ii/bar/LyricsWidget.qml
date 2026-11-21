import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris

Rectangle {
    id: root

    // --- Konfigurasi Tema & Ukuran ---
    property color bgColor: "#101010"
    property color surfaceColor: "#292d42"
    property color borderColor: Qt.rgba(0.51, 0.67, 1.0, 0.24)
    property color accentColor: "#82aaff"
    property color lyricActiveColor: "#c8d3f5"
    property color lyricDimColor: Qt.rgba(0.78, 0.83, 0.96, 0.36)
    property color subTextColor: Qt.rgba(0.78, 0.83, 0.96, 0.65)
    property real maxCompactLyricWidth: 360

    readonly property real expandedWidth: 424
    readonly property real expandedHeight: 348

    // --- Mode Tampilan Lirik (2 Tombol Hover: Translate & Romaji) ---
    property bool showTranslate: true
    property bool showRomajiSubline: true

    // --- State Internal Lirik, Romanisasi & Terjemahan ---
    property string currentRawLyric: ""
    property string displayedRawText: ""
    property string displayedRomanized: ""
    property string displayedTranslation: ""
    property bool useSlotA: true
    property real karaokeProgress: 0.0
    property bool isLoadingLyrics: false
    property bool sessionActive: false
    property bool isFallbackLine: true
    property var lineCache: ({})

    // --- Antrean Terjemahan & Romanisasi (Prioritas Baris Aktif, Anti Rate-Limit) ---
    property var translationQueue: []
    property var queuedSet: ({})
    property bool isTranslatingNow: false
    property string activeQueueTrackId: ""

    // --- State Sinkronisasi Tempo & Clock Audio ---
    property real anchorPlayerPos: 0.0
    property double anchorWallMs: 0.0
    property double posQueryStartMs: 0.0
    property real lastReportedPos: -1.0
    property int movingPosTicks: 0
    readonly property bool hasReliablePlayerClock: movingPosTicks >= 1 && lastReportedPos >= 0.0

    property double lineStartWallMs: 0.0
    property double pauseStartedWallMs: 0.0
    property real activeLineStartSec: 0.0
    property real activeLineDurationSec: 3.0
    property var activeWordTimings: []
    property double lastFallbackLineMs: 0.0
    property int lastFallbackCharCount: 0
    property real adaptiveMsPerChar: 72.0

    // --- State Expanded (Hover Bouncy Floating Popup) ---
    property bool isExpanded: false
    property real expandProgress: isExpanded ? 1.0 : 0.0
    property real bounceScale: 1.0
    property int activeLyricIndex: -1
    property bool hasSyncedLrc: false
    property int lrcSourcePriority: 0
    property real systemVolume: 0.7
    property bool systemMuted: false
    property rect cachedAnchorRect: Qt.rect(0, 0, 1, 1)

    function updatePopupAnchor() {
        const win = root.QsWindow.window
        if (!win || !win.contentItem)
            return
        const pos = root.mapToItem(win.contentItem, 0, 0)
        const maxX = Math.max(8, win.width - expandedPopup.implicitWidth - 8)
        const centeredX = Math.max(8, Math.min(maxX, pos.x + (root.width - expandedPopup.implicitWidth) * 0.5))
        cachedAnchorRect = Qt.rect(centeredX, pos.y, expandedPopup.implicitWidth, root.height)
    }

    Behavior on expandProgress {
        NumberAnimation {
            duration: 340
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: expandBounceAnim
        NumberAnimation {
            target: root
            property: "bounceScale"
            to: 1.035
            duration: 160
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "bounceScale"
            to: 1.0
            duration: 340
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
    }

    SequentialAnimation {
        id: collapseBounceAnim
        NumberAnimation {
            target: root
            property: "bounceScale"
            to: 0.96
            duration: 120
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "bounceScale"
            to: 1.0
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    onIsExpandedChanged: {
        expandBounceAnim.stop()
        collapseBounceAnim.stop()
        if (isExpanded) {
            updatePopupAnchor()
            expandBounceAnim.start()
            if (root.activeLyricIndex >= 0) {
                fullLyricsView.positionViewAtIndex(root.activeLyricIndex, ListView.Center)
            }
        } else {
            collapseBounceAnim.start()
        }
    }

    // Ambil MPRIS player yang sedang aktif (prioritas Playing)
    readonly property var activePlayer: {
        const players = Mpris.players.values
        if (!players || players.length === 0)
            return null
        let pausedPlayer = null
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing)
                return players[i]
            if (!pausedPlayer && players[i].playbackState === MprisPlaybackState.Paused)
                pausedPlayer = players[i]
        }
        return pausedPlayer ? pausedPlayer : players[0]
    }

    readonly property string activePlayerName: {
        if (!activePlayer)
            return ""
        if (activePlayer.dbusName && activePlayer.dbusName.indexOf("org.mpris.MediaPlayer2.") === 0)
            return activePlayer.dbusName.replace("org.mpris.MediaPlayer2.", "")
        return activePlayer.identity ? activePlayer.identity.toLowerCase() : ""
    }

    readonly property bool isPlaying: activePlayer ? activePlayer.playbackState === MprisPlaybackState.Playing : false
    readonly property bool hasActivePlayer: activePlayer !== null && activePlayer.playbackState !== MprisPlaybackState.Stopped
    readonly property string albumArtUrl: activePlayer ? (activePlayer.trackArtUrl ?? "") : ""
    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle ?? "") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist ?? "") : ""
    readonly property string trackAlbum: activePlayer ? (activePlayer.trackAlbum ?? "") : ""
    readonly property string currentTrackId: activePlayer ? (trackTitle + "|" + trackArtist) : ""

    readonly property bool isIslandVisible: true

    readonly property real currentVolume: {
        if (activePlayer && activePlayer.volumeSupported)
            return Math.max(0.0, Math.min(1.0, activePlayer.volume))
        return systemMuted ? 0.0 : systemVolume
    }

    readonly property var activeSlotItem: useSlotA ? slotALoader.item : slotBLoader.item
    readonly property real currentTextWidth: activeSlotItem ? activeSlotItem.implicitWidth : 0
    readonly property int currentTierCount: activeSlotItem ? activeSlotItem.tierCount : 1

    readonly property real compactTargetWidth: isIslandVisible
        ? Math.max(150, (currentTierCount >= 3 ? 30 : 26) + currentTextWidth + 36 + 34)
        : 36
    readonly property real compactTargetHeight: {
        if (!isIslandVisible)
            return 36
        if (currentTierCount >= 3)
            return 42
        if (currentTierCount === 2)
            return 38
        return 34
    }

    // --- Ukuran Kapsul di Top Bar (Tetap Kompak agar Tidak Terpotong Bar) ---
    visible: opacity > 0.01
    opacity: isIslandVisible ? 1.0 : 0.0
    transformOrigin: Item.Top
    scale: isIslandVisible ? bounceScale : 0.86

    implicitWidth: compactTargetWidth
    implicitHeight: compactTargetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    radius: 12
    color: bgColor
    border.width: 1
    border.color: borderColor
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 340
            easing.type: Easing.OutBack
            easing.overshoot: 0.85
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 0.85
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        enabled: !root.isIslandVisible
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutBack
        }
    }

    // --- Sinkronisasi Jam Audio Real-Time (Latency-Compensated playerctl + MPRIS) ---
    function queryPlayerctlPosition() {
        if (!playerctlPosProc.running) {
            posQueryStartMs = Date.now()
            playerctlPosProc.running = true
        }
    }

    function applyReportedPosition(pos, forceSnap, sampleWallMs) {
        if (pos === undefined || pos === null || isNaN(pos) || pos < 0)
            return

        const refMs = sampleWallMs > 0 ? sampleWallMs : Date.now()

        if (lastReportedPos >= 0 && Math.abs(pos - lastReportedPos) > 0.015) {
            movingPosTicks = Math.min(10, movingPosTicks + 1)
        } else if (pos <= 0.01 && lastReportedPos > 0.5) {
            movingPosTicks = 0
        }
        lastReportedPos = pos

        const currentLive = getRawLivePositionSec()
        const delta = pos - currentLive

        if (forceSnap || movingPosTicks <= 1 || Math.abs(delta) > 0.35) {
            anchorPlayerPos = pos
            anchorWallMs = refMs
        } else if (Math.abs(delta) > 0.03) {
            anchorPlayerPos = currentLive + (delta * 0.35)
            anchorWallMs = refMs
        }
    }

    function syncClockAnchor(forceSnap) {
        if (forceSnap && activePlayer && activePlayer.position >= 0 && lastReportedPos < 0) {
            applyReportedPosition(activePlayer.position, true, Date.now())
        }
        queryPlayerctlPosition()
    }

    function getRawLivePositionSec() {
        if (!activePlayer)
            return anchorPlayerPos
        if (!isPlaying)
            return anchorPlayerPos
        const rate = activePlayer.rate > 0 ? activePlayer.rate : 1.0
        const elapsedSec = Math.max(0.0, (Date.now() - anchorWallMs) / 1000.0)
        return anchorPlayerPos + (elapsedSec * rate)
    }

    function getCalibratedPositionSec() {
        return Math.max(0.0, getRawLivePositionSec())
    }

    Process {
        id: playerctlPosProc
        command: root.activePlayerName !== ""
            ? ["playerctl", "-p", root.activePlayerName, "position"]
            : ["playerctl", "position"]
        stdout: SplitParser {
            onRead: data => {
                const val = parseFloat(data.trim())
                if (!isNaN(val) && val >= 0) {
                    const nowMs = Date.now()
                    const midWallMs = root.posQueryStartMs > 0
                        ? (root.posQueryStartMs + nowMs) * 0.5
                        : nowMs
                    root.applyReportedPosition(val, false, midWallMs)
                    root.updateKaraokeFrame()
                }
            }
        }
    }

    Timer {
        id: posPollTimer
        interval: root.movingPosTicks < 2 ? 150 : 250
        repeat: true
        running: root.isPlaying && root.isIslandVisible
        onTriggered: root.queryPlayerctlPosition()
    }

    // --- Perhitungan Kurva Karaoke Relatif (0.0s -> Durasi Baris) ---
    function buildRelativeWordTimings(text, totalDurationSec) {
        if (!text || text.length === 0)
            return []

        const vocalSpan = Math.max(0.35, totalDurationSec)

        const weights = []
        let totalWeight = 0
        for (let i = 0; i < text.length; i++) {
            const ch = text[i]
            let w = 1.0
            if (ch === " ")
                w = 0.42
            else if (",;、，".indexOf(ch) !== -1)
                w = 1.55
            else if (".!?。！？—–".indexOf(ch) !== -1)
                w = 1.75
            weights.push(w)
            totalWeight += w
        }

        const result = []
        let cursorRel = 0.0
        for (let j = 0; j < text.length; j++) {
            const stepDur = (weights[j] / totalWeight) * vocalSpan
            result.push({
                relStart: cursorRel,
                relEnd: cursorRel + stepDur,
                ratioStart: j / text.length,
                ratioEnd: (j + 1) / text.length
            })
            cursorRel += stepDur
        }
        return result
    }

    function computeLineDurationSec(idx, startSec, textLength) {
        const estimatedVocalSec = Math.max(2.2, textLength * 0.145)
        if (idx + 1 < lyricModel.count) {
            const nextStart = lyricModel.get(idx + 1).timeSec
            const gap = nextStart - startSec
            if (gap > 0.25) {
                if (gap > 8.5)
                    return Math.min(gap - 0.35, Math.max(3.2, estimatedVocalSec))
                return Math.max(0.4, gap * 0.94)
            }
        }
        const trackLen = (activePlayer && activePlayer.length > startSec) ? activePlayer.length : (startSec + 10.0)
        return Math.min(trackLen - startSec, estimatedVocalSec)
    }

    function activateSyncedIndex(idx, syncFromPlayerClock) {
        if (idx < 0 || idx >= lyricModel.count)
            return

        const item = lyricModel.get(idx)
        const cached = root.lineCache[item.rawText]
        const rawText = item.rawText
        const instantRom = instantLocalRomanize(rawText)
        const romText = (cached && cached.romanizedText !== "")
            ? cached.romanizedText
            : (item.romanizedText !== "" ? item.romanizedText : instantRom)
        const transText = (cached && cached.translatedText !== "")
            ? cached.translatedText
            : item.translatedText
        const measureLen = Math.max(rawText.length, romText.length)

        const baseStart = item.timeSec >= 0 ? item.timeSec : 0.0
        const durSec = (item.endSec > baseStart && (item.endSec - baseStart) <= 8.5)
            ? Math.max(0.4, (item.endSec - baseStart) * 0.94)
            : (item.timeSec >= 0
                ? computeLineDurationSec(idx, item.timeSec, measureLen)
                : Math.max(1.4, (measureLen * root.adaptiveMsPerChar) / 1000.0))

        let parsedWords = []
        if (item.wordTimingsJson && item.wordTimingsJson !== "") {
            try {
                parsedWords = JSON.parse(item.wordTimingsJson)
            } catch (e) {
                parsedWords = []
            }
        }
        if (!parsedWords || parsedWords.length === 0) {
            parsedWords = buildRelativeWordTimings(rawText, durSec)
        }

        const now = Date.now()
        const calPos = getCalibratedPositionSec()
        let initialElapsedSec = 0.0
        if (syncFromPlayerClock && root.hasReliablePlayerClock && item.timeSec >= 0 && Math.abs(calPos - item.timeSec) < 4.0) {
            initialElapsedSec = Math.max(0.0, calPos - item.timeSec)
        }

        root.activeLyricIndex = idx
        root.activeLineStartSec = baseStart
        root.activeLineDurationSec = Math.max(0.4, durSec)
        root.activeWordTimings = parsedWords
        root.lineStartWallMs = now - (initialElapsedSec * 1000.0)
        root.pauseStartedWallMs = root.isPlaying ? 0.0 : now
        root.currentRawLyric = rawText
        root.isLoadingLyrics = false
        root.sessionActive = true

        transitionToText(rawText, romText, transText, false)
        updateKaraokeFrame()

        if (!cached || cached.translatedText === "") {
            enqueueTranslationLines([rawText], true)
        }
    }

    function getCurrentLineElapsedSec() {
        const now = root.isPlaying ? Date.now() : (root.pauseStartedWallMs > 0 ? root.pauseStartedWallMs : Date.now())
        const rate = (activePlayer && activePlayer.rate > 0) ? activePlayer.rate : 1.0
        const wallElapsed = Math.max(0.0, ((now - root.lineStartWallMs) / 1000.0) * rate)

        if (root.hasReliablePlayerClock && root.hasSyncedLrc && root.activeLineStartSec >= 0) {
            const calPos = getCalibratedPositionSec()
            const playerElapsed = calPos - root.activeLineStartSec
            if (playerElapsed >= -0.25 && playerElapsed <= root.activeLineDurationSec + 1.0) {
                return Math.max(0.0, playerElapsed)
            }
        }
        return wallElapsed
    }

    function evaluateKaraokeProgress(elapsedSec) {
        const words = root.activeWordTimings
        if (words && words.length > 0) {
            if (elapsedSec <= words[0].relStart)
                return 0.0
            const last = words[words.length - 1]
            if (elapsedSec >= last.relEnd)
                return 1.0

            for (let i = 0; i < words.length; i++) {
                const w = words[i]
                if (elapsedSec >= w.relStart && elapsedSec <= w.relEnd) {
                    const dur = Math.max(0.01, w.relEnd - w.relStart)
                    const localT = (elapsedSec - w.relStart) / dur
                    return w.ratioStart + ((w.ratioEnd - w.ratioStart) * localT)
                }
                if (i + 1 < words.length && elapsedSec > w.relEnd && elapsedSec < words[i + 1].relStart) {
                    return w.ratioEnd
                }
            }
        }

        const span = Math.max(0.4, root.activeLineDurationSec)
        return Math.max(0.0, Math.min(1.0, elapsedSec / span))
    }

    function updateKaraokeFrame() {
        if (root.hasReliablePlayerClock && root.hasSyncedLrc && lyricModel.count > 0) {
            const calPos = getCalibratedPositionSec()
            if (calPos >= 0.0) {
                let targetIdx = -1
                const lookupPos = calPos + 0.04
                for (let i = 0; i < lyricModel.count; i++) {
                    if (lyricModel.get(i).timeSec <= lookupPos)
                        targetIdx = i
                    else
                        break
                }
                if (targetIdx >= 0 && targetIdx !== root.activeLyricIndex) {
                    activateSyncedIndex(targetIdx, true)
                    return
                }
            }
        }

        if (root.isFallbackLine) {
            root.karaokeProgress = 1.0
            return
        }

        const elapsed = getCurrentLineElapsedSec()
        root.karaokeProgress = evaluateKaraokeProgress(elapsed)
    }

    Timer {
        id: karaokeTicker
        interval: 16
        repeat: true
        running: root.isPlaying && root.isIslandVisible && !root.isFallbackLine
        onTriggered: root.updateKaraokeFrame()
    }

    onIsPlayingChanged: {
        const now = Date.now()
        if (isPlaying) {
            if (pauseStartedWallMs > 0) {
                lineStartWallMs += (now - pauseStartedWallMs)
                pauseStartedWallMs = 0
            }
            syncClockAnchor(true)
            updateKaraokeFrame()
        } else {
            pauseStartedWallMs = now
            queryPlayerctlPosition()
        }
    }

    Connections {
        target: root.activePlayer
        function onPositionChanged() {
            if (root.activePlayer && root.activePlayer.position >= 0) {
                root.applyReportedPosition(root.activePlayer.position, true, Date.now())
            }
            root.queryPlayerctlPosition()
            root.updateKaraokeFrame()
        }
        function onRateChanged() {
            root.queryPlayerctlPosition()
        }
    }

    // --- Helper Romanisasi Lokal Instan (Hangeul Korea) & Normalisasi Alfabet ---
    function containsNonLatin(str) {
        if (!str)
            return false
        return /[^\u0000-\u024F\u1E00-\u1EFF\s\d.,!?'"()\-:;~♪…—–\/&+*#@%]/.test(str)
    }

    function toPlainLatinAlphabet(str) {
        if (!str)
            return ""
        let clean = str
        try {
            clean = clean.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        } catch (e) {}

        const map = {
            "ā": "a", "á": "a", "ǎ": "a", "à": "a",
            "ē": "e", "é": "e", "ě": "e", "è": "e",
            "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
            "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
            "ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
            "ǖ": "u", "ǘ": "u", "ǚ": "u", "ǜ": "u", "ü": "u",
            "Ā": "A", "Á": "A", "Ǎ": "A", "À": "A",
            "Ē": "E", "É": "E", "Ě": "E", "È": "E",
            "Ī": "I", "Í": "I", "Ǐ": "I", "Ì": "I",
            "Ō": "O", "Ó": "O", "Ǒ": "O", "Ò": "O",
            "Ū": "U", "Ú": "U", "Ǔ": "U", "Ù": "U",
            "Ǖ": "U", "Ǘ": "U", "Ǚ": "U", "Ǜ": "U", "Ü": "U",
            "ń": "n", "ň": "n", "ǹ": "n"
        }
        return clean.replace(/[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜüĀÁǍÀĒÉĚÈĪÍǏÌŌÓǑÒŪÚǓÙǕǗǙǛÜńňǹ]/g, ch => map[ch] || ch)
    }

    function instantLocalRomanize(str) {
        if (!str || !containsNonLatin(str))
            return ""

        const initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
        const medials = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
        const finals = ["", "k", "k", "ks", "n", "nj", "nh", "t", "l", "lk", "lm", "lb", "ls", "lt", "lp", "lh", "m", "p", "ps", "t", "t", "ng", "t", "t", "k", "t", "p", "h"]

        let out = ""
        let convertedAny = false
        let prevWasHangul = false

        for (let i = 0; i < str.length; i++) {
            const code = str.charCodeAt(i)
            if (code >= 0xAC00 && code <= 0xD7A3) {
                const sIndex = code - 0xAC00
                const ini = Math.floor(sIndex / 588)
                const med = Math.floor((sIndex % 588) / 28)
                const fin = sIndex % 28
                if (prevWasHangul && ini === 11) {
                    out += "-"
                }
                out += initials[ini] + medials[med] + finals[fin]
                convertedAny = true
                prevWasHangul = true
            } else {
                prevWasHangul = false
                out += str[i]
            }
        }

        if (convertedAny && !containsNonLatin(out))
            return out.trim()
        return ""
    }

    function normalizeLyricMatchKey(str) {
        return (str || "")
            .toLowerCase()
            .replace(/[\u2018\u2019\u02BC]/g, "'")
            .replace(/[\u201C\u201D]/g, "\"")
            .replace(/[\u2026]/g, "...")
            .replace(/[\u200B-\u200D\uFEFF]/g, "")
            .replace(/\s+/g, " ")
            .trim()
    }

    function normalizeCompare(str) {
        return (str || "").toLowerCase().replace(/[^a-z0-9]/g, "")
    }

    // --- Sinkronisasi Hover antara Kapsul Top Bar & Floating Popup ---
    function updateHoverState() {
        if (rootHover.hovered || popupHover.hovered || volumeDragArea.pressed) {
            collapseTimer.stop()
            if (!root.isExpanded) {
                root.isExpanded = true
                root.refreshVolume()
            }
        } else {
            collapseTimer.restart()
        }
    }

    HoverHandler {
        id: rootHover
        onHoveredChanged: root.updateHoverState()
    }

    Timer {
        id: collapseTimer
        interval: 280
        onTriggered: {
            if (!rootHover.hovered && !popupHover.hovered && !volumeDragArea.pressed)
                root.isExpanded = false
        }
    }

    // --- Kontrol Volume (MPRIS atau PipeWire wpctl fallback) ---
    function setVolumeLevel(val) {
        const clamped = Math.max(0.0, Math.min(1.0, val))
        if (activePlayer && activePlayer.volumeSupported) {
            activePlayer.volume = clamped
        } else {
            systemVolume = clamped
            systemMuted = clamped <= 0.001
            wpctlSetProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", clamped.toFixed(2)]
            wpctlSetProc.running = true
        }
    }

    function toggleMute() {
        if (activePlayer && activePlayer.volumeSupported) {
            if (activePlayer.volume > 0.01) {
                systemVolume = activePlayer.volume
                activePlayer.volume = 0.0
            } else {
                activePlayer.volume = systemVolume > 0.05 ? systemVolume : 0.5
            }
        } else {
            wpctlMuteProc.running = true
        }
    }

    function refreshVolume() {
        if (!activePlayer || !activePlayer.volumeSupported)
            wpctlGetProc.running = true
    }

    Process {
        id: wpctlGetProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                const match = data.match(/Volume:\s*([0-9.]+)/)
                if (match)
                    root.systemVolume = Math.max(0.0, Math.min(1.0, parseFloat(match[1])))
                root.systemMuted = data.indexOf("MUTED") !== -1
            }
        }
    }

    Process {
        id: wpctlSetProc
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.70"]
    }

    Process {
        id: wpctlMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        onExited: (code, status) => root.refreshVolume()
    }

    // --- Model Seluruh Baris Lirik (3 Tier: rawText, romanizedText, translatedText) ---
    ListModel {
        id: lyricModel
    }

    // =========================================================================
    // ENGINE TERJEMAHAN & ROMANISASI (ANTREAN BERTAHAP + DUAL API FALLBACK)
    // =========================================================================
    Timer {
        id: queuePaceTimer
        interval: 85
        repeat: false
        onTriggered: root.processNextInTranslationQueue()
    }

    function enqueueTranslationLines(linesArray, highPriority) {
        if (!linesArray || linesArray.length === 0)
            return

        const trackSnapshot = root.currentTrackId
        if (root.activeQueueTrackId !== trackSnapshot) {
            root.activeQueueTrackId = trackSnapshot
            root.translationQueue = []
            root.queuedSet = ({})
            root.isTranslatingNow = false
        }

        for (let i = 0; i < linesArray.length; i++) {
            const line = (linesArray[i] || "").trim()
            if (line === "")
                continue

            const cached = root.lineCache[line]
            if (cached && cached.translatedText !== "")
                continue

            if (root.queuedSet[line]) {
                if (highPriority) {
                    const existingIdx = root.translationQueue.indexOf(line)
                    if (existingIdx > 0) {
                        root.translationQueue.splice(existingIdx, 1)
                        root.translationQueue.unshift(line)
                    }
                }
                continue
            }

            root.queuedSet[line] = true
            if (highPriority)
                root.translationQueue.unshift(line)
            else
                root.translationQueue.push(line)
        }

        if (!root.isTranslatingNow && root.translationQueue.length > 0) {
            processNextInTranslationQueue()
        }
    }

    function ensureCurrentAndModelTranslated() {
        if (root.currentRawLyric !== "" && !root.isFallbackLine) {
            enqueueTranslationLines([root.currentRawLyric], true)
        }
        const batch = []
        for (let i = 0; i < lyricModel.count; i++) {
            const item = lyricModel.get(i)
            if (item.rawText !== "" && (item.translatedText === "" || (containsNonLatin(item.rawText) && item.romanizedText === ""))) {
                batch.push(item.rawText)
            }
        }
        if (batch.length > 0) {
            enqueueTranslationLines(batch, false)
        }
    }

    function commitLineTranslationResult(origLine, romText, transText, trackSnapshot) {
        if (trackSnapshot !== "" && root.currentTrackId !== trackSnapshot)
            return

        const needRom = containsNonLatin(origLine)
        const fallbackRom = needRom ? instantLocalRomanize(origLine) : ""
        const finalRom = needRom ? (romText !== "" ? romText : fallbackRom) : ""

        const entry = {
            rawText: origLine,
            romanizedText: finalRom,
            translatedText: transText
        }
        root.lineCache[origLine] = entry

        for (let idx = 0; idx < lyricModel.count; idx++) {
            if (lyricModel.get(idx).rawText === origLine) {
                lyricModel.setProperty(idx, "romanizedText", finalRom)
                lyricModel.setProperty(idx, "translatedText", transText)
            }
        }

        if (root.currentRawLyric === origLine) {
            applyEntryToActiveSlot(entry)
        }
    }

    function processNextInTranslationQueue() {
        if (root.translationQueue.length === 0) {
            root.isTranslatingNow = false
            return
        }

        const trackSnapshot = root.currentTrackId
        const line = root.translationQueue.shift()
        delete root.queuedSet[line]

        const cached = root.lineCache[line]
        if (cached && cached.translatedText !== "") {
            commitLineTranslationResult(line, cached.romanizedText, cached.translatedText, trackSnapshot)
            queuePaceTimer.start()
            return
        }

        root.isTranslatingNow = true
        fetchSingleLineGoogleTranslate(line, trackSnapshot, function(success, romText, transText) {
            if (success && transText !== "") {
                commitLineTranslationResult(line, romText, transText, trackSnapshot)
                root.isTranslatingNow = false
                queuePaceTimer.start()
            } else {
                fetchSingleLineMyMemory(line, trackSnapshot, function(mmTrans) {
                    commitLineTranslationResult(line, romText, mmTrans, trackSnapshot)
                    root.isTranslatingNow = false
                    queuePaceTimer.start()
                })
            }
        })
    }

    function fetchSingleLineGoogleTranslate(line, trackSnapshot, callback) {
        const xhr = new XMLHttpRequest()
        const url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=id&dt=t&dt=rm&q=" + encodeURIComponent(line)

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (trackSnapshot !== "" && root.currentTrackId !== trackSnapshot)
                return

            if (xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText)
                    const detectedLang = (res && res[2]) ? String(res[2]).toLowerCase() : ""
                    let translated = ""
                    let romanized = ""

                    if (res && Array.isArray(res[0])) {
                        for (let i = 0; i < res[0].length; i++) {
                            const chunk = res[0][i]
                            if (chunk && typeof chunk[0] === "string")
                                translated += chunk[0]
                            if (chunk && typeof chunk[3] === "string")
                                romanized += chunk[3]
                        }
                    }

                    const needRom = containsNonLatin(line)
                    const plainRom = (needRom && romanized.trim() !== "") ? toPlainLatinAlphabet(romanized.trim()) : ""
                    const finalRom = (plainRom !== "" && plainRom.toLowerCase() !== line.toLowerCase()) ? plainRom : ""

                    const cleanTrans = translated.trim()
                    const isSameIndo = detectedLang === "id" && normalizeCompare(cleanTrans) === normalizeCompare(line)
                    const finalTrans = (!isSameIndo && cleanTrans !== "") ? cleanTrans : ""

                    callback(true, finalRom, finalTrans)
                    return
                } catch (e) {}
            }
            callback(false, "", "")
        }

        xhr.open("GET", url)
        xhr.send()
    }

    function fetchSingleLineMyMemory(line, trackSnapshot, callback) {
        const xhr = new XMLHttpRequest()
        const langPair = containsNonLatin(line) ? "ko|id" : "en|id"
        const url = "https://api.mymemory.translated.net/get?q=" + encodeURIComponent(line) + "&langpair=" + langPair

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (trackSnapshot !== "" && root.currentTrackId !== trackSnapshot)
                return

            if (xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText)
                    const trans = res && res.responseData ? String(res.responseData.translatedText || "").trim() : ""
                    if (trans !== "" && trans.toUpperCase().indexOf("MYMEMORY WARNING") === -1) {
                        callback(trans)
                        return
                    }
                } catch (e) {}
            }
            callback("")
        }

        xhr.open("GET", url)
        xhr.send()
    }

    function applyEntryToActiveSlot(entry) {
        root.displayedRawText = entry.rawText
        root.displayedRomanized = entry.romanizedText
        root.displayedTranslation = entry.translatedText
        const activeSlot = root.useSlotA ? slotALoader.item : slotBLoader.item
        if (activeSlot) {
            activeSlot.rawText = entry.rawText
            activeSlot.romanizedText = entry.romanizedText
            activeSlot.translatedText = entry.translatedText
        }
    }

    // =========================================================================
    // SUMBER EKSTERNAL LIRIK (1. NetEase YRC/LRC, 2. LRCLIB ELRC/LRC)
    // =========================================================================
    function fetchExternalLyrics(title, artist, album, durationSec) {
        if (!title)
            return

        const trackSnapshot = root.currentTrackId
        root.lrcSourcePriority = 0

        fetchNetEaseLyrics(title, artist, durationSec, trackSnapshot)
        fetchLrclibLyrics(title, artist, album, durationSec, trackSnapshot)
    }

    function fetchNetEaseLyrics(title, artist, durationSec, trackSnapshot) {
        const xhr = new XMLHttpRequest()
        const query = encodeURIComponent((artist ? artist + " " : "") + title)
        const searchUrl = "https://music.163.com/api/search/get/web?s=" + query + "&type=1&limit=5"

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.currentTrackId !== trackSnapshot)
                return
            if (xhr.status !== 200)
                return

            try {
                const res = JSON.parse(xhr.responseText)
                const songs = res && res.result ? res.result.songs : null
                if (!Array.isArray(songs) || songs.length === 0)
                    return

                let chosenId = songs[0].id
                if (durationSec > 0) {
                    let bestDiff = 999999
                    for (let i = 0; i < songs.length; i++) {
                        const songDurSec = (songs[i].duration || 0) / 1000.0
                        if (songDurSec > 0) {
                            const diff = Math.abs(songDurSec - durationSec)
                            if (diff < bestDiff) {
                                bestDiff = diff
                                chosenId = songs[i].id
                            }
                        }
                    }
                }

                fetchNetEaseSongLyricById(chosenId, trackSnapshot)
            } catch (e) {}
        }

        xhr.open("GET", searchUrl)
        xhr.send()
    }

    function fetchNetEaseSongLyricById(songId, trackSnapshot) {
        if (!songId)
            return

        const xhr = new XMLHttpRequest()
        const lyricUrl = "https://music.163.com/api/song/lyric?id=" + songId + "&lv=1&kv=1&tv=-1&yv=1"

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.currentTrackId !== trackSnapshot)
                return
            if (xhr.status !== 200)
                return

            try {
                const data = JSON.parse(xhr.responseText)
                if (data && data.yrc && data.yrc.lyric) {
                    const yrcParsed = parseNetEaseYrc(data.yrc.lyric)
                    if (yrcParsed.length > 0 && root.lrcSourcePriority < 2) {
                        applyParsedLyricsToModel(yrcParsed, 2, trackSnapshot)
                        return
                    }
                }
                if (data && data.lrc && data.lrc.lyric && root.lrcSourcePriority < 1) {
                    const lrcParsed = parseLrcToEntries(data.lrc.lyric)
                    if (lrcParsed.length > 0) {
                        applyParsedLyricsToModel(lrcParsed, 1, trackSnapshot)
                    }
                }
            } catch (e) {}
        }

        xhr.open("GET", lyricUrl)
        xhr.send()
    }

    function parseNetEaseYrc(yrcText) {
        const lines = yrcText.split(/\r?\n/)
        const parsed = []
        const lineHeaderRegex = /^\[(\d+),(\d+)\](.*)$/
        const wordRegex = /\((\d+),(\d+),\d+\)([^(]*)/g

        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i].trim()
            const headerMatch = lineHeaderRegex.exec(raw)
            if (!headerMatch)
                continue

            const lineStartSec = parseInt(headerMatch[1], 10) / 1000.0
            const lineDurSec = parseInt(headerMatch[2], 10) / 1000.0
            const body = headerMatch[3]

            let fullLine = ""
            const rawWords = []
            let wMatch
            wordRegex.lastIndex = 0
            while ((wMatch = wordRegex.exec(body)) !== null) {
                const wStart = parseInt(wMatch[1], 10) / 1000.0
                const wDur = parseInt(wMatch[2], 10) / 1000.0
                const token = wMatch[3]
                if (token !== "") {
                    const relS = Math.max(0.0, wStart - lineStartSec)
                    rawWords.push({
                        relStart: relS,
                        relEnd: relS + Math.max(0.03, wDur),
                        charStart: fullLine.length,
                        charEnd: fullLine.length + token.length
                    })
                    fullLine += token
                }
            }

            const cleanText = fullLine.trim()
            if (cleanText !== "" && rawWords.length > 0) {
                const totalLen = Math.max(1, fullLine.length)
                const normalizedWords = rawWords.map(w => ({
                    relStart: w.relStart,
                    relEnd: w.relEnd,
                    ratioStart: w.charStart / totalLen,
                    ratioEnd: w.charEnd / totalLen
                }))
                parsed.push({
                    timeSec: lineStartSec,
                    endSec: lineStartSec + Math.max(0.4, lineDurSec),
                    rawText: cleanText,
                    romanizedText: instantLocalRomanize(cleanText),
                    translatedText: "",
                    wordTimingsJson: JSON.stringify(normalizedWords)
                })
            }
        }
        return parsed
    }

    function fetchLrclibLyrics(title, artist, album, durationSec, trackSnapshot) {
        const xhr = new XMLHttpRequest()
        let url = "https://lrclib.net/api/get?track_name=" + encodeURIComponent(title)
        if (artist)
            url += "&artist_name=" + encodeURIComponent(artist)
        if (album)
            url += "&album_name=" + encodeURIComponent(album)
        if (durationSec > 0)
            url += "&duration=" + Math.round(durationSec)

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.currentTrackId !== trackSnapshot)
                return

            if (xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText)
                    if (res && res.syncedLyrics) {
                        const entries = parseLrcToEntries(res.syncedLyrics)
                        const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                        const prio = hasWords ? 2 : 1
                        if (entries.length > 0 && root.lrcSourcePriority < prio) {
                            applyParsedLyricsToModel(entries, prio, trackSnapshot)
                        }
                        return
                    }
                } catch (e) {}
            }
            searchLrclibLyrics(title, artist, trackSnapshot)
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function searchLrclibLyrics(title, artist, trackSnapshot) {
        const xhr = new XMLHttpRequest()
        const q = encodeURIComponent((artist ? artist + " " : "") + title)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.currentTrackId !== trackSnapshot)
                return
            if (xhr.status === 200) {
                try {
                    const list = JSON.parse(xhr.responseText)
                    if (Array.isArray(list)) {
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].syncedLyrics) {
                                const entries = parseLrcToEntries(list[i].syncedLyrics)
                                const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                                const prio = hasWords ? 2 : 1
                                if (entries.length > 0 && root.lrcSourcePriority < prio) {
                                    applyParsedLyricsToModel(entries, prio, trackSnapshot)
                                }
                                return
                            }
                        }
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "https://lrclib.net/api/search?q=" + q)
        xhr.send()
    }

    function parseTimestampToken(minStr, secStr, msStr) {
        const min = parseInt(minStr, 10)
        const sec = parseInt(secStr, 10)
        const msPart = msStr ? msStr.padEnd(3, "0").slice(0, 3) : "000"
        return min * 60 + sec + parseInt(msPart, 10) / 1000.0
    }

    function parseLrcToEntries(lrcText) {
        const lines = lrcText.split(/\r?\n/)
        const parsed = []
        const lineTimeRegex = /\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]/g
        const enhancedWordRegex = /<(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?>([^<]*)/g

        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            let match
            const timestamps = []
            lineTimeRegex.lastIndex = 0
            while ((match = lineTimeRegex.exec(raw)) !== null) {
                timestamps.push(parseTimestampToken(match[1], match[2], match[3]))
            }

            const bodyWithoutLineTags = raw.replace(lineTimeRegex, "").trim()
            if (timestamps.length === 0 || bodyWithoutLineTags === "")
                continue

            let cleanText = bodyWithoutLineTags
            let wordTimingsJson = ""
            if (bodyWithoutLineTags.indexOf("<") !== -1) {
                const rawWords = []
                let assembled = ""
                let wMatch
                enhancedWordRegex.lastIndex = 0
                while ((wMatch = enhancedWordRegex.exec(bodyWithoutLineTags)) !== null) {
                    const wTime = parseTimestampToken(wMatch[1], wMatch[2], wMatch[3])
                    const token = wMatch[4]
                    if (token !== "") {
                        rawWords.push({
                            startSec: wTime,
                            charStart: assembled.length,
                            charEnd: assembled.length + token.length
                        })
                        assembled += token
                    }
                }
                if (rawWords.length > 0 && assembled.trim() !== "") {
                    cleanText = assembled.trim()
                    const totalLen = Math.max(1, assembled.length)
                    const baseLineT = timestamps[0]
                    const finalized = []
                    for (let w = 0; w < rawWords.length; w++) {
                        const relS = Math.max(0.0, rawWords[w].startSec - baseLineT)
                        const nextRelS = (w + 1 < rawWords.length)
                            ? Math.max(relS + 0.04, rawWords[w + 1].startSec - baseLineT)
                            : (relS + 0.45)
                        finalized.push({
                            relStart: relS,
                            relEnd: nextRelS,
                            ratioStart: rawWords[w].charStart / totalLen,
                            ratioEnd: rawWords[w].charEnd / totalLen
                        })
                    }
                    wordTimingsJson = JSON.stringify(finalized)
                }
            }

            const instantRom = instantLocalRomanize(cleanText)
            for (let t = 0; t < timestamps.length; t++) {
                parsed.push({
                    timeSec: timestamps[t],
                    endSec: -1,
                    rawText: cleanText,
                    romanizedText: instantRom,
                    translatedText: "",
                    wordTimingsJson: wordTimingsJson
                })
            }
        }

        parsed.sort((a, b) => a.timeSec - b.timeSec)
        for (let k = 0; k < parsed.length; k++) {
            if (parsed[k].endSec < 0) {
                parsed[k].endSec = (k + 1 < parsed.length) ? parsed[k + 1].timeSec : -1
            }
        }
        return parsed
    }

    function applyParsedLyricsToModel(entries, priority, trackSnapshot) {
        if (!entries || entries.length === 0 || root.currentTrackId !== trackSnapshot)
            return

        root.lrcSourcePriority = priority
        lyricModel.clear()
        const linesToQueue = []
        for (let j = 0; j < entries.length; j++) {
            const entry = entries[j]
            const cached = root.lineCache[entry.rawText]
            if (cached) {
                if (cached.romanizedText !== "")
                    entry.romanizedText = cached.romanizedText
                entry.translatedText = cached.translatedText
            }
            lyricModel.append(entry)
            if (entry.translatedText === "") {
                linesToQueue.push(entry.rawText)
            }
        }
        root.hasSyncedLrc = true
        syncClockAnchor(true)
        syncIndexWithCurrentState()

        if (linesToQueue.length > 0) {
            enqueueTranslationLines(linesToQueue, false)
        }
    }

    function findBestMatchingIndex(rawLine, calLivePos) {
        if (lyricModel.count === 0 || rawLine === "")
            return -1

        const targetNorm = normalizeLyricMatchKey(rawLine)
        let bestIdx = -1
        let minDiff = 999999

        for (let i = 0; i < lyricModel.count; i++) {
            const item = lyricModel.get(i)
            if (normalizeLyricMatchKey(item.rawText) === targetNorm) {
                if (root.hasReliablePlayerClock && calLivePos >= 0.0 && item.timeSec >= 0) {
                    const diff = Math.abs(item.timeSec - calLivePos)
                    if (diff < minDiff) {
                        minDiff = diff
                        bestIdx = i
                    }
                } else {
                    if (i >= root.activeLyricIndex)
                        return i
                    if (bestIdx === -1)
                        bestIdx = i
                }
            }
        }
        return bestIdx
    }

    function syncIndexWithCurrentState() {
        if (lyricModel.count === 0)
            return

        const calPos = getCalibratedPositionSec()

        if (root.hasReliablePlayerClock && calPos >= 0.0) {
            const lookupPos = calPos + 0.04
            let idx = 0
            for (let i = 0; i < lyricModel.count; i++) {
                if (lyricModel.get(i).timeSec <= lookupPos)
                    idx = i
                else
                    break
            }
            activateSyncedIndex(idx, true)
            return
        }

        if (root.currentRawLyric !== "") {
            const matchedIdx = findBestMatchingIndex(root.currentRawLyric, calPos)
            if (matchedIdx !== -1) {
                activateSyncedIndex(matchedIdx, false)
            }
        }
    }

    // --- Penjaga Sesi agar Tidak Kedip saat Transisi Lagu ---
    onHasActivePlayerChanged: {
        if (hasActivePlayer) {
            keepAliveTimer.stop()
            sessionActive = true
            syncClockAnchor(true)
            if (displayedRawText === "")
                showFallbackLine()
        } else {
            keepAliveTimer.restart()
        }
    }

    Timer {
        id: keepAliveTimer
        interval: 2500
        onTriggered: {
            if (!root.hasActivePlayer) {
                root.sessionActive = false
                root.currentRawLyric = ""
                root.displayedRawText = ""
                root.displayedRomanized = ""
                root.displayedTranslation = ""
                root.isLoadingLyrics = false
                root.isExpanded = false
                lyricModel.clear()
                root.activeLyricIndex = -1
                root.hasSyncedLrc = false
                root.lrcSourcePriority = 0
                root.movingPosTicks = 0
                root.lastReportedPos = -1.0
                root.translationQueue = []
                root.queuedSet = ({})
                root.isTranslatingNow = false
            }
        }
    }

    onCurrentTrackIdChanged: {
        if (currentTrackId !== "") {
            keepAliveTimer.stop()
            sessionActive = true
            currentRawLyric = ""
            isLoadingLyrics = true
            hasSyncedLrc = false
            lrcSourcePriority = 0
            activeLyricIndex = -1
            activeWordTimings = []
            lineCache = ({})
            translationQueue = []
            queuedSet = ({})
            isTranslatingNow = false
            activeQueueTrackId = currentTrackId
            movingPosTicks = 0
            lastReportedPos = -1.0
            anchorPlayerPos = 0.0
            anchorWallMs = Date.now()
            lastFallbackLineMs = 0
            lastFallbackCharCount = 0
            adaptiveMsPerChar = 72.0
            lyricModel.clear()
            syncClockAnchor(true)
            showFallbackLine()
            fetchExternalLyrics(trackTitle, trackArtist, trackAlbum, activePlayer ? activePlayer.length : 0)
        }
    }

    function showFallbackLine() {
        const fallback = trackTitle !== "" ? ("♪ " + trackTitle) : "Memuat lirik..."
        transitionToText(fallback, "", "", true)
    }

    function transitionToText(rawText, romText, transText, isFallback) {
        if (rawText === root.displayedRawText
            && romText === root.displayedRomanized
            && transText === root.displayedTranslation
            && isFallback === root.isFallbackLine)
            return

        root.displayedRawText = rawText
        root.displayedRomanized = romText
        root.displayedTranslation = transText
        root.isFallbackLine = isFallback

        const slotA = slotALoader.item
        const slotB = slotBLoader.item
        if (!slotA || !slotB)
            return

        root.useSlotA = !root.useSlotA
        const incoming = root.useSlotA ? slotA : slotB
        const outgoing = root.useSlotA ? slotB : slotA

        outgoing.active = false
        incoming.rawText = rawText
        incoming.romanizedText = romText
        incoming.translatedText = transText
        incoming.isFallback = isFallback
        incoming.active = true

        if (isFallback)
            root.karaokeProgress = 1.0
        else
            updateKaraokeFrame()
    }

    function updateLyricLine(newLine) {
        if (root.hasSyncedLrc && root.hasReliablePlayerClock) {
            return
        }

        if (newLine === "") {
            root.currentRawLyric = ""
            if (root.sessionActive || root.hasActivePlayer) {
                root.isLoadingLyrics = true
                root.showFallbackLine()
            }
            return
        }

        if (newLine === root.currentRawLyric && !root.isLoadingLyrics)
            return

        queryPlayerctlPosition()
        const calPos = getCalibratedPositionSec()

        if (root.hasSyncedLrc) {
            const matchedIdx = findBestMatchingIndex(newLine, calPos)
            if (matchedIdx !== -1) {
                if (matchedIdx !== root.activeLyricIndex || root.isLoadingLyrics) {
                    activateSyncedIndex(matchedIdx, false)
                }
                return
            }
        }

        const nowMs = Date.now()
        if (root.lastFallbackLineMs > 0 && root.lastFallbackCharCount > 0) {
            const elapsedMs = nowMs - root.lastFallbackLineMs
            if (elapsedMs > 600 && elapsedMs < 12000) {
                const measured = elapsedMs / root.lastFallbackCharCount
                root.adaptiveMsPerChar = Math.max(40.0, Math.min(160.0, (root.adaptiveMsPerChar * 0.6) + (measured * 0.4)))
            }
        }

        root.currentRawLyric = newLine
        root.isLoadingLyrics = false
        root.sessionActive = true

        const cached = root.lineCache[newLine]
        const instantRom = instantLocalRomanize(newLine)
        const initialRom = (cached && cached.romanizedText !== "") ? cached.romanizedText : instantRom
        const initialTrans = (cached && cached.translatedText !== "") ? cached.translatedText : ""
        const measureLen = Math.max(1, newLine.length, initialRom.length)
        const estDur = Math.min(9.5, Math.max(1.2, (measureLen * root.adaptiveMsPerChar) / 1000.0))

        root.lastFallbackLineMs = nowMs
        root.lastFallbackCharCount = measureLen
        root.lineStartWallMs = nowMs
        root.pauseStartedWallMs = root.isPlaying ? 0.0 : nowMs
        root.activeLineStartSec = 0.0
        root.activeLineDurationSec = estDur
        root.activeWordTimings = buildRelativeWordTimings(newLine, estDur)

        transitionToText(newLine, initialRom, initialTrans, false)

        if (!root.hasSyncedLrc) {
            if (lyricModel.count === 0 || lyricModel.get(lyricModel.count - 1).rawText !== newLine) {
                lyricModel.append({
                    timeSec: -1,
                    endSec: -1,
                    rawText: newLine,
                    romanizedText: initialRom,
                    translatedText: initialTrans,
                    wordTimingsJson: ""
                })
            }
            root.activeLyricIndex = lyricModel.count - 1
        }

        if (!cached || cached.translatedText === "") {
            enqueueTranslationLines([newLine], true)
        }
    }

    // --- Proses sptlrx ---
    Process {
        id: sptlrxProc
        command: ["sptlrx", "--player", "mpris", "pipe"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                root.updateLyricLine(data.trim())
            }
        }

        onExited: (exitCode, exitStatus) => {
            restartTimer.start()
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: sptlrxProc.running = true
    }

    Component.onCompleted: {
        refreshVolume()
        if (hasActivePlayer) {
            sessionActive = true
            isLoadingLyrics = true
            syncClockAnchor(true)
            showFallbackLine()
            fetchExternalLyrics(trackTitle, trackArtist, trackAlbum, activePlayer ? activePlayer.length : 0)
        }
    }

    // --- Template Komponen Baris Lirik Dinamis (Compact Pill) ---
    Component {
        id: karaokeLineComponent

        Item {
            id: lineItem
            property string rawText: ""
            property string romanizedText: ""
            property string translatedText: ""
            property bool active: false
            property bool isFallback: false
            property real progress: 0.0

            readonly property bool showSecondLine: root.showRomajiSubline && romanizedText !== "" && !isFallback
            readonly property bool showThirdLine: root.showTranslate && translatedText !== "" && !isFallback
            readonly property int tierCount: 1 + (showSecondLine ? 1 : 0) + (showThirdLine ? 1 : 0)

            readonly property real maxContentW: Math.max(
                origDimText.implicitWidth,
                showSecondLine ? romDimText.implicitWidth : 0,
                showThirdLine ? subLineText.implicitWidth : 0
            )

            implicitWidth: Math.min(maxContentW, root.maxCompactLyricWidth)
            implicitHeight: linesCol.implicitHeight
            clip: true

            opacity: active ? (isFallback && root.isLoadingLyrics ? pulseOpacity : 1.0) : 0.0
            y: 10

            property real pulseOpacity: 1.0

            SequentialAnimation on pulseOpacity {
                running: lineItem.active && lineItem.isFallback && root.isLoadingLyrics
                loops: Animation.Infinite
                NumberAnimation { to: 0.52; duration: 750; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutSine }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }

            NumberAnimation {
                id: slideAnim
                target: lineItem
                property: "y"
                duration: 300
                easing.type: Easing.OutCubic
            }

            onActiveChanged: {
                slideAnim.stop()
                if (active) {
                    y = 10
                    slideAnim.to = 0
                } else {
                    slideAnim.to = -10
                }
                slideAnim.start()
            }

            readonly property real panRatio: Math.max(0, Math.min(1, (progress - 0.15) / 0.75))
            readonly property real origOverflow: Math.max(0, origDimText.implicitWidth - root.maxCompactLyricWidth)
            readonly property real romOverflow: Math.max(0, romDimText.implicitWidth - root.maxCompactLyricWidth)

            Column {
                id: linesCol
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                // 1. Baris Pertama: Lirik Asli
                Item {
                    width: origDimText.implicitWidth
                    height: origDimText.implicitHeight
                    x: -lineItem.origOverflow * lineItem.panRatio

                    Text {
                        id: origDimText
                        text: lineItem.rawText
                        color: root.lyricDimColor
                        font.pixelSize: lineItem.tierCount >= 3 ? 11 : (lineItem.tierCount === 2 ? 12 : 13)
                        font.weight: Font.DemiBold
                    }

                    Item {
                        anchors.left: origDimText.left
                        anchors.top: origDimText.top
                        anchors.bottom: origDimText.bottom
                        width: origDimText.implicitWidth * lineItem.progress
                        clip: true

                        Text {
                            text: lineItem.rawText
                            color: root.lyricActiveColor
                            font.pixelSize: lineItem.tierCount >= 3 ? 11 : (lineItem.tierCount === 2 ? 12 : 13)
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // 2. Baris Kedua: Romaji (di bawah bahasa asli saat tombol Romaji aktif)
                Item {
                    visible: lineItem.showSecondLine
                    width: romDimText.implicitWidth
                    height: romDimText.implicitHeight
                    x: -lineItem.romOverflow * lineItem.panRatio

                    Text {
                        id: romDimText
                        text: lineItem.romanizedText
                        color: Qt.rgba(0.51, 0.67, 1.0, 0.35)
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }

                    Item {
                        anchors.left: romDimText.left
                        anchors.top: romDimText.top
                        anchors.bottom: romDimText.bottom
                        width: romDimText.implicitWidth * lineItem.progress
                        clip: true

                        Text {
                            text: lineItem.romanizedText
                            color: root.accentColor
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }
                }

                // 3. Baris Ketiga: Terjemahan Bahasa Indonesia (saat tombol Translate aktif)
                Text {
                    id: subLineText
                    visible: lineItem.showThirdLine
                    text: lineItem.translatedText
                    color: root.subTextColor
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.maxCompactLyricWidth)
                }
            }
        }
    }

    // =========================================================================
    // 1. TAMPILAN COMPACT PILL DI TOP BAR
    // =========================================================================
    Item {
        id: compactWrapper
        anchors.fill: parent
        opacity: Math.max(0.0, 1.0 - (root.expandProgress * 2.4))

        RowLayout {
            id: compactView
            anchors.centerIn: parent
            spacing: 8

            ClippingRectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 7
                color: Qt.darker(root.bgColor, 1.2)
                scale: root.isPlaying ? 1.0 : 0.9

                Behavior on scale {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }

                Image {
                    id: compactArt
                    anchors.fill: parent
                    source: root.albumArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    cache: true
                    opacity: (root.albumArtUrl !== "" && status !== Image.Error) ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation { duration: 250 }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: compactArt.opacity < 0.1
                    text: "󰎆"
                    color: root.accentColor
                    font.pixelSize: 12
                }
            }

            Item {
                Layout.preferredWidth: root.currentTextWidth
                Layout.preferredHeight: Math.max(
                    slotALoader.item ? slotALoader.item.implicitHeight : 18,
                    slotBLoader.item ? slotBLoader.item.implicitHeight : 18
                )

                Loader {
                    id: slotALoader
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: karaokeLineComponent

                    Binding {
                        target: slotALoader.item
                        property: "progress"
                        value: root.useSlotA ? root.karaokeProgress : 1.0
                        when: slotALoader.item !== null
                    }
                }

                Loader {
                    id: slotBLoader
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: karaokeLineComponent

                    Binding {
                        target: slotBLoader.item
                        property: "progress"
                        value: !root.useSlotA ? root.karaokeProgress : 1.0
                        when: slotBLoader.item !== null
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Repeater {
                    model: [
                        { minH: 4, maxH: 14, speed: 420 },
                        { minH: 5, maxH: 16, speed: 310 },
                        { minH: 4, maxH: 12, speed: 490 }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: 2.5
                        height: root.isPlaying ? modelData.maxH : modelData.minH
                        radius: 1.25
                        color: root.accentColor
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on height {
                            running: root.isPlaying && root.isIslandVisible && !root.isExpanded
                            loops: Animation.Infinite
                            NumberAnimation { to: modelData.maxH; duration: modelData.speed; easing.type: Easing.InOutSine }
                            NumberAnimation { to: modelData.minH; duration: modelData.speed; easing.type: Easing.InOutSine }
                        }

                        Behavior on height {
                            enabled: !root.isPlaying
                            NumberAnimation { duration: 200 }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.isExpanded
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: mouse => {
                if (!root.activePlayer)
                    return
                if (mouse.button === Qt.LeftButton)
                    root.activePlayer.togglePlaying()
                else if (mouse.button === Qt.MiddleButton)
                    root.activePlayer.next()
            }
        }
    }

    // =========================================================================
    // 2. FLOATING POPUP WINDOW (Z-INDEX PALING ATAS, BEBAS POTONGAN TOP BAR)
    // =========================================================================
    PopupWindow {
        id: expandedPopup
        visible: root.isExpanded || root.expandProgress > 0.01
        color: "transparent"
        implicitWidth: root.expandedWidth + 16
        implicitHeight: root.expandedHeight + 24

        anchor.window: root.QsWindow.window
        anchor.rect: root.cachedAnchorRect

        Item {
            id: popupHoverContainer
            anchors.fill: parent

            HoverHandler {
                id: popupHover
                onHoveredChanged: root.updateHoverState()
            }

            Rectangle {
                id: expandedCard
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: root.expandedWidth
                height: root.expandedHeight
                radius: 24
                color: Qt.lighter(root.bgColor, 1.18)
                border.width: 1
                border.color: root.accentColor
                clip: true

                opacity: Math.max(0.0, (root.expandProgress - 0.08) / 0.92)
                scale: (0.86 + (0.14 * root.expandProgress)) * root.bounceScale
                transformOrigin: Item.Top

                ColumnLayout {
                    width: root.expandedWidth - 28
                    height: root.expandedHeight - 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    spacing: 9

                    // --- Baris Atas: Album Cover, Judul/Artis, & Kontrol Prev/Play/Next ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ClippingRectangle {
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 50
                            radius: 12
                            color: root.surfaceColor
                            scale: root.isPlaying ? 1.0 : 0.94

                            Behavior on scale {
                                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                            }

                            Image {
                                id: expandedArt
                                anchors.fill: parent
                                source: root.albumArtUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                cache: true
                                opacity: (root.albumArtUrl !== "" && status !== Image.Error) ? 1.0 : 0.0
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: expandedArt.opacity < 0.1
                                text: "󰎆"
                                color: root.accentColor
                                font.pixelSize: 22
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.trackTitle !== "" ? root.trackTitle : "Tidak ada media"
                                color: root.lyricActiveColor
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.trackArtist !== "" ? root.trackArtist : "MPRIS Player"
                                color: root.subTextColor
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            spacing: 6
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                width: 30
                                height: 30
                                radius: 15
                                color: prevMouse.containsMouse ? root.surfaceColor : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒮"
                                    color: root.lyricActiveColor
                                    font.pixelSize: 15
                                }

                                MouseArea {
                                    id: prevMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.activePlayer) root.activePlayer.previous()
                                }
                            }

                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: playMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor
                                scale: playMouse.pressed ? 0.90 : 1.0

                                Behavior on scale {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.isPlaying ? "󰏤" : "󰐊"
                                    color: root.bgColor
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    id: playMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                                }
                            }

                            Rectangle {
                                width: 30
                                height: 30
                                radius: 15
                                color: nextMouse.containsMouse ? root.surfaceColor : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒭"
                                    color: root.lyricActiveColor
                                    font.pixelSize: 15
                                }

                                MouseArea {
                                    id: nextMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.activePlayer) root.activePlayer.next()
                                }
                            }
                        }
                    }

                    // --- Baris Tengah: Volume Slider ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.currentVolume <= 0.01 ? "󰖁" : (root.currentVolume < 0.5 ? "󰖀" : "󰕾")
                            color: root.subTextColor
                            font.pixelSize: 14

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleMute()
                            }
                        }

                        Item {
                            id: volumeTrack
                            Layout.fillWidth: true
                            height: 18

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 5
                                radius: 3
                                color: root.surfaceColor

                                Rectangle {
                                    width: parent.width * root.currentVolume
                                    height: parent.height
                                    radius: 3
                                    color: root.accentColor

                                    Behavior on width {
                                        enabled: !volumeDragArea.pressed
                                        NumberAnimation { duration: 120 }
                                    }
                                }
                            }

                            Rectangle {
                                id: volumeThumb
                                width: volumeDragArea.containsMouse || volumeDragArea.pressed ? 13 : 10
                                height: width
                                radius: width / 2
                                color: root.lyricActiveColor
                                border.width: 2
                                border.color: root.accentColor
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(volumeTrack.width - width, (volumeTrack.width * root.currentVolume) - (width / 2)))

                                Behavior on width {
                                    NumberAnimation { duration: 120 }
                                }
                            }

                            MouseArea {
                                id: volumeDragArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                function applyMouseVolume(mouseX) {
                                    const ratio = Math.max(0.0, Math.min(1.0, mouseX / width))
                                    root.setVolumeLevel(ratio)
                                }

                                onPressed: mouse => applyMouseVolume(mouse.x)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        applyMouseVolume(mouse.x)
                                }
                                onReleased: root.updateHoverState()
                                onWheel: wheel => {
                                    const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                                    root.setVolumeLevel(root.currentVolume + delta)
                                }
                            }
                        }

                        Text {
                            text: Math.round(root.currentVolume * 100) + "%"
                            color: root.subTextColor
                            font.pixelSize: 11
                            Layout.preferredWidth: 30
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // --- Baris 2 Tombol Mode Lirik: Nyalakan Translate & Aktifkan Romaji ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // 1. Tombol Nyalakan Translate
                        Rectangle {
                            id: btnTranslate
                            Layout.fillWidth: true
                            height: 28
                            radius: 14
                            scale: transBtnMouse.pressed ? 0.94 : 1.0
                            color: root.showTranslate
                                ? Qt.rgba(0.51, 0.67, 1.0, 0.22)
                                : (transBtnMouse.containsMouse ? root.surfaceColor : Qt.rgba(1, 1, 1, 0.04))
                            border.width: 1
                            border.color: root.showTranslate ? root.accentColor : Qt.rgba(1, 1, 1, 0.1)

                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "󰗊"
                                    color: root.showTranslate ? root.accentColor : root.subTextColor
                                    font.pixelSize: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Translate"
                                    color: root.showTranslate ? root.lyricActiveColor : root.subTextColor
                                    font.pixelSize: 12
                                    font.weight: root.showTranslate ? Font.DemiBold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: transBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.showTranslate = !root.showTranslate
                                    if (root.showTranslate)
                                        root.ensureCurrentAndModelTranslated()
                                }
                            }
                        }

                        // 2. Tombol Aktifkan Romaji (di bawah bahasa asli)
                        Rectangle {
                            id: btnRomajiSub
                            Layout.fillWidth: true
                            height: 28
                            radius: 14
                            scale: romSubBtnMouse.pressed ? 0.94 : 1.0
                            color: root.showRomajiSubline
                                ? Qt.rgba(0.51, 0.67, 1.0, 0.22)
                                : (romSubBtnMouse.containsMouse ? root.surfaceColor : Qt.rgba(1, 1, 1, 0.04))
                            border.width: 1
                            border.color: root.showRomajiSubline ? root.accentColor : Qt.rgba(1, 1, 1, 0.1)

                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "Aa"
                                    color: root.showRomajiSubline ? root.accentColor : root.subTextColor
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Romaji"
                                    color: root.showRomajiSubline ? root.lyricActiveColor : root.subTextColor
                                    font.pixelSize: 12
                                    font.weight: root.showRomajiSubline ? Font.DemiBold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: romSubBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.showRomajiSubline = !root.showRomajiSubline
                                    if (root.showRomajiSubline)
                                        root.ensureCurrentAndModelTranslated()
                                }
                            }
                        }
                    }

                    // Garis Pemisah Halus
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // --- Area Bawah: Daftar Lirik Sinkron (Bahasa Asli + Romaji + Translate) ---
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            visible: lyricModel.count === 0
                            text: root.displayedRawText !== "" ? root.displayedRawText : "Menunggu lirik..."
                            color: root.subTextColor
                            font.pixelSize: 13
                        }

                        ListView {
                            id: fullLyricsView
                            anchors.fill: parent
                            model: lyricModel
                            spacing: 12
                            clip: true
                            interactive: true
                            boundsBehavior: Flickable.StopAtBounds

                            currentIndex: root.activeLyricIndex
                            preferredHighlightBegin: height * 0.30
                            preferredHighlightEnd: height * 0.70
                            highlightRangeMode: ListView.StrictlyEnforceRange
                            highlightMoveDuration: 360
                            highlightMoveVelocity: -1

                            delegate: Item {
                                id: rowDelegate
                                required property int index
                                required property string rawText
                                required property string romanizedText
                                required property string translatedText
                                required property real timeSec

                                readonly property bool isCurrent: index === root.activeLyricIndex
                                readonly property bool showSecondRom: root.showRomajiSubline && romanizedText !== ""
                                readonly property bool showThirdTrans: root.showTranslate && translatedText !== ""

                                width: fullLyricsView.width
                                height: lyricRowColumn.implicitHeight + 4

                                layer.enabled: !isCurrent
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blur: 0.48
                                    blurMax: 16
                                    brightness: -0.35
                                }

                                opacity: isCurrent ? 1.0 : 0.5
                                scale: isCurrent ? 1.0 : 0.94

                                Behavior on opacity {
                                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                                }

                                Column {
                                    id: lyricRowColumn
                                    width: parent.width
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    // 1. Baris Pertama: Bahasa Asli
                                    Item {
                                        width: parent.width
                                        implicitHeight: baseLineText.implicitHeight

                                        Text {
                                            id: baseLineText
                                            width: parent.width
                                            text: rowDelegate.rawText
                                            wrapMode: Text.WordWrap
                                            horizontalAlignment: Text.AlignHCenter
                                            color: rowDelegate.isCurrent ? root.lyricDimColor : root.lyricActiveColor
                                            font.pixelSize: rowDelegate.isCurrent ? 14 : 13
                                            font.weight: rowDelegate.isCurrent ? Font.Bold : Font.Medium
                                        }

                                        Item {
                                            id: baseClipBox
                                            visible: rowDelegate.isCurrent
                                            readonly property real activeSpanW: baseLineText.lineCount === 1
                                                ? baseLineText.contentWidth
                                                : baseLineText.width
                                            x: baseLineText.lineCount === 1
                                                ? Math.max(0, (baseLineText.width - baseLineText.contentWidth) * 0.5)
                                                : 0
                                            anchors.top: baseLineText.top
                                            anchors.bottom: baseLineText.bottom
                                            width: activeSpanW * root.karaokeProgress
                                            clip: true

                                            Text {
                                                x: -baseClipBox.x
                                                width: baseLineText.width
                                                text: rowDelegate.rawText
                                                wrapMode: Text.WordWrap
                                                horizontalAlignment: Text.AlignHCenter
                                                color: root.lyricActiveColor
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }

                                    // 2. Baris Kedua: Romaji
                                    Item {
                                        visible: rowDelegate.showSecondRom
                                        width: parent.width
                                        implicitHeight: romLineBase.implicitHeight

                                        Text {
                                            id: romLineBase
                                            width: parent.width
                                            text: rowDelegate.romanizedText
                                            wrapMode: Text.WordWrap
                                            horizontalAlignment: Text.AlignHCenter
                                            color: rowDelegate.isCurrent ? Qt.rgba(0.51, 0.67, 1.0, 0.38) : root.accentColor
                                            font.pixelSize: rowDelegate.isCurrent ? 12 : 11
                                            font.weight: Font.Medium
                                        }

                                        Item {
                                            id: romClipBox
                                            visible: rowDelegate.isCurrent
                                            readonly property real activeRomSpanW: romLineBase.lineCount === 1
                                                ? romLineBase.contentWidth
                                                : romLineBase.width
                                            x: romLineBase.lineCount === 1
                                                ? Math.max(0, (romLineBase.width - romLineBase.contentWidth) * 0.5)
                                                : 0
                                            anchors.top: romLineBase.top
                                            anchors.bottom: romLineBase.bottom
                                            width: activeRomSpanW * root.karaokeProgress
                                            clip: true

                                            Text {
                                                x: -romClipBox.x
                                                width: romLineBase.width
                                                text: rowDelegate.romanizedText
                                                wrapMode: Text.WordWrap
                                                horizontalAlignment: Text.AlignHCenter
                                                color: root.accentColor
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    // 3. Baris Ketiga: Terjemahan Bahasa Indonesia
                                    Text {
                                        visible: rowDelegate.showThirdTrans
                                        width: parent.width
                                        text: rowDelegate.translatedText
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: Text.AlignHCenter
                                        color: root.subTextColor
                                        font.pixelSize: 11
                                        font.italic: true
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: rowDelegate.timeSec >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (rowDelegate.timeSec >= 0 && root.activePlayer && root.activePlayer.canSeek) {
                                            const delta = rowDelegate.timeSec - root.activePlayer.position
                                            root.activePlayer.seek(delta)
                                            root.applyReportedPosition(rowDelegate.timeSec, true, Date.now())
                                            root.activateSyncedIndex(rowDelegate.index, false)
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
}