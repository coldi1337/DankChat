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
    property bool english: Quickshell.env("DANKCHAT_TEST_LANGUAGE") === "en"
    property int step: 0
    property int voicePreviewWaits: 0
    property int testWidth: 900
    Rectangle { id: contrastProbe; color: Colors.readable(Theme.primaryContainer, Theme.surfaceText, Theme.primaryText) }
    Component.onCompleted: { DC.Style.theme = Theme; DC.Style.settings = SettingsData; SessionData.locale = root.english ? "en" : "de"; I18n.registerPluginTranslations("dankChat", JSON.parse(Quickshell.env("DANKCHAT_TEST_TRANSLATIONS"))); }
    QtObject {
        id: mock
        signal messagesReplacing()
        property bool demo: true
        property bool telegramEnabled: true
        property bool whatsappEnabled: true
        property bool settingsOpen: false
        property var appInfo: ({version: "0.5.0", development: true, revision: "test"})
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
        function accountLabel(chat) { return chat?.provider || ""; }
        function accountConnectionText(provider, account) { return I18n.trFor("dankChat", "Connected"); }
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
            if (root.step < 121) mock.accountsOpen = root.step >= 60 ? false : root.step % 7 < 2;
            root.testWidth = root.step >= 60 ? 480 : [360, 480, 760, 1080][root.step % 4];
            if (root.step >= 60 && root.step <= 68) { mock.accountsOpen = false; root.testWidth = 480; Theme.fontScale = 1; }
            if (root.step >= 70 && root.step < 121) { mock.accountsOpen = false; root.testWidth = 480; Theme.fontScale = 1; }
            if (root.step >= 41 && root.step <= 43) mock.accountsOpen = false;
            if (root.step === 15) mock.presenceText = I18n.trFor("dankChat", "Typing…");
            if (root.step === 16) {
                const label = root.findItem(view.item, "chatPresenceLabel");
                if (!label || !label.text.includes(root.english ? "Typing…" : "Schreibt …")) return "FAIL translated typing status";
                mock.presenceText = I18n.trFor("dankChat", "Last seen within a month");
            }
            if (root.step === 17) {
                const label = root.findItem(view.item, "chatPresenceLabel");
                if (!label.text.includes(root.english ? "Last seen within a month" : "Innerhalb eines Monats online")) return "FAIL translated last seen";
                mock.presenceText = "";
            }
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
            if (root.step === 57) {
                mock.messages = [{id: "voice", text: "", mediaType: "audio", mimeType: "audio/ogg", mediaPath: Quickshell.env("DANKCHAT_TEST_VOICE"), out: false, sender: "Test"}];
            }
            if (root.step === 58) {
                const audio = root.findItem(view.item, "inlineMediaPlayer");
                const speed = root.findItem(view.item, "audioPlaybackSpeed");
                const progress = root.findItem(view.item, "audioPlaybackPosition");
                if (!audio?.audioOnly || !speed?.visible || !progress?.enabled || progress.to < 2900) return "FAIL voice player controls or duration";
                speed.clicked();
                if (speed.text !== (root.english ? "1.5×" : "1,5×")) return "FAIL voice playback speed";
                progress.value = 1200; progress.moved();
                audio.togglePlayback();
            }
            if (root.step === 59) mock.surfaceOpen = false;
            if (root.step === 60) {
                if (root.findItem(view.item, "inlineMediaPlayer")?.playing) return "FAIL voice kept playing after closing";
                mock.surfaceOpen = true;
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
            if (root.step >= 97 && root.step <= 100) {
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
            if (root.step === 101) { mock.demo = false; root.findItem(view.item, "recordVoiceButton").clicked(); }
            if (root.step === 102) {
                const box = root.findItem(view.item, "voiceComposer");
                if (!box.visible || box.height < 60 || box.width > view.item.width) return "FAIL voice recording layout";
                if (mock.voiceState !== "recording") return "FAIL microphone button";
                if (I18n.trFor("dankChat", "Stop recording") !== (root.english ? "Stop recording" : "Aufnahme stoppen")) return "FAIL recording translation";
                mock.stopVoice();
            }
            if (root.step === 103) {
                const box = root.findItem(view.item, "voiceComposer");
                const player = root.findItem(box, "inlineMediaPlayer");
                if (!player || box.height < 150) {
                    if (++root.voicePreviewWaits <= 20) { root.step--; return "STEP waiting for voice preview layout"; }
                    return "FAIL voice preview " + JSON.stringify({player: !!player, height: box.height});
                }
                if (!player.audioOnly) return "FAIL voice preview is not audio";
                view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/voice-preview.png"));
            }
            if (root.step === 104) mock.discardVoice();
            if (root.step === 105 && root.findItem(view.item, "voiceComposer").visible) return "FAIL discard voice preview";
            if (root.step === 106) {
                mock.selectedChat = {key: "delete-wa", provider: "whatsapp", deleteForMe: true};
                view.item.openDeleteMessage({id: "7", text: "Synthetic message", out: true});
            }
            if (root.step === 107) {
                const dialog = view.item.deleteMessageDialog;
                const scope = root.findItem(dialog.contentItem, "deleteForEveryone");
                if (!dialog.visible || !scope.visible || scope.checked || mock.deletionCalls.length) return "FAIL delete dialog default or premature deletion";
                if (scope.text !== (root.english ? "Delete for everyone" : "Für alle löschen")) return "FAIL delete translation";
                dialog.accept();
                if (mock.deletionCalls.length !== 1 || !mock.deletionCalls[0].forMe) return "FAIL delete for me";
                view.item.openDeleteMessage({id: "8", text: "Synthetic outgoing", out: true});
                scope.checked = true;
                dialog.accept();
                if (mock.deletionCalls.length !== 2 || mock.deletionCalls[1].forMe) return "FAIL delete for everyone";
                view.item.openDeleteMessage({id: "9", text: "Synthetic incoming", out: false});
                if (scope.visible) return "FAIL WhatsApp incoming delete for everyone offered";
                dialog.reject();
            }
            if (root.step === 108) {
                mock.selectedChat = {key: "delete-tg", provider: "telegram", deleteForMe: false};
                view.item.openDeleteMessage({id: "10", text: "Synthetic group message", out: true});
            }
            if (root.step === 109) {
                const dialog = view.item.deleteMessageDialog;
                if (root.findItem(dialog.contentItem, "deleteForEveryone").visible) return "FAIL misleading Telegram group scope";
                dialog.accept();
                if (mock.deletionCalls.length !== 3 || mock.deletionCalls[2].forMe) return "FAIL Telegram group deletion scope";
                view.item.openDeleteMessage({id: "11", text: "Synthetic cancelled message", out: true});
                mock.selectedChat = {key: "different", provider: "telegram"};
                if (dialog.visible || mock.deletionCalls.length !== 3) return "FAIL stale delete dialog";
            }
            if (root.step === 110) {
                mock.selectedChat = {key: "scroll-performance", provider: "telegram", name: "Scroll test"};
                mock.messages = Array.from({length: 60}, (_, i) => ({id: "scroll-" + i, text: "Synthetic message " + i, out: false, time: "12:00", mediaType: i === 59 ? "image" : "", mediaPath: "", reactions: []}));
            }
            if (root.step === 112 && !messagesView.atYEnd) return "FAIL switched chat did not open at latest";
            if (root.step === 113) {
                mock.messagesReplacing();
                mock.messages = mock.messages.map(row => row.id === "scroll-59" ? Object.assign({}, row, {mediaPath: Quickshell.env("DANKCHAT_TEST_IMAGE")}) : row);
            }
            if (root.step === 116 && !messagesView.atYEnd) return "FAIL delayed image moved chat off latest";
            if (root.step === 117) { messagesView.followTail = false; messagesView.positionViewAtBeginning(); }
            if (root.step === 118) { mock.messagesReplacing(); mock.messages = mock.messages.map(row => Object.assign({}, row, {deliveryStatus: "read"})); }
            if (root.step === 120 && !messagesView.atYBeginning) return "FAIL background update stole reading position";
            if (root.step === 121) { mock.settingsOpen = true; root.testWidth = 380; Theme.fontScale = 1.2; }
            if (root.step === 124) {
                if (I18n.trFor("dankChat", "Settings") !== (root.english ? "Settings" : "Einstellungen")) return "FAIL settings translation";
                const version = root.findItem(view.item, "installedVersion");
                if (!version || version.text !== "DankChat v0.5.0") return "FAIL installed version";
                view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/settings.png"));
            }
            if (root.step === 125) { mock.settingsOpen = false; mock.accountsOpen = true; mock.accounts = [{provider: "telegram", id: "a", label: "Privat und Familie"}, {provider:"whatsapp", id:"b", label:"Arbeit und Projekte"}, {provider:"telegram", id:"c", label:"Zweites Telegram-Konto"}]; }
            if (root.step === 128) view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/accounts.png"));
            if (root.step === 129) { mock.accountsOpen = false; mock.browseMode = "search"; mock.browseResults = [{id:"result",text:"Synthetic search result",timestamp:1}]; }
            if (root.step === 132) {
                if (!root.findItem(view.item, "messageSearch")) return "FAIL search view";
                view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/search.png"));
            }
            if (root.step === 133) { mock.browseMode = ""; mock.selectedChat = null; }
            if (root.step === 135) {
                const selectors = root.findItem(view.item, "accountSelectors");
                const buttons = [];
                for (let i = 0; i < selectors.children.length; ++i) if (selectors.children[i].objectName === "accountFilterButton") buttons.push(selectors.children[i]);
                if (buttons.length !== 4 || buttons.some(b => Math.abs(b.width - selectors.width) > 1)) return "FAIL account buttons do not fill sidebar";
                if (Math.abs(root.findItem(view.item, "unreadFilter").width - selectors.width) > 1) return "FAIL unread button does not fill sidebar";
                view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/account-buttons.png"));
            }
            return root.step === 137 ? "PASS accounts, settings, search, resize, picker open/close" : "STEP " + root.step;

        }
    }
}
