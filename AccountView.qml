import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import qs.Common
import qs.Widgets
import "linkify.js" as Links

Controls.ScrollView {
    id: root
    required property var service
    clip: true
    component Label: StyledText { Layout.fillWidth: true; color: Theme.surfaceText; textFormat: Text.PlainText; wrapMode: Text.Wrap }
    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.spacingM
        Label { text: I18n.trFor("dankChat", "Accounts"); font.pixelSize: Theme.fontSizeLarge }
        Repeater {
            model: root.service.accounts || []
            delegate: ColumnLayout {
                id: account
                required property var modelData
                readonly property string identity: root.service.accountKey(modelData.provider, modelData.id)
                readonly property var status: root.service.accountStatuses?.[identity] || {}
                readonly property bool busy: !!root.service.accountBusy?.[identity]
                property bool confirmDisconnect: false
                Layout.fillWidth: true
                spacing: Theme.spacingS
                Label { text: (account.modelData.provider === "telegram" ? "Telegram" : "WhatsApp") + " · " + account.modelData.label; font.weight: Font.Medium }
                DankTextField { id: nameField; Layout.fillWidth: true; text: account.modelData.label; placeholderText: I18n.trFor("dankChat", "Account name"); maximumLength: 48 }
                DankButton { text: I18n.trFor("dankChat", "Rename account"); enabled: !!nameField.text.trim() && !root.service.demo; onClicked: root.service.changeAccount(account.modelData.provider, account.modelData.id, nameField.text, false) }
                Label { visible: (account.modelData.provider === "telegram" ? !root.service.telegramEnabled : !root.service.whatsappEnabled); text: I18n.trFor("dankChat", "This service is disabled."); color: Theme.surfaceVariantText }
                Label { text: root.service.accountConnectionText(account.modelData.provider, account.modelData.id); color: Theme.surfaceVariantText }
                Label { visible: !account.status.authorized; text: I18n.trFor("dankChat", account.modelData.provider === "telegram" ? "Scan the QR code in Telegram → Settings → Devices." : "Scan the QR code in WhatsApp → Linked devices → Link a device.") }
                Image {
                    visible: !!account.status.qrPath
                    source: visible ? Links.localFileUrl(account.status.qrPath) : ""
                    sourceSize: Qt.size(220, 220); cache: false
                    Layout.preferredWidth: 220; Layout.preferredHeight: visible ? 220 : 0
                }
                Label { visible: ["waiting", "failed", "expired"].includes(account.status.authState); text: I18n.trFor("dankChat", account.status.authState === "waiting" ? "Waiting for scan…" : "Linking failed or expired. Please try again.") }
                ColumnLayout {
                    visible: account.status.authState === "password"
                    Layout.fillWidth: true
                    DankTextField { id: password; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: I18n.trFor("dankChat", "Telegram password") }
                    DankButton { text: I18n.trFor("dankChat", "Sign in"); enabled: !!password.text; onClicked: { root.service.submitPassword(password.text, account.modelData.id); password.text = ""; } }
                }
                DankButton {
                    text: I18n.trFor("dankChat", account.status.authorized ? "Disconnect account" : "Link account")
                    enabled: !root.service.demo && !account.busy && (account.modelData.provider === "telegram" ? root.service.telegramEnabled : root.service.whatsappEnabled)
                    onClicked: { if (account.status.authorized) account.confirmDisconnect = true; else root.service.accountAction(account.modelData.provider, "login", account.modelData.id); }
                }
                ColumnLayout {
                    visible: account.confirmDisconnect
                    Layout.fillWidth: true
                    Label { text: I18n.trFor("dankChat", "Disconnect this account from DankChat?") }
                    DankButton { text: I18n.trFor("dankChat", "Disconnect"); enabled: !account.busy; onClicked: { root.service.accountAction(account.modelData.provider, "logout", account.modelData.id); account.confirmDisconnect = false; } }
                    DankButton { text: I18n.trFor("dankChat", "Cancel"); onClicked: account.confirmDisconnect = false }
                }
                DankButton { visible: !account.status.authorized && (!!account.status.qrPath || !!account.status.linking); text: I18n.trFor("dankChat", "Cancel"); enabled: !account.busy; onClicked: root.service.accountAction(account.modelData.provider, "cancel_login", account.modelData.id) }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: I18n.trFor("dankChat", "Synchronize read state with other devices") }
                    DankToggle {
                        hideText: true
                        checked: root.service.preference(account.modelData.provider, account.modelData.id, "syncRead", account.modelData.provider === "telegram" ? root.service.readReceipts : root.service.whatsappReadState)
                        onToggled: value => root.service.saveAccountPreference(account.modelData.provider, account.modelData.id, "syncRead", value)
                    }
                }
                DankButton {
                    Layout.fillWidth: true
                    readonly property string mode: root.service.preference(account.modelData.provider, account.modelData.id, "notifications", "default")
                    text: I18n.trFor("dankChat", "Notifications") + ": " + I18n.trFor("dankChat", mode === "default" ? "Use app setting" : mode === "off" ? "Off" : mode === "mentions" ? "Mentions only" : "All messages")
                    onClicked: { const modes = account.modelData.provider === "telegram" ? ["default", "all", "mentions", "off"] : ["default", "all", "off"]; root.service.saveAccountPreference(account.modelData.provider, account.modelData.id, "notifications", modes[(modes.indexOf(mode) + 1) % modes.length]); }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline; opacity: 0.3 }
            }
        }
        Label { text: I18n.trFor("dankChat", "Add another account"); font.pixelSize: Theme.fontSizeLarge }
        DankTextField { id: newName; Layout.fillWidth: true; placeholderText: I18n.trFor("dankChat", "Account name"); maximumLength: 48 }
        Flow {
            Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: Theme.spacingS
            DankButton { text: "Telegram +"; enabled: !root.service.demo && root.service.telegramEnabled && !!newName.text.trim(); onClicked: { root.service.changeAccount("telegram", "", newName.text, true); newName.text = ""; } }
            DankButton { text: "WhatsApp +"; enabled: !root.service.demo && root.service.whatsappEnabled && !!newName.text.trim(); onClicked: { root.service.changeAccount("whatsapp", "", newName.text, true); newName.text = ""; } }
        }
    }
}
