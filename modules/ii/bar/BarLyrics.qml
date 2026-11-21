import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

BarGroup {
    id: root
    // Otomatis sembunyi jika tidak ada teks lirik yang aktif
    visible: lyricsWidget.visible && lyricsWidget.implicitWidth > 0
    implicitWidth: lyricsWidget.implicitWidth + 20

    Lyrics {
        id: lyricsWidget
        anchors.centerIn: parent
        Layout.maximumWidth: 320
    }
}
