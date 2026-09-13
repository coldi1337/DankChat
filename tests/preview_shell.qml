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
            Theme.currentTheme = "purple"; Theme.isLightMode = false; Theme.fontScale = 1;
            mock.accountsOpen = false; root.testWidth = 1080;
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
                    {id: "5", text: "See you there!", out: false, sender: "Alex · demo", time: "10:28"}
                ];
            }
            if (view.status !== Loader.Ready) return "FAIL preview not ready";
            if (root.step >= 4 && I18n.trFor("dankChat", "Unread chats") !== "Unread chats") return "FAIL preview must use English";
            if (root.step === 6) view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/dankchat-preview.png"));
            return root.step === 12 ? "PASS synthetic preview" : "STEP " + root.step;
        }
    }
}
