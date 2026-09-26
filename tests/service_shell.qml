import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DankCommon.Common as DC
import qs.Modals.FileBrowser
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
ShellRoot {
    id: root
    property int step: 0
    property bool automaticMediaObserved: false
    property var readCalls: []
    property int attachmentsSent: -1
    property string recoveryChatKey: ""
    Component.onCompleted: { DC.Style.theme = Theme; DC.Style.settings = SettingsData; }
    Loader {
        id: service
        Component.onCompleted: source = Quickshell.env("DANKCHAT_TEST_SERVICE")
    }
    IpcHandler {
        target: "test"
        function advance(): string {
            if (service.status !== Loader.Ready) return "FAIL service not ready";
            root.step++;
            if (root.step % 10 === 0 && root.step < 180) {
                service.active = false;
                Qt.callLater(() => { service.active = true; });
                return "STEP reload " + root.step;
            }
            const chat = service.item;
            if (chat.messages.some(message => message.mediaType && message.mediaPath)) automaticMediaObserved = true;
            if (root.step === 189) {
                if (root.attachmentsSent !== 1 || chat.writing || !chat.errorText.includes("Synthetic attachment failure")) return "FAIL attachment failure did not stop batch " + JSON.stringify({sent: root.attachmentsSent, writing: chat.writing, error: chat.errorText});
                chat.errorText = "";
            }
            if (root.step === 216) {
                if (!chat.errorText.includes("Synthetic deletion failure") || !chat.messages.some(row => row.id === "1") || chat.writing) return "FAIL failed deletion removed message";
                chat.errorText = "";
            }
            if (root.step > 180 && !chat.windowReady) return "FAIL chat view did not load";
            if (chat.errorText && (root.step <= 226 || root.step >= 245)) return "FAIL " + chat.errorText;
            chat.refresh();
            if (root.step < 262) chat.accountsOpen = root.step % 3 === 0;
            if (root.step === 1) chat.openWindow();
            if (root.step === 183 && !chat.presenceText) return "FAIL live presence poll";
            if (root.step === 185) {
                chat.filter = "all"; chat.query = ""; chat.unreadOnly = true;
                if (chat.chats.length !== 240 || chat.visibleChats.length !== 180 || chat.unreadChatCount !== 180 || chat.unread !== 180 || chat.unreadMessages !== 360) return "FAIL unread-only filter/count";
                chat.filter = "telegram"; chat.query = "  Synthetic chat 119  ";
                if (chat.visibleChats.length !== 1 || chat.unreadChatCount !== 1 || chat.visibleChats[0].provider !== "telegram") return "FAIL unread provider/search combination";
                chat.query = "Synthetic chat 116";
                if (chat.visibleChats.length !== 0 || chat.unreadChatCount !== 0) return "FAIL read chat included";
                chat.unreadOnly = false;
                if (chat.visibleChats.length !== 1) return "FAIL unread filter cannot clear";
                chat.filter = "all"; chat.query = "";
            }
            if (root.step === 186) {
                chat.setDraft("Batch caption");
                chat.sendAttachments(["/tmp/test-one", "/tmp/test-two", "/tmp/test-three"], chat.selectedChat.key, sent => root.attachmentsSent = sent);
            }
            if (root.step === 187 && (root.attachmentsSent !== 3 || chat.writing || chat.draft !== "")) return "FAIL attachment batch";
            if (root.step === 188) {
                root.attachmentsSent = -1;
                chat.sendAttachments(["/tmp/test-ok", "/tmp/test-fail", "/tmp/test-not-sent"], chat.selectedChat.key, sent => root.attachmentsSent = sent);
            }
            if (root.step === 190) chat.jumpToReply("older-original");
            if (root.step === 191 && (!chat.historyContext || !chat.messages.some(message => message.id === "older-original"))) return "FAIL reply context";
            if (root.step === 191) chat.showLatest();
            if (root.step <= 200 && root.step % 4 === 0 && chat.chats.length) chat.selectChat(chat.chats[root.step % chat.chats.length]);
            if (root.step <= 200 && root.step % 10 === 0) {
                chat.setAnchor(400, 0, 40, "center", Quickshell.screens[0], 0, 48, 4, null);
                chat.openDropdown();
            }
            if (root.step <= 200 && root.step % 10 === 5) chat.openWindow();
            if (root.step === 201) { chat.setDraft("Keep this text"); chat.startVoice(); }
            if (root.step === 202) { if (chat.voiceState !== "recording") return "FAIL voice start"; chat.stopVoice(); }
            if (root.step === 203) { if (chat.voiceState !== "ready" || !chat.voicePath) return "FAIL voice stop"; chat.sendVoice(); }
            if (root.step === 204 && (chat.voiceState || chat.writing || chat.draft !== "Keep this text")) return "FAIL voice send or preserved text draft";
            if (root.step === 205) chat.startVoice();
            if (root.step === 206) { chat.closeDropdown(); chat.closeWindow(); }
            if (root.step === 207) { if (chat.voiceState !== "ready") return "FAIL close did not stop recording"; chat.discardVoice(); }
            if (root.step === 208 && (chat.voiceState || chat.voicePath)) return "FAIL voice discard";
            if (root.step === 211) { chat.setReply(chat.messages.find(row => row.id === "0")); chat.deleteMessage({id: "0"}, true, chat.selectedChat.key); }
            if (root.step === 212 && (chat.messages.some(row => row.id === "0") || chat.reply || chat.writing)) return "FAIL confirmed deletion or reply cleanup";
            if (root.step === 213) {
                chat.deleteMessage({id: "1"}, false, "different-chat");
                if (!chat.errorText || chat.writing) return "FAIL stale deletion target";
                chat.errorText = "";
            }
            if (root.step === 215) chat.deleteMessage({id: "1"}, false, chat.selectedChat.key);
            if (root.step === 218) { chat.openWindow(); chat.selectChat(chat.chats.find(row => row.provider === "whatsapp" && row.unread > 0)); }
            if (root.step === 219) {
                const count = chat.chats.length, key = chat.selectedChat.key;
                chat.setDraft("Preserve on network failure");
                chat.chatPresence = {activity: "typing", activityExpiresAt: Date.now() / 1000 + 30};
                chat.acceptProviderStatus("whatsapp", {ok: false});
                if (chat.chats.length !== count || chat.selectedChat.key !== key || chat.draft !== "Preserve on network failure" || Object.keys(chat.chatPresence).length) return "FAIL transient failure lost chat/draft or retained presence";
                chat.acceptProviderStatus("whatsapp", {ok: true, authorized: true});
                if (chat.syncFailures.whatsapp) return "FAIL recovery retained failure";
            }
            if (root.step === 220) chat.sendRequest("whatsapp", "test_external_read", {key: chat.selectedChat.key}, result => {});
            if (root.step === 224 && chat.chats.find(row => row.key === chat.selectedChat.key).unread !== 0) return "FAIL external read did not update unread state";
            if (root.step === 225 && (chat.diagnosticRequests.length === 0 || chat.diagnosticRequests.some(row => row.text || row.chat || row.path))) return "FAIL diagnostic metadata";
            if (root.step === 226) {
                root.recoveryChatKey = chat.selectedChat.key;
                chat.setAttachmentPaths(["/tmp/synthetic-pending"], root.recoveryChatKey);
                chat.selectChat(chat.chats.find(row => row.key !== root.recoveryChatKey));
                chat.selectChat(chat.chats.find(row => row.key === root.recoveryChatKey));
                if (chat.attachmentDrafts[root.recoveryChatKey][0] !== "/tmp/synthetic-pending") return "FAIL attachment draft lost on chat switch";
                chat.setDraft("Preserve across bridge restart");
                chat.sendRequest("whatsapp", "test_exit", {}, result => {});
            }
            if (root.step === 245) {
                if (chat.reconnecting || chat.syncFailures.whatsapp || chat.chats.length !== 240) return "FAIL bridge recovery";
                chat.selectChat(chat.chats.find(row => row.key === root.recoveryChatKey));
                if (chat.draft !== "Preserve across bridge restart" || Object.keys(chat.attachmentDrafts).length) return "FAIL restart draft retention/attachment cleanup";
            }
            if (root.step === 246) {
                const previous = chat.selectedChat;
                chat.selectChat(chat.chats.find(row => row.key !== previous.key));
                chat.selectChat(previous);
                if (!chat.messages.length) return "FAIL cached chat did not render immediately";
                chat.sendRequest("telegram", "test_slow_next_messages", {}, () => {});
            }
            if (root.step === 247) chat.selectChat(chat.chats.find(row => row.key === "telegram40"));
            if (root.step === 248) chat.selectChat(chat.chats.find(row => row.key === "telegram44"));
            if (root.step === 250 && (chat.loadingMessages || chat.messages.length !== 80)) return "FAIL slow old chat blocked new chat";
            if (root.step === 260 && (chat.selectedChat.key !== "telegram44" || !chat.messageCache.telegram40?.length)) return "FAIL delayed chat response lost or changed selection";
            if (root.step === 261) {
                const target = chat.selectedChat;
                const row = {id: "confirmed-image", out: true, text: "Sent", timestamp: 9999, mediaPath: "/tmp/confirmed.png", mediaType: "image"};
                chat.acceptSentMessage(target, {message: row});
                if (!chat.messages.some(item => item.id === row.id && item.mediaPath === row.mediaPath)) return "FAIL confirmed image not visible immediately";
                const stale = chat.mergeMessages(target.key, []);
                if (!stale.some(item => item.id === row.id)) return "FAIL stale fetch removed confirmed send";
                const synced = chat.mergeMessages(target.key, [Object.assign({}, row, {mediaPath: "", deliveryStatus: "read"})]);
                if (synced.length !== 1 || synced[0].deliveryStatus !== "read" || !synced[0].mediaPath) return "FAIL send reconciliation duplicated/lost receipt or preview";
            }
            if (root.step === 262) chat.changeAccount("telegram", "", "Work", true);
            if (root.step === 266) {
                if (!chat.accounts.some(a => a.id === "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" && a.label === "Work")) return "FAIL add account";
                const extra = chat.chats.find(c => c.account === "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" && c.id === "7");
                if (!extra) return "FAIL account chat listing";
                chat.accountFilter = chat.accountKey(extra.provider, extra.account);
                if (chat.visibleChats.some(c => c.account !== extra.account)) return "FAIL account filter leak";
                chat.selectChat(extra);
                chat.changeAccount(extra.provider, extra.account, "Family", false);
            }
            if (root.step === 270) {
                if (chat.accountLabel(chat.selectedChat) !== "Family") return "FAIL rename tab label";
                chat.browse("search", "match", false);
            }
            if (root.step === 273) {
                if (chat.browseResults[0]?.id !== "older-result") return "FAIL search results";
                chat.jumpToReply(chat.browseResults[0].id); chat.closeBrowse();
            }
            if (root.step === 276) {
                if (!chat.historyContext || chat.messages[0]?.id !== "older-result") return "FAIL open search result";
                chat.pluginData = Object.assign({}, chat.pluginData, {whatsappReadState: true, telegramReadReceipts: true});
                chat.accountFilter = "all"; chat.settingsOpen = false; chat.accountsOpen = false; chat.openWindow();
                chat.selectChat(chat.chats.find(c => c.key === "whatsapp7"));
            }
            if (root.step === 282) chat.sendRequest("", "test_read_calls", {}, result => root.readCalls = result.calls);
            if (root.step === 285) {
                if (!root.readCalls.includes("whatsapp7")) return "FAIL WhatsApp automatic read " + JSON.stringify({latest:chat.readingLatest,loading:chat.loadingMessages,enabled:chat.whatsappReadState, surface:chat.surfaceOpen, accounts:chat.accountsOpen, settings:chat.settingsOpen, browse:chat.browseMode, history:chat.historyContext, id:chat.selectedChat?.key, messages:chat.messages.length, attempts:chat.automaticReadAttempts});
                chat.readingLatest = false;
                chat.automaticReadAttempts = {};
                chat.settingsOpen = true;
                chat.readVisibleChat();
                chat.sendRequest("", "test_read_calls", {}, result => { if (result.calls.length !== root.readCalls.length) root.readCalls = ["unexpected"]; });
            }
            if (root.step === 288 && root.readCalls.includes("unexpected")) return "FAIL hidden chat marked read";
            return root.step === 290 ? (automaticMediaObserved ? "PASS service refresh, surfaces and automatic media" : "FAIL automatic media not loaded") : "STEP " + root.step;
        }
    }
}
