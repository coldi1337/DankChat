import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DankCommon.Common as DC
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
ShellRoot {
    id: root
    property int step: 0
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
            const chat = service.item;
            chat.refresh();
            chat.accountsOpen = root.step % 3 === 0;
            if (root.step === 1) chat.openWindow();
            if (root.step % 4 === 0 && chat.chats.length) chat.selectChat(chat.chats[root.step % chat.chats.length]);
            if (root.step % 10 === 0) {
                chat.setAnchor(400, 0, 40, "center", Quickshell.screens[0], 0, 48, 4, null);
                chat.openDropdown();
            }
            if (root.step % 10 === 5) chat.openWindow();
            return root.step === 200 ? "PASS service refresh and surfaces" : "STEP " + root.step;
        }
    }
}
