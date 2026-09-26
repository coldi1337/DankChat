import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import qs.Common
import qs.Widgets

Controls.ScrollView {
    id: root
    required property var service
    signal exportRequested()
    clip: true
    onVisibleChanged: if (visible && typeof service.storageAction === "function") service.storageAction(false, false)
    component Label: StyledText { textFormat: Text.PlainText; color: Theme.surfaceText; wrapMode: Text.Wrap; Layout.fillWidth: true }
    component Toggle: RowLayout {
        property string text
        property string description: ""
        property bool checked
        signal toggled(bool value)
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            Label { text: parent.parent.text }
            Label { visible: !!parent.parent.description; text: parent.parent.description; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
        }
        DankToggle { hideText: true; checked: parent.checked; onToggled: value => parent.toggled(value); Accessible.name: parent.text }
    }
    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.spacingM
        Label { text: I18n.trFor("dankChat", "Settings"); font.pixelSize: Theme.fontSizeLarge }
        Label { text: I18n.trFor("dankChat", "Language follows your DMS settings."); color: Theme.surfaceVariantText }
        Toggle {
            text: I18n.trFor("dankChat", "Close dropdown when focus leaves")
            checked: root.service.closeOnBlur ?? true
            onToggled: value => root.service.savePreference("closeOnBlur", value)
        }
        Label { text: I18n.trFor("dankChat", "Chats and media"); font.weight: Font.Medium }
        Label { text: I18n.trFor("dankChat", "Read synchronization and notification overrides are available for each account under Accounts.") }
        Toggle { text: I18n.trFor("dankChat", "Load media automatically"); checked: root.service.automaticMedia; onToggled: value => root.service.savePreference("automaticMedia", value) }
        Label { text: I18n.trFor("dankChat", "Files with an unknown size require a manual download."); color: Theme.surfaceVariantText }
        Repeater {
            model: [{key: "images", label: "Images and stickers"}, {key: "videos", label: "Videos"}, {key: "audio", label: "Audio and voice messages"}, {key: "files", label: "Files"}]
            delegate: Toggle {
                required property var modelData
                text: I18n.trFor("dankChat", modelData.label)
                checked: (root.service.mediaTypes || []).includes(modelData.key)
                onToggled: value => root.service.savePreference("mediaTypes", value ? root.service.mediaTypes.concat([modelData.key]) : root.service.mediaTypes.filter(x => x !== modelData.key))
            }
        }
        DankButton {
            Layout.fillWidth: true
            text: I18n.trFor("dankChat", "Automatic download limit") + ": " + root.service.mediaLimitMb + " MB"
            onClicked: { const values = [5, 10, 25, 50, 100]; root.service.savePreference("mediaLimitMb", values[(values.indexOf(root.service.mediaLimitMb) + 1) % values.length]); }
        }
        Label { text: I18n.trFor("dankChat", "Notifications"); font.weight: Font.Medium }
        DankButton {
            Layout.fillWidth: true
            text: I18n.trFor("dankChat", "Notifications") + ": " + I18n.trFor("dankChat", root.service.notificationMode === "off" ? "Off" : root.service.notificationMode === "mentions" ? "Mentions only" : "All messages")
            onClicked: { const modes = ["off", "all", "mentions"]; root.service.savePreference("notificationMode", modes[(modes.indexOf(root.service.notificationMode) + 1) % 3]); }
        }
        Label { text: I18n.trFor("dankChat", "Mentions-only notifications currently require Telegram. WhatsApp stays silent in this mode."); color: Theme.surfaceVariantText }
        Toggle { text: I18n.trFor("dankChat", "Show message previews"); checked: root.service.notificationPreview; onToggled: value => root.service.savePreference("notificationPreview", value) }
        Toggle { text: I18n.trFor("dankChat", "Notification sound"); checked: root.service.notificationSound; onToggled: value => root.service.savePreference("notificationSound", value) }
        Toggle { text: I18n.trFor("dankChat", "Silence the open chat"); checked: root.service.suppressActive; onToggled: value => root.service.savePreference("suppressActive", value) }
        Label { text: I18n.trFor("dankChat", "Storage"); font.weight: Font.Medium }
        Label { text: I18n.trFor("dankChat", "Downloaded media") + ": " + ((root.service.storageInfo?.bytes || 0) / 1048576).toFixed(1) + " MB" }
        DankButton {
            Layout.fillWidth: true
            text: I18n.trFor("dankChat", "Cache limit") + ": " + root.service.cacheLimitMb + " MB"
            onClicked: { const values = [128, 256, 512, 1024, 2048]; root.service.savePreference("cacheLimitMb", values[(values.indexOf(root.service.cacheLimitMb) + 1) % values.length]); }
        }
        DankButton {
            Layout.fillWidth: true
            text: I18n.trFor("dankChat", "Remove downloads after") + ": " + root.service.cacheDays + " " + I18n.trFor("dankChat", "days")
            onClicked: { const values = [7, 14, 30, 90, 365]; root.service.savePreference("cacheDays", values[(values.indexOf(root.service.cacheDays) + 1) % values.length]); }
        }
        Label { text: I18n.trFor("dankChat", "Cleanup keeps media in the open conversation and never removes original files or account data."); color: Theme.surfaceVariantText }
        DankButton { Layout.fillWidth: true; text: I18n.trFor("dankChat", "Clean downloaded media"); enabled: !root.service.storageBusy && !root.service.writing && Object.keys(root.service.downloads || {}).length === 0; onClicked: root.service.storageAction(true, true) }
        Label { text: I18n.trFor("dankChat", "Version and updates"); font.weight: Font.Medium }
        Label { objectName: "installedVersion"; text: "DankChat " + (root.service.appInfo?.version ? "v" + root.service.appInfo.version : "…") }
        Label { visible: !!root.service.appInfo?.development; text: I18n.trFor("dankChat", "Local development changes") + " · " + (root.service.appInfo?.revision || ""); color: Theme.surfaceVariantText }
        Toggle { text: I18n.trFor("dankChat", "Check GitHub for updates daily"); checked: root.service.automaticUpdates; onToggled: value => root.service.savePreference("automaticUpdates", value) }
        Label {
            text: root.service.checkingUpdates ? I18n.trFor("dankChat", "Checking for updates…") : root.service.updateInfo?.error ? I18n.trFor("dankChat", root.service.updateInfo.error)
                : root.service.updateInfo?.latest ? I18n.trFor("dankChat", root.service.updateInfo.available ? "Update available" : "No newer release found") + " · v" + root.service.updateInfo.latest : I18n.trFor("dankChat", "Not checked yet")
        }
        DankButton { Layout.fillWidth: true; text: I18n.trFor("dankChat", "Check for updates"); enabled: !root.service.checkingUpdates && !root.service.demo; onClicked: root.service.checkUpdates(true) }
        DankButton { Layout.fillWidth: true; text: I18n.trFor("dankChat", "Open releases"); onClicked: Qt.openUrlExternally("https://github.com/coldi1337/DankChat/releases") }
        Label { text: I18n.trFor("dankChat", "Connection and diagnostics"); font.weight: Font.Medium }
        Repeater {
            model: root.service.accounts || []
            delegate: Label {
                required property var modelData
                text: modelData.label + " · " + root.service.accountConnectionText(modelData.provider, modelData.id)
            }
        }
        Label { text: I18n.trFor("dankChat", "The report contains versions, connection states and request timings, without account names, messages or credentials."); color: Theme.surfaceVariantText }
        DankButton { Layout.fillWidth: true; text: I18n.trFor("dankChat", "Save diagnostic report…"); enabled: !root.service.demo; onClicked: root.exportRequested() }
        Label { text: I18n.trFor("dankChat", "Keyboard shortcuts"); font.weight: Font.Medium }
        Label { text: "Ctrl+K · " + I18n.trFor("dankChat", "Search chats") + "\nCtrl+F · " + I18n.trFor("dankChat", "Search messages") + "\nAlt+↑ / Alt+↓ · " + I18n.trFor("dankChat", "Previous / next chat") + "\nCtrl+R · " + I18n.trFor("dankChat", "Reply to the latest message") + "\nEsc · " + I18n.trFor("dankChat", "Close the current view") }
    }
}
