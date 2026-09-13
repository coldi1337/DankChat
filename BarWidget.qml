import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    readonly property var chat: PluginService.pluginDaemonInstances[pluginId] || null
    pillClickAction: () => {
        if (!chat) return;
        const screen = parentScreen || Quickshell.screens[0];
        const edge = axis?.edge === "left" ? 2 : axis?.edge === "right" ? 3 : axis?.edge === "bottom" ? 1 : 0;
        const pos = SettingsData.getPopupTriggerPosition(mapToItem(null, 0, 0), screen, barThickness, width, barSpacing, edge, barConfig);
        chat.setAnchor(pos.x, pos.y, pos.width, section, screen, edge, barThickness, barSpacing, barConfig);
        chat.openDropdown();
    }
    pillRightClickAction: () => chat?.openWindow()
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            height: root.widgetThickness
            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: "forum"; size: root.iconSize; color: root.chat?.unread ? Theme.primary : Theme.widgetIconColor }
            StyledText { anchors.verticalCenter: parent.verticalCenter; visible: (root.chat?.unread || 0) > 0; text: String(root.chat?.unread || 0); color: Theme.surfaceText }
        }
    }
    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: root.iconSize + ((root.chat?.unread || 0) > 0 ? 18 : 0)
            DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "forum"; size: root.iconSize; color: root.chat?.unread ? Theme.primary : Theme.widgetIconColor }
            StyledText { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; visible: (root.chat?.unread || 0) > 0; text: String(root.chat?.unread || 0); font.pixelSize: Theme.fontSizeSmall }
        }
    }
}
