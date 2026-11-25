import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.modules.common
import qs.services

Rectangle {
    id: root

    // --- Opsi dari Settings > Bar > Lyrics widget ---
    property string placementMode: Config.options.bar.lyricsWidget?.mode ?? "notch"
    property bool useAlbumColor: Config.options.bar.lyricsWidget?.useAlbumColor ?? true
    // "gradient" = hitam dengan gradasi warna cover di bawah, "full" = warna cover solid.
    readonly property string albumColorStyle: Config.options.bar.lyricsWidget?.albumColorStyle ?? "gradient"
    readonly property bool fullAlbumColor: root.useAlbumColor && root.albumColorStyle === "full"
    property bool enableKaraoke: Config.options.bar.lyricsWidget?.enableKaraoke ?? true
    onEnableKaraokeChanged: if (!enableKaraoke) karaokeProgress = 1.0

    readonly property string translationTargetLanguage:
        Config.options.bar.lyricsWidget?.translation?.targetLanguage || "id"
    property string detectedTrackLanguage: ""

    onTranslationTargetLanguageChanged: {
        detectedTrackLanguage = ""
        lineCache = ({})
        if (!lyricModel)
            return
        const pending = []
        for (let i = 0; i < lyricModel.count; i++) {
            const raw = lyricModel.get(i).rawText
            if (raw && pending.indexOf(raw) === -1)
                pending.push(raw)
        }
        if (pending.length > 0)
            enqueueTranslationLines(pending, false)
    }
    readonly property bool isFloatingIsland: placementMode === "floating" || placementMode === "floating-island"
    // Ukuran compact (notch & floating island) dan kartu expanded ikut skala ini.
    readonly property string widgetSize: Config.options.bar.lyricsWidget?.size ?? "default"
    readonly property real widgetScale: ({
        "extra-small": 0.8,
        "small": 0.9,
        "default": 1.0,
        "medium": 1.1,
        "large": 1.25,
        "very-large": 1.4
    })[widgetSize] ?? 1.0
    function sp(value) { return value * root.widgetScale }

    readonly property int lyricTextAlignment: ({
        "left": Text.AlignLeft,
        "center": Text.AlignCenter,
        "right": Text.AlignRight
    })[Config.options.bar.lyricsWidget?.textAlignment ?? "left"] ?? Text.AlignLeft

    // Kedua mode memakai siluet notch: hitam, leher rata di tepi layar/bar,
    // sudut bawah membulat. Floating island hanya digeser sedikit dari tepi atas.
    readonly property bool notchAtTop: !Config.options.bar.bottom
    readonly property int barCornerStyle: Config.options.bar.cornerStyle ?? 0
    // Semua style bar non-floating memakai siluet notch yang sama seperti
    // sebelumnya, termasuk Islands.
    readonly property bool notchSilhouette: !root.isFloatingIsland
    // Notch Mac: bahu cekung di tepi bar, badan lebih sempit,
    // lalu sudut bawah membulat.
    readonly property int notchShoulderInset: Math.round(root.sp(22))
    readonly property int notchShoulderDrop: Math.max(root.sp(10), Math.round(root.height * 0.28))
    readonly property int notchBottomRadius: Math.max(root.sp(12), Math.round(root.height * 0.35))

    // --- Konfigurasi Tema, Posisi & Ukuran ---
    property color bgColor: "#000000"
    property color surfaceColor: "#292d42"
    property color borderColor: "transparent"
    property color accentColor: "#82aaff"
    property color lyricActiveColor: "#ffffff"
    property color lyricDimColor: Qt.rgba(1.0, 1.0, 1.0, 0.36)
    property color subTextColor: Qt.rgba(1.0, 1.0, 1.0, 0.72)
    readonly property real maxCompactLyricWidth: root.sp(420)
    // BarGroup mengapungkan widget di tengah bar. Untuk notch 1 baris yang
    // lebih pendek dari bar, celah 1-2 px membuat siluet terlihat mengambang:
    // tarik ke tepi bar (atas/bawah sesuai posisi bar) sampai mentok.
    readonly property real notchSurfaceHeight: Appearance.sizes.barHeight
        - (root.barCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
    readonly property int notchEdgeYOffset: (root.notchSilhouette
        && !Config.options.bar.vertical
        && root.currentTierCount === 1
        && !root.isExpanded
        && root.morphProgress <= 0.01)
        ? (root.notchAtTop ? -1 : 1) * Math.max(0, Math.round((root.notchSurfaceHeight - root.height) / 2))
        : 0
    property int yOffset: root.notchEdgeYOffset

    readonly property real expandedWidth: 492
    readonly property real expandedHeight: 404

    // Ukuran compact diambil saat ekspansi dimulai agar perubahan lirik tidak
    // menggeser popup/expanded card.
    property real morphBaseWidth: 96
    property real morphBaseHeight: 38

    // --- Palet Warna Dinamis dari Cover Album ---
    property color albumAccentColor: "#262626"
    property color albumGlowColor: "#525252"
    property color albumButtonFill: "#3d3d3d"
    property color albumButtonBorder: "#5c5c5c"
    property color albumSliderColor: "#b8b8b8"
    property string lastExtractedArtUrl: ""

    Behavior on albumAccentColor { ColorAnimation { duration: 560; easing.type: Easing.InOutQuad } }
    Behavior on albumGlowColor { ColorAnimation { duration: 640; easing.type: Easing.InOutQuad } }
    Behavior on albumButtonFill { ColorAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    Behavior on albumButtonBorder { ColorAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    Behavior on albumSliderColor { ColorAnimation { duration: 520; easing.type: Easing.InOutQuad } }

    // Warna pakai hasil ekstraksi cover hanya saat toggle album color aktif.
    // Saat nonaktif, aksen tetap netral abu-abu agar kontras teks terjaga.
    readonly property color effectiveAccentColor: root.useAlbumColor ? albumAccentColor : "#4a4a4a"
    readonly property color effectiveGlowColor: root.useAlbumColor ? albumGlowColor : "#333333"
    readonly property color effectiveButtonFill: root.useAlbumColor ? albumButtonFill : "#3d3d3d"
    readonly property color effectiveButtonBorder: root.useAlbumColor ? albumButtonBorder : "#5c5c5c"
    readonly property color effectiveSliderColor: root.useAlbumColor ? albumSliderColor : "#b8b8b8"

    // Romaji tetap kontras di atas latar hitam walau pewarnaan album dimatikan.
    readonly property color romajiActiveColor: root.useAlbumColor
        ? Qt.lighter(root.effectiveAccentColor, 1.42)
        : "#ededed"
    readonly property color romajiDimColor: root.useAlbumColor
        ? Qt.rgba(romajiActiveColor.r, romajiActiveColor.g, romajiActiveColor.b, 0.38)
        : "#9e9e9e"

    // Expanded view memakai permukaan near-black yang datar. Warna cover
    // hanya jadi hint sangat tipis (atau solid penuh saat gaya "full").
    readonly property color expandedSurfaceColor: root.fullAlbumColor
        ? root.effectiveAccentColor
        : (root.useAlbumColor
            ? Qt.tint("#080808", Qt.rgba(root.effectiveAccentColor.r, root.effectiveAccentColor.g, root.effectiveAccentColor.b, 0.12))
            : "#080808")
    readonly property color gradientMidColor: root.expandedSurfaceColor
    readonly property color gradientBottomColor: root.fullAlbumColor
        ? root.effectiveAccentColor
        : (root.useAlbumColor
            ? Qt.tint("#0b0b0b", Qt.rgba(root.effectiveAccentColor.r, root.effectiveAccentColor.g, root.effectiveAccentColor.b, 0.26))
            : "#0b0b0b")
    readonly property color expandedBorderColor: root.useAlbumColor
        ? Qt.rgba(root.effectiveAccentColor.r, root.effectiveAccentColor.g, root.effectiveAccentColor.b, 0.18)
        : Qt.rgba(1, 1, 1, 0.08)

    // --- Mode Tampilan Lirik (3 Tombol: Translate, Romaji, Original) ---
    property bool showTranslate: true
    property bool showRomajiSubline: true
    property bool showOriginalLanguage: true

    // --- State Internal Lirik, Romanisasi & Terjemahan ---
    property string currentRawLyric: ""
    property string displayedRawText: ""
    property string displayedRomanized: ""
    property string displayedTranslation: ""
    property bool useSlotA: true
    property real karaokeProgress: 0.0
    property bool isLoadingLyrics: false
    // True hanya setelah semua sumber selesai dan tidak ada satu pun baris lirik.
    property bool lyricsNotFound: false
    property bool sessionActive: false
    property bool isFallbackLine: true
    property bool isInstrumentalLine: false
    property var lineCache: ({})

    // --- Antrean Terjemahan & Romanisasi (Prioritas Baris Aktif, Anti Rate-Limit) ---
    property var translationQueue: []
    property var queuedSet: ({})
    property bool isTranslatingNow: false
    property string activeQueueTrackId: ""

    // --- State Sinkronisasi Tempo & Clock Audio (Anti-Teleport Guard) ---
    property real anchorPlayerPos: 0.0
    property double anchorWallMs: 0.0
    property double posQueryStartMs: 0.0
    property string posQueryTrackId: ""
    property double trackChangeWallMs: 0.0
    property real pendingJumpPos: -1.0
    property double pendingJumpWallMs: 0.0
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
    // Baris live dari Sonora sesegera mengalahkan auto-advance model tersinkron.
    property double lastLiveLineWallMs: 0.0

    // Retry fetch saat durasi baru diketahui (umum pada Spotify/MPRIS awal).
    property real lastFetchDurationSec: -1.0
    property string lastFetchTrackId: ""

    // --- State Slider Musik & Durasi ---
    property real fallbackTrackLengthSec: 0.0
    readonly property real trackDurationSec: {
        if (activePlayer && activePlayer.length > 0.5)
            return activePlayer.length
        return fallbackTrackLengthSec
    }
    property real sliderDisplayPosSec: 0.0
    property bool isSeekingSlider: false

    // --- State Expanded (Bouncy Morph Expansion dari Compact Pill) ---
    property bool isExpanded: false
    property real morphProgress: 0.0
    property int activeLyricIndex: -1

    // Arah perpindahan lirik di compact pill: 1 = lirik baru naik dari bawah,
    // -1 = lirik baru turun dari atas (dipakai saat mundur/seek).
    property int lyricSlideDirection: 1
    property int lastAnimatedLyricIndex: -1
    readonly property real compactSlideDistance: root.sp(11)
    readonly property bool compactSlideEnabled: !root.isExpanded && root.morphProgress < 0.08

    property bool hasSyncedLrc: false
    property int lrcSourcePriority: 0
    // Sonora adalah sumber lirik utama. Sheet-nya dibaca lewat CLI, bukan
    // lewat MPRIS (metadata MPRIS Sonora tidak membawa lirik).
    property real systemVolume: 0.7
    property bool systemMuted: false
    property bool volumeOsdActive: false
    property rect cachedAnchorRect: Qt.rect(0, 0, 1, 1)

    transform: Translate {
        y: root.yOffset
    }

    function formatDuration(sec) {
        if (isNaN(sec) || sec <= 0)
            return "0:00"
        const total = Math.floor(sec)
        const mins = Math.floor(total / 60)
        const secs = total % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    function escapeHtml(str) {
        return (str || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    // Kurva Ease-In-Out halus untuk sapuan karaoke di mode expanded
    function easeInOutKaraoke(p) {
        const t = Math.max(0.0, Math.min(1.0, p))
        const cubic = t < 0.5
            ? 4.0 * t * t * t
            : 1.0 - Math.pow(-2.0 * t + 2.0, 3.0) / 2.0
        return (t * 0.35) + (cubic * 0.65)
    }

    function buildRichKaraokeText(text, progress, activeCol, dimCol) {
        if (!text || text.length === 0)
            return ""
        const eased = easeInOutKaraoke(progress)
        const splitIdx = Math.round(text.length * eased)
        if (splitIdx <= 0)
            return "<font color=\"" + dimCol + "\">" + escapeHtml(text) + "</font>"
        if (splitIdx >= text.length)
            return "<font color=\"" + activeCol + "\">" + escapeHtml(text) + "</font>"
        const sung = escapeHtml(text.slice(0, splitIdx))
        const unsung = escapeHtml(text.slice(splitIdx))
        return "<font color=\"" + activeCol + "\">" + sung + "</font><font color=\"" + dimCol + "\">" + unsung + "</font>"
    }

    // --- Ekstraktor Warna Dominan/Aksen dari Cover Album ---
    function resetAlbumPalette() {
        albumAccentColor = "#2a2a2a"
        albumGlowColor = "#545454"
        albumButtonFill = "#424242"
        albumButtonBorder = "#616161"
        albumSliderColor = "#bdbdbd"
    }

    function rgbToHsl(r, g, b) {
        r /= 255.0
        g /= 255.0
        b /= 255.0
        const max = Math.max(r, g, b)
        const min = Math.min(r, g, b)
        let h = 0.0
        let s = 0.0
        const l = (max + min) * 0.5

        if (max !== min) {
            const d = max - min
            s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min)
            if (max === r)
                h = ((g - b) / d) + (g < b ? 6.0 : 0.0)
            else if (max === g)
                h = ((b - r) / d) + 2.0
            else
                h = ((r - g) / d) + 4.0
            h /= 6.0
        }
        return [h, s, l]
    }

    function hslToHex(h, s, l) {
        function hue2rgb(p, q, t) {
            if (t < 0.0) t += 1.0
            if (t > 1.0) t -= 1.0
            if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t
            if (t < 0.5) return q
            if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0
            return p
        }
        let r, g, b
        if (s === 0.0) {
            r = g = b = l
        } else {
            const q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
            const p = 2.0 * l - q
            r = hue2rgb(p, q, h + 1.0 / 3.0)
            g = hue2rgb(p, q, h)
            b = hue2rgb(p, q, h - 1.0 / 3.0)
        }
        const toHex = v => {
            const n = Math.max(0, Math.min(255, Math.round(v * 255)))
            return (n < 16 ? "0" : "") + n.toString(16)
        }
        return "#" + toHex(r) + toHex(g) + toHex(b)
    }

    function extractColorsFromArt(artUrl) {
        if (!artUrl || artUrl === "") {
            lastExtractedArtUrl = ""
            resetAlbumPalette()
            return
        }
        if (artUrl === lastExtractedArtUrl)
            return

        if (lastExtractedArtUrl !== "" && colorSamplerCanvas.isImageLoaded(lastExtractedArtUrl)) {
            colorSamplerCanvas.unloadImage(lastExtractedArtUrl)
        }
        lastExtractedArtUrl = artUrl
        colorSamplerCanvas.loadImage(artUrl)
    }

    onAlbumArtUrlChanged: extractColorsFromArt(albumArtUrl)

    Canvas {
        id: colorSamplerCanvas
        width: 36
        height: 36
        visible: false

        onImageLoaded: {
            const url = root.lastExtractedArtUrl
            if (!url || !isImageLoaded(url))
                return

            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(url, 0, 0, width, height)

            let imgData
            try {
                imgData = ctx.getImageData(0, 0, width, height).data
            } catch (e) {
                root.resetAlbumPalette()
                return
            }

            const binCount = 24
            const bins = []
            for (let b = 0; b < binCount; b++) {
                bins.push({ weight: 0.0, hSum: 0.0, sSum: 0.0, lSum: 0.0 })
            }

            let totalVibrantWeight = 0.0
            for (let i = 0; i < imgData.length; i += 4) {
                const alpha = imgData[i + 3]
                if (alpha < 128)
                    continue

                const r = imgData[i]
                const g = imgData[i + 1]
                const bVal = imgData[i + 2]
                const hsl = root.rgbToHsl(r, g, bVal)
                const h = hsl[0]
                const s = hsl[1]
                const l = hsl[2]

                if (l > 0.90 || l < 0.09 || s < 0.16)
                    continue

                const lumFactor = 1.0 - Math.min(0.85, Math.abs(l - 0.50) * 1.4)
                const w = Math.pow(s, 1.35) * lumFactor
                const binIdx = Math.min(binCount - 1, Math.floor(h * binCount))

                bins[binIdx].weight += w
                bins[binIdx].hSum += h * w
                bins[binIdx].sSum += s * w
                bins[binIdx].lSum += l * w
                totalVibrantWeight += w
            }

            if (totalVibrantWeight <= 0.05) {
                albumAccentColor = "#475161"
                albumGlowColor = "#7d8fa8"
                albumButtonFill = "#55647a"
                albumButtonBorder = "#7486a1"
                albumSliderColor = "#b4c5e0"
                return
            }

            let bestBin = bins[0]
            for (let k = 1; k < binCount; k++) {
                if (bins[k].weight > bestBin.weight)
                    bestBin = bins[k]
            }

            const domH = bestBin.hSum / bestBin.weight
            const domS = Math.max(0.42, Math.min(0.85, bestBin.sSum / bestBin.weight))

            albumAccentColor = root.hslToHex(domH, Math.min(0.86, domS + 0.06), 0.50)
            albumGlowColor = root.hslToHex(domH, Math.max(0.45, domS * 0.85), 0.70)
            albumButtonFill = root.hslToHex(domH, Math.min(0.78, domS), 0.46)
            albumButtonBorder = root.hslToHex(domH, Math.min(0.82, domS + 0.04), 0.56)
            albumSliderColor = root.hslToHex(domH, Math.max(0.48, domS * 0.9), 0.76)
        }
    }

    function updatePopupAnchor() {
        const win = root.QsWindow.window
        if (!win || !win.contentItem)
            return
        const pos = root.mapToItem(win.contentItem, 0, 0)
        const anchorW = (isExpanded || morphProgress > 0.01) ? morphBaseWidth : root.width
        const maxX = Math.max(8, win.width - expandedPopup.implicitWidth - 8)
        const centeredX = Math.max(8, Math.min(maxX, pos.x + (anchorW - expandedPopup.implicitWidth) * 0.5))
        cachedAnchorRect = Qt.rect(centeredX, pos.y, expandedPopup.implicitWidth, root.height)
    }

    onXChanged: if (!isExpanded && morphProgress <= 0.01) updatePopupAnchor()
    onWidthChanged: if (!isExpanded && morphProgress <= 0.01) updatePopupAnchor()
    onHeightChanged: if (!isExpanded && morphProgress <= 0.01) updatePopupAnchor()
    onYChanged: if (!isExpanded && morphProgress <= 0.01) updatePopupAnchor()
    onYOffsetChanged: updatePopupAnchor()

    NumberAnimation {
        id: expandMorphAnim
        target: root
        property: "morphProgress"
        to: 1.0
        duration: 520
        easing.type: Easing.OutBack
        easing.overshoot: 1.16
    }

    NumberAnimation {
        id: collapseMorphAnim
        target: root
        property: "morphProgress"
        to: 0.0
        duration: 340
        easing.type: Easing.OutQuint
    }

    onIsExpandedChanged: {
        expandMorphAnim.stop()
        collapseMorphAnim.stop()
        if (isExpanded) {
            morphBaseWidth = root.width
            morphBaseHeight = root.height
            updatePopupAnchor()
            expandMorphAnim.start()
            if (root.activeLyricIndex >= 0) {
                fullLyricsView.positionViewAtIndex(root.activeLyricIndex, ListView.Center)
            }
        } else {
            collapseMorphAnim.start()
        }
    }

    // Pakai selector pusat agar "Preferred player" (mis. spotify) dihormati,
    // duplicate player difilter, dan player yang baru mulai dipakai dipantau.
    readonly property var activePlayer: MprisController.activePlayer

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
    readonly property string currentTrackId: activePlayer
        ? (trackTitle + "|" + trackArtist + "|" + String(activePlayer.metadata?.["mpris:trackid"] ?? ""))
        : ""

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
        ? Math.max(root.sp(96), (currentTierCount >= 3 ? root.sp(30) : root.sp(26)) + currentTextWidth + root.sp(36) + root.sp(34))
            + (root.notchSilhouette ? notchShoulderInset * 2 : 0)
        : root.sp(36)
    readonly property real compactTargetHeight: {
        if (!isIslandVisible)
            return root.sp(40)
        if (currentTierCount >= 3)
            return root.sp(50)
        if (currentTierCount === 2)
            return root.sp(42)
        return root.sp(38)
    }

    // --- Ukuran Kapsul di Top Bar (Gradasi #000000 -> Warna Cover Album, Tanpa Border) ---
    visible: opacity > 0.01
    opacity: isIslandVisible ? 1.0 : 0.0
    transformOrigin: Item.Top
    scale: isIslandVisible ? 1.0 : 0.86

    implicitWidth: compactTargetWidth
    implicitHeight: compactTargetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    // Background digambar oleh child di bawah agar notch bisa memakai
    // bentuk bahu cekung, sementara floating island tetap rounded penuh.
    color: "transparent"
    radius: 0
    border.width: 0
    border.color: "transparent"
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        enabled: !root.isIslandVisible
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    // --- Sinkronisasi Jam Audio Real-Time & Durasi Lagu ---
    function queryPlayerctlPosition() {
        if (!playerctlPosProc.running) {
            posQueryStartMs = Date.now()
            posQueryTrackId = root.currentTrackId
            playerctlPosProc.running = true
        }
        if (root.trackDurationSec <= 0.5 && !playerctlLenProc.running) {
            playerctlLenProc.running = true
        }
    }

    function seekToSeconds(targetSec) {
        const maxDur = root.trackDurationSec
        const clamped = maxDur > 0 ? Math.max(0.0, Math.min(maxDur, targetSec)) : Math.max(0.0, targetSec)
        if (root.activePlayer && root.activePlayer.canSeek) {
            const delta = clamped - root.activePlayer.position
            root.activePlayer.seek(delta)
        } else {
            playerctlSeekProc.command = root.activePlayerName !== ""
                ? ["playerctl", "-p", root.activePlayerName, "position", clamped.toFixed(2)]
                : ["playerctl", "position", clamped.toFixed(2)]
            playerctlSeekProc.running = true
        }
        root.applyReportedPosition(clamped, true, Date.now(), false)
        root.sliderDisplayPosSec = clamped
    }

    Process {
        id: playerctlSeekProc
        command: ["playerctl", "position", "0"]
    }

    Process {
        id: playerctlLenProc
        command: root.activePlayerName !== ""
            ? ["playerctl", "-p", root.activePlayerName, "metadata", "mpris:length"]
            : ["playerctl", "metadata", "mpris:length"]
        stdout: SplitParser {
            onRead: data => {
                const micro = parseFloat(data.trim())
                if (!isNaN(micro) && micro > 1000000) {
                    root.fallbackTrackLengthSec = micro / 1000000.0
                    root.retryLyricsFetchIfNeeded()
                }
            }
        }
    }

    function applyReportedPosition(pos, forceSnap, sampleWallMs, fromMprisSignal) {
        if (pos === undefined || pos === null || isNaN(pos) || pos < 0)
            return

        const nowMs = Date.now()
        const refMs = sampleWallMs > 0 ? sampleWallMs : nowMs

        const trackLen = root.trackDurationSec
        if (trackLen > 1.0 && pos > trackLen + 2.0)
            return

        if (!forceSnap && (nowMs - trackChangeWallMs) < 1200 && pos > 4.0)
            return

        if (lastReportedPos >= 0 && Math.abs(pos - lastReportedPos) > 0.015) {
            movingPosTicks = Math.min(10, movingPosTicks + 1)
        } else if (pos <= 0.01 && lastReportedPos > 0.5 && (nowMs - trackChangeWallMs) < 2000) {
            movingPosTicks = 0
        }
        lastReportedPos = pos

        const currentLive = getRawLivePositionSec()
        const delta = pos - currentLive

        if (forceSnap || movingPosTicks <= 1) {
            pendingJumpPos = -1.0
            const isBackward = delta < -0.5
            anchorPlayerPos = pos
            anchorWallMs = refMs
            if (!isSeekingSlider)
                sliderDisplayPosSec = pos
            if (isBackward) {
                root.activeLyricIndex = -1
                root.karaokeProgress = 0.0
            }
            updateKaraokeFrame(true)
            return
        }

        if (fromMprisSignal && Math.abs(delta) > 0.45) {
            queryPlayerctlPosition()
            return
        }

        // Anti-Teleport: lonjakan besar (> 1.2s) harus terkonfirmasi 2 sampel berturut-turut
        if (Math.abs(delta) > 1.2) {
            const rate = (activePlayer && activePlayer.rate > 0) ? activePlayer.rate : 1.0
            if (pendingJumpPos >= 0 && (refMs - pendingJumpWallMs) < 1500) {
                const expectedJump = pendingJumpPos + (((refMs - pendingJumpWallMs) / 1000.0) * rate)
                if (Math.abs(pos - expectedJump) < 0.85) {
                    pendingJumpPos = -1.0
                    const isBackwardSeek = delta < -0.65
                    anchorPlayerPos = pos
                    anchorWallMs = refMs
                    if (!isSeekingSlider)
                        sliderDisplayPosSec = pos
                    if (isBackwardSeek) {
                        root.activeLyricIndex = -1
                        root.karaokeProgress = 0.0
                    }
                    updateKaraokeFrame(true)
                    return
                }
            }
            pendingJumpPos = pos
            pendingJumpWallMs = refMs
            confirmSeekTimer.restart()
            return
        }

        pendingJumpPos = -1.0

        // Koreksi fase halus untuk drift kecil (0.08s .. 1.2s)
        if (Math.abs(delta) >= 0.08) {
            anchorPlayerPos = currentLive + (delta * 0.28)
            anchorWallMs = refMs
            updateKaraokeFrame(false)
        }
    }

    Timer {
        id: confirmSeekTimer
        interval: 120
        repeat: false
        onTriggered: root.queryPlayerctlPosition()
    }

    function syncClockAnchor(forceSnap) {
        if (forceSnap && activePlayer && activePlayer.position >= 0 && lastReportedPos < 0) {
            const nowMs = Date.now()
            if ((nowMs - trackChangeWallMs) >= 1200 || activePlayer.position <= 4.0) {
                applyReportedPosition(activePlayer.position, true, nowMs, true)
            }
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
                if (root.posQueryTrackId !== "" && root.posQueryTrackId !== root.currentTrackId)
                    return

                const val = parseFloat(data.trim())
                if (!isNaN(val) && val >= 0) {
                    const nowMs = Date.now()
                    const midWallMs = root.posQueryStartMs > 0
                        ? (root.posQueryStartMs + nowMs) * 0.5
                        : nowMs
                    root.applyReportedPosition(val, false, midWallMs, false)
                }
            }
        }
    }

    Timer {
        id: posPollTimer
        interval: root.movingPosTicks < 2 ? 200 : 800
        repeat: true
        running: root.isPlaying && root.isIslandVisible
        onTriggered: root.queryPlayerctlPosition()
    }

    // --- Deteksi Bagian Instrumental / Tanpa Vokal ---
    function isInstrumentalText(str) {
        const trimmed = (str || "").trim()
        if (trimmed === "")
            return true
        if (/^[\s♪♫♩♬🎵🎶♭♮♯~～\-—–_•·.…*]+$/.test(trimmed))
            return true
        if (/^[(\[【（]?\s*(instrumental|interlude|intro|introduction|opening|outro|reff|refrain|chorus|bridge|music|solo|guitar solo|piano solo|melody|break|musik)\s*[)\]】）]?$/i.test(trimmed))
            return true
        return false
    }

    // Label yang ditampilkan menggantikan titik-titik pada bagian tanpa vokal.
    function instrumentalSectionLabel(str) {
        const t = (str || "").trim().toLowerCase()
        if (/opening|intro|introduction|pembukaan/.test(t))
            return Translation.tr("Opening")
        if (/reff|refrain|chorus|refr/.test(t))
            return Translation.tr("Reff")
        if (/outro|ending|penutup/.test(t))
            return Translation.tr("Outro")
        return Translation.tr("Instrumental")
    }

    // --- Estimasi Durasi Vokal Berdasarkan Panjang-Pendek & Jenis Aksara Baris Lirik ---
    function estimateNaturalVocalDurationSec(text) {
        if (!text || text.length === 0)
            return 1.2
        let syllableUnits = 0.0
        for (let i = 0; i < text.length; i++) {
            const code = text.charCodeAt(i)
            if ((code >= 0x3040 && code <= 0x30FF)
                || (code >= 0x4E00 && code <= 0x9FFF)
                || (code >= 0xAC00 && code <= 0xD7AF)) {
                syllableUnits += 1.0
            } else if (text[i] === " ") {
                syllableUnits += 0.15
            } else {
                syllableUnits += 0.45
            }
        }
        return Math.max(0.75, Math.min(8.5, syllableUnits * 0.25))
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
                w = 0.35
            else if (",;、，".indexOf(ch) !== -1)
                w = 1.5
            else if (".!?。！？—–".indexOf(ch) !== -1)
                w = 1.65
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

    function computeLineDurationSec(idx, startSec, rawText) {
        const estimatedVocalSec = estimateNaturalVocalDurationSec(rawText)
        if (idx + 1 < lyricModel.count) {
            const nextStart = lyricModel.get(idx + 1).timeSec
            const gap = nextStart - startSec
            if (gap > 0.25) {
                // Sweep mengikuti jarak ke lirik berikutnya, bukan hanya panjang teks,
                // sehingga baris pendek tidak selesai lebih awal dari vokal.
                return Math.max(0.45, Math.min(gap - 0.12, Math.max(estimatedVocalSec, gap * 0.93)))
            }
        }
        const trackLen = (root.trackDurationSec > startSec) ? root.trackDurationSec : (startSec + 10.0)
        return Math.max(0.5, Math.min(trackLen - startSec, estimatedVocalSec))
    }

    function activateSyncedIndex(idx, syncFromPlayerClock) {
        if (idx < 0 || idx >= lyricModel.count)
            return

        const item = lyricModel.get(idx)
        const now = Date.now()
        const calPos = getCalibratedPositionSec()
        const baseStart = item.timeSec >= 0 ? item.timeSec : 0.0

        if (item.isInstrumental) {
            const instDur = (item.endSec > baseStart) ? (item.endSec - baseStart) : 8.0
            root.activeLyricIndex = idx
            root.activeLineStartSec = baseStart
            root.activeLineDurationSec = Math.max(1.0, instDur)
            root.activeWordTimings = []
            root.lineStartWallMs = now
            root.pauseStartedWallMs = root.isPlaying ? 0.0 : now
            root.currentRawLyric = ""
            root.isLoadingLyrics = false
            root.sessionActive = true
            root.karaokeProgress = 1.0
            transitionToText(item.rawText && item.rawText !== "" ? item.rawText : "Instrumental", "", "", false, true)
            return
        }

        const cached = root.lineCache[item.rawText]
        const rawText = item.rawText
        const instantRom = instantLocalRomanize(rawText)
        const romText = (cached && cached.romanizedText !== "")
            ? cached.romanizedText
            : (item.romanizedText !== "" ? item.romanizedText : instantRom)
        const transText = (cached && cached.translatedText !== "")
            ? cached.translatedText
            : item.translatedText

        const durSec = (item.explicitEndSec > baseStart && (item.explicitEndSec - baseStart) <= 10.0)
            ? Math.max(0.45, (item.explicitEndSec - baseStart))
            : (item.timeSec >= 0
                ? computeLineDurationSec(idx, item.timeSec, rawText)
                : estimateNaturalVocalDurationSec(rawText))

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

        let initialElapsedSec = 0.0
        if (syncFromPlayerClock && root.hasReliablePlayerClock && item.timeSec >= 0 && Math.abs(calPos - item.timeSec) < 8.0) {
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
        root.karaokeProgress = 0.0

        transitionToText(rawText, romText, transText, false, false)
        updateKaraokeFrame(true)

        if (!cached || cached.translatedText === "") {
            enqueueTranslationLines([rawText], true)
        }
    }

    function getCurrentLineElapsedSec() {
        // Untuk lirik tersinkron, pakai posisi player terkalibrasi (bukan wall clock)
        // agar koreksi drift/seek langsung tercermin di progres karaoke.
        if (root.hasSyncedLrc && root.hasReliablePlayerClock && root.activeLineStartSec >= 0) {
            const calPos = getCalibratedPositionSec()
            if (calPos >= 0.0)
                return Math.max(0.0, calPos - root.activeLineStartSec)
        }
        const now = root.isPlaying ? Date.now() : (root.pauseStartedWallMs > 0 ? root.pauseStartedWallMs : Date.now())
        const rate = (activePlayer && activePlayer.rate > 0) ? activePlayer.rate : 1.0
        return Math.max(0.0, ((now - root.lineStartWallMs) / 1000.0) * rate)
    }

    function evaluateKaraokeProgress(elapsedSec) {
        // Karaoke dimatikan: seluruh baris aktif langsung terisi, tanpa sapuan.
        if (!root.enableKaraoke)
            return 1.0

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

    function updateKaraokeFrame(allowBackward) {
        const calPos = getCalibratedPositionSec()
        if (!root.isSeekingSlider) {
            root.sliderDisplayPosSec = root.trackDurationSec > 0
                ? Math.min(root.trackDurationSec, calPos)
                : calPos
        }

        const liveLineFresh = root.lastLiveLineWallMs > 0
            && (Date.now() - root.lastLiveLineWallMs) < 3500

        const activeIsLiveRow = root.activeLyricIndex >= 0
            && root.activeLyricIndex < lyricModel.count
            && lyricModel.get(root.activeLyricIndex).timeSec < 0

        if (!activeIsLiveRow && !liveLineFresh && root.hasReliablePlayerClock
            && root.hasSyncedLrc && lyricModel.count > 0) {
            if (calPos >= 0.0) {
                let targetIdx = -1
                const lookupPos = calPos
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

        if (!root.hasSyncedLrc && !root.isFallbackLine && !root.isInstrumentalLine && root.isPlaying) {
            const elapsedSinceLine = getCurrentLineElapsedSec()
            if (elapsedSinceLine > Math.max(11.0, root.activeLineDurationSec + 7.5)) {
                root.currentRawLyric = ""
                transitionToText("", "", "", false, true)
                return
            }
        }

        if (root.isFallbackLine || root.isInstrumentalLine) {
            root.karaokeProgress = 1.0
            return
        }

        const elapsed = getCurrentLineElapsedSec()
        const nextProgress = evaluateKaraokeProgress(elapsed)

        if (allowBackward || root.hasReliablePlayerClock)
            root.karaokeProgress = nextProgress
        else
            root.karaokeProgress = Math.max(root.karaokeProgress, nextProgress)
    }

    Timer {
        id: karaokeTicker
        interval: 16
        repeat: true
        running: root.isPlaying && root.isIslandVisible
        onTriggered: root.updateKaraokeFrame(false)
    }

    onIsPlayingChanged: {
        const now = Date.now()
        if (isPlaying) {
            if (pauseStartedWallMs > 0) {
                lineStartWallMs += (now - pauseStartedWallMs)
                pauseStartedWallMs = 0
            }
            anchorWallMs = now
            queryPlayerctlPosition()
            updateKaraokeFrame(false)
        } else {
            anchorPlayerPos = getRawLivePositionSec()
            pauseStartedWallMs = now
            queryPlayerctlPosition()
        }
    }

    Connections {
        target: root.activePlayer
        function onPositionChanged() {
            root.queryPlayerctlPosition()
        }
        function onRateChanged() {
            root.anchorPlayerPos = root.getRawLivePositionSec()
            root.anchorWallMs = Date.now()
        }
        function onLengthChanged() {
            root.retryLyricsFetchIfNeeded()
        }
        function onPlaybackStateChanged() {
            root.retryLyricsFetchIfNeeded()
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

    // Baris yang sudah memakai alfabet Latin (mis. lirik Inggris di tengah lagu
    // Korea/Jepang/Arab) tidak punya romaji. Saat tombol Original mati, baris itu
    // ditampilkan apa adanya agar tidak otomatis berubah menjadi terjemahan.
    function romajiForDisplay(rawText, romanizedText) {
        if (romanizedText && romanizedText !== "")
            return romanizedText
        if (isInstrumentalText(rawText) || containsNonLatin(rawText))
            return ""
        return rawText
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

    // --- Sinkronisasi Hover antara Kapsul Top Bar & Expanded Morph Card ---
    function updateHoverState() {
        if (rootHover.hovered || popupHover.hovered || volumeDragArea.pressed || customSliderMouse.pressed) {
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
        interval: 260
        onTriggered: {
            if (!rootHover.hovered && !popupHover.hovered && !volumeDragArea.pressed && !customSliderMouse.pressed)
                root.isExpanded = false
        }
    }

    // --- Kontrol Volume (MPRIS atau PipeWire wpctl fallback) ---
    Timer {
        id: volumeOsdHideTimer
        interval: 1500
        onTriggered: root.volumeOsdActive = false
    }

    function showVolumeFeedback() {
        root.volumeOsdActive = true
        volumeOsdHideTimer.restart()
    }

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
        showVolumeFeedback()
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
        showVolumeFeedback()
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

    // --- Model Seluruh Baris Lirik (3 Tier + Flag Instrumental) ---
    ListModel {
        id: lyricModel
    }

    // =========================================================================
    // HTTP helper ringan: timeout + status + stale-track guard dipakai bersama
    // oleh sumber lirik dan penyedia terjemahan.
    // =========================================================================
    function httpRequest(url, trackSnapshot, callback, timeoutMs, headers) {
        const xhr = new XMLHttpRequest()
        let finished = false
        const finish = result => {
            if (finished) return
            finished = true
            xhr.onreadystatechange = null
            xhr.onerror = null
            xhr.ontimeout = null
            const stale = Boolean(trackSnapshot) && root.currentTrackId !== trackSnapshot
            result.stale = stale
            callback(result)
        }

        xhr.timeout = timeoutMs || 8000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                finish({ ok: false, error: "http-" + xhr.status })
                return
            }
            finish({ ok: true, data: xhr.responseText })
        }
        xhr.onerror = () => finish({ ok: false, error: "network" })
        xhr.ontimeout = () => {
            try { xhr.abort() } catch (e) {}
            finish({ ok: false, error: "timeout" })
        }

        try {
            xhr.open("GET", url)
            if (headers && typeof headers === "object") {
                for (const key of Object.keys(headers))
                    xhr.setRequestHeader(key, headers[key])
            }
            xhr.send()
        } catch (e) {
            finish({ ok: false, error: "request" })
        }
    }

    function httpJson(url, trackSnapshot, callback, timeoutMs, headers) {
        httpRequest(url, trackSnapshot, res => {
            if (res.ok) {
                try {
                    res.data = JSON.parse(res.data)
                } catch (e) {
                    res.ok = false
                    res.error = "parse"
                }
            }
            callback(res)
        }, timeoutMs, headers)
    }

    function decodeBase64Utf8(input) {
        const text = String(input || "").replace(/\s/g, "")
        if (text === "")
            return ""
        const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
        let out = ""
        let i = 0
        while (i < text.length) {
            const e1 = chars.indexOf(text.charAt(i++))
            const e2 = chars.indexOf(text.charAt(i++))
            const e3 = chars.indexOf(text.charAt(i++))
            const e4 = chars.indexOf(text.charAt(i++))
            const bits = (e1 << 18) | (e2 << 12) | ((e3 < 0 ? 0 : e3) << 6) | (e4 < 0 ? 0 : e4)
            out += String.fromCharCode((bits >> 16) & 0xff)
            if (e3 !== 64 && e3 >= 0) out += String.fromCharCode((bits >> 8) & 0xff)
            if (e4 !== 64 && e4 >= 0) out += String.fromCharCode(bits & 0xff)
        }
        try { return decodeURIComponent(escape(out)) } catch (e) { return out }
    }

    function vttToLrc(vtt) {
        const lines = String(vtt || "").split(/\r?\n/)
        const out = []
        let pending = ""
        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            const cue = raw.match(/(\d{2}):(\d{2})[.,](\d{2,3})/)
            if (cue && raw.indexOf("-->") !== -1) {
                pending = "[" + cue[1] + ":" + cue[2] + "." + cue[3].padEnd(3, "0").slice(0, 3) + "]"
                continue
            }
            const body = raw.trim()
            if (pending !== "" && body !== "" && !/^\d+$/.test(body) && body.toUpperCase().indexOf("WEBVTT") !== 0) {
                out.push(pending + body)
                pending = ""
            }
        }
        return out.join("\n")
    }

    // =========================================================================
    // ENGINE TERJEMAHAN & ROMANISASI (ANTREAN BERTAHAP + MULTI API FALLBACK)
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

        const sameLanguage = root.detectedTrackLanguage !== ""
            && langCodesMatch(root.detectedTrackLanguage, translateTargetLanguage())

        for (let i = 0; i < linesArray.length; i++) {
            const line = (linesArray[i] || "").trim()
            if (line === "" || isInstrumentalText(line))
                continue

            // Bahasa sudah sama dengan target: tidak perlu terjemahan.
            // Baris non-Latin tetap lewat supaya romanisasi tetap tersedia.
            if (sameLanguage && !containsNonLatin(line))
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
        if (root.currentRawLyric !== "" && !root.isFallbackLine && !root.isInstrumentalLine) {
            enqueueTranslationLines([root.currentRawLyric], true)
        }
        const batch = []
        for (let i = 0; i < lyricModel.count; i++) {
            const item = lyricModel.get(i)
            if (!item.isInstrumental && item.rawText !== "" && (item.translatedText === "" || (containsNonLatin(item.rawText) && item.romanizedText === ""))) {
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
            const row = lyricModel.get(idx)
            if (!row.isInstrumental && row.rawText === origLine) {
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
        translateLineWithFallback(line, trackSnapshot, function(success, romText, transText) {
            root.isTranslatingNow = false
            if (trackSnapshot && root.currentTrackId !== trackSnapshot)
                return
            // Walau semua provider gagal, romanisasi lokal tetap dipakai.
            commitLineTranslationResult(line, romText, success ? transText : "", trackSnapshot)
            queuePaceTimer.start()
        })
    }

    function translateLineWithFallback(line, trackSnapshot, done) {
        const providers = [
            (s, cb) => fetchSingleLineGoogleTranslate(line, s, cb),
            (s, cb) => fetchSingleLineMyMemory(line, s, cb),
            (s, cb) => fetchSingleLineCustomTranslation(line, s, cb)
        ]
        let idx = 0
        let bestRom = ""

        const next = (rom, trans) => {
            if (rom) bestRom = rom
            if (trackSnapshot && root.currentTrackId !== trackSnapshot) {
                done(false, bestRom, "")
                return
            }
            // Baris Latin dari lagu yang sudah sebahasa dengan target tidak perlu
            // diterjemahkan. Baris non-Latin tetap diterjemahkan walaupun bahasa
            // utama terdeteksi sama (kasus lagu campur bahasa).
            if (root.detectedTrackLanguage !== ""
                && langCodesMatch(root.detectedTrackLanguage, translateTargetLanguage())
                && !containsNonLatin(line)) {
                done(bestRom !== "", bestRom, "")
                return
            }
            if (idx >= providers.length || trans !== "") {
                done(trans !== "", bestRom, trans)
                return
            }
            const provider = providers[idx++]
            provider(trackSnapshot, (ok, pRom, pTrans) => next(pRom, pTrans))
        }
        next("", "")
    }

    function translateTargetLanguage() {
        return root.translationTargetLanguage
    }

    function normalizeLangCode(code) {
        let c = String(code || "").toLowerCase().trim().replace(/_/g, "-")
        const aliases = {
            "in": "id",
            "iw": "he",
            "ji": "yi",
            "zh": "zh-cn",
            "zh-hans": "zh-cn",
            "zh-cn": "zh-cn"
        }
        return aliases[c] || c
    }

    function langCodesMatch(a, b) {
        const left = normalizeLangCode(a)
        const right = normalizeLangCode(b)
        if (left === "" || right === "")
            return false
        if (left === right)
            return true
        return left.split("-")[0] === right.split("-")[0]
    }

    function fetchSingleLineGoogleTranslate(line, trackSnapshot, callback) {
        const tl = encodeURIComponent(translateTargetLanguage())
        const url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" + tl + "&dt=t&dt=rm&q=" + encodeURIComponent(line)

        httpJson(url, trackSnapshot, res => {
            if (!res.ok || res.stale) {
                callback(false, "", "")
                return
            }
            const data = res.data
            const detectedLang = (data && data[2]) ? String(data[2]) : ""
            let translated = ""
            let romanized = ""

            if (data && Array.isArray(data[0])) {
                for (let i = 0; i < data[0].length; i++) {
                    const chunk = data[0][i]
                    if (chunk && typeof chunk[0] === "string") translated += chunk[0]
                    if (chunk && typeof chunk[3] === "string") romanized += chunk[3]
                }
            }

            const needRom = containsNonLatin(line)
            const plainRom = (needRom && romanized.trim() !== "") ? toPlainLatinAlphabet(romanized.trim()) : ""
            const finalRom = (plainRom !== "" && plainRom.toLowerCase() !== line.toLowerCase()) ? plainRom : ""

            const cleanTrans = translated.trim()
            const sameLanguage = detectedLang !== "" && langCodesMatch(detectedLang, translateTargetLanguage())

            if (sameLanguage) {
                const firstDetection = root.detectedTrackLanguage === ""
                // Satu baris Latin di tengah lagu Korea/Jepang/Arab tidak boleh
                // menimpa bahasa utama yang sudah terdeteksi dari baris non-Latin.
                if (firstDetection || containsNonLatin(line))
                    root.detectedTrackLanguage = normalizeLangCode(detectedLang)
                // Matikan tombol translate sekali saat bahasa lagu terdeteksi
                // sama dengan target. User masih bisa menyalakannya manual.
                if (firstDetection)
                    root.showTranslate = false
            }

            // Jangan minta provider lain menerjemahkan baris yang sudah
            // berada di bahasa target. Romanisasi tetap dikembalikan.
            callback(true, finalRom, (!sameLanguage && cleanTrans !== "") ? cleanTrans : "")
        }, 7000)
    }

    function guessSourceLanguage(line) {
        if (/[\u3040-\u30ff]/.test(line)) return "ja"
        if (/[\uac00-\ud7af]/.test(line)) return "ko"
        if (/[\u4e00-\u9fff]/.test(line)) return "zh-CN"
        if (/[\u0400-\u04ff]/.test(line)) return "ru"
        return "en"
    }

    function fetchSingleLineMyMemory(line, trackSnapshot, callback) {
        const target = translateTargetLanguage()
        const langPair = guessSourceLanguage(line) + "|" + target
        const url = "https://api.mymemory.translated.net/get?q=" + encodeURIComponent(line) + "&langpair=" + encodeURIComponent(langPair)

        httpJson(url, trackSnapshot, res => {
            if (!res.ok || res.stale) {
                callback(false, "", "")
                return
            }
            const data = res.data
            let trans = data && data.responseData ? String(data.responseData.translatedText || "").trim() : ""
            if (trans.toUpperCase().indexOf("MYMEMORY WARNING") !== -1)
                trans = ""
            callback(trans !== "", "", trans)
        }, 7000)
    }

    function fetchSingleLineCustomTranslation(line, trackSnapshot, callback) {
        const endpoint = Config.options.bar.lyricsWidget?.translation?.customEndpoint || ""
        if (endpoint.trim() === "") {
            callback(false, "", "")
            return
        }
        const sep = endpoint.indexOf("?") === -1 ? "?" : "&"
        const url = endpoint + sep + "q=" + encodeURIComponent(line) + "&target=" + encodeURIComponent(translateTargetLanguage())
        httpRequest(url, trackSnapshot, res => {
            if (!res.ok || res.stale) {
                callback(false, "", "")
                return
            }
            let trans = String(res.data || "").trim()
            try {
                const data = JSON.parse(res.data)
                trans = String(data.translatedText || data.translation || data.text || "").trim()
            } catch (e) {}
            callback(trans !== "", "", trans)
        }, 7000)
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
    // SUMBER EKSTERNAL LIRIK — BERANTAI DENGAN FALLBACK
    // =========================================================================
    readonly property var lyricProviderMap: ({
        lrclib: ctx => fetchLrclibLyrics(ctx, ctx.done),
        netease: ctx => fetchNetEaseLyrics(ctx, ctx.done),
        kugou: ctx => fetchKugouLyrics(ctx, ctx.done),
        musixmatch: ctx => fetchMusixmatchLyrics(ctx, ctx.done),
        subsonic: ctx => fetchSubsonicLyrics(ctx, ctx.done),
        jellyfin: ctx => fetchJellyfinLyrics(ctx, ctx.done),
        applemusic: ctx => fetchAppleMusicLyrics(ctx, ctx.done),
        youtubemusic: ctx => fetchYouTubeMusicLyrics(ctx, ctx.done)
    })

    // Cache lintas lagu: begitu sebuah lagu pernah diambil, lirik lengkapnya
    // langsung dipakai saat lagu itu diputar lagi tanpa menunggu jaringan.
    property var lyricsPrefetchCache: ({})
    property string activeLyricsCacheKey: ""
    readonly property int maxCachedLyricsTracks: 32

    function lyricsCacheKey(title, artist, album) {
        return [
            normalizeLyricMatchKey(title),
            normalizeLyricMatchKey(artist),
            normalizeLyricMatchKey(album)
        ].join("|")
    }

    function readCachedLyrics(key) {
        if (!key || key === "||")
            return null
        const memory = root.lyricsPrefetchCache[key]
        if (memory && Array.isArray(memory.entries) && memory.entries.length > 0)
            return memory

        const stored = Persistent.states && Persistent.states.lyricCache
            ? Persistent.states.lyricCache[key]
            : null
        if (!stored)
            return null
        try {
            const payload = typeof stored === "string" ? JSON.parse(stored) : stored
            if (payload && Array.isArray(payload.entries) && payload.entries.length > 0) {
                root.lyricsPrefetchCache = Object.assign({}, root.lyricsPrefetchCache, {
                    [key]: payload
                })
                return payload
            }
        } catch (e) {}
        return null
    }

    function writeCachedLyrics(key, entries, priority) {
        if (!key || key === "||" || !entries || entries.length === 0)
            return
        const previous = readCachedLyrics(key)
        if (previous && (previous.priority || 0) > priority)
            return

        const payload = {
            priority: priority || 0,
            entries: entries,
            savedAt: Date.now()
        }
        let memory = Object.assign({}, root.lyricsPrefetchCache)
        memory[key] = payload

        if (Persistent.ready) {
            const current = Persistent.states.lyricCache
            const cache = (current && typeof current === "object" && !Array.isArray(current))
                ? Object.assign({}, current)
                : {}
            cache[key] = JSON.stringify(payload)
            const keys = Object.keys(cache)
            if (keys.length > root.maxCachedLyricsTracks) {
                keys.slice(0, keys.length - root.maxCachedLyricsTracks).forEach(oldKey => {
                    delete cache[oldKey]
                    delete memory[oldKey]
                })
            }
            Persistent.states.lyricCache = cache
        }
        root.lyricsPrefetchCache = memory
    }

    // Metadata MPRIS sering datang bertahap (judul dulu, durasi kemudian).
    // Fetch ditunda sebentar supaya query tidak memakai metadata setengah jadi.
    Timer {
        id: lyricsPrefetchTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.currentTrackId || !root.trackTitle)
                return
            if (root.isLoadingLyrics)
                return
            if (root.hasSyncedLrc && root.lrcSourcePriority >= 2)
                return
            fetchExternalLyrics(root.trackTitle, root.trackArtist, root.trackAlbum,
                root.trackDurationSec, root.lrcSourcePriority)
        }
    }

    function prepareLyricsForCurrentTrack() {
        if (!root.currentTrackId)
            return
        root.activeLyricsCacheKey = lyricsCacheKey(root.trackTitle, root.trackArtist, root.trackAlbum)
        const cached = readCachedLyrics(root.activeLyricsCacheKey)
        // Cache priority 5 berasal dari lirik native Sonora. Saat player
        // berganti ke yang lain, cache itu tidak boleh dipakai: LRCLIB harus
        // langsung menjadi satu-satunya sumber eksternal.
        const cachedUsable = cached && cached.entries.length > 0
            && (root.activePlayerIsSonora || (cached.priority || 1) < 5)
        if (cachedUsable) {
            applyParsedLyricsToModel(cached.entries, cached.priority || 1, root.currentTrackId)
            root.lyricsNotFound = false
        } else {
            showFallbackLine()
        }
        lyricsPrefetchTimer.restart()
    }

    function fetchExternalLyrics(title, artist, album, durationSec, minPriority) {
        if (!title)
            return

        lyricsPrefetchTimer.stop()
        retryLyricsFetchTimer.stop()
        root.lrcSourcePriority = minPriority || 0
        root.lyricsNotFound = false
        root.isLoadingLyrics = true
        const trackSnapshot = root.currentTrackId
        // Sonora memakai sheet liriknya sendiri + rantai fallback bawaan.
        // Untuk player lain, permintaan langsung ditujukan ke LRCLIB saja.
        const order = root.activePlayerIsSonora
            ? (Config.options.bar.lyricsWidget?.sourceOrder || [])
            : ["lrclib"]
        const ctx = {
            title: title,
            artist: artist || "",
            album: album || "",
            durationSec: durationSec || 0,
            trackSnapshot: trackSnapshot,
            cacheKey: lyricsCacheKey(title, artist, album),
            done: null,
            completed: false
        }
        root.lyricFetchContext = ctx
        root.lastFetchDurationSec = ctx.durationSec
        root.lastFetchTrackId = trackSnapshot
        tryLyricProvider(0, order, ctx)
    }

    property var lyricFetchContext: null
    // Rantai sumber gagal di awal bisa diulang beberapa kali: penyedia sering
    // baru punya data setelah lagu berjalan beberapa detik.
    property int lyricFetchAttempt: 0
    readonly property int maxLyricFetchAttempts: 2

    Timer {
        id: retryLyricsFetchTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.hasSyncedLrc || root.isLoadingLyrics)
                return
            if (!root.currentTrackId || root.currentTrackId !== root.lastFetchTrackId)
                return
            root.lyricFetchAttempt++
            fetchExternalLyrics(root.trackTitle, root.trackArtist, root.trackAlbum,
                root.trackDurationSec, root.lrcSourcePriority)
        }
    }

    function retryLyricsFetchIfNeeded() {
        const id = root.currentTrackId
        if (!id || id !== root.lastFetchTrackId)
            return
        if (root.isLoadingLyrics)
            return
        if (root.hasSyncedLrc && root.lrcSourcePriority >= 2)
            return
        const dur = root.trackDurationSec
        if (Math.abs(dur - root.lastFetchDurationSec) < 0.5)
            return
        fetchExternalLyrics(root.trackTitle, root.trackArtist, root.trackAlbum, dur,
            root.lrcSourcePriority)
    }

    function markLyricsNotFound() {
        if (!root.sessionActive && !root.hasActivePlayer)
            return
        root.isLoadingLyrics = false
        if (!root.hasSyncedLrc && lyricModel.count === 0)
            root.lyricsNotFound = true
        // Baris live Sonora tidak menghalangi pencarian ulang: begitu sumber
        // lain berhasil, model akan ditimpa lirik tersinkron yang baru.
        if (!root.hasSyncedLrc && root.lyricFetchAttempt < root.maxLyricFetchAttempts) {
            retryLyricsFetchTimer.stop()
            retryLyricsFetchTimer.restart()
        }
    }

    function tryLyricProvider(index, order, ctx) {
        if (!ctx || ctx.completed || ctx.trackSnapshot && root.currentTrackId !== ctx.trackSnapshot)
            return
        if (root.hasSyncedLrc)
            return
        if (index >= order.length) {
            markLyricsNotFound()
            return
        }

        const name = String(order[index] || "").toLowerCase()
        const provider = root.lyricProviderMap[name]
        if (!provider) {
            tryLyricProvider(index + 1, order, ctx)
            return
        }

        // Settled mencegah callback terlambat dari sumber sebelumnya melompati
        // sumber berikutnya. Gagal/kosong selalu lanjut, sukses penuh (word
        // timing) menghentikan pencarian.
        let settled = false
        const finish = (ok, priority) => {
            if (settled || !ctx || ctx.completed)
                return
            settled = true
            if (ctx.trackSnapshot && root.currentTrackId !== ctx.trackSnapshot)
                return
            if (ok && priority >= 2) {
                ctx.completed = true
                return
            }
            tryLyricProvider(index + 1, order, ctx)
        }
        ctx.done = finish
        provider(ctx)
    }

    function commitLyricResult(entries, priority, ctx, done) {
        // Metadata LRC atau blok "[Instrumental]" saja bukan lirik: anggap gagal
        // agar sumber berikutnya tetap dicoba.
        const hasVocalLine = (entries || []).some(e => e && !e.isInstrumental && (e.rawText || "").trim() !== "")
        if (!hasVocalLine || !ctx || ctx.trackSnapshot && root.currentTrackId !== ctx.trackSnapshot) {
            if (done) done(false, priority)
            return false
        }
        if (priority <= root.lrcSourcePriority) {
            if (done) done(false, priority)
            return false
        }
        writeCachedLyrics(ctx.cacheKey || lyricsCacheKey(ctx.title, ctx.artist, ctx.album),
            entries, priority)
        applyParsedLyricsToModel(entries, priority, ctx.trackSnapshot)
        if (done) done(true, priority)
        return true
    }

    function queryText(s, extra) {
        return (String(s || "") + " " + String(extra || "")).trim()
    }

    function fetchNetEaseLyrics(ctx, done) {
        const query = encodeURIComponent(queryText(ctx.artist, ctx.title))
        const searchUrl = "https://music.163.com/api/search/get/web?s=" + query + "&type=1&limit=8"

        httpJson(searchUrl, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale) {
                done(false, 0)
                return
            }
            const songs = res.data && res.data.result ? res.data.result.songs : null
            if (!Array.isArray(songs) || songs.length === 0) {
                done(false, 0)
                return
            }

            let chosenId = -1
            if (ctx.durationSec > 0) {
                let bestDiff = 999999
                for (let i = 0; i < songs.length; i++) {
                    const songDurSec = (songs[i].duration || 0) / 1000.0
                    if (songDurSec > 0) {
                        const diff = Math.abs(songDurSec - ctx.durationSec)
                        if (diff < bestDiff) {
                            bestDiff = diff
                            chosenId = songs[i].id
                        }
                    }
                }
                if (bestDiff > 9.0) chosenId = -1
            } else {
                chosenId = songs[0].id
            }

            if (chosenId === -1) {
                done(false, 0)
                return
            }
            fetchNetEaseSongLyricById(chosenId, ctx, done)
        })
    }

    function fetchNetEaseSongLyricById(songId, ctx, done) {
        if (!songId) {
            done(false, 0)
            return
        }
        const url = "https://music.163.com/api/song/lyric?id=" + songId + "&lv=1&kv=1&tv=-1&yv=1"
        httpJson(url, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale) {
                done(false, 0)
                return
            }
            const data = res.data
            if (data && data.yrc && data.yrc.lyric) {
                const yrcParsed = parseNetEaseYrc(data.yrc.lyric)
                if (commitLyricResult(yrcParsed, 2, ctx, done)) return
            }
            if (data && data.lrc && data.lrc.lyric) {
                const lrcParsed = parseLrcToEntries(data.lrc.lyric)
                commitLyricResult(lrcParsed, 1, ctx, done)
                return
            }
            done(false, 0)
        })
    }

    function enrichEntriesWithInstrumentalBreaks(sortedEntries) {
        if (!sortedEntries || sortedEntries.length === 0)
            return []

        const expanded = []

        // Intro instrumental: beri entri kosong sejak 0 agar vokal tidak muncul duluan.
        if (sortedEntries[0].timeSec >= 1.0 && !sortedEntries[0].isInstrumental) {
            expanded.push({
                timeSec: 0.0,
                endSec: sortedEntries[0].timeSec,
                explicitEndSec: sortedEntries[0].timeSec,
                rawText: "Opening",
                romanizedText: "",
                translatedText: "",
                wordTimingsJson: "",
                isInstrumental: true
            })
        }

        for (let k = 0; k < sortedEntries.length; k++) {
            const cur = sortedEntries[k]
            const nextStart = (k + 1 < sortedEntries.length) ? sortedEntries[k + 1].timeSec : -1

            if (!cur.isInstrumental && cur.explicitEndSec > cur.timeSec && nextStart > cur.timeSec) {
                cur.explicitEndSec = Math.min(cur.explicitEndSec, nextStart - 0.05)
            }

            if (cur.isInstrumental) {
                if (nextStart > 0 && (nextStart - cur.timeSec) < 2.5) {
                    if (expanded.length > 0)
                        expanded[expanded.length - 1].endSec = nextStart
                    continue
                }
                cur.endSec = nextStart
                expanded.push(cur)
                continue
            }

            const estVocalDur = estimateNaturalVocalDurationSec(cur.rawText)
            const vocalEnd = (cur.explicitEndSec > cur.timeSec)
                ? cur.explicitEndSec
                : (cur.timeSec + estVocalDur)

            if (nextStart > 0 && !sortedEntries[k + 1].isInstrumental && (nextStart - cur.timeSec) >= 11.0 && (nextStart - vocalEnd) >= 5.5) {
                const breakStart = Math.max(vocalEnd + 1.0, cur.timeSec + 5.0)
                cur.endSec = breakStart
                expanded.push(cur)
                expanded.push({
                    timeSec: breakStart,
                    endSec: nextStart,
                    explicitEndSec: nextStart,
                    rawText: "Instrumental",
                    romanizedText: "",
                    translatedText: "",
                    wordTimingsJson: "",
                    isInstrumental: true
                })
            } else {
                cur.endSec = nextStart
                expanded.push(cur)
            }
        }

        const trackLen = root.trackDurationSec
        if (expanded.length > 0 && trackLen > 0) {
            const last = expanded[expanded.length - 1]
            if (!last.isInstrumental) {
                const lastVocalEnd = (last.explicitEndSec > last.timeSec)
                    ? last.explicitEndSec
                    : (last.timeSec + estimateNaturalVocalDurationSec(last.rawText))
                if (trackLen - lastVocalEnd >= 7.5) {
                    const outroStart = lastVocalEnd + 1.0
                    last.endSec = outroStart
                    expanded.push({
                        timeSec: outroStart,
                        endSec: trackLen,
                        explicitEndSec: trackLen,
                        rawText: "Outro",
                        romanizedText: "",
                        translatedText: "",
                        wordTimingsJson: "",
                        isInstrumental: true
                    })
                }
            }
        }

        const finalized = []
        for (let m = 0; m < expanded.length; m++) {
            const item = expanded[m]
            if (item.isInstrumental && finalized.length > 0 && finalized[finalized.length - 1].isInstrumental) {
                finalized[finalized.length - 1].endSec = item.endSec
                continue
            }
            finalized.push(item)
        }

        return finalized
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
            if (isInstrumentalText(cleanText)) {
                parsed.push({
                    timeSec: lineStartSec,
                    endSec: lineStartSec + Math.max(0.4, lineDurSec),
                    explicitEndSec: lineStartSec + Math.max(0.4, lineDurSec),
                    rawText: cleanText !== "" ? cleanText : "Instrumental",
                    romanizedText: "",
                    translatedText: "",
                    wordTimingsJson: "",
                    isInstrumental: true
                })
            } else if (cleanText !== "" && rawWords.length > 0) {
                const totalLen = Math.max(1, fullLine.length)
                const normalizedWords = rawWords.map(w => ({
                    relStart: w.relStart,
                    relEnd: w.relEnd,
                    ratioStart: w.charStart / totalLen,
                    ratioEnd: w.charEnd / totalLen
                }))
                const explicitEnd = lineStartSec + Math.max(0.4, lineDurSec)
                parsed.push({
                    timeSec: lineStartSec,
                    endSec: explicitEnd,
                    explicitEndSec: explicitEnd,
                    rawText: cleanText,
                    romanizedText: instantLocalRomanize(cleanText),
                    translatedText: "",
                    wordTimingsJson: JSON.stringify(normalizedWords),
                    isInstrumental: false
                })
            }
        }
        parsed.sort((a, b) => a.timeSec - b.timeSec)
        return enrichEntriesWithInstrumentalBreaks(parsed)
    }

    function fetchLrclibLyrics(ctx, done) {
        let url = "https://lrclib.net/api/get?track_name=" + encodeURIComponent(ctx.title)
        if (ctx.artist) url += "&artist_name=" + encodeURIComponent(ctx.artist)
        if (ctx.album) url += "&album_name=" + encodeURIComponent(ctx.album)
        if (ctx.durationSec > 0) url += "&duration=" + Math.round(ctx.durationSec)

        httpJson(url, ctx.trackSnapshot, res => {
            if (res.stale) return
            if (res.ok && res.data && res.data.syncedLyrics) {
                const entries = parseLrcToEntries(res.data.syncedLyrics)
                const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                if (commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)) return
            }
            searchLrclibLyrics(ctx, done)
        })
    }

    function searchLrclibLyrics(ctx, done) {
        const cleanTitle = ctx.title.replace(/\s*[\[(](official|lyrics|audio|video|mv|hd|4k)[^\])]*[\])]/gi, "").trim()
        const q = encodeURIComponent(queryText(ctx.artist, cleanTitle))
        httpJson("https://lrclib.net/api/search?q=" + q, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale) {
                done(false, 0)
                return
            }
            const list = res.data
            if (!Array.isArray(list)) {
                done(false, 0)
                return
            }
            let bestItem = null
            let bestDiff = 999999
            for (let i = 0; i < list.length; i++) {
                if (!list[i].syncedLyrics) continue
                if (ctx.durationSec > 0 && list[i].duration > 0) {
                    const diff = Math.abs(list[i].duration - ctx.durationSec)
                    if (diff < bestDiff) {
                        bestDiff = diff
                        bestItem = list[i]
                    }
                } else if (!bestItem) {
                    bestItem = list[i]
                }
            }
            if (!bestItem || (ctx.durationSec > 0 && bestDiff > 9.0)) {
                done(false, 0)
                return
            }
            const entries = parseLrcToEntries(bestItem.syncedLyrics)
            const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
            commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)
        })
    }

    // --- Kugou (endpoint publik, tidak butuh login) ---
    function fetchKugouLyrics(ctx, done) {
        const keyword = encodeURIComponent(queryText(ctx.artist, ctx.title))
        const durationMs = Math.max(0, Math.round(ctx.durationSec * 1000))
        const searchUrl = "https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=" + keyword + "&duration=" + durationMs

        httpJson(searchUrl, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale || !res.data || !Array.isArray(res.data.candidates) || res.data.candidates.length === 0) {
                done(false, 0)
                return
            }
            let best = res.data.candidates[0]
            let bestDiff = 999999
            for (const cand of res.data.candidates) {
                const diff = Math.abs(Number(cand.duration || 0) - durationMs)
                if (diff < bestDiff) {
                    bestDiff = diff
                    best = cand
                }
            }
            if (!best.id || !best.accesskey) {
                done(false, 0)
                return
            }
            const dl = "https://lyrics.kugou.com/download?ver=1&client=pc&id=" + encodeURIComponent(best.id)
                + "&accesskey=" + encodeURIComponent(best.accesskey)
                + "&format=lrc&content=" + encodeURIComponent(best.contentid || "")
                + "&hash=" + encodeURIComponent(best.hash || "")
            httpJson(dl, ctx.trackSnapshot, dlRes => {
                if (!dlRes.ok || dlRes.stale || !dlRes.data || !dlRes.data.content) {
                    done(false, 0)
                    return
                }
                const lrc = decodeBase64Utf8(dlRes.data.content)
                const entries = parseLrcToEntries(lrc)
                const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)
            })
        })
    }

    // --- Musixmatch (token web publik, bisa ditimpa di config) ---
    function fetchMusixmatchLyrics(ctx, done) {
        const creds = Config.options.bar.lyricsWidget?.credentials || ({})
        const token = creds.musixmatchToken || "20052115310630bcb171d09f9e09f491"
        const base = "https://www.musixmatch.com/ws/1.1/"
        const searchUrl = base + "track.search?q_track=" + encodeURIComponent(ctx.title)
            + "&q_artist=" + encodeURIComponent(ctx.artist)
            + "&page_size=3&s_track_rating=desc&quorum_factor=1&apikey=" + encodeURIComponent(token)

        httpJson(searchUrl, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale || !res.data) {
                done(false, 0)
                return
            }
            let tracks = []
            try { tracks = res.data.message.body.track_list || [] } catch (e) {}
            if (!Array.isArray(tracks) || tracks.length === 0) {
                done(false, 0)
                return
            }
            const trackId = tracks[0].track.track_id
            if (!trackId) {
                done(false, 0)
                return
            }
            const subUrl = base + "track.subtitles.get?track_id=" + encodeURIComponent(trackId)
                + "&subtitle_format=lrc&apikey=" + encodeURIComponent(token)
            httpJson(subUrl, ctx.trackSnapshot, subRes => {
                if (!subRes.ok || subRes.stale || !subRes.data) {
                    done(false, 0)
                    return
                }
                try {
                    const body = subRes.data.message.body.subtitle
                    const raw = body && body.subtitle_body ? decodeBase64Utf8(body.subtitle_body) : ""
                    if (raw.trim() === "") {
                        done(false, 0)
                        return
                    }
                    const entries = parseLrcToEntries(raw)
                    const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                    commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)
                } catch (e) {
                    done(false, 0)
                }
            })
        })
    }

    // --- Subsonic (butuh URL/user/password di config) ---
    function fetchSubsonicLyrics(ctx, done) {
        const creds = Config.options.bar.lyricsWidget?.credentials || ({})
        if (!creds.subsonicUrl || !creds.subsonicUser || !creds.subsonicPassword) {
            done(false, 0)
            return
        }
        const base = String(creds.subsonicUrl).replace(/\/+$/, "")
        const url = base + "/rest/getLyrics.view"
            + "?u=" + encodeURIComponent(creds.subsonicUser)
            + "&p=" + encodeURIComponent(creds.subsonicPassword)
            + "&v=1.16.1&c=quickshell&f=json"
            + "&artist=" + encodeURIComponent(ctx.artist)
            + "&title=" + encodeURIComponent(ctx.title)

        httpJson(url, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale || !res.data) {
                done(false, 0)
                return
            }
            const data = res.data["subsonic-response"] || {}
            const text = data.lyrics && data.lyrics.lyricsText ? String(data.lyrics.lyricsText) : ""
            if (text.indexOf("[") === -1) {
                done(false, 0)
                return
            }
            const entries = parseLrcToEntries(text)
            const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
            commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)
        })
    }

    // --- Jellyfin (butuh URL + token di config) ---
    function fetchJellyfinLyrics(ctx, done) {
        const creds = Config.options.bar.lyricsWidget?.credentials || ({})
        if (!creds.jellyfinUrl || !creds.jellyfinToken) {
            done(false, 0)
            return
        }
        const base = String(creds.jellyfinUrl).replace(/\/+$/, "")
        const q = encodeURIComponent(queryText(ctx.artist, ctx.title))
        const searchUrl = base + "/Items?SearchTerms=" + q + "&IncludeItemTypes=Audio&Limit=5&api_key=" + encodeURIComponent(creds.jellyfinToken)

        httpJson(searchUrl, ctx.trackSnapshot, res => {
            if (!res.ok || res.stale || !res.data || !res.data.Items || res.data.Items.length === 0) {
                done(false, 0)
                return
            }
            const item = res.data.Items[0]
            const lyricUrl = base + "/Items/" + encodeURIComponent(item.Id) + "/Lyrics?api_key=" + encodeURIComponent(creds.jellyfinToken)
            httpRequest(lyricUrl, ctx.trackSnapshot, lyricRes => {
                if (!lyricRes.ok || lyricRes.stale) {
                    done(false, 0)
                    return
                }
                let text = String(lyricRes.data || "")
                if (text.trim().indexOf("{") === 0) {
                    try {
                        const obj = JSON.parse(text)
                        text = String(obj.Lyrics || obj.lyrics || "")
                    } catch (e) {}
                }
                if (text.indexOf("[") === -1) {
                    done(false, 0)
                    return
                }
                const entries = parseLrcToEntries(text)
                const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)
            })
        })
    }

    // --- Apple Music (butuh developer token di config) ---
    function fetchAppleMusicLyrics(ctx, done) {
        const creds = Config.options.bar.lyricsWidget?.credentials || ({})
        if (!creds.appleMusicToken) {
            done(false, 0)
            return
        }
        const q = encodeURIComponent(queryText(ctx.artist, ctx.title))
        httpJson("https://itunes.apple.com/search?term=" + q + "&entity=song&limit=3", ctx.trackSnapshot, res => {
            if (!res.ok || res.stale || !res.data || !res.data.results || res.data.results.length === 0) {
                done(false, 0)
                return
            }
            const songId = res.data.results[0].trackId
            if (!songId) {
                done(false, 0)
                return
            }
            const headers = { Authorization: "Bearer " + creds.appleMusicToken }
            const url = "https://api.music.apple.com/v1/catalog/us/songs/" + encodeURIComponent(songId) + "/lyrics"
            httpJson(url, ctx.trackSnapshot, lyricRes => {
                if (!lyricRes.ok || lyricRes.stale || !lyricRes.data) {
                    done(false, 0)
                    return
                }
                try {
                    let raw = lyricRes.data.attributes && lyricRes.data.attributes.lyrics
                    if (Array.isArray(raw)) raw = raw.map(x => x.text || "").join("\n")
                    else if (raw && typeof raw === "object") raw = raw.text || ""
                    raw = String(raw || "")
                    if (raw.indexOf("[") === -1) {
                        done(false, 0)
                        return
                    }
                    const entries = parseLrcToEntries(raw)
                    const hasWords = entries.length > 0 && entries[0].wordTimingsJson !== ""
                    commitLyricResult(entries, hasWords ? 2 : 1, ctx, done)
                } catch (e) {
                    done(false, 0)
                }
            }, 8000, headers)
        })
    }

    // --- YouTube Music lewat Invidious/Piped (butuh base URL di config) ---
    function fetchYouTubeMusicLyrics(ctx, done) {
        const creds = Config.options.bar.lyricsWidget?.credentials || ({})
        if (!creds.youTubeMusicApi) {
            done(false, 0)
            return
        }
        const base = String(creds.youTubeMusicApi).replace(/\/+$/, "")
        const q = encodeURIComponent(queryText(ctx.artist, ctx.title))
        httpJson(base + "/api/v1/search?q=" + q + "&type=video&sort_by=relevance", ctx.trackSnapshot, res => {
            if (!res.ok || res.stale || !Array.isArray(res.data) || res.data.length === 0) {
                done(false, 0)
                return
            }
            const videoId = res.data[0].videoId
            if (!videoId) {
                done(false, 0)
                return
            }
            httpJson(base + "/api/v1/captions/" + encodeURIComponent(videoId), ctx.trackSnapshot, capRes => {
                if (!capRes.ok || capRes.stale || !Array.isArray(capRes.data) || capRes.data.length === 0) {
                    done(false, 0)
                    return
                }
                let cap = capRes.data[0]
                for (const c of capRes.data) {
                    const label = String(c.label || c.languageCode || "").toLowerCase()
                    if (label.indexOf("lyric") !== -1) { cap = c; break }
                }
                if (!cap || !cap.url) {
                    done(false, 0)
                    return
                }
                const captionUrl = String(cap.url).indexOf("http") === 0 ? cap.url : base + cap.url
                httpRequest(captionUrl, ctx.trackSnapshot, vttRes => {
                    if (!vttRes.ok || vttRes.stale) {
                        done(false, 0)
                        return
                    }
                    const entries = parseLrcToEntries(vttToLrc(vttRes.data))
                    if (entries.length === 0) {
                        done(false, 0)
                        return
                    }
                    commitLyricResult(entries, 1, ctx, done)
                })
            })
        })
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

            if (timestamps.length === 0)
                continue

            const bodyWithoutLineTags = raw.replace(lineTimeRegex, "").trim()

            if (isInstrumentalText(bodyWithoutLineTags)) {
                for (let t0 = 0; t0 < timestamps.length; t0++) {
                    parsed.push({
                        timeSec: timestamps[t0],
                        endSec: -1,
                        explicitEndSec: -1,
                        rawText: bodyWithoutLineTags !== "" ? bodyWithoutLineTags : "Instrumental",
                        romanizedText: "",
                        translatedText: "",
                        wordTimingsJson: "",
                        isInstrumental: true
                    })
                }
                continue
            }

            let cleanText = bodyWithoutLineTags
            let wordTimingsJson = ""
            let explicitLineEndRelSec = -1
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
                    const lastWord = rawWords[rawWords.length - 1]
                    const tailSec = Math.max(0.2, Math.min(1.2, (lastWord.charEnd - lastWord.charStart) * 0.16))
                    explicitLineEndRelSec = Math.max(0.0, lastWord.startSec - baseLineT) + tailSec
                }
            }

            const isInst = isInstrumentalText(cleanText)
            const instantRom = isInst ? "" : instantLocalRomanize(cleanText)
            for (let t = 0; t < timestamps.length; t++) {
                parsed.push({
                    timeSec: timestamps[t],
                    endSec: -1,
                    explicitEndSec: (!isInst && explicitLineEndRelSec > 0) ? timestamps[t] + explicitLineEndRelSec : -1,
                    rawText: isInst ? (cleanText !== "" ? cleanText : "Instrumental") : cleanText,
                    romanizedText: instantRom,
                    translatedText: "",
                    wordTimingsJson: isInst ? "" : wordTimingsJson,
                    isInstrumental: isInst
                })
            }
        }

        parsed.sort((a, b) => a.timeSec - b.timeSec)
        return enrichEntriesWithInstrumentalBreaks(parsed)
    }

    function applyParsedLyricsToModel(entries, priority, trackSnapshot) {
        if (!entries || entries.length === 0 || root.currentTrackId !== trackSnapshot)
            return

        retryLyricsFetchTimer.stop()
        root.lrcSourcePriority = priority
        root.lyricsNotFound = false
        root.isLoadingLyrics = false
        lyricModel.clear()
        const linesToQueue = []
        for (let j = 0; j < entries.length; j++) {
            const entry = entries[j]
            if (!entry.isInstrumental) {
                const cached = root.lineCache[entry.rawText]
                if (cached) {
                    if (cached.romanizedText !== "")
                        entry.romanizedText = cached.romanizedText
                    entry.translatedText = cached.translatedText
                }
                if (entry.translatedText === "") {
                    linesToQueue.push(entry.rawText)
                }
            }
            lyricModel.append(entry)
        }
        root.hasSyncedLrc = true
        root.lastLiveLineWallMs = 0.0
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
            if (item.isInstrumental)
                continue
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
            const lookupPos = calPos
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
            if (!root.hasSyncedLrc && root.currentTrackId !== "")
                prepareLyricsForCurrentTrack()
            else if (displayedRawText === "" && !isInstrumentalLine)
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
                root.lyricsNotFound = false
                root.lyricFetchAttempt = 0
                retryLyricsFetchTimer.stop()
                root.isInstrumentalLine = false
                root.isExpanded = false
                lyricModel.clear()
                root.activeLyricIndex = -1
                root.hasSyncedLrc = false
                root.lrcSourcePriority = 0
                root.movingPosTicks = 0
                root.lastReportedPos = -1.0
                root.pendingJumpPos = -1.0
                root.fallbackTrackLengthSec = 0.0
                root.sliderDisplayPosSec = 0.0
                root.karaokeProgress = 0.0
                root.translationQueue = []
                root.queuedSet = ({})
                root.isTranslatingNow = false
                root.detectedTrackLanguage = ""
            }
        }
    }

    // Bersihkan semua jejak lagu sebelumnya, termasuk slot compact yang
    // menampilkan teks. Model saja tidak cukup: slot bisa menyimpan lirik lama
    // sampai fetch lagu baru selesai.
    function resetLyricsForTrackChange() {
        keepAliveTimer.stop()
        confirmSeekTimer.stop()
        sessionActive = true
        currentRawLyric = ""
        displayedRawText = ""
        displayedRomanized = ""
        displayedTranslation = ""
        isFallbackLine = true
        isInstrumentalLine = false
        isLoadingLyrics = true
        lyricsNotFound = false
        lyricFetchAttempt = 0
        retryLyricsFetchTimer.stop()
        hasSyncedLrc = false
        lrcSourcePriority = 0
        activeLyricIndex = -1
        activeLineStartSec = 0.0
        activeLineDurationSec = 3.0
        activeWordTimings = []
        lineCache = ({})
        translationQueue = []
        queuedSet = ({})
        isTranslatingNow = false
        activeQueueTrackId = currentTrackId
        activeLyricsCacheKey = ""
        lyricFetchContext = null
        lastFetchTrackId = ""
        nativeLrcAttemptedTrackId = ""
        nativeBridgeRequestedTrackId = ""
        nativeLrcPendingTrackId = ""
        lastAnimatedLyricIndex = -1
        lyricSlideDirection = 1
        trackChangeWallMs = Date.now()
        posQueryTrackId = currentTrackId
        pendingJumpPos = -1.0
        movingPosTicks = 0
        lastReportedPos = -1.0
        anchorPlayerPos = 0.0
        anchorWallMs = Date.now()
        fallbackTrackLengthSec = 0.0
        sliderDisplayPosSec = 0.0
        karaokeProgress = 0.0
        lastFallbackLineMs = 0
        lastFallbackCharCount = 0
        adaptiveMsPerChar = 72.0
        lastLiveLineWallMs = 0.0
        lastFetchDurationSec = -1.0
        detectedTrackLanguage = ""
        lyricModel.clear()

        // Matikan kedua slot sebelum transisi baru supaya tidak ada teks lama
        // yang ikut tersisa saat crossfade.
        const slotA = slotALoader.item
        const slotB = slotBLoader.item
        if (slotA) {
            slotA.slideReady = false
            slotA.active = false
            slotA.rawText = ""
            slotA.romanizedText = ""
            slotA.translatedText = ""
        }
        if (slotB) {
            slotB.slideReady = false
            slotB.active = false
            slotB.rawText = ""
            slotB.romanizedText = ""
            slotB.translatedText = ""
        }

        syncClockAnchor(true)
        showFallbackLine()
    }

    onCurrentTrackIdChanged: {
        if (currentTrackId !== "") {
            resetLyricsForTrackChange()
            prepareLyricsForCurrentTrack()
        }
    }

    function showFallbackLine() {
        // Awal lagu sering berisi intro instrumental. Jangan tampilkan teks
        // berbentuk lirik sebelum ada timestamp vokal pertama.
        const pos = getCalibratedPositionSec()
        if (!root.hasSyncedLrc && pos < 1.25) {
            transitionToText("Opening", "", "", false, true)
            return
        }
        const fallback = trackTitle !== "" ? ("♪ " + trackTitle) : "Memuat lirik..."
        transitionToText(fallback, "", "", true, false)
    }

    function transitionToText(rawText, romText, transText, isFallback, isInstrumental) {
        const instFlag = Boolean(isInstrumental)
        if (rawText === root.displayedRawText
            && romText === root.displayedRomanized
            && transText === root.displayedTranslation
            && isFallback === root.isFallbackLine
            && instFlag === root.isInstrumentalLine)
            return

        // Tentukan arah geser sebelum state lirik ditimpa.
        const prevIdx = root.lastAnimatedLyricIndex
        const nextIdx = root.activeLyricIndex
        if (nextIdx >= 0 && prevIdx >= 0 && nextIdx !== prevIdx)
            root.lyricSlideDirection = nextIdx > prevIdx ? 1 : -1
        root.lastAnimatedLyricIndex = nextIdx

        root.displayedRawText = rawText
        root.displayedRomanized = romText
        root.displayedTranslation = transText
        root.isFallbackLine = isFallback
        root.isInstrumentalLine = instFlag
        root.karaokeProgress = (isFallback || instFlag) ? 1.0 : 0.0

        const slotA = slotALoader.item
        const slotB = slotBLoader.item
        if (!slotA || !slotB)
            return

        root.useSlotA = !root.useSlotA
        const incoming = root.useSlotA ? slotA : slotB
        const outgoing = root.useSlotA ? slotB : slotA
        const slideDist = root.compactSlideEnabled ? root.compactSlideDistance : 0
        const dir = root.lyricSlideDirection

        // Reset posisi tanpa animasi, lalu jalankan ease-in-out bersamaan
        // dengan crossfade opacity. Hanya aktif saat compact pill terlihat.
        incoming.slideReady = false
        outgoing.slideReady = false
        incoming.y = dir * slideDist
        outgoing.y = 0

        outgoing.active = false
        incoming.rawText = rawText
        incoming.romanizedText = romText
        incoming.translatedText = transText
        incoming.isFallback = isFallback
        incoming.isInstrumental = instFlag
        incoming.active = true

        incoming.slideReady = true
        outgoing.slideReady = true
        incoming.y = 0
        outgoing.y = -dir * slideDist

        if (!isFallback && !instFlag)
            updateKaraokeFrame(true)
    }

    function updateLyricLine(newLine) {
        // Jangan buang baris live hanya karena LRC tersinkron sudah ada.
        // Spotify sering punya intro instrumental panjang sebelum baris LRC
        // pertama; baris live Sonora tetap harus bisa menampilkan lirik di situ.
        if (isInstrumentalText(newLine)) {
            root.currentRawLyric = ""
            if (root.sessionActive || root.hasActivePlayer) {
                root.isLoadingLyrics = false
                transitionToText(newLine !== "" ? newLine : "Instrumental", "", "", false, true)
            }
            return
        }

        if (newLine === root.currentRawLyric && !root.isLoadingLyrics && !root.isInstrumentalLine)
            return

        queryPlayerctlPosition()
        const calPos = getCalibratedPositionSec()

        if (root.hasSyncedLrc) {
            const matchedIdx = findBestMatchingIndex(newLine, calPos)
            if (matchedIdx !== -1) {
                root.lastLiveLineWallMs = 0.0
                if (matchedIdx !== root.activeLyricIndex || root.isLoadingLyrics || root.isInstrumentalLine) {
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
        root.lyricsNotFound = false
        root.sessionActive = true

        const cached = root.lineCache[newLine]
        const instantRom = instantLocalRomanize(newLine)
        const initialRom = (cached && cached.romanizedText !== "") ? cached.romanizedText : instantRom
        const initialTrans = (cached && cached.translatedText !== "") ? cached.translatedText : ""
        const measureLen = Math.max(1, newLine.length, initialRom.length)
        const estDur = estimateNaturalVocalDurationSec(newLine)

        root.lastFallbackLineMs = nowMs
        root.lastFallbackCharCount = measureLen
        root.lastLiveLineWallMs = nowMs
        root.lineStartWallMs = nowMs
        root.pauseStartedWallMs = root.isPlaying ? 0.0 : nowMs
        // -1 membuat progres karaoke memakai wall clock untuk baris live,
        // bukan posisi absolut player (yang sudah jauh melewati awal baris).
        root.activeLineStartSec = -1.0
        root.activeLineDurationSec = estDur
        root.activeWordTimings = buildRelativeWordTimings(newLine, estDur)

        // Baris live yang tidak cocok dengan model (juga saat LRC sinkron
        // sudah ada) harus masuk ke model. Jika tidak, compact menampilkan
        // baris Sonora yang benar sementara expanded tetap menampilkan baris
        // lama dari LRC.
        if (lyricModel.count === 0 || lyricModel.get(lyricModel.count - 1).rawText !== newLine) {
            lyricModel.append({
                timeSec: -1,
                endSec: -1,
                explicitEndSec: -1,
                rawText: newLine,
                romanizedText: initialRom,
                translatedText: initialTrans,
                wordTimingsJson: "",
                isInstrumental: false
            })
        }
        root.activeLyricIndex = lyricModel.count - 1

        transitionToText(newLine, initialRom, initialTrans, false, false)

        if (!cached || cached.translatedText === "") {
            enqueueTranslationLines([newLine], true)
        }
    }

    // --- Sumber lirik utama: aplikasi musik yang sedang aktif ---
    // Sonora dibaca lewat bridge CLI + cache (ada word timing asli).
    // Player lain langsung memakai LRCLIB; cache native Sonora tidak
    // dipakai ulang saat player berganti.
    readonly property bool activePlayerIsSonora: root.activePlayerName.indexOf("sonora") !== -1
    // Sonora memakai id video sebagai track id. MPRIS Sonora menyimpannya di
    // xesam:url (?v=...), jadi ini dipakai untuk membuang jawaban lama.
    readonly property string expectedNativeTrackId: {
        if (!root.activePlayer)
            return ""
        const raw = String(root.activePlayer.metadata?.["xesam:url"] || "")
        const match = raw.match(/[?&]v=([^&#]+)/)
        if (match) {
            try {
                return decodeURIComponent(match[1])
            } catch (e) {
                return match[1]
            }
        }
        const clean = raw.split("?")[0].replace(/\/$/, "")
        return clean.slice(clean.lastIndexOf("/") + 1)
    }
    property string nativeLrcAttemptedTrackId: ""
    property string nativeBridgeRequestedTrackId: ""
    property string nativeLrcPendingTrackId: ""

    function applyNativeLyricsEntries(entries, priority) {
        if (!entries || entries.length === 0 || root.lrcSourcePriority >= priority)
            return
        root.applyParsedLyricsToModel(entries, priority, root.currentTrackId)
        root.writeCachedLyrics(
            root.lyricsCacheKey(root.trackTitle, root.trackArtist, root.trackAlbum),
            entries, priority)
    }

    function sonoraWordMap(words) {
        const map = ({})
        const list = Array.isArray(words) ? words : []
        for (let i = 0; i < list.length; i++) {
            const item = list[i] || {}
            const key = String(Math.round(Number(item.start_ms)))
            if (Array.isArray(item.words))
                map[key] = item.words
        }
        return map
    }

    // Word timing bisa datang setelah baris lirik dipasang. Patch ini
    // mengisi ulang model tanpa mengulang transisi/animasi baris.
    function patchKaraokeWordTimings(words) {
        const map = root.sonoraWordMap(words)
        if (Object.keys(map).length === 0)
            return
        let changed = false
        for (let i = 0; i < lyricModel.count; i++) {
            const item = lyricModel.get(i)
            if (item.wordTimingsJson && item.wordTimingsJson !== "")
                continue
            const key = String(Math.round(item.timeSec * 1000.0))
            if (map[key]) {
                lyricModel.setProperty(i, "wordTimingsJson", JSON.stringify(map[key]))
                changed = true
            }
        }
        if (!changed)
            return
        const idx = root.activeLyricIndex
        if (idx >= 0 && idx < lyricModel.count) {
            const active = lyricModel.get(idx)
            if (active.wordTimingsJson && active.wordTimingsJson !== "") {
                try {
                    root.activeWordTimings = JSON.parse(active.wordTimingsJson)
                } catch (e) {}
            }
        }
        const entries = []
        for (let j = 0; j < lyricModel.count; j++)
            entries.push(lyricModel.get(j))
        root.writeCachedLyrics(
            root.lyricsCacheKey(root.trackTitle, root.trackArtist, root.trackAlbum),
            entries, Math.max(5, root.lrcSourcePriority))
    }

    function handleActivePlayerLyrics(payload) {
        if (!payload || typeof payload !== "object" || !root.hasActivePlayer)
            return
        const data = (payload.lyrics && typeof payload.lyrics === "object") ? payload.lyrics : payload
        const trackId = root.currentTrackId
        if (!trackId)
            return

        // Jawaban process yang masih berjalan saat lagu berganti harus dibuang.
        // Tanpa ini, sheet lirik lagu lama bisa dipasang ke lagu baru.
        if (root.nativeBridgeRequestedTrackId !== ""
            && root.nativeBridgeRequestedTrackId !== trackId)
            return
        if (root.activePlayerIsSonora) {
            const reportedId = String(payload.trackId || "")
            const reportedTitle = String(payload.trackTitle || "")
            if (root.expectedNativeTrackId !== "" && reportedId !== ""
                && reportedId !== root.expectedNativeTrackId)
                return
            if (reportedTitle !== "" && root.trackTitle !== ""
                && reportedTitle !== root.trackTitle)
                return
        }

        const wordMap = root.sonoraWordMap(payload.words)
        const state = String(data.state || "").toLowerCase()
        if (state === "instrumental" || data.instrumental === true) {
            root.updateLyricLine(Translation.tr("Instrumental"))
            return
        }
        // Player belum punya jawaban: biarkan rantai fallback yang menampilkan
        // "Lyric not found" atau mencari dari penyedia lain.
        if (state !== "ready" && state !== "")
            return

        const lines = Array.isArray(data.lines) ? data.lines : []
        if (lines.length > 0 && root.lrcSourcePriority < 5) {
            const entries = []
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i] || {}
                const text = String(line.text || "").trim()
                if (text === "" || root.isInstrumentalText(text))
                    continue
                const startMs = Number(line.start_ms)
                if (!isFinite(startMs) || startMs < 0)
                    continue
                const nextMs = (i + 1 < lines.length) ? Number(lines[i + 1]?.start_ms) : NaN
                const endSec = (isFinite(nextMs) && nextMs > startMs) ? nextMs / 1000.0 : -1
                const timing = wordMap[String(Math.round(startMs))]
                entries.push({
                    timeSec: startMs / 1000.0,
                    endSec: endSec,
                    explicitEndSec: endSec,
                    rawText: text,
                    romanizedText: String(line.romanized || ""),
                    translatedText: "",
                    wordTimingsJson: timing ? JSON.stringify(timing) : "",
                    isInstrumental: false
                })
            }
            root.applyNativeLyricsEntries(entries, 5)
        }
        root.patchKaraokeWordTimings(payload.words)

        const current = data.current || null
        const currentText = current && typeof current.text === "string" ? current.text.trim() : ""
        if (currentText !== "")
            root.updateLyricLine(currentText)
    }

    function metadataLyricsText() {
        const md = root.activePlayer ? root.activePlayer.metadata : null
        if (!md)
            return ""
        const keys = ["xesam:lyrics", "mpris:lyrics", "lyrics"]
        for (let i = 0; i < keys.length; i++) {
            const value = md[keys[i]]
            if (typeof value === "string" && value.trim() !== "")
                return value
        }
        return ""
    }

    function localLrcPath(rawUrl) {
        if (!rawUrl || rawUrl.indexOf("file://") !== 0)
            return ""
        let path = rawUrl.slice(7)
        try {
            path = decodeURIComponent(path)
        } catch (e) {}
        const dot = path.lastIndexOf(".")
        if (dot <= 0)
            return ""
        return path.slice(0, dot) + ".lrc"
    }

    function tryActivePlayerNativeLyrics() {
        if (!root.hasActivePlayer || root.activePlayerIsSonora)
            return
        const metadataText = root.metadataLyricsText()
        if (metadataText !== "" && root.lrcSourcePriority < 5) {
            root.applyNativeLyricsEntries(root.parseLrcToEntries(metadataText), 5)
            return
        }
        const md = root.activePlayer ? root.activePlayer.metadata : null
        const url = (md && md["xesam:url"]) ? String(md["xesam:url"]) : ""
        const path = root.localLrcPath(url)
        if (path !== "" && root.nativeLrcAttemptedTrackId !== root.currentTrackId) {
            root.nativeLrcAttemptedTrackId = root.currentTrackId
            root.nativeLrcPendingTrackId = root.currentTrackId
            localLrcProc.command = ["cat", path]
            localLrcProc.running = true
        }
    }

    Process {
        id: sonoraBridgeProc
        command: ["python3", `${Directories.scriptPath}/lyrics/sonora_bridge.py`,
            String(Directories.genericCache).replace("file://", "") + "/sonora/cache.sqlite"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let payload = null
                try {
                    payload = JSON.parse(text.trim())
                } catch (e) {
                    return
                }
                root.handleActivePlayerLyrics(payload)
            }
        }
        onExited: (exitCode, exitStatus) => nativeLyricsPollTimer.start()
    }

    Process {
        id: localLrcProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.activePlayerIsSonora || root.lrcSourcePriority >= 5)
                    return
                if (root.nativeLrcPendingTrackId !== ""
                    && root.nativeLrcPendingTrackId !== root.currentTrackId)
                    return
                root.applyNativeLyricsEntries(root.parseLrcToEntries(text), 5)
            }
        }
    }

    // Sumber asli bersifat snapshot, jadi dibaca berkala untuk mengikuti
    // baris aktif. Pergantian lagu ditangani lewat currentTrackId.
    Timer {
        id: nativeLyricsPollTimer
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            if (!root.hasActivePlayer)
                return
            if (!root.activePlayerIsSonora)
                return
            if (!sonoraBridgeProc.running) {
                root.nativeBridgeRequestedTrackId = root.currentTrackId
                sonoraBridgeProc.running = true
            }
        }
    }

    Component.onCompleted: {
        refreshVolume()
        if (hasActivePlayer) {
            sessionActive = true
            isLoadingLyrics = true
            trackChangeWallMs = Date.now()
            syncClockAnchor(true)
            prepareLyricsForCurrentTrack()
            extractColorsFromArt(albumArtUrl)
        }
    }

    // --- Template Komponen Baris Lirik Dinamis (Compact Pill, Tanpa Shake) ---
    Component {
        id: karaokeLineComponent

        Item {
            id: lineItem
            property string rawText: ""
            property string romanizedText: ""
            property string translatedText: ""
            property bool active: false
            property bool isFallback: false
            property bool isInstrumental: false
            property real progress: 0.0

            readonly property string displayRomaji: !isInstrumental && !root.showOriginalLanguage
                ? root.romajiForDisplay(rawText, romanizedText)
                : romanizedText
            readonly property bool showSecondLine: !isInstrumental && root.showRomajiSubline && displayRomaji !== "" && !isFallback
            readonly property bool showThirdLine: !isInstrumental && root.showTranslate && translatedText !== "" && !isFallback
            // Baris asli tetap tampil bila semua baris lain mati/kosong agar pill tidak kosong.
            readonly property bool showFirstLine: !isInstrumental && (root.showOriginalLanguage || (!showSecondLine && !showThirdLine))
            readonly property int tierCount: isInstrumental ? 1 : ((showFirstLine ? 1 : 0) + (showSecondLine ? 1 : 0) + (showThirdLine ? 1 : 0))
            readonly property bool primaryIsRomaji: !showFirstLine && showSecondLine
            readonly property bool primaryIsTrans: !showFirstLine && !showSecondLine && showThirdLine

            // Warna Romaji diambil dari warna dominan cover album
            readonly property color romajiActiveCol: root.romajiActiveColor
            readonly property color romajiDimCol: root.romajiDimColor

            readonly property real maxContentW: isInstrumental
                ? instrumentalRow.implicitWidth
                : Math.max(
                    showFirstLine ? origDimText.implicitWidth : 0,
                    showSecondLine ? romDimText.implicitWidth : 0,
                    showThirdLine ? subLineText.implicitWidth : 0
                )

            readonly property real contentWidth: Math.min(maxContentW, root.maxCompactLyricWidth)

            function alignedX(textWidth) {
                if (root.lyricTextAlignment === Text.AlignCenter)
                    return Math.max(0, (lineItem.contentWidth - textWidth) / 2)
                if (root.lyricTextAlignment === Text.AlignRight)
                    return Math.max(0, lineItem.contentWidth - textWidth)
                return 0
            }

            implicitWidth: contentWidth
            implicitHeight: isInstrumental ? instrumentalRow.implicitHeight : linesCol.implicitHeight
            clip: true

            opacity: active ? (isFallback && root.isLoadingLyrics ? pulseOpacity : 1.0) : 0.0
            scale: active ? 1.0 : 0.985
            transformOrigin: Item.Center
            y: 0

            // Dinyaktifkan sebentar saat slot disiapkan agar lompatan posisi
            // awal tidak ikut dianimasikan.
            property bool slideReady: false

            property real pulseOpacity: 1.0

            SequentialAnimation on pulseOpacity {
                running: lineItem.active && lineItem.isFallback && root.isLoadingLyrics
                loops: Animation.Infinite
                NumberAnimation { to: 0.52; duration: 750; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutSine }
            }

            Behavior on opacity {
                enabled: !(lineItem.active && lineItem.isFallback && root.isLoadingLyrics)
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.InOutQuint
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.InOutQuint
                }
            }

            Behavior on y {
                enabled: lineItem.slideReady
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.InOutQuint
                }
            }

            readonly property real easedProgress: root.easeInOutKaraoke(progress)
            readonly property real panRatio: Math.max(0, Math.min(1, (easedProgress - 0.12) / 0.80))
            readonly property real origOverflow: Math.max(0, origDimText.implicitWidth - root.maxCompactLyricWidth)
            readonly property real romOverflow: Math.max(0, romDimText.implicitWidth - root.maxCompactLyricWidth)

            // Tampilan Ikon Lagu saat Instrumental / Tanpa Vokal
            Row {
                id: instrumentalRow
                visible: lineItem.isInstrumental
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.sp(7)

                Text {
                    text: "󰎇"
                    color: root.effectiveSliderColor
                    font.pixelSize: root.sp(15)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.instrumentalSectionLabel(lineItem.rawText)
                    color: root.lyricActiveColor
                    font.pixelSize: root.sp(12)
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: 0.82

                    SequentialAnimation on opacity {
                        running: lineItem.active && lineItem.isInstrumental && root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Tampilan Teks Lirik 3-Tier (Compact Pill)
            Column {
                id: linesCol
                visible: !lineItem.isInstrumental
                anchors.verticalCenter: parent.verticalCenter
                width: lineItem.contentWidth
                spacing: 0

                Item {
                    visible: lineItem.showFirstLine
                    width: linesCol.width
                    height: origDimText.implicitHeight
                    x: -lineItem.origOverflow * lineItem.panRatio

                    Text {
                        id: origDimText
                        text: lineItem.rawText
                        width: parent.width
                        horizontalAlignment: root.lyricTextAlignment
                        color: root.lyricDimColor
                        font.pixelSize: root.sp(lineItem.tierCount >= 3 ? 13 : (lineItem.tierCount === 2 ? 14 : 15))
                        font.weight: Font.DemiBold
                    }

                    Item {
                        x: lineItem.alignedX(origDimText.implicitWidth)
                        anchors.top: origDimText.top
                        anchors.bottom: origDimText.bottom
                        width: origDimText.implicitWidth * lineItem.easedProgress
                        clip: true

                        Text {
                            text: lineItem.rawText
                            width: origDimText.implicitWidth
                            color: root.lyricActiveColor
                            font.pixelSize: root.sp(lineItem.tierCount >= 3 ? 13 : (lineItem.tierCount === 2 ? 14 : 15))
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Item {
                    visible: lineItem.showSecondLine
                    width: linesCol.width
                    height: romDimText.implicitHeight
                    x: -lineItem.romOverflow * lineItem.panRatio

                    Text {
                        id: romDimText
                        text: lineItem.displayRomaji
                        width: parent.width
                        horizontalAlignment: root.lyricTextAlignment
                        color: lineItem.romajiDimCol
                        // Harus sama dengan teks aktif di overlay, kalau tidak
                        // huruf yang belum dinyanyikan tampak lebih kecil.
                        font.pixelSize: root.sp(lineItem.primaryIsRomaji ? 14 : 12)
                        font.weight: Font.Medium
                    }

                    Item {
                        x: lineItem.alignedX(romDimText.implicitWidth)
                        anchors.top: romDimText.top
                        anchors.bottom: romDimText.bottom
                        width: romDimText.implicitWidth * lineItem.easedProgress
                        clip: true

                        Text {
                            text: lineItem.displayRomaji
                            width: romDimText.implicitWidth
                            color: lineItem.romajiActiveCol
                            font.pixelSize: root.sp(lineItem.primaryIsRomaji ? 14 : 12)
                            font.weight: Font.Medium
                        }
                    }
                }

                Text {
                    id: subLineText
                    visible: lineItem.showThirdLine
                    text: lineItem.translatedText
                    color: root.subTextColor
                    font.pixelSize: root.sp(lineItem.primaryIsTrans ? 14 : 11)
                    elide: Text.ElideRight
                    width: lineItem.contentWidth
                    horizontalAlignment: root.lyricTextAlignment
                }
            }
        }
    }

    // =========================================================================
    // Background compact: notch Mac dengan bahu cekung / floating rounded penuh
    // =========================================================================
    Rectangle {
        id: floatingBackground
        anchors.fill: parent
        visible: !root.notchSilhouette
        radius: root.sp(24)
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.fullAlbumColor ? root.effectiveAccentColor : "#000000"
            }
            GradientStop {
                position: 0.62
                color: root.fullAlbumColor
                    ? root.effectiveAccentColor
                    : (root.useAlbumColor
                        ? Qt.tint("#070707", Qt.rgba(root.effectiveAccentColor.r, root.effectiveAccentColor.g, root.effectiveAccentColor.b, 0.28))
                        : "#000000")
            }
            GradientStop {
                position: 1.0
                color: root.fullAlbumColor
                    ? root.effectiveAccentColor
                    : (root.useAlbumColor ? root.effectiveAccentColor : "#000000")
            }
        }
    }

    Shape {
        id: notchBackground
        anchors.fill: parent
        visible: root.notchSilhouette
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        // Bar bawah: cerminkan bentuk secara vertikal.
        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            yScale: root.notchAtTop ? 1 : -1
        }

        // Opsional: gradien diambil dari warna cover album.
        // Koordinat gradient mengikuti tinggi shape lokal (sebelum mirror).
        LinearGradient {
            id: notchAlbumGradient
            y1: 0
            y2: root.height
            GradientStop {
                position: 0.0
                color: root.fullAlbumColor ? root.effectiveAccentColor : "#000000"
            }
            GradientStop {
                position: 0.55
                color: root.fullAlbumColor
                    ? root.effectiveAccentColor
                    : Qt.tint("#050505", Qt.rgba(root.effectiveAccentColor.r, root.effectiveAccentColor.g, root.effectiveAccentColor.b, 0.28))
            }
            GradientStop {
                position: 1.0
                color: root.fullAlbumColor
                    ? root.effectiveAccentColor
                    : Qt.tint("#080808", Qt.rgba(root.effectiveAccentColor.r, root.effectiveAccentColor.g, root.effectiveAccentColor.b, 0.62))
            }
        }

        ShapePath {
            fillColor: "#000000"
            fillGradient: root.useAlbumColor ? notchAlbumGradient : null
            strokeWidth: 0
            startX: 0
            startY: 0

            // Tepi atas penuh (menyatu dengan bar).
            PathLine { x: root.width; y: 0 }

            // Bahu cekung kanan: (width, 0) -> (width - inset, drop).
            PathCubic {
                x: root.width - root.notchShoulderInset
                y: root.notchShoulderDrop
                control1X: root.width - root.notchShoulderInset * 0.552
                control1Y: 0
                control2X: root.width - root.notchShoulderInset
                control2Y: root.notchShoulderDrop * 0.448
            }

            PathLine {
                x: root.width - root.notchShoulderInset
                y: root.height - root.notchBottomRadius
            }

            // Sudut bawah kanan.
            PathCubic {
                x: root.width - root.notchShoulderInset - root.notchBottomRadius
                y: root.height
                control1X: root.width - root.notchShoulderInset
                control1Y: root.height - root.notchBottomRadius + root.notchBottomRadius * 0.552
                control2X: root.width - root.notchShoulderInset - root.notchBottomRadius * 0.448
                control2Y: root.height
            }

            PathLine {
                x: root.notchShoulderInset + root.notchBottomRadius
                y: root.height
            }

            // Sudut bawah kiri.
            PathCubic {
                x: root.notchShoulderInset
                y: root.height - root.notchBottomRadius
                control1X: root.notchShoulderInset + root.notchBottomRadius * 0.448
                control1Y: root.height
                control2X: root.notchShoulderInset
                control2Y: root.height - root.notchBottomRadius + root.notchBottomRadius * 0.552
            }

            PathLine {
                x: root.notchShoulderInset
                y: root.notchShoulderDrop
            }

            // Bahu cekung kiri: (inset, drop) -> (0, 0).
            PathCubic {
                x: 0
                y: 0
                control1X: root.notchShoulderInset
                control1Y: root.notchShoulderDrop * 0.448
                control2X: root.notchShoulderInset * 0.552
                control2Y: 0
            }
        }
    }

    // =========================================================================
    // 1. TAMPILAN COMPACT PILL DI TOP BAR
    // =========================================================================
    Item {
        id: compactWrapper
        anchors.fill: parent
        opacity: Math.max(0.0, 1.0 - (root.morphProgress * 3.6))

        RowLayout {
            id: compactView
            anchors.centerIn: parent
            spacing: root.sp(10)

            ClippingRectangle {
                Layout.preferredWidth: root.sp(28)
                Layout.preferredHeight: root.sp(28)
                radius: root.sp(root.notchSilhouette ? 8 : 6)
                color: "#141414"
                border.width: root.notchSilhouette ? 1 : 0
                border.color: Qt.rgba(1, 1, 1, 0.08)
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
                    color: root.effectiveSliderColor
                    font.pixelSize: root.sp(12)
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
                spacing: root.sp(2)

                Repeater {
                    model: [
                        { minH: 4, maxH: 14, speed: 420 },
                        { minH: 5, maxH: 16, speed: 310 },
                        { minH: 4, maxH: 12, speed: 490 }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: root.sp(2.5)
                        height: root.isPlaying ? root.sp(modelData.maxH) : root.sp(modelData.minH)
                        radius: root.sp(1.25)
                        color: root.effectiveSliderColor
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on height {
                            running: root.isPlaying && root.isIslandVisible && !root.isExpanded
                            loops: Animation.Infinite
                            NumberAnimation { to: root.sp(modelData.maxH); duration: modelData.speed; easing.type: Easing.InOutSine }
                            NumberAnimation { to: root.sp(modelData.minH); duration: modelData.speed; easing.type: Easing.InOutSine }
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
    // 2. MORPHING EXPANDED CARD (MEMBESAR BOUNCY DARI KOTAK COMPACT)
    // =========================================================================
    PopupWindow {
        id: expandedPopup
        visible: root.isExpanded || root.morphProgress > 0.01
        color: "transparent"
        implicitWidth: root.sp(root.expandedWidth + 48)
        implicitHeight: root.sp(root.expandedHeight + 48)

        anchor.window: root.QsWindow.window
        anchor.rect: root.cachedAnchorRect

        Item {
            id: popupRootContainer
            anchors.fill: parent

            Rectangle {
                id: expandedCard
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top

                // Morphing memakai ukuran compact yang dibekukan saat ekspansi,
                // dan progress di-clamp agar OutBack tidak membuat kartu bergetar.
                width: morphBaseWidth + ((root.sp(root.expandedWidth) - morphBaseWidth) * Math.max(0.0, Math.min(1.0, root.morphProgress)))
                height: morphBaseHeight + ((root.sp(root.expandedHeight) - morphBaseHeight) * Math.max(0.0, Math.min(1.0, root.morphProgress)))
                radius: root.sp(12 + (8 * Math.max(0.0, Math.min(1.0, root.morphProgress))))
                border.width: 1
                border.color: root.expandedBorderColor
                clip: true

                HoverHandler {
                    id: popupHover
                    onHoveredChanged: root.updateHoverState()
                }

                // Permukaan flat: satu warna dominan, tanpa highlight dekoratif.
                gradient: Gradient {
                    GradientStop { position: 0.00; color: root.expandedSurfaceColor }
                    GradientStop { position: 0.64; color: root.expandedSurfaceColor }
                    GradientStop { position: 1.00; color: root.gradientBottomColor }
                }

                opacity: Math.max(0.0, Math.min(1.0, root.morphProgress * 6.0))

                // Konten dalam kartu membesar dengan skala halus agar terasa menyatu
                Item {
                    id: expandedContentWrapper
                    width: root.expandedWidth
                    height: root.expandedHeight
                    anchors.left: parent.left
                    anchors.top: parent.top
                    opacity: Math.max(0.0, Math.min(1.0, (root.morphProgress - 0.14) / 0.65))
                    scale: root.widgetScale * (0.90 + (0.10 * Math.max(0.0, Math.min(1.0, root.morphProgress))))
                    transformOrigin: Item.TopLeft

                    // =============================================================
                    // KOLOM KIRI: ALBUM ART, JUDUL/ARTIS, CUSTOM SLIDER & KONTROL
                    // =============================================================
                    Column {
                        id: leftMediaColumn
                        anchors.left: parent.left
                        anchors.leftMargin: 22
                        anchors.top: parent.top
                        anchors.topMargin: 22
                        width: 186
                        spacing: 0

                        // 1. Cover Album
                        ClippingRectangle {
                            width: 186
                            height: 186
                            radius: 16
                            color: "#1a1a1a"
                            scale: root.isPlaying ? 1.0 : 0.96

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

                                Behavior on opacity {
                                    NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: expandedArt.opacity < 0.1
                                text: "󰎆"
                                color: root.effectiveAccentColor
                                font.pixelSize: 38
                            }
                        }

                        // 2. Judul Lagu
                        Text {
                            width: parent.width
                            topPadding: 11
                            text: root.trackTitle !== "" ? root.trackTitle : "Tidak ada media"
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        // 3. Nama Artis
                        Text {
                            width: parent.width
                            topPadding: 2
                            text: root.trackArtist !== "" ? root.trackArtist : "MPRIS Player"
                            color: Qt.rgba(1, 1, 1, 0.70)
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        // 4. Custom Music Slider Interaktif
                        RowLayout {
                            width: parent.width
                            height: 30
                            spacing: 7

                            Text {
                                text: root.formatDuration(root.sliderDisplayPosSec)
                                color: customSliderMouse.pressed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                                font.pixelSize: 10
                                font.weight: customSliderMouse.pressed ? Font.DemiBold : Font.Normal
                            }

                            Item {
                                id: customSliderContainer
                                Layout.fillWidth: true
                                height: 22

                                readonly property bool hoveredOrPressed: customSliderMouse.containsMouse || customSliderMouse.pressed
                                readonly property real progressRatio: root.trackDurationSec > 0
                                    ? Math.max(0.0, Math.min(1.0, root.sliderDisplayPosSec / root.trackDurationSec))
                                    : 0.0
                                readonly property real thumbCenterX: width * progressRatio

                                // Tooltip waktu melayang saat hover atau menggeser slider
                                Rectangle {
                                    id: seekTooltip
                                    visible: opacity > 0.01
                                    opacity: customSliderContainer.hoveredOrPressed && root.trackDurationSec > 0 ? 1.0 : 0.0
                                    y: -22
                                    x: Math.max(0, Math.min(customSliderContainer.width - width,
                                        (customSliderMouse.pressed ? customSliderContainer.thumbCenterX : customSliderMouse.mouseX) - width * 0.5))
                                    width: tooltipText.implicitWidth + 10
                                    height: 18
                                    radius: 6
                                    color: Qt.rgba(0.06, 0.06, 0.06, 0.92)
                                    border.width: 1
                                    border.color: root.effectiveSliderColor

                                    Behavior on opacity {
                                        NumberAnimation { duration: 150; easing.type: Easing.InOutCubic }
                                    }

                                    Text {
                                        id: tooltipText
                                        anchors.centerIn: parent
                                        color: "#ffffff"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        text: {
                                            if (customSliderMouse.pressed)
                                                return root.formatDuration(root.sliderDisplayPosSec)
                                            const hoverRatio = Math.max(0.0, Math.min(1.0, customSliderMouse.mouseX / Math.max(1, customSliderContainer.width)))
                                            return root.formatDuration(hoverRatio * root.trackDurationSec)
                                        }
                                    }
                                }

                                // Soft Glow di belakang bar aktif
                                Rectangle {
                                    id: sliderGlow
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: -2
                                    width: (parent.width * customSliderContainer.progressRatio) + 4
                                    height: customSliderContainer.hoveredOrPressed ? 12 : 8
                                    radius: height / 2
                                    property real glowPulse: 1.0
                                    color: Qt.rgba(root.effectiveSliderColor.r,
                                        root.effectiveSliderColor.g,
                                        root.effectiveSliderColor.b,
                                        (customSliderContainer.hoveredOrPressed ? 0.32 : 0.16) * sliderGlow.glowPulse)

                                    SequentialAnimation on glowPulse {
                                        running: root.isExpanded && root.isPlaying && !customSliderContainer.hoveredOrPressed
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 1.28; duration: 1600; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
                                        onRunningChanged: if (!running) sliderGlow.glowPulse = 1.0
                                    }

                                    Behavior on height {
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }
                                }

                                // Track Latar Belakang
                                Rectangle {
                                    id: sliderBgTrack
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: customSliderContainer.hoveredOrPressed ? 8 : 5
                                    radius: height / 2
                                    color: Qt.rgba(1, 1, 1, 0.20)
                                    clip: true

                                    Behavior on height {
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    // Bar Aktif Bergradasi Warna Cover Album
                                    Rectangle {
                                        width: parent.width * customSliderContainer.progressRatio
                                        height: parent.height
                                        radius: parent.radius
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: root.effectiveAccentColor }
                                            GradientStop { position: 1.0; color: root.effectiveSliderColor }
                                        }
                                    }
                                }

                                // Custom Dual-Ring Knob / Thumb
                                Rectangle {
                                    id: customSliderThumb
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: customSliderMouse.pressed ? 15 : (customSliderMouse.containsMouse ? 13 : 10)
                                    height: width
                                    radius: width / 2
                                    color: "#ffffff"
                                    x: Math.max(0, Math.min(customSliderContainer.width - width, customSliderContainer.thumbCenterX - (width / 2)))

                                    Behavior on width {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.46
                                        height: width
                                        radius: width / 2
                                        color: root.effectiveAccentColor
                                    }
                                }

                                MouseArea {
                                    id: customSliderMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: root.trackDurationSec > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor

                                    function previewSeek(mouseX) {
                                        if (root.trackDurationSec <= 0)
                                            return
                                        const ratio = Math.max(0.0, Math.min(1.0, mouseX / width))
                                        root.sliderDisplayPosSec = ratio * root.trackDurationSec
                                    }

                                    onPressed: mouse => {
                                        root.isSeekingSlider = true
                                        previewSeek(mouse.x)
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed)
                                            previewSeek(mouse.x)
                                    }
                                    onReleased: mouse => {
                                        if (root.trackDurationSec > 0) {
                                            const ratio = Math.max(0.0, Math.min(1.0, mouse.x / width))
                                            root.seekToSeconds(ratio * root.trackDurationSec)
                                        }
                                        root.isSeekingSlider = false
                                        root.updateHoverState()
                                    }
                                    onWheel: wheel => {
                                        if (root.trackDurationSec > 0) {
                                            const step = wheel.angleDelta.y > 0 ? 5.0 : -5.0
                                            root.seekToSeconds(root.sliderDisplayPosSec + step)
                                        }
                                    }
                                }
                            }

                            Text {
                                text: root.formatDuration(root.trackDurationSec)
                                color: Qt.rgba(1, 1, 1, 0.75)
                                font.pixelSize: 10
                            }
                        }

                        // 5. Kontrol Prev / Play-Pause / Next & Ikon Speaker Volume
                        Item {
                            width: parent.width
                            height: 32

                            Row {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -10
                                spacing: 16

                                // Tombol Previous
                                Item {
                                    width: 26
                                    height: 26
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        color: prevMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.88)
                                        font.pixelSize: 16
                                    }

                                    MouseArea {
                                        id: prevMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.activePlayer) root.activePlayer.previous()
                                    }
                                }

                                // Tombol Play / Pause
                                Item {
                                    width: 30
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    scale: playMouse.pressed ? 0.88 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isPlaying ? "󰏤" : "󰐊"
                                        color: "#ffffff"
                                        font.pixelSize: 21
                                    }

                                    MouseArea {
                                        id: playMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                                    }
                                }

                                // Tombol Next
                                Item {
                                    width: 26
                                    height: 26
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        color: nextMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.88)
                                        font.pixelSize: 16
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

                            // Ikon Speaker Volume di sisi kanan baris kontrol
                            Item {
                                id: speakerControl
                                width: 28
                                height: 28
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: root.currentVolume <= 0.01 ? "󰖁" : (root.currentVolume < 0.5 ? "󰖀" : "󰕾")
                                    color: speakerMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.90)
                                    font.pixelSize: 16
                                }

                                MouseArea {
                                    id: speakerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleMute()
                                    onWheel: wheel => {
                                        const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                                        root.setVolumeLevel(root.currentVolume + delta)
                                    }
                                }
                            }
                        }
                    }

                    // Popover Volume Halus
                    Rectangle {
                        id: volumePopover
                        visible: opacity > 0.01
                        opacity: (speakerMouse.containsMouse || volumePopoverHover.hovered || volumeDragArea.pressed || root.volumeOsdActive) ? 1.0 : 0.0
                        anchors.left: leftMediaColumn.left
                        anchors.bottom: leftMediaColumn.bottom
                        anchors.bottomMargin: 32
                        width: leftMediaColumn.width
                        height: 28
                        radius: 14
                        color: Qt.rgba(0.06, 0.06, 0.06, 0.92)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                        z: 10

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.InOutCubic }
                        }

                        HoverHandler {
                            id: volumePopoverHover
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Text {
                                text: root.currentVolume <= 0.01 ? "󰖁" : "󰕾"
                                color: root.effectiveSliderColor
                                font.pixelSize: 12
                            }

                            Item {
                                id: volumeTrack
                                Layout.fillWidth: true
                                height: 16

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.22)

                                    Rectangle {
                                        width: parent.width * root.currentVolume
                                        height: parent.height
                                        radius: 2
                                        color: root.effectiveSliderColor
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
                                color: "#ffffff"
                                font.pixelSize: 10
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // =============================================================
                    // KOLOM KANAN: DAFTAR LIRIK RATA KIRI (EASE IN/OUT KARAOKE)
                    // =============================================================
                    Item {
                        id: rightLyricsContainer
                        anchors.left: leftMediaColumn.right
                        anchors.leftMargin: 22
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.top: parent.top
                        anchors.topMargin: 22
                        anchors.bottom: bottomActionRow.top
                        anchors.bottomMargin: 14
                        clip: true

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 16
                            visible: lyricModel.count === 0
                            spacing: 8

                            Text {
                                text: root.isInstrumentalLine
                                    ? ("󰎇   " + root.instrumentalSectionLabel(root.displayedRawText) + "   󰎇")
                                    : (root.lyricsNotFound
                                        ? Translation.tr("Lyric not found")
                                        : (root.displayedRawText !== "" ? root.displayedRawText : "Menunggu lirik..."))
                                color: root.isInstrumentalLine ? root.effectiveSliderColor : Qt.rgba(1, 1, 1, 0.72)
                                font.pixelSize: root.isInstrumentalLine ? 18 : 15
                                font.weight: Font.Bold
                                wrapMode: Text.WordWrap
                                width: parent.width
                                horizontalAlignment: root.lyricTextAlignment
                            }
                        }

                        ListView {
                            id: fullLyricsView
                            anchors.fill: parent
                            model: lyricModel
                            spacing: 18
                            clip: true
                            interactive: true
                            boundsBehavior: Flickable.StopAtBounds

                            currentIndex: root.activeLyricIndex
                            preferredHighlightBegin: 0
                            preferredHighlightEnd: height * 0.42
                            highlightRangeMode: ListView.NoHighlightRange
                            highlightMoveDuration: 240
                            highlightMoveVelocity: -1

                            // Hanya scroll saat baris aktif benar-benar keluar dari
                            // area nyaman. Tidak menggeser daftar tiap ganti lirik.
                            onCurrentIndexChanged: {
                                if (!root.isExpanded) return
                                const item = fullLyricsView.itemAtIndex(currentIndex)
                                if (!item) return
                                const top = item.y - fullLyricsView.contentY
                                const bottom = top + item.height
                                if (top < 24 || bottom > fullLyricsView.height - 24)
                                    fullLyricsView.positionViewAtIndex(currentIndex, ListView.Center)
                            }

                            delegate: Item {
                                id: rowDelegate
                                required property int index
                                required property string rawText
                                required property string romanizedText
                                required property string translatedText
                                required property real timeSec
                                required property bool isInstrumental

                                readonly property bool isCurrent: index === root.activeLyricIndex
                                readonly property string displayRomaji: !isInstrumental && !root.showOriginalLanguage
                                    ? root.romajiForDisplay(rawText, romanizedText)
                                    : romanizedText
                                readonly property bool showSecondRom: !isInstrumental && root.showRomajiSubline && displayRomaji !== ""
                                readonly property bool showThirdTrans: !isInstrumental && root.showTranslate && translatedText !== ""
                                readonly property bool showFirstRaw: !isInstrumental && (root.showOriginalLanguage || (!showSecondRom && !showThirdTrans))

                                width: fullLyricsView.width
                                height: (isInstrumental ? instrumentalDelegateRow.implicitHeight : lyricRowColumn.implicitHeight) + 2

                                // Layer blur dulu menyala/mati mendadak tiap lirik
                                // dan terasa seperti shake. Sekarang hanya opacity.
                                layer.enabled: false

                                opacity: isCurrent ? 1.0 : 0.48
                                scale: 1.0

                                Behavior on opacity {
                                    NumberAnimation { duration: 360; easing.type: Easing.InOutCubic }
                                }

                                // Baris Indikator Instrumental / Tanpa Vokal
                                Row {
                                    id: instrumentalDelegateRow
                                    visible: rowDelegate.isInstrumental
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    Text {
                                        text: "󰎇"
                                        color: rowDelegate.isCurrent ? root.effectiveSliderColor : Qt.rgba(1, 1, 1, 0.55)
                                        font.pixelSize: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: root.instrumentalSectionLabel(rowDelegate.rawText)
                                        color: rowDelegate.isCurrent ? "#ffffff" : Qt.rgba(1, 1, 1, 0.55)
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Baris Lirik 3-Tier (Karaoke Ease-In-Out Sweep)
                                Column {
                                    id: lyricRowColumn
                                    visible: !rowDelegate.isInstrumental
                                    width: parent.width
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    // 1. Bahasa Asli
                                    Text {
                                        visible: rowDelegate.showFirstRaw
                                        width: parent.width
                                        textFormat: Text.RichText
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: root.lyricTextAlignment
                                        lineHeight: 1.15
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                        text: rowDelegate.isCurrent
                                            ? root.buildRichKaraokeText(rowDelegate.rawText, root.karaokeProgress, "#ffffff", "#636262")
                                            : "<font color=\"#a8a8a8\">" + root.escapeHtml(rowDelegate.rawText) + "</font>"
                                    }

                                    // 2. Romaji (Mengikuti warna cover album)
                                    Text {
                                        visible: rowDelegate.showSecondRom
                                        width: parent.width
                                        textFormat: Text.RichText
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: root.lyricTextAlignment
                                        lineHeight: 1.15
                                        font.pixelSize: rowDelegate.showFirstRaw ? 13 : 17
                                        font.weight: Font.DemiBold
                                        text: {
                                            const activeHex = (root.useAlbumColor
                                                ? root.effectiveSliderColor
                                                : root.romajiActiveColor).toString()
                                            const dimHex = (root.useAlbumColor
                                                ? Qt.darker(root.effectiveAccentColor, 2.0)
                                                : root.romajiDimColor).toString()
                                            const romaji = rowDelegate.displayRomaji
                                            return rowDelegate.isCurrent
                                                ? root.buildRichKaraokeText(romaji, root.karaokeProgress, activeHex, dimHex)
                                                : "<font color=\"" + activeHex + "\">" + root.escapeHtml(romaji) + "</font>"
                                        }
                                    }

                                    // 3. Terjemahan Bahasa Indonesia
                                    Text {
                                        visible: rowDelegate.showThirdTrans
                                        width: parent.width
                                        text: rowDelegate.translatedText
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: root.lyricTextAlignment
                                        lineHeight: 1.2
                                        color: rowDelegate.isCurrent ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.62)
                                        font.pixelSize: rowDelegate.showFirstRaw ? 12 : 15
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: rowDelegate.timeSec >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (rowDelegate.timeSec >= 0) {
                                            root.seekToSeconds(rowDelegate.timeSec)
                                            root.activateSyncedIndex(rowDelegate.index, false)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // =============================================================
                    // BARIS BAWAH: 3 TOMBOL PILL (Translate, Romaji, Original)
                    // =============================================================
                    Row {
                        id: bottomActionRow
                        anchors.left: parent.left
                        anchors.leftMargin: 22
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20
                        spacing: 9

                        Rectangle {
                            id: btnTranslate
                            width: 132
                            height: 38
                            radius: 19
                            scale: transBtnMouse.pressed ? 0.95 : 1.0
                            color: root.showTranslate
                                ? Qt.rgba(root.effectiveButtonFill.r, root.effectiveButtonFill.g, root.effectiveButtonFill.b, 0.46)
                                : Qt.rgba(root.effectiveButtonFill.r, root.effectiveButtonFill.g, root.effectiveButtonFill.b,
                                    transBtnMouse.containsMouse ? 0.20 : 0.08)
                            border.width: 1
                            border.color: root.showTranslate
                                ? Qt.rgba(root.effectiveButtonBorder.r, root.effectiveButtonBorder.g, root.effectiveButtonBorder.b, 0.45)
                                : Qt.rgba(root.effectiveButtonBorder.r, root.effectiveButtonBorder.g, root.effectiveButtonBorder.b, 0.24)

                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: root.effectiveSliderColor
                                visible: root.showTranslate
                            }

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: root.showTranslate ? 4 : 0
                                text: "Translate"
                                color: root.showTranslate ? "#ffffff" : Qt.rgba(1, 1, 1, 0.82)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
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

                        Rectangle {
                            id: btnRomajiSub
                            width: 132
                            height: 38
                            radius: 19
                            scale: romSubBtnMouse.pressed ? 0.95 : 1.0
                            color: root.showRomajiSubline
                                ? Qt.rgba(root.effectiveButtonFill.r, root.effectiveButtonFill.g, root.effectiveButtonFill.b, 0.46)
                                : Qt.rgba(root.effectiveButtonFill.r, root.effectiveButtonFill.g, root.effectiveButtonFill.b,
                                    romSubBtnMouse.containsMouse ? 0.20 : 0.08)
                            border.width: 1
                            border.color: root.showRomajiSubline
                                ? Qt.rgba(root.effectiveButtonBorder.r, root.effectiveButtonBorder.g, root.effectiveButtonBorder.b, 0.45)
                                : Qt.rgba(root.effectiveButtonBorder.r, root.effectiveButtonBorder.g, root.effectiveButtonBorder.b, 0.24)

                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: root.effectiveSliderColor
                                visible: root.showRomajiSubline
                            }

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: root.showRomajiSubline ? 4 : 0
                                text: "Romaji"
                                color: root.showRomajiSubline ? "#ffffff" : Qt.rgba(1, 1, 1, 0.82)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
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

                        Rectangle {
                            id: btnOriginalLang
                            width: 132
                            height: 38
                            radius: 19
                            scale: origBtnMouse.pressed ? 0.95 : 1.0
                            color: root.showOriginalLanguage
                                ? Qt.rgba(root.effectiveButtonFill.r, root.effectiveButtonFill.g, root.effectiveButtonFill.b, 0.46)
                                : Qt.rgba(root.effectiveButtonFill.r, root.effectiveButtonFill.g, root.effectiveButtonFill.b,
                                    origBtnMouse.containsMouse ? 0.20 : 0.08)
                            border.width: 1
                            border.color: root.showOriginalLanguage
                                ? Qt.rgba(root.effectiveButtonBorder.r, root.effectiveButtonBorder.g, root.effectiveButtonBorder.b, 0.45)
                                : Qt.rgba(root.effectiveButtonBorder.r, root.effectiveButtonBorder.g, root.effectiveButtonBorder.b, 0.24)

                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: root.effectiveSliderColor
                                visible: root.showOriginalLanguage
                            }

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: root.showOriginalLanguage ? 4 : 0
                                text: "Original"
                                color: root.showOriginalLanguage ? "#ffffff" : Qt.rgba(1, 1, 1, 0.82)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: origBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showOriginalLanguage = !root.showOriginalLanguage
                            }
                        }
                    }
                }
            }
        }
    }
}