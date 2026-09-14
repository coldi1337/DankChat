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
    property int attachmentsSent: -1
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
            if (chat.errorText) return "FAIL " + chat.errorText;
            chat.refresh();
            chat.accountsOpen = root.step % 3 === 0;
            if (root.step === 1) chat.openWindow();
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
            if (root.step % 4 === 0 && chat.chats.length) chat.selectChat(chat.chats[root.step % chat.chats.length]);
            if (root.step % 10 === 0) {
                chat.setAnchor(400, 0, 40, "center", Quickshell.screens[0], 0, 48, 4, null);
                chat.openDropdown();
            }
            if (root.step % 10 === 5) chat.openWindow();
            return root.step === 200 ? (automaticMediaObserved ? "PASS service refresh, surfaces and automatic media" : "FAIL automatic media not loaded") : "STEP " + root.step;
        }
    }
}
