import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common

Scope {
    id: root

    Variants {
        model: {
            const screens = Quickshell.screens
            const list = Config.options.bar.screenList
            if (!list || list.length === 0)
                return screens
            return screens.filter(screen => list.includes(screen.name))
        }

        LazyLoader {
            id: islandLoader
            active: !Config.options.bar.vertical
                && Config.lyricsWidgetInLayout
                && ["floating", "floating-island"].includes(Config.options.bar.lyricsWidget?.mode ?? "notch")
                && GlobalStates.barOpen
                && !GlobalStates.screenLocked
                && !GlobalStates.startupLockPending

            required property ShellScreen modelData

            component: PanelWindow {
                id: islandRoot
                screen: islandLoader.modelData

                WlrLayershell.namespace: "quickshell:lyricsWidget"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                color: "transparent"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                mask: Region { item: islandHost }

                Item {
                    id: islandHost
                    width: lyrics.implicitWidth
                    height: lyrics.implicitHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: !Config.options.bar.bottom ? parent.top : undefined
                    anchors.bottom: Config.options.bar.bottom ? parent.bottom : undefined
                    anchors.topMargin: !Config.options.bar.bottom ? Appearance.sizes.barHeight + 8 : 0
                    anchors.bottomMargin: Config.options.bar.bottom ? Appearance.sizes.barHeight + 8 : 0

                    LyricsWidget {
                        id: lyrics
                        anchors.centerIn: parent
                    }
                }
            }
        }
    }
}
