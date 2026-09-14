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
        if (item.objectName === name) return item;
        for (let child of item.children || []) {
            const found = findItem(child, name);
            if (found) return found;
        }
        return null;
    }
    property var observedVideo: null
    property real videoScroll: 0
    property bool english: Quickshell.env("DANKCHAT_TEST_LANGUAGE") === "en"
    property int step: 0
    property int testWidth: 900
    Rectangle { id: contrastProbe; color: Colors.readable(Theme.primaryContainer, Theme.surfaceText, Theme.primaryText) }
    Component.onCompleted: { DC.Style.theme = Theme; DC.Style.settings = SettingsData; SessionData.locale = root.english ? "en" : "de"; I18n.registerPluginTranslations("dankChat", JSON.parse(Quickshell.env("DANKCHAT_TEST_TRANSLATIONS"))); }
    QtObject {
        id: mock
        signal messagesReplacing()
        property bool demo: true
        property bool telegramEnabled: true
        property bool whatsappEnabled: true
        property bool accountsOpen: false
        property bool writing: false
        property bool surfaceOpen: true
        property bool historyContext: false
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
        property int clipboardRequests: 0
        function sendRequest(provider, action, payload, callback) {
            if (action === "clipboard_image") { clipboardRequests++; callback({ok: true, paths: [Quickshell.env("DANKCHAT_TEST_IMAGE")]}); }
            else callback({ok: true});
            return true;
        }
        property var reactionEvents: []
        function reactToMessage(message, emoji, chat) {
            reactionEvents = reactionEvents.concat([{id: message.id, emoji: emoji, chat: chat.key}]);
        }
        function setDraft(value) { draft = value; }
        function setReply(value) { reply = value; }
        function closeDropdown() {}
    }
    FloatingWindow {
        id: window
        visible: true
        title: "DankChat isolated test"
        color: Theme.surface
        implicitWidth: 900
        implicitHeight: 700
        Loader {
            id: view
            width: root.testWidth
            height: 700
            Component.onCompleted: setSource(Quickshell.env("DANKCHAT_TEST_VIEW"), {service: mock, compact: false})
            onStatusChanged: if (status === Loader.Error) { console.error("TEST: view failed " + Qt.createComponent(Quickshell.env("DANKCHAT_TEST_VIEW")).errorString()); Quickshell.quit(); }
        }
    }
    IpcHandler {
        target: "test"
        function advance(): string {
            root.step++;
            if (view.status === Loader.Ready) view.item.compact = root.step % 2 === 0;
            if (I18n.trFor("dankChat", "Send attachments") !== (root.english ? "Send attachments" : "Anhänge senden")) return "FAIL attachment title translation";
            if (I18n.trFor("dankChat", "Choose a local file smaller than 100 MB.") !== (root.english ? "Choose a local file smaller than 100 MB." : "Wähle eine lokale Datei mit weniger als 100 MB.")) return "FAIL file size translation";
            if (root.step < 92) {
                Theme.currentTheme = StockThemes.getAllThemeNames()[Math.floor((root.step - 1) / 10) % StockThemes.getAllThemeNames().length];
                Theme.isLightMode = root.step % 2 === 0;
            }
            Theme.fontScale = root.step >= 60 ? 1 : root.step % 5 === 0 ? 1.5 : 1;
            if (Colors.contrast(Theme.primaryContainer, contrastProbe.color) < 4.5) return "FAIL bubble contrast " + Theme.currentTheme;
            if (view.status !== Loader.Ready) return "FAIL view not ready";
            if (I18n.trFor("dankChat", "Unread chats") !== (root.english ? "Unread chats" : "Ungelesene Chats")) return "FAIL unread translation";
            const pinError = I18n.trFor("dankChat", "Telegram pin limit reached: the main chat list allows 5 pinned chats without Premium (10 with Premium). Unpin another chat first.");
            if (!pinError.startsWith(root.english ? "Telegram pin limit" : "Telegram-Pin-Limit")) return "FAIL pin-limit translation";
            mock.errorText = root.step >= 24 && root.step <= 27 ? pinError : "";
            mock.statuses = root.step % 2 ? {telegram: {authorized: true}, whatsapp: {authorized: true}} : {};
            mock.accountsOpen = root.step >= 60 ? false : root.step % 7 < 2;
            root.testWidth = root.step >= 60 ? 480 : [360, 480, 760, 1080][root.step % 4];
            if (root.step >= 60 && root.step <= 68) { mock.accountsOpen = false; root.testWidth = 480; Theme.fontScale = 1; }
            if (root.step >= 70) { mock.accountsOpen = false; root.testWidth = 480; Theme.fontScale = 1; }
            if (root.step >= 41 && root.step <= 43) mock.accountsOpen = false;
            if (root.step === 41) {
                mock.messages = mock.messages.map((row, index) => index === 0 ? Object.assign({}, row, {reactions: [{emoji: "👍", count: 2, chosen: true, custom: false}]}) : row);
                mock.draft = "Keep this draft";
                view.item.openReactionPicker(mock.messages[0]);
                view.item.insertEmoji("👍");
                if (mock.draft !== "Keep this draft" || mock.reactionEvents.length !== 1 || mock.reactionEvents[0].emoji !== "") return "FAIL reaction removal changed draft or wrong action";
                view.item.openReactionPicker(mock.messages[0]);
                view.item.insertEmoji("❤️");
                if (mock.reactionEvents[1].emoji !== "❤️") return "FAIL reaction selection";
                view.item.openReactionPicker(mock.messages[0]);
                mock.selectedChat = {key: "different", provider: "telegram"};
                view.item.insertEmoji("🔥");
                if (mock.reactionEvents.length !== 2) return "FAIL reaction sent after chat switch";
                mock.selectedChat = mock.chats[0];
            }
            if (root.step >= 44 && root.step <= 48) mock.accountsOpen = false;
            if (root.step === 44) mock.reply = {id: "quoted", sender: "A deliberately long sender name", text: "A long quoted message that should wrap inside its own box. ".repeat(8)};
            if (root.step === 45) {
                const replyBox = root.findItem(view.item, "replyComposerPreview");
                if (!replyBox || !replyBox.visible || replyBox.height < 50 || replyBox.height > 180) return "FAIL reply preview layout";
            }
            if (root.step === 46) {
                view.item.addAttachments([Quickshell.env("DANKCHAT_TEST_VIDEO"), "/tmp/synthetic-document.pdf"]);
                view.item.addAttachments([Quickshell.env("DANKCHAT_TEST_VIDEO")]);
                if (view.item.attachmentPaths.length !== 2) return "FAIL multiple attachments or deduplication";
                view.item.attachmentChatKey = mock.selectedChat.key;
                mock.demo = false;
                view.item.pasteClipboard();
                if (mock.clipboardRequests !== 1 || view.item.attachmentPaths.length !== 3) return "FAIL clipboard image staging";
                mock.demo = true;
            }
            if (root.step === 47) {
                const status = JSON.parse(view.item.attachmentPreviewStatus());
                if (!status.visible || status.count !== 3 || status.height < 100 || status.height > 700) return "FAIL attachment preview dialog";
            }
            if (root.step === 47) view.item.previewAttachmentImage(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/attachments-dialog.png");
            if (root.step === 48) { view.item.previewAttachments(false); mock.reply = null; }
            if (root.step === 43) {
                const chip = root.findItem(view.item, "reactionChip");
                if (!chip || !chip.modelData.chosen || chip.modelData.count !== 2 || !chip.visible || chip.width <= 0 || chip.height <= 0) return "FAIL own reaction display";
            }
            if (root.step === 67) {
                mock.messages = [{id: "wa-gif", text: "", mediaType: "gif", mimeType: "video/mp4", mediaPath: Quickshell.env("DANKCHAT_TEST_WHATSAPP_GIF"), out: false, sender: "Test"}];
            }
            if (root.step === 68) {
                const gifPlayer = root.findItem(view.item, "inlineMediaPlayer");
                if (!gifPlayer || !gifPlayer.visible || gifPlayer.audioOnly) return "FAIL WhatsApp MP4 GIF was not rendered as video";
            }
            if (root.step === 70 || root.step === 80) {
                mock.selectedChat = {key: "scroll-" + root.step, provider: "telegram", name: "Scroll test"};
                mock.messages = [];
            }
            if ([71, 81, 89].includes(root.step)) {
                mock.messagesReplacing();
                mock.messages = Array.from({length: 80}, (_, i) => ({id: String(i), text: "Synthetic message " + i + "\nSecond line", out: i % 2 === 0, sender: "Test"}));
            }
            const messagesView = root.findItem(view.item, "messageList");
            if ([73, 83, 86, 91].includes(root.step) && !messagesView.atYEnd) return "FAIL chat did not open/stay at latest message " + root.step;
            if (root.step === 74) { messagesView.followTail = false; messagesView.positionViewAtBeginning(); }
            if (root.step === 75 || root.step === 84) {
                mock.messagesReplacing();
                mock.messages = mock.messages.concat([{id: "extra", text: "Later content\n".repeat(12), out: false, sender: "Test"}]);
            }
            if (root.step === 77 && messagesView.atYEnd) return "FAIL refresh interrupted reading older messages";
            if (root.step === 88) { messagesView.followTail = false; messagesView.positionViewAtBeginning(); mock.messages = []; }
            if (root.step === 92) {
                mock.messagesReplacing();
                mock.messages = mock.messages.concat([{id: "video-last", text: "", mediaType: "video", mediaPath: Quickshell.env("DANKCHAT_TEST_VIDEO"), out: false, sender: "Test"}]);
            }
            if (root.step === 95) {
                root.observedVideo = root.findItem(view.item, "inlineMediaPlayer");
                root.videoScroll = root.observedVideo ? root.observedVideo.mapToItem(messagesView, 0, 0).y : 0;
                if (!root.observedVideo) return "FAIL last video missing";
            }
            if (root.step === 96) {
                mock.messagesReplacing();
                mock.messages = mock.messages.map(message => message.id === "0" ? Object.assign({}, message, {deliveryStatus: "read"}) : message);
            }
            if (root.step === 98) {
                mock.messagesReplacing();
                mock.messages = mock.messages.map(message => message.id === "video-last" ? Object.assign({}, message, {deliveryStatus: "read"}) : message);
            }
            if (root.step >= 97) {
                if (!root.observedVideo || root.findItem(view.item, "inlineMediaPlayer") !== root.observedVideo) return "FAIL last video recreated";
                if (!messagesView.atYEnd || Math.abs(root.observedVideo.mapToItem(messagesView, 0, 0).y - root.videoScroll) > 1) return "FAIL last video scroll unstable";
            }
            if (root.step === 30) { view.item.savingMedia = true; view.item.exportMessage = {filename: "synthetic.png"}; }
            if (root.step === 10 || root.step === 30) view.item.previewAttachmentPicker(true);
            if (root.step === 20 || root.step === 40) view.item.previewAttachmentPicker(false);
            if (root.step === 50) {
                mock.accountsOpen = false;
                const editor = root.findItem(view.item, "messageComposer");
                editor.text = "Hallo Welt";
                editor.select(6, 10);
                view.item.openEmojiPicker();
            }
            if (root.step === 51) {
                view.item.insertEmoji("❤️");
                if (mock.draft !== "Hallo ❤️") return "FAIL emoji selection replacement";
                const editor = root.findItem(view.item, "messageComposer");
                editor.cursorPosition = 0;
                view.item.openEmojiPicker();
                view.item.insertEmoji("😀");
                if (mock.draft !== "😀Hallo ❤️" || editor.cursorPosition !== 2) return "FAIL emoji cursor insertion";
                view.item.openEmojiPicker();
                mock.selectedChat = {key: "different", provider: "telegram"};
                view.item.insertEmoji("🔥");
                if (mock.draft !== "😀Hallo ❤️") return "FAIL emoji inserted into different chat";
                mock.selectedChat = mock.chats[0];
            }
            if (root.step === 52) { view.item.openEmojiPicker(); view.item.previewEmojiSearch("österreich"); }
            if (root.step === 54) {
                const layout = JSON.parse(view.item.emojiLayoutStatus());
                if (layout.count !== 1 || layout.text !== "🇦🇹") return "FAIL German emoji search " + JSON.stringify(layout);
                view.item.previewEmojiSearch("zzzz-no-match");
            }
            if (root.step === 56 && JSON.parse(view.item.emojiLayoutStatus()).count !== 0) return "FAIL emoji empty search";
            if (root.step === 60) { mock.accountsOpen = false; view.item.openEmojiPicker(); }
            if (root.step === 63) {
                const layout = JSON.parse(view.item.emojiLayoutStatus());
                if (layout.count !== 3953 || layout.height < 160 || !(layout.labelWidth >= 24) || !(layout.labelHeight >= 24) || layout.text !== "😀") return "FAIL emoji grid " + JSON.stringify(layout);
                view.item.previewEmojiImage(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/emoji.png");
            }
            if (root.step === 68) view.item.insertEmoji("👍");
            if ([4, 5, 6, 7, 8, 24, 25, 26, 27, 43, 45, 47].includes(root.step)) view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/layout-" + root.step + ".png"));
            return root.step === 100 ? "PASS accounts, resize, picker open/close" : "STEP " + root.step;

        }
    }
}
