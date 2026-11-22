import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

BarGroup {
    id: root
    // Otomatis sembunyi jika tidak ada teks lirik yang aktif
    visible: lyricsWidget.visible && lyricsWidget.implicitWidth > 0
    implicitWidth: lyricsWidget.implicitWidth + 20

    // Dengan satu baris lirik, tinggi notch (38px) lebih kecil dari bar (40px).
    // Tanpa koreksi, anchors.centerIn menyisakan celah di tepi bar sehingga
    // siluet notch terlihat mengambang. Tarik ke tepi agar tetap menempel.
    readonly property bool pullNotchToEdge: !Config.options.bar.vertical
        && !lyricsWidget.isFloatingIsland
        && lyricsWidget.currentTierCount === 1

    Lyrics {
        id: lyricsWidget
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.pullNotchToEdge
            ? (Config.options.bar.bottom ? 1 : -1) * Math.max(0, (parent.height - height) / 2)
            : 0
        Layout.maximumWidth: 320 * lyricsWidget.widgetScale
    }
}
