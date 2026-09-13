import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "dankChat"
    ToggleSetting { settingKey: "telegramEnabled"; label: I18n.trFor("dankChat", "Telegram"); defaultValue: true }
    ToggleSetting { settingKey: "whatsappEnabled"; label: I18n.trFor("dankChat", "WhatsApp"); defaultValue: true }
    ToggleSetting {
        settingKey: "telegramReadReceipts"
        label: I18n.trFor("dankChat", "Telegram read receipts")
        description: I18n.trFor("dankChat", "Mark Telegram messages as read when opening a chat.")
        defaultValue: false
    }
    ToggleSetting {
        settingKey: "demoMode"
        label: I18n.trFor("dankChat", "Demo mode")
        description: I18n.trFor("dankChat", "Show sample conversations and disconnect real services. Sending is disabled.")
        defaultValue: false
    }
}
