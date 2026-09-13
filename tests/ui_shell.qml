import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DankCommon.Common as DC
import qs.Widgets
import "testplugin/linkify.js" as Colors
import "Common/StockThemes.js" as StockThemes

ShellRoot {
    id: root
    property int step: 0
    property int testWidth: 900
    Rectangle { id: contrastProbe; color: Colors.readable(Theme.primaryContainer, Theme.surfaceText, Theme.primaryText) }
    Component.onCompleted: { DC.Style.theme = Theme; DC.Style.settings = SettingsData; I18n.registerPluginTranslations("dankChat", JSON.parse(Quickshell.env("DANKCHAT_TEST_TRANSLATIONS"))); }
    QtObject {
        id: mock
        property bool demo: true
        property bool telegramEnabled: true
        property bool whatsappEnabled: true
        property bool accountsOpen: false
        property bool writing: false
        property bool surfaceOpen: true
        property var activePlayer: null
        property string viewRevision: "test"
        property string filter: "all"
        property string query: ""
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
            Theme.currentTheme = StockThemes.getAllThemeNames()[Math.floor((root.step - 1) / 10) % StockThemes.getAllThemeNames().length];
            Theme.isLightMode = root.step % 2 === 0;
            Theme.fontScale = root.step % 5 === 0 ? 1.5 : 1;
            if (Colors.contrast(Theme.primaryContainer, contrastProbe.color) < 4.5) return "FAIL bubble contrast " + Theme.currentTheme;
            if (view.status !== Loader.Ready) return "FAIL view not ready";
            mock.statuses = root.step % 2 ? {telegram: {authorized: true}, whatsapp: {authorized: true}} : {};
            mock.accountsOpen = root.step % 7 < 2;
            root.testWidth = [360, 480, 760, 1080][root.step % 4];
            if (root.step === 10 || root.step === 30) view.item.previewAttachmentPicker(true);
            if (root.step === 20 || root.step === 40) view.item.previewAttachmentPicker(false);
            if ([4, 5, 6, 7, 8, 24, 25, 26, 27].includes(root.step)) view.item.grabToImage(result => result.saveToFile(Quickshell.env("DANKCHAT_TEST_ARTIFACTS") + "/layout-" + root.step + ".png"));
            return root.step === 100 ? "PASS accounts, resize, picker open/close" : "STEP " + root.step;

        }
    }
}
