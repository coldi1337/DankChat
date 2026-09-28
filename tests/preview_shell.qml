import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DankCommon.Common as DC
import qs.Modals.FileBrowser
import qs.Widgets
import "testplugin/linkify.js" as Colors
import "Common/StockThemes.js" as StockThemes

ShellRoot {
    id: root
    function findItem(item, name) {
        // Avoid recursive QML-list iterators surviving nested engine GC passes.
        const pending = [item];
        while (pending.length) {
            const current = pending.pop();
            if (!current) continue;
            if (current.objectName === name) return current;
            const children = current.children;
            if (children) for (let i = children.length - 1; i >= 0; --i) pending.push(children[i]);
        }
        return null;
    }
    property var observedVideo: null
    property real videoScroll: 0
    property bool promo: Quickshell.env("DANKCHAT_PROMO") === "1"
    property int step: 0
    property int testWidth: 900
    Rectangle { id: contrastProbe; color: Colors.readable(Theme.primaryContainer, Theme.surfaceText, Theme.primaryText) }
    Component.onCompleted: { DC.Style.theme = Theme; DC.Style.settings = SettingsData; SessionData.locale = "en"; }
    QtObject {
        id: mock
        signal messagesReplacing()
        property bool demo: true
        property bool telegramEnabled: true
        property bool whatsappEnabled: true
        property bool settingsOpen: false
        property var appInfo: ({version: "0.5.1", development: true, revision: "test"})
        property var updateInfo: ({})
        property bool checkingUpdates: false
        property bool automaticMedia: true
        property bool automaticUpdates: false
        property bool readReceipts: false
        property bool whatsappReadState: false
        property var accounts: [{provider: "telegram", id: "", label: "Private"}, {provider: "whatsapp", id: "", label: "Work"}]
        property var accountStatuses: ({})
        property string accountFilter: "all"
        property string browseMode: ""
        property string messageQuery: ""
        property var browseResults: []
        property string browseNext: ""
        property bool browsing: false
        property var storageInfo: ({bytes: 10485760})
        property bool storageBusy: false
        property int mediaLimitMb: 25
        property int cacheLimitMb: 512
        property int cacheDays: 30
        property var mediaTypes: ["images", "videos", "audio"]
        property string notificationMode: "off"
        property bool notificationPreview: false
        property bool notificationSound: false
        property bool suppressActive: true
        property var transferStates: ({})
        function accountKey(provider, account) { return provider + (account ? ":" + account : ""); }
        function accountLabel(chat) { return accounts.find(a => a.provider === chat?.provider && a.id === (chat?.account || ""))?.label || chat?.provider || ""; }
        function accountConnectionText(provider, account) { return "Connected"; }
        function notificationPolicy(chat) { return "off"; }
        function cycleChatNotifications(chat) {}
        function preference(provider, account, key, fallback) { return fallback; }
        function savePreference(key, value) {}
        function saveAccountPreference(provider, account, key, value) {}
        function changeAccount(provider, account, label, add) {}
        function storageAction(clean, clear) {}
        function checkUpdates(force) {}
        function closeBrowse() { browseMode = ""; }
        function browse(mode, query, more) { browseMode = mode; }
        function editMessage(message, text, chat) {}
        property bool accountsOpen: false
        property var attachmentDrafts: ({})
        function setAttachmentPaths(paths, key) { attachmentDrafts = Object.assign({}, attachmentDrafts, {[key]: paths}); }
        property bool writing: false
        property bool reconnecting: false
        property var syncFailures: ({})
        function retryConnection() {}
        function connectionText(provider) { return I18n.trFor("dankChat", "Connected"); }
        property bool surfaceOpen: true
        property bool historyContext: false
        property string presenceText: ""
        property string voiceState: ""
        property string voicePath: ""
        property int voiceSeconds: 0
        function startVoice() { voiceState = "recording"; voiceSeconds = 3; }
        function stopVoice() { voiceState = "ready"; voicePath = Quickshell.env("DANKCHAT_TEST_VOICE"); }
        function discardVoice() { voiceState = ""; voicePath = ""; }
        function sendVoice() { discardVoice(); }
        property var deletionCalls: []
        function deleteMessage(message, forMe, key) { deletionCalls = deletionCalls.concat([{id: message.id, forMe: forMe, key: key}]); }
        function showLatest() {}
        property var activePlayer: null
        property string viewRevision: "test"
        property string filter: "all"
        property string query: ""
        property bool unreadOnly: false
        property int unreadChatCount: 123
        property string errorText: ""
        property string draft: ""
        property string qrPath: ""
        property var reply: null
        property var downloads: ({})
        property var accountBusy: ({})
        property var statuses: ({})
        property var chats: [{key: "synthetic", id: "synthetic", provider: "telegram", name: "Test chat", preview: "Synthetic data", unread: 0}]
        property var visibleChats: chats
        property var selectedChat: chats[0]
        property var messages: [
            {id: "1", text: "Synthetic message https://example.org", out: false, sender: "Ein besonders langer Beispiel-Absendername", mediaType: "", mediaPath: "", time: "12:00"},
            {id: "2", text: "Eine längere Beispielnachricht für schmale Fenster und unterschiedliche Farbschemata.", out: true, sender: "", mediaType: "", mediaPath: "", time: "12:01", deliveryStatus: "read"},
            {id: "3", text: "Diese Antwort dient ausschließlich dem Layouttest.", out: false, sender: "Ein besonders langer Beispiel-Absendername", mediaType: "", mediaPath: "", time: "12:02", replyText: "Eine längere Beispielnachricht …"}
        ]
        function setDraft(value) { draft = value; }
        function setReply(value) { reply = value; }
        function closeDropdown() {}
    }
    FloatingWindow {
        id: window
        visible: true
        title: "DankChat isolated test"
        color: Theme.surface
        implicitWidth: root.promo ? 1280 : 900
        implicitHeight: root.promo ? 720 : 700
        Rectangle {
            id: promoBoard
            anchors.fill: parent
            visible: root.promo
            gradient: Gradient { GradientStop { position: 0; color: "#211a30" } GradientStop { position: 1; color: "#100e16" } }
            Text { x: 64; y: 90; text: "DANKMATERIALSHELL PLUGIN"; color: "#cbb7fa"; font.pixelSize: 16; font.letterSpacing: 3 }
            Text { x: 64; y: 190; text: "DankChat"; color: "#f2ecfa"; font.pixelSize: 56; lineHeight: 1.2 }
            Text { x: 64; y: 316; text: "Your accounts. One place."; color: "#c9bfd5"; font.pixelSize: 23 }
            Rectangle { x: 64; y: 364; width: 68; height: 3; color: "#cbb7fa" }
            Text { x: 64; y: 391; text: "DankChat 0.5.0"; color: "#e5ddec"; font.pixelSize: 23 }
            Text { x: 64; y: 443; text: "Telegram + WhatsApp accounts\nSearch, media & notifications\nDropdown + tiling window"; color: "#baadc9"; font.pixelSize: 20; lineHeight: 1.8 }
            Text { x: 64; y: 674; text: "NATIVE DMS CLIENT  /  OPEN SOURCE"; color: "#a69ab5"; font.pixelSize: 12; font.letterSpacing: 2 }
            Rectangle { x: 600; y: 64; width: 622; height: 540; radius: 20; color: Theme.surface; border.color: Theme.outline }
            Text { x: 600; y: 620; text: "Synthetic chats • No private messages"; color: "#a69ab5"; font.pixelSize: 14 }
        }
        Loader {
            id: view
            parent: root.promo ? promoBoard : window.contentItem
            x: root.promo ? 610 : 0
            y: root.promo ? 76 : 0
            scale: root.promo ? 0.69 : 1
            transformOrigin: Item.TopLeft
            width: root.testWidth
            height: root.promo ? 744 : 700
            Component.onCompleted: setSource(Quickshell.env("DANKCHAT_TEST_VIEW"), {service: mock, compact: false})
            onStatusChanged: if (status === Loader.Error) { console.error("TEST: view failed " + Qt.createComponent(Quickshell.env("DANKCHAT_TEST_VIEW")).errorString()); }
        }
    }
    IpcHandler {
        target: "test"
        function advance(): string {
            root.step++;
            Theme.currentTheme = "purple"; Theme.isLightMode = false; Theme.fontScale = 1;
            mock.accountsOpen = false; root.testWidth = root.promo ? 870 : 1080;
            if (root.step === 1) {
                mock.chats = [
                    {key: "demo-tg", id: "demo-tg", provider: "telegram", name: "Weekend plans", preview: "See you there!", unread: 2, pinned: true},
                    {key: "demo-wa", id: "demo-wa", provider: "whatsapp", name: "Coffee club", preview: "Saturday at ten?", unread: 3, pinned: true},
                    {key: "demo-work", id: "demo-work", provider: "telegram", name: "Design notes", preview: "The new colors look great.", unread: 0},
                    {key: "demo-family", id: "demo-family", provider: "whatsapp", name: "Family", preview: "Photo received", unread: 0}
                ];
                mock.unreadChatCount = 2;
                mock.selectedChat = mock.chats[0];
                mock.messages = [
                    {id: "1", text: "Anyone up for a walk and coffee this weekend? ☕", out: false, sender: "Alex · demo", time: "10:24"},
                    {id: "2", text: "Sounds good! Saturday works for me.", out: true, sender: "", time: "10:25", deliveryStatus: "read"},
                    {id: "3", text: "Let's meet by the park at ten.", out: false, sender: "Sam · demo", time: "10:26", replyId: "2", replyText: "Saturday works for me."},
                    {id: "4", text: "Perfect. I'll bring the snacks 🥐", out: true, sender: "", time: "10:27", deliveryStatus: "read"},
                    {id: "5", text: "See you there!", mediaType: "voice", mimeType: "audio/ogg", mediaPath: Quickshell.env("DANKCHAT_TEST_VOICE"), out: false, sender: "Alex · demo", time: "10:28", reactions: [{emoji: "👍", count: 2, chosen: true, custom: false}]}
                ];
            }
            if (root.step === 3) mock.reply = {id: "5", sender: "Alex · demo", text: "See you there!"};
            if (view.status !== Loader.Ready) return "FAIL preview not ready";
            if (root.step >= 4 && I18n.trFor("dankChat", "Unread chats") !== "Unread chats") return "FAIL preview must use English";
            if (root.step === 6) {
                if (root.promo) promoBoard.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/dankchat-promo.png"));
                else view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/dankchat-preview.png"));
            }
            return root.step === 12 ? "PASS synthetic preview" : "STEP " + root.step;
        }
    }
}
