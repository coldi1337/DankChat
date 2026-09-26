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
    ToggleSetting { settingKey: "whatsappReadState"; label: I18n.trFor("dankChat", "WhatsApp read synchronization"); description: I18n.trFor("dankChat", "Mark WhatsApp chats as read on all your devices when reading them here."); defaultValue: false }
    ToggleSetting { settingKey: "automaticMedia"; label: I18n.trFor("dankChat", "Load media automatically"); defaultValue: true }
    ToggleSetting { settingKey: "automaticUpdates"; label: I18n.trFor("dankChat", "Check GitHub for updates daily"); defaultValue: true }
    ToggleSetting {
        settingKey: "demoMode"
        label: I18n.trFor("dankChat", "Demo mode")
        description: I18n.trFor("dankChat", "Show sample conversations and disconnect real services. Sending is disabled.")
        defaultValue: false
    }
}
