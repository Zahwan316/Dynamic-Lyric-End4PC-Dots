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

    // --- State Sinkronisasi Tempo & Clock Audio ---
    property real anchorPlayerPos: 0.0
    property double anchorWallMs: 0.0
    property real activeLineStartSec: 0.0
    property real activeLineEndSec: 3.0
    property double lastFallbackLineMs: 0.0
    property int lastFallbackCharCount: 0
    property real adaptiveMsPerChar: 72.0

    // --- State Expanded Popup (Hover) ---
    property bool isExpanded: false
    property real expandProgress: isExpanded ? 1.0 : 0.0
    property int activeLyricIndex: -1
    property bool hasSyncedLrc: false
    property real systemVolume: 0.7
    property bool systemMuted: false

    Behavior on expandProgress {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutExpo
        }
    }

    // Ambil MPRIS player yang sedang aktif (prioritas Playing)
    readonly property var activePlayer: {
        const players = Mpris.players.values
        if (!players || players.length === 0)
            return null
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing)
                return players[i]
        }
        return players[0]
    }

    readonly property bool isPlaying: activePlayer ? activePlayer.playbackState === MprisPlaybackState.Playing : false
    readonly property bool hasActivePlayer: activePlayer !== null && activePlayer.playbackState !== MprisPlaybackState.Stopped
    readonly property string albumArtUrl: activePlayer ? (activePlayer.trackArtUrl ?? "") : ""
    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle ?? "") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist ?? "") : ""
    readonly property string trackAlbum: activePlayer ? (activePlayer.trackAlbum ?? "") : ""
    readonly property string currentTrackId: activePlayer ? (trackTitle + "|" + trackArtist) : ""

    readonly property bool isIslandVisible: sessionActive || hasActivePlayer || currentRawLyric !== ""

    readonly property real currentVolume: {
        if (activePlayer && activePlayer.volumeSupported)
            return Math.max(0.0, Math.min(1.0, activePlayer.volume))
        return systemMuted ? 0.0 : systemVolume
    }

    readonly property var activeSlotItem: useSlotA ? slotALoader.item : slotBLoader.item
    readonly property real currentTextWidth: activeSlotItem ? activeSlotItem.implicitWidth : 0
    readonly property int currentTierCount: activeSlotItem ? activeSlotItem.tierCount : 1

    // --- Ukuran & Animasi Kapsul Compact di Dalam Top Bar ---
    visible: opacity > 0.01
    opacity: isIslandVisible ? 1.0 : 0.0
    scale: isIslandVisible ? (isExpanded ? 1.03 : 1.0) : 0.88

    implicitWidth: isIslandVisible ? Math.max(146, (currentTierCount >= 3 ? 32 : 26) + currentTextWidth + 38 + 38) : 36
    implicitHeight: {
        if (!isIslandVisible)
            return 36
        if (currentTierCount >= 3)
            return 54
        if (currentTierCount === 2)
            return 44
        return 40
    }
    radius: height / 3
    color: isExpanded ? Qt.lighter(bgColor, 1.35) : bgColor
    border.width: 1
    border.color: isExpanded ? accentColor : borderColor
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutExpo
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutBack
        }
    }
    Behavior on color {
        ColorAnimation { duration: 180 }
    }
    Behavior on border.color {
        ColorAnimation { duration: 180 }
    }

    // --- Sinkronisasi Jam Audio & Perhitungan Tempo Karaoke Real-Time ---
    function syncClockAnchor(forceSnap) {
        if (!activePlayer)
            return
        const pos = activePlayer.position
        if (pos >= 0) {
            const currentLive = getLivePositionSec()
            if (forceSnap || Math.abs(pos - currentLive) > 0.22) {
                anchorPlayerPos = pos
                anchorWallMs = Date.now()
            }
        }
    }

    function getLivePositionSec() {
        if (!activePlayer)
            return anchorPlayerPos
        if (!isPlaying)
            return activePlayer.position >= 0 ? activePlayer.position : anchorPlayerPos
        const rate = activePlayer.rate > 0 ? activePlayer.rate : 1.0
        const elapsedSec = Math.max(0.0, (Date.now() - anchorWallMs) / 1000.0)
        return anchorPlayerPos + (elapsedSec * rate)
    }

    function computeLineEndSec(idx, startSec, textLength) {
        const estimatedVocalSec = Math.max(2.2, textLength * 0.11)
        if (idx + 1 < lyricModel.count) {
            const nextStart = lyricModel.get(idx + 1).timeSec
            const gap = nextStart - startSec
            if (gap > 0.2) {
                if (gap > 12.0)
                    return startSec + Math.min(gap - 0.2, Math.max(3.8, estimatedVocalSec))
                return nextStart - 0.06
            }
        }
        const trackLen = (activePlayer && activePlayer.length > startSec) ? activePlayer.length : (startSec + 10.0)
        return Math.min(trackLen, startSec + estimatedVocalSec)
    }

    function activateSyncedIndex(idx, livePos) {
        if (idx < 0 || idx >= lyricModel.count)
            return

        const item = lyricModel.get(idx)
        const cached = root.lineCache[item.rawText]
        const rawText = item.rawText
        const romText = cached ? cached.romanizedText : item.romanizedText
        const transText = cached ? cached.translatedText : item.translatedText
        const measureLen = Math.max(rawText.length, romText.length)

        const effectiveStart = (item.timeSec >= 0 && livePos < item.timeSec && (item.timeSec - livePos) < 0.45)
            ? livePos
            : (item.timeSec >= 0 ? item.timeSec : livePos)
        const effectiveEnd = item.timeSec >= 0
            ? computeLineEndSec(idx, item.timeSec, measureLen)
            : (effectiveStart + Math.max(1.5, (measureLen * root.adaptiveMsPerChar) / 1000.0))

        root.activeLyricIndex = idx
        root.activeLineStartSec = effectiveStart
        root.activeLineEndSec = Math.max(effectiveStart + 0.4, effectiveEnd)
        root.currentRawLyric = rawText
        root.isLoadingLyrics = false
        root.sessionActive = true

        transitionToText(rawText, romText, transText, false)
    }

    function updateKaraokeFrame() {
        const livePos = getLivePositionSec()

        if (root.hasSyncedLrc && lyricModel.count > 0 && livePos >= 0) {
            let targetIdx = -1
            const lookupPos = livePos + 0.05
            for (let i = 0; i < lyricModel.count; i++) {
                if (lyricModel.get(i).timeSec <= lookupPos)
                    targetIdx = i
                else
                    break
            }

            if (targetIdx >= 0 && targetIdx !== root.activeLyricIndex) {
                activateSyncedIndex(targetIdx, livePos)
            }
        }

        if (root.isFallbackLine) {
            root.karaokeProgress = 1.0
            return
        }

        const span = Math.max(0.4, root.activeLineEndSec - root.activeLineStartSec)
        const ratio = (livePos - root.activeLineStartSec) / span
        root.karaokeProgress = Math.max(0.0, Math.min(1.0, ratio))
    }

    Connections {
        target: root.activePlayer
        function onPositionChanged() {
            root.syncClockAnchor(true)
            root.updateKaraokeFrame()
        }
        function onPlaybackStateChanged() {
            root.syncClockAnchor(true)
            root.updateKaraokeFrame()
        }
        function onRateChanged() {
            root.syncClockAnchor(true)
        }
    }

    FrameAnimation {
        id: karaokeFrameAnim
        running: root.isPlaying && root.isIslandVisible && !root.isFallbackLine
        onTriggered: root.updateKaraokeFrame()
    }

    Timer {
        id: driftSyncTimer
        interval: 800
        repeat: true
        running: root.isPlaying && root.isIslandVisible
        onTriggered: {
            root.syncClockAnchor(false)
            root.updateKaraokeFrame()
        }
    }

    onIsPlayingChanged: {
        syncClockAnchor(true)
        updateKaraokeFrame()
    }

    // --- Helper Normalisasi ke Alfabet Latin Biasa ---
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

    function normalizeCompare(str) {
        return (str || "").toLowerCase().replace(/[^a-z0-9]/g, "")
    }

    // --- Sinkronisasi Hover antara Kapsul Bar & PopupWindow ---
    function updateHoverState() {
        if (compactHover.hovered || popupHover.hovered || volumeDragArea.pressed) {
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
        id: compactHover
        onHoveredChanged: root.updateHoverState()
    }

    Timer {
        id: collapseTimer
        interval: 260
        onTriggered: {
            if (!compactHover.hovered && !popupHover.hovered && !volumeDragArea.pressed)
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

    // --- Engine Romanisasi (CJK/Korea/dll -> Alfabet) & Translate ke Bahasa Indonesia ---
    function requestRomanizeAndTranslate(linesArray, expectedTrackId, onDone) {
        if (!linesArray || linesArray.length === 0)
            return

        const joined = linesArray.join("\n")
        const xhr = new XMLHttpRequest()
        const url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=id&dt=t&dt=rm&q=" + encodeURIComponent(joined)

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (expectedTrackId !== "" && root.currentTrackId !== expectedTrackId)
                return

            if (xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText)
                    const detectedLang = (res && res[2]) ? String(res[2]).toLowerCase() : ""
                    let fullTranslated = ""
                    let fullRomanized = ""

                    if (res && Array.isArray(res[0])) {
                        for (let i = 0; i < res[0].length; i++) {
                            const chunk = res[0][i]
                            if (chunk && typeof chunk[0] === "string")
                                fullTranslated += chunk[0]
                            if (chunk && typeof chunk[3] === "string")
                                fullRomanized += chunk[3]
                        }
                    }

                    const transSplit = linesArray.length === 1 ? [fullTranslated] : fullTranslated.split("\n")
                    const romSplit = linesArray.length === 1 ? [fullRomanized] : fullRomanized.split("\n")
                    const results = []

                    for (let j = 0; j < linesArray.length; j++) {
                        const orig = linesArray[j]
                        const needRom = containsNonLatin(orig)
                        const rawRom = (romSplit.length === linesArray.length && romSplit[j]) ? romSplit[j].trim() : ""
                        const plainRom = (needRom && rawRom !== "") ? toPlainLatinAlphabet(rawRom) : ""
                        const finalRom = (plainRom !== "" && plainRom.toLowerCase() !== orig.toLowerCase()) ? plainRom : ""

                        const rawTrans = (transSplit.length === linesArray.length && transSplit[j]) ? transSplit[j].trim() : ""
                        const isIndo = detectedLang === "id" || (normalizeCompare(rawTrans) !== "" && normalizeCompare(rawTrans) === normalizeCompare(orig))
                        const finalTrans = (!isIndo && rawTrans !== "") ? rawTrans : ""

                        const entry = {
                            rawText: orig,
                            romanizedText: finalRom,
                            translatedText: finalTrans
                        }
                        root.lineCache[orig] = entry
                        results.push(entry)
                    }

                    onDone(results)
                    return
                } catch (e) {}
            }
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

    function batchProcessLyricModel(expectedTrackId) {
        const total = lyricModel.count
        if (total === 0)
            return

        const chunkSize = 20
        for (let start = 0; start < total; start += chunkSize) {
            const end = Math.min(start + chunkSize, total)
            const batchLines = []
            for (let i = start; i < end; i++) {
                batchLines.push(lyricModel.get(i).rawText)
            }

            (function(offset, lines) {
                requestRomanizeAndTranslate(lines, expectedTrackId, function(results) {
                    for (let k = 0; k < results.length; k++) {
                        const idx = offset + k
                        if (idx < lyricModel.count) {
                            lyricModel.setProperty(idx, "romanizedText", results[k].romanizedText)
                            lyricModel.setProperty(idx, "translatedText", results[k].translatedText)
                        }
                    }
                    if (root.currentRawLyric !== "" && root.lineCache[root.currentRawLyric]) {
                        const cached = root.lineCache[root.currentRawLyric]
                        if (root.displayedRawText !== cached.rawText
                            || root.displayedRomanized !== cached.romanizedText
                            || root.displayedTranslation !== cached.translatedText) {
                            applyEntryToActiveSlot(cached)
                        }
                    }
                })
            })(start, batchLines)
        }
    }

    // --- Ambil Lirik LRC Lengkap dari lrclib.net ---
    function fetchSyncedLyrics(title, artist, album, durationSec) {
        if (!title)
            return

        const trackSnapshot = root.currentTrackId
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
                        parseLrcString(res.syncedLyrics, trackSnapshot)
                        return
                    }
                } catch (e) {}
            }
            searchSyncedLyrics(title, artist, trackSnapshot)
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function searchSyncedLyrics(title, artist, trackSnapshot) {
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
                                parseLrcString(list[i].syncedLyrics, trackSnapshot)
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

    function parseLrcString(lrcText, trackSnapshot) {
        const lines = lrcText.split(/\r?\n/)
        const parsed = []
        const timeRegex = /\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]/g

        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            let match
            const timestamps = []
            timeRegex.lastIndex = 0
            while ((match = timeRegex.exec(raw)) !== null) {
                const min = parseInt(match[1], 10)
                const sec = parseInt(match[2], 10)
                const msPart = match[3] ? match[3].padEnd(3, "0") : "000"
                const ms = parseInt(msPart, 10)
                timestamps.push(min * 60 + sec + ms / 1000.0)
            }
            const cleanText = raw.replace(timeRegex, "").trim()
            if (timestamps.length > 0 && cleanText !== "") {
                for (let t = 0; t < timestamps.length; t++) {
                    parsed.push({
                        timeSec: timestamps[t],
                        rawText: cleanText,
                        romanizedText: "",
                        translatedText: ""
                    })
                }
            }
        }

        if (parsed.length === 0)
            return

        parsed.sort((a, b) => a.timeSec - b.timeSec)
        lyricModel.clear()
        for (let j = 0; j < parsed.length; j++) {
            lyricModel.append(parsed[j])
        }
        root.hasSyncedLrc = true
        syncClockAnchor(true)
        syncIndexWithCurrentState()
        updateKaraokeFrame()
        batchProcessLyricModel(trackSnapshot)
    }

    function findBestMatchingIndex(rawLine, livePos) {
        if (lyricModel.count === 0 || rawLine === "")
            return -1

        const targetNorm = rawLine.toLowerCase()
        let bestIdx = -1
        let minDiff = 999999

        for (let i = 0; i < lyricModel.count; i++) {
            const item = lyricModel.get(i)
            if (item.rawText.toLowerCase() === targetNorm) {
                if (livePos >= 0 && item.timeSec >= 0) {
                    const diff = Math.abs(item.timeSec - livePos)
                    if (diff < minDiff) {
                        minDiff = diff
                        bestIdx = i
                    }
                } else {
                    return i
                }
            }
        }
        return bestIdx
    }

    function syncIndexWithCurrentState() {
        if (lyricModel.count === 0)
            return

        const livePos = getLivePositionSec()

        if (root.currentRawLyric !== "") {
            const matchedIdx = findBestMatchingIndex(root.currentRawLyric, livePos)
            if (matchedIdx !== -1) {
                activateSyncedIndex(matchedIdx, livePos)
                return
            }
        }

        if (livePos >= 0) {
            const lookupPos = livePos + 0.05
            let idx = 0
            for (let i = 0; i < lyricModel.count; i++) {
                if (lyricModel.get(i).timeSec <= lookupPos)
                    idx = i
                else
                    break
            }
            activateSyncedIndex(idx, livePos)
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
            activeLyricIndex = -1
            lineCache = ({})
            lastFallbackLineMs = 0
            lastFallbackCharCount = 0
            adaptiveMsPerChar = 72.0
            lyricModel.clear()
            syncClockAnchor(true)
            showFallbackLine()
            fetchSyncedLyrics(trackTitle, trackArtist, trackAlbum, activePlayer ? activePlayer.length : 0)
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

        syncClockAnchor(false)
        const livePos = getLivePositionSec()

        if (root.hasSyncedLrc) {
            const matchedIdx = findBestMatchingIndex(newLine, livePos)
            if (matchedIdx !== -1) {
                if (matchedIdx !== root.activeLyricIndex || root.isLoadingLyrics) {
                    activateSyncedIndex(matchedIdx, livePos)
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
        const initialRom = cached ? cached.romanizedText : ""
        const initialTrans = cached ? cached.translatedText : ""
        const measureLen = Math.max(1, newLine.length, initialRom.length)

        root.lastFallbackLineMs = nowMs
        root.lastFallbackCharCount = measureLen
        root.activeLineStartSec = livePos
        root.activeLineEndSec = livePos + Math.min(9.5, Math.max(1.2, (measureLen * root.adaptiveMsPerChar) / 1000.0))

        transitionToText(newLine, initialRom, initialTrans, false)

        if (!root.hasSyncedLrc) {
            if (lyricModel.count === 0 || lyricModel.get(lyricModel.count - 1).rawText !== newLine) {
                lyricModel.append({
                    timeSec: -1,
                    rawText: newLine,
                    romanizedText: initialRom,
                    translatedText: initialTrans
                })
            }
            root.activeLyricIndex = lyricModel.count - 1
        }

        if (!cached) {
            const trackSnapshot = root.currentTrackId
            requestRomanizeAndTranslate([newLine], trackSnapshot, function(results) {
                if (results.length === 0)
                    return
                const item = results[0]

                for (let i = lyricModel.count - 1; i >= 0; i--) {
                    if (lyricModel.get(i).rawText === newLine) {
                        lyricModel.setProperty(i, "romanizedText", item.romanizedText)
                        lyricModel.setProperty(i, "translatedText", item.translatedText)
                        break
                    }
                }

                if (root.currentRawLyric === newLine) {
                    applyEntryToActiveSlot(item)
                }
            })
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
            fetchSyncedLyrics(trackTitle, trackArtist, trackAlbum, activePlayer ? activePlayer.length : 0)
        }
    }

    // --- Template Komponen Baris Lirik 3-Tier (Asli + Romanization + Translate) ---
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

            readonly property bool hasRomanized: romanizedText !== "" && !isFallback
            readonly property bool hasTranslated: translatedText !== "" && !isFallback
            readonly property int tierCount: 1 + (hasRomanized ? 1 : 0) + (hasTranslated ? 1 : 0)

            readonly property real maxContentW: Math.max(
                origDimText.implicitWidth,
                hasRomanized ? romDimText.implicitWidth : 0,
                hasTranslated ? subLineText.implicitWidth : 0
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
                spacing: 1

                // 1. Baris Pertama: Lirik Asli (mis. Hangeul / Kanji / Hanzi / Inggris / ID)
                Item {
                    width: origDimText.implicitWidth
                    height: origDimText.implicitHeight
                    x: -lineItem.origOverflow * lineItem.panRatio

                    Text {
                        id: origDimText
                        text: lineItem.rawText
                        color: root.lyricDimColor
                        font.pixelSize: lineItem.tierCount >= 2 ? 12 : 14
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
                            font.pixelSize: lineItem.tierCount >= 2 ? 12 : 14
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // 2. Baris Kedua: Romanization Alfabet Latin (jika lirik asli non-Latin)
                Item {
                    visible: lineItem.hasRomanized
                    width: romDimText.implicitWidth
                    height: romDimText.implicitHeight
                    x: -lineItem.romOverflow * lineItem.panRatio

                    Text {
                        id: romDimText
                        text: lineItem.romanizedText
                        color: Qt.rgba(0.51, 0.67, 1.0, 0.35)
                        font.pixelSize: 11
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
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }

                // 3. Baris Ketiga: Terjemahan Bahasa Indonesia (jika lagu bukan Bahasa Indonesia)
                Text {
                    id: subLineText
                    visible: lineItem.hasTranslated
                    text: lineItem.translatedText
                    color: root.subTextColor
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.maxCompactLyricWidth)
                }
            }
        }
    }

    // =========================================================================
    // 1. TAMPILAN COMPACT PILL (MENYATU DI TOP BAR)
    // =========================================================================
    RowLayout {
        id: compactView
        anchors.centerIn: parent
        spacing: 9

        ClippingRectangle {
            Layout.preferredWidth: root.currentTierCount >= 3 ? 32 : 26
            Layout.preferredHeight: root.currentTierCount >= 3 ? 32 : 26
            radius: 8
            color: Qt.darker(root.bgColor, 1.2)
            scale: root.isPlaying ? 1.0 : 0.9

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
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
                font.pixelSize: 13
            }
        }

        Item {
            Layout.preferredWidth: root.currentTextWidth
            Layout.preferredHeight: Math.max(
                slotALoader.item ? slotALoader.item.implicitHeight : 20,
                slotBLoader.item ? slotBLoader.item.implicitHeight : 20
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
                    { minH: 5, maxH: 15, speed: 420 },
                    { minH: 6, maxH: 18, speed: 310 },
                    { minH: 5, maxH: 13, speed: 490 }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: 2.5
                    height: root.isPlaying ? modelData.maxH : modelData.minH
                    radius: 1.25
                    color: root.accentColor
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on height {
                        running: root.isPlaying && root.isIslandVisible
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

    // =========================================================================
    // 2. POPUPWINDOW TERPISAH (TURUN KE BAWAH & MENGAMBANG DI ATAS SEMUA WINDOW)
    // =========================================================================
    PopupWindow {
        id: expandedPopup
        visible: root.isIslandVisible && root.expandProgress > 0.01
        color: "transparent"

        implicitWidth: 430
        implicitHeight: 320

        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 8
        anchor.adjustment: PopupAdjustment.Slide

        onVisibleChanged: {
            if (visible && root.activeLyricIndex >= 0) {
                fullLyricsView.positionViewAtIndex(root.activeLyricIndex, ListView.Center)
            }
        }

        Rectangle {
            id: popupCard
            anchors.fill: parent
            radius: 22
            color: root.bgColor
            border.width: 1
            border.color: Qt.rgba(0.51, 0.67, 1.0, 0.42)
            clip: true

            opacity: root.expandProgress
            scale: 0.92 + (0.08 * root.expandProgress)
            transformOrigin: Item.Top

            HoverHandler {
                id: popupHover
                onHoveredChanged: root.updateHoverState()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // --- Baris Atas: Album Cover, Judul/Artis, & Kontrol Prev/Play/Next ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ClippingRectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
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
                            scale: playMouse.pressed ? 0.92 : 1.0

                            Behavior on scale {
                                NumberAnimation { duration: 120 }
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

                // Garis Pemisah Halus
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // --- Area Bawah: Semua Lirik 3-Tier (Asli + Romanization + Translate ID) ---
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
                            width: fullLyricsView.width
                            height: lyricRowColumn.implicitHeight + 4

                            // Lirik sebelum & sesudah: blur & brightness setengah
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

                                // 1. Baris Pertama: Teks Asli (Hangeul / Kanji / Hanzi / Latin)
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
                                        visible: rowDelegate.isCurrent
                                        anchors.left: baseLineText.left
                                        anchors.top: baseLineText.top
                                        anchors.bottom: baseLineText.bottom
                                        width: baseLineText.width * root.karaokeProgress
                                        clip: true

                                        Text {
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

                                // 2. Baris Kedua: Romanization Alfabet Latin
                                Item {
                                    visible: rowDelegate.romanizedText !== ""
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
                                        visible: rowDelegate.isCurrent
                                        anchors.left: romLineBase.left
                                        anchors.top: romLineBase.top
                                        anchors.bottom: romLineBase.bottom
                                        width: romLineBase.width * root.karaokeProgress
                                        clip: true

                                        Text {
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
                                    visible: rowDelegate.translatedText !== ""
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
                                        root.syncClockAnchor(true)
                                        root.activateSyncedIndex(rowDelegate.index, rowDelegate.timeSec)
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