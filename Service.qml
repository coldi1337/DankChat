import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null
    readonly property string viewRevision: String(Date.now())
    readonly property bool demo: pluginData.demoMode ?? false
    readonly property bool telegramEnabled: pluginData.telegramEnabled ?? true
    readonly property bool whatsappEnabled: pluginData.whatsappEnabled ?? true
    readonly property bool readReceipts: pluginData.telegramReadReceipts ?? false
    property var chats: []
    property var messages: []
    property var selectedChat: null
    property var statuses: ({})
    property var drafts: ({})
    property var replies: ({})
    property string filter: "all"
    property string query: ""
    property string errorText: ""
    property string qrPath: ""
    property bool accountsOpen: false
    property bool writing: false
    property bool loadingMessages: false
    property int nextRequest: 0
    property int configurationEpoch: 0
    property var pending: ({})
    readonly property int unread: chats.reduce((sum, chat) => sum + chat.unread, 0)
    readonly property bool surfaceOpen: popout.shouldBeVisible || app.visible
    readonly property var visibleChats: chats.filter(chat => (filter === "all" || chat.provider === filter)
        && (chat.name + " " + chat.preview).toLowerCase().includes(query.toLowerCase()))
    readonly property string draft: selectedChat ? (drafts[selectedChat.key] || "") : ""
    readonly property var reply: selectedChat ? (replies[selectedChat.key] || null) : null

    function sendRequest(provider, action, payload, callback) {
        if (!bridge.running || demo) return false;
        if (["status", "chats"].includes(action) && Object.values(pending).some(entry => entry.provider === provider && entry.action === action)) return false;
        const id = ++nextRequest;
        const request = Object.assign({}, payload || {}, {provider: provider, action: action, requestId: id});
        const epoch = configurationEpoch;
        pending[id] = {provider: provider, action: action, callback: result => { if (epoch === configurationEpoch && callback) callback(result); }};
        bridge.write(JSON.stringify(request) + "\n");
        return true;
    }
    function configure() {
        configurationEpoch++;
        loadingMessages = false;
        chats = []; messages = []; selectedChat = null; statuses = {}; qrPath = "";
        if (demo) { loadDemo(); return; }
        const enabled = [];
        if (telegramEnabled) enabled.push("telegram");
        if (whatsappEnabled) enabled.push("whatsapp");
        sendRequest("", "configure", {enabled: enabled}, () => refresh());
    }
    function refresh() {
        if (demo) return;
        ["telegram", "whatsapp"].forEach(provider => {
            if ((provider === "telegram" && !telegramEnabled) || (provider === "whatsapp" && !whatsappEnabled)) return;
            sendRequest(provider, "status", {}, result => {
                const states = Object.assign({}, statuses); states[provider] = result; statuses = states;
                if (provider === "telegram") qrPath = result.qrPath || "";
                if (!result.authorized) return;
                if (provider === "telegram") qrPath = "";
                sendRequest(provider, "chats", {}, result => {
                    if (!result.ok) { errorText = result.error || ""; return; }
                    chats = chats.filter(chat => chat.provider !== provider).concat(result.chats || [])
                        .sort((a, b) => b.timestamp - a.timestamp || a.key.localeCompare(b.key));
                });
            });
        });
        if (surfaceOpen && selectedChat) loadMessages();
    }
    function selectChat(chat) {
        selectedChat = chat; messages = []; errorText = "";
        if (demo) { demoMessages(); return; }
        loadMessages();
        if (chat.provider === "telegram" && readReceipts)
            sendRequest("telegram", "read", {chat: chat}, result => { if (!result.ok) errorText = result.error; });
        if (chat.provider === "whatsapp")
            sendRequest("whatsapp", "acknowledge", {chat: chat}, result => { if (!result.ok) errorText = result.error; });
    }
    function loadMessages() {
        if (!selectedChat || loadingMessages || demo) return;
        const chat = selectedChat;
        loadingMessages = true;
        if (!sendRequest(chat.provider, "messages", {chat: chat}, result => {
            loadingMessages = false;
            if (selectedChat?.key !== chat.key) { loadMessages(); return; }
            if (result.ok) {
                const incoming = result.messages || [];
                if (JSON.stringify(incoming) !== JSON.stringify(messages)) messages = incoming;
            } else errorText = result.error || "";
        })) loadingMessages = false;
    }
    function setDraft(text) {
        if (!selectedChat) return;
        const values = Object.assign({}, drafts); values[selectedChat.key] = text; drafts = values;
    }
    function setReply(message) {
        if (!selectedChat) return;
        const values = Object.assign({}, replies); values[selectedChat.key] = message; replies = values;
    }
    function sendMessage(path, expectedKey) {
        if (!selectedChat || writing || demo || (!path && !draft.trim())) return;
        if (expectedKey && selectedChat.key !== expectedKey) {
            errorText = I18n.trFor("dankChat", "The selected chat changed. Choose the attachment again."); return;
        }
        const chat = selectedChat;
        const text = draft;
        writing = true; errorText = "";
        if (!sendRequest(chat.provider, path ? "file" : "send", {chat: chat, text: text, path: path || "", replyId: reply?.id || ""}, result => {
            writing = false;
            if (!result.ok) { errorText = result.error; return; }
            const values = Object.assign({}, drafts);
            if (values[chat.key] === text) values[chat.key] = "";
            drafts = values;
            const replyValues = Object.assign({}, replies); delete replyValues[chat.key]; replies = replyValues;
            if (selectedChat?.key === chat.key) loadMessages();
        })) writing = false;
    }
    function loginTelegram() {
        errorText = "";
        sendRequest("telegram", "login", {}, result => {
            if (result.ok) { qrPath = result.qrPath || ""; refresh(); }
            else errorText = result.error;
        });
    }
    function submitPassword(password) {
        sendRequest("telegram", "password", {password: password}, result => {
            if (!result.ok) errorText = result.error;
            else refresh();
        });
    }
    function openWindow() {
        if (IdleService.isShellLocked) return;
        popout.close(); app.visible = true; refresh();
    }
    function openDropdown() {
        if (IdleService.isShellLocked) return;
        app.visible = false; popout.toggle(); refresh();
    }
    function setAnchor(x, y, width, section, screen, edge, thickness, spacing, config) {
        popout.setTriggerPosition(x, y, width, section, screen, edge, thickness, spacing, config);
    }
    function loadDemo() {
        const now = Date.now() / 1000;
        chats = [
            {key: "demo-wa-team", provider: "whatsapp", id: "demo-team", account: "demo", name: "Design team", preview: "One home for both conversations.", timestamp: now, unread: 3, group: true},
            {key: "demo-tg-alex", provider: "telegram", id: "demo-alex", account: "", name: "Alex", preview: "Looks good. See you tomorrow!", timestamp: now - 80, unread: 1},
            {key: "demo-tg-dms", provider: "telegram", id: "demo-dms", account: "", name: "Desktop ideas", preview: "The new layout is ready to try.", timestamp: now - 300, unread: 0, group: true},
            {key: "demo-wa-sam", provider: "whatsapp", id: "demo-sam", account: "demo", name: "Sam", preview: "Coffee at ten?", timestamp: now - 600, unread: 0}
        ];
        statuses = {telegram: {authorized: true}, whatsapp: {authorized: true}};
        selectedChat = chats[0]; demoMessages();
    }
    function demoMessages() {
        messages = [
            {id: "demo-1", sender: "Alex", text: "How is the shared chat layout coming along?", out: false, time: "10:24", mediaType: "", mediaPath: "", replyText: ""},
            {id: "demo-2", sender: "You", text: "Telegram and WhatsApp now share the same chat list and composer.", out: true, time: "10:25", mediaType: "", mediaPath: "", replyText: ""},
            {id: "demo-3", sender: "Alex", text: "Nice — quick replies from the bar, and more room when you need it.", out: false, time: "10:26", mediaType: "", mediaPath: "", replyText: ""},
            {id: "demo-4", sender: "You", text: "Exactly. This conversation stays selected when opening the full window.", out: true, time: "10:27", mediaType: "", mediaPath: "", replyText: ""}
        ];
    }

    onDemoChanged: { pending = {}; writing = false; loadingMessages = false; configure(); }
    onTelegramEnabledChanged: configure()
    onWhatsappEnabledChanged: configure()
    Connections {
        target: IdleService
        function onIsShellLockedChanged() {
            if (IdleService.isShellLocked) { popout.close(); app.visible = false; qrPath = ""; }
        }
    }
    Process {
        id: bridge
        command: ["sh", Qt.resolvedUrl("scripts/run-bridge").toString().replace("file://", "")]
        running: !root.demo
        stdinEnabled: true
        onStarted: root.configure()
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    const entry = root.pending[result.requestId];
                    delete root.pending[result.requestId];
                    if (entry) entry.callback(result);
                } catch (e) { root.errorText = I18n.trFor("dankChat", "Could not read the service response."); }
            }
        }
        stderr: StdioCollector {}
        onExited: {
            root.pending = {}; root.writing = false; root.loadingMessages = false;
            if (!root.demo) root.errorText = I18n.trFor("dankChat", "The chat service stopped. Reload DankChat to reconnect.");
        }
    }
    Timer { interval: root.accountsOpen ? 2000 : root.surfaceOpen ? 5000 : 30000; running: !root.demo; repeat: true; onTriggered: root.refresh() }
    DankPopout {
        id: popout
        popupWidth: 760
        popupHeight: 590
        contentHandlesKeys: true
        content: Component {
            Loader {
                id: dropdownView
                anchors.fill: parent
                Component.onCompleted: setSource(Qt.resolvedUrl("ChatView.qml") + "?revision=" + root.viewRevision, {service: root, compact: true})
                Connections {
                    target: dropdownView.item
                    function onExpandRequested() { root.openWindow(); }
                    function onCloseRequested() { popout.close(); }
                }
            }
        }
    }
    DankFloatingWindow {
        id: app
        title: "DankChat"
        surfaceColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 1)
        visible: false
        implicitWidth: 1080
        implicitHeight: 740
        minimumSize: Qt.size(360, 420)
        onClosed: visible = false
        Loader {
            id: windowView
            anchors.fill: parent
            Component.onCompleted: setSource(Qt.resolvedUrl("ChatView.qml") + "?revision=" + root.viewRevision, {service: root, compact: false})
            Connections {
                target: windowView.item
                function onCloseRequested() { app.visible = false; }
            }
        }
    }
    IpcHandler {
        target: "dankChat"
        function open(): void { root.openWindow(); }
        function close(): void { popout.close(); app.visible = false; }
        function refresh(): void { root.refresh(); }
        function accounts(): void { root.accountsOpen = true; root.openWindow(); }
        function preview(): string {
            if (!root.demo || !app.visible) return "Demo window must be open.";
            windowView.item.grabToImage(result => result.saveToFile(Quickshell.env("HOME") + "/.cache/dankchat-preview.png"));
            return "Capturing demo view to ~/.cache/dankchat-preview.png";
        }
        function demo(enabled: bool): void { root.pluginService?.savePluginData("dankChat", "demoMode", enabled); }
        function status(): string { return JSON.stringify({demo: root.demo, window: app.visible, dropdown: popout.shouldBeVisible, bridge: bridge.running, pending: Object.keys(root.pending).length, telegram: !!root.statuses.telegram?.authorized, whatsapp: !!root.statuses.whatsapp?.authorized, telegramAuthState: root.statuses.telegram?.authState || ""}); }
    }
}
