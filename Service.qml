import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
    readonly property bool whatsappReadState: pluginData.whatsappReadState ?? false
    readonly property bool automaticMedia: pluginData.automaticMedia ?? true
    readonly property bool automaticUpdates: pluginData.automaticUpdates ?? true
    readonly property bool windowReady: windowView.status === Loader.Ready
    property bool settingsOpen: false
    property var appInfo: ({})
    property var updateInfo: ({})
    property bool checkingUpdates: false
    property double lastUpdateAttempt: 0
    function savePreference(key, value) {
        if (!["telegramReadReceipts", "whatsappReadState", "automaticMedia", "automaticUpdates", "cacheLimitMb", "cacheDays", "mediaLimitMb", "mediaTypes", "notificationMode", "notificationPreview", "notificationSound", "suppressActive", "closeOnBlur"].includes(key)) return;
        pluginService?.savePluginData("dankChat", key, value);
        if (key === "whatsappReadState") Qt.callLater(refresh);
        if (key === "automaticMedia" && value) Qt.callLater(loadNextMedia);
        if (key === "automaticUpdates" && value) checkUpdates(false);
    }
    function checkUpdates(force) {
        if (demo || checkingUpdates || (!force && Date.now() - lastUpdateAttempt < 86400000)) return;
        checkingUpdates = true; lastUpdateAttempt = Date.now();
        if (!sendRequest("", "check_updates", {force: !!force}, result => {
            checkingUpdates = false; updateInfo = result;
            if (result.version) appInfo = result;
        })) { checkingUpdates = false; lastUpdateAttempt = 0; }
    }
    property bool readingLatest: false
    property var automaticReadAttempts: ({})
    function readVisibleChat() {
        if (!surfaceOpen || settingsOpen || accountsOpen || !!browseMode || !readingLatest || historyContext || loadingMessages || !selectedChat || !messages.length) return;
        const chat = selectedChat;
        if (!syncReadEnabled(chat)) return;
        const latest = messages[messages.length - 1].id;
        if (automaticReadAttempts[chat.key] === latest) return;
        automaticReadAttempts = Object.assign({}, automaticReadAttempts, {[chat.key]: latest});
        markChatRead(chat, latest);
    }
    property var accounts: [{provider: "telegram", id: "", label: "Telegram"}, {provider: "whatsapp", id: "", label: "WhatsApp"}]
    property var accountStatuses: ({})
    property string accountFilter: "all"
    function accountKey(provider, account) { return provider + (account ? ":" + account : ""); }
    function accountLabel(chat) { return accounts.find(a => a.provider === chat?.provider && a.id === (chat?.account || ""))?.label || chat?.provider || ""; }
    function preference(provider, account, key, fallback) { return pluginData.accountPreferences?.[accountKey(provider, account)]?.[key] ?? fallback; }
    function saveAccountPreference(provider, account, key, value) {
        const identity = accountKey(provider, account);
        const prefs = Object.assign({}, pluginData.accountPreferences || {});
        prefs[identity] = Object.assign({}, prefs[identity] || {}, {[key]: value});
        pluginService?.savePluginData("dankChat", "accountPreferences", prefs);
        refreshProvider(provider);
    }
    function syncReadEnabled(chat) { return preference(chat.provider, chat.account, "syncRead", chat.provider === "telegram" ? readReceipts : whatsappReadState); }
    function changeAccount(provider, account, label, add) {
        sendRequest(provider, add ? "add_account" : "rename_account", {account: account, label: label}, result => {
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); return; }
            accounts = result.accounts; refresh();
        });
    }
    property string browseMode: ""
    property string messageQuery: ""
    property var browseResults: []
    property string browseNext: ""
    property bool browsing: false
    property int browseGeneration: 0
    function browse(mode, query, more) {
        if (!selectedChat || demo) return;
        const chat = selectedChat, generation = ++browseGeneration;
        browseMode = mode; messageQuery = query || ""; browsing = true;
        if (!more) { browseResults = []; browseNext = ""; }
        const category = mode === "search" ? "" : mode;
        if (!sendRequest(chat.provider, "browse", {chat: chat, category: category, query: messageQuery, offset: more ? browseNext : ""}, result => {
            if (generation !== browseGeneration || selectedChat?.key !== chat.key) return;
            browsing = false;
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); return; }
            const previous = more ? browseResults : [];
            const seen = new Set(previous.map(row => row.id));
            browseResults = previous.concat((result.messages || []).filter(row => !seen.has(row.id)));
            browseNext = result.next || "";
        })) browsing = false;
    }
    function closeBrowse() { browseGeneration++; browseMode = ""; browsing = false; browseResults = []; }
    function editMessage(message, text, chat) {
        if (!chat || !message.out || writing || demo) return;
        writing = true;
        sendRequest(chat.provider, "edit", {chat: chat, messageId: message.id, text: text}, result => {
            writing = false;
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); return; }
            const update = rows => rows.map(row => row.id === message.id ? Object.assign({}, row, {text: text, edited: true}) : row);
            cacheMessages(chat.key, update(messageCache[chat.key] || []));
            if (selectedChat?.key === chat.key) messages = update(messages);
            if (confirmedMessages[chat.key]) delete confirmedMessages[chat.key][message.id];
            refreshProvider(chat.provider);
        });
    }
    property var storageInfo: ({})
    property bool storageBusy: false
    readonly property int cacheLimitMb: pluginData.cacheLimitMb ?? 512
    readonly property int cacheDays: pluginData.cacheDays ?? 30
    readonly property int mediaLimitMb: pluginData.mediaLimitMb ?? 25
    readonly property var mediaTypes: pluginData.mediaTypes ?? ["images", "videos", "audio"]
    function mediaGroup(type) { return ["photo", "image", "sticker"].includes(type) ? "images" : ["video", "gif"].includes(type) ? "videos" : ["audio", "voice", "ptt"].includes(type) ? "audio" : "files"; }
    function storageAction(clean, clear) {
        if (storageBusy || demo || Object.keys(downloads).length || writing) return;
        storageBusy = true;
        const protect = messages.map(row => row.mediaPath).filter(Boolean);
        if (!sendRequest("", clean ? "clean_storage" : "storage_info", {limitMb: cacheLimitMb, days: cacheDays, clear: !!clear, protect: protect}, result => {
            storageBusy = false;
            if (result.ok) {
                storageInfo = result;
                if (clean) {
                    messageCache = {};
                    const attempts = {};
                    Object.keys(automaticMediaAttempts).filter(key => key.startsWith(selectedChat?.key + ":")).forEach(key => attempts[key] = automaticMediaAttempts[key]);
                    automaticMediaAttempts = attempts;
                }
            }
            else errorText = I18n.trFor("dankChat", result.error);
        })) storageBusy = false;
    }
    function exportDiagnostics(destination) {
        sendRequest("", "export_diagnostics", {destination: destination}, result => {
            if (!result.ok) errorText = I18n.trFor("dankChat", result.error);
            else ToastService.showInfo(I18n.trFor("dankChat", "Diagnostic report saved"));
        });
    }
    readonly property bool closeOnBlur: pluginData.closeOnBlur ?? true
    readonly property string notificationMode: pluginData.notificationMode ?? "off"
    readonly property bool notificationPreview: pluginData.notificationPreview ?? false
    readonly property bool notificationSound: pluginData.notificationSound ?? false
    readonly property bool suppressActive: pluginData.suppressActive ?? true
    property var notificationSnapshots: ({})
    function notificationPolicy(chat) {
        const override = pluginData.chatNotifications?.[chat.key];
        const account = preference(chat.provider, chat.account, "notifications", "default");
        const mode = override || (account === "default" ? notificationMode : account);
        return mode === "mentions" && chat.provider === "whatsapp" ? "off" : mode;
    }
    function cycleChatNotifications(chat) {
        const modes = chat.provider === "telegram" ? ["default", "all", "mentions", "off"] : ["default", "all", "off"];
        const current = pluginData.chatNotifications?.[chat.key] || "default";
        const prefs = Object.assign({}, pluginData.chatNotifications || {});
        const next = modes[(modes.indexOf(current) + 1) % modes.length];
        if (next === "default") delete prefs[chat.key]; else prefs[chat.key] = next;
        pluginService?.savePluginData("dankChat", "chatNotifications", prefs);
    }
    function considerNotifications(incoming, identity) {
        const previous = notificationSnapshots[identity];
        const next = {};
        let count = 0;
        incoming.forEach(chat => {
            next[chat.key] = {timestamp: chat.timestamp, unread: chat.serverUnread ?? chat.unread};
            const old = previous?.[chat.key], mode = notificationPolicy(chat);
            if (!previous || mode === "off" || count >= 3 || (suppressActive && surfaceOpen && !accountsOpen && !settingsOpen && selectedChat?.key === chat.key)) return;
            if ((chat.serverUnread ?? chat.unread) <= (old?.unread || 0) || chat.timestamp < (old?.timestamp || 0)) return;
            count++;
            sendRequest(chat.provider, "notify", {chat: chat, since: old?.timestamp || Date.now() / 1000 - 30, mentionsOnly: mode === "mentions", preview: notificationPreview, sound: notificationSound, fallback: I18n.trFor("dankChat", "New message")}, () => {});
        });
        notificationSnapshots = Object.assign({}, notificationSnapshots, {[identity]: next});
    }
    function accountConnectionText(provider, account) {
        const identity = accountKey(provider, account), state = accountStatuses[identity];
        if (syncFailures[identity]) return I18n.trFor("dankChat", "Connection interrupted — retrying");
        if (!state?.authorized) return I18n.trFor("dankChat", "Not connected");
        return I18n.trFor("dankChat", provider === "whatsapp" && !state.syncActive ? "Sync service is starting" : "Connected")
            + (lastChecks[identity] ? " · " + I18n.trFor("dankChat", "Last checked") + " " + Qt.formatTime(new Date(lastChecks[identity]), "HH:mm:ss") : "");
    }
    property var transferStates: ({})
    function transferState(key, state) { const states = Object.assign({}, transferStates); delete states[key]; states[key] = state; while (Object.keys(states).length > 200) delete states[Object.keys(states)[0]]; transferStates = states; }
    property var chats: []
    property var messages: []
    property bool historyContext: false
    signal focusMessageRequested(string messageId)
    signal messagesReplacing
    property var selectedChat: null
    property var statuses: ({})
    property var syncFailures: ({})
    property var lastChecks: ({})
    property int reconnectAttempts: 0
    property bool reconnecting: false
    property bool interruptedWrite: false
    property var changedProviders: ({})
    property var diagnosticRequests: []
    function connectionText(provider) {
        if (syncFailures[provider]) return I18n.trFor("dankChat", "Connection interrupted — retrying");
        if (!statuses[provider]?.authorized) return "";
        const state = provider === "whatsapp"
            ? I18n.trFor("dankChat", statuses[provider]?.syncActive === false ? "Sync service is starting" : "Sync service running")
            : I18n.trFor("dankChat", "Connected");
        return state + (lastChecks[provider] ? " · " + I18n.trFor("dankChat", "Last checked") + " " + Qt.formatTime(new Date(lastChecks[provider]), "HH:mm:ss") : "");
    }
    function retryConnection() {
        if (demo) return;
        reconnectAttempts = 0;
        if (!bridge.running) { reconnecting = true; bridge.running = true; }
        else refresh();
    }
    function providerChanged(provider) {
        if (!["telegram", "whatsapp"].includes(provider)) return;
        if (surfaceOpen && selectedChat?.provider === provider) loadMessages();
        changedProviders = Object.assign({}, changedProviders, {[provider]: true});
        if (!providerUpdateTimer.running) providerUpdateTimer.start();
    }
    Timer {
        id: providerUpdateTimer; interval: 150
        onTriggered: {
            const changed = root.changedProviders; root.changedProviders = {};
            Object.keys(changed).forEach(provider => root.refreshProvider(provider));
        }
    }
    Timer {
        id: reconnectTimer
        interval: Math.min(30000, 1000 * Math.pow(2, root.reconnectAttempts)); repeat: false
        onTriggered: { if (!root.demo && !bridge.running) { root.reconnectAttempts++; root.reconnecting = true; bridge.running = true; } }
    }
    property var drafts: ({})
    property var replies: ({})
    property var attachmentDrafts: ({})
    function setAttachmentPaths(paths, key) {
        if (!key) return;
        const values = Object.assign({}, attachmentDrafts);
        if (paths.length) values[key] = paths.slice(); else delete values[key];
        attachmentDrafts = values;
    }
    property var downloads: ({})
    property var automaticMediaAttempts: ({})
    property var messageCache: ({})
    property var messageRequests: ({})
    property var messageReloads: ({})
    property var confirmedMessages: ({})
    property var visibleMediaIds: []
    function cacheMessages(key, rows) {
        const cache = Object.assign({}, messageCache);
        delete cache[key]; cache[key] = rows;
        while (Object.keys(cache).length > 12) delete cache[Object.keys(cache)[0]];
        messageCache = cache;
    }
    function mergeMessages(key, incoming) {
        const previous = messageCache[key] || [];
        const paths = {};
        previous.forEach(row => { if (row.mediaPath) paths[row.id] = row.mediaPath; });
        const receipts = Object.assign({}, confirmedMessages[key] || {});
        const rows = incoming.map(row => {
            delete receipts[row.id];
            return !row.mediaPath && paths[row.id] ? Object.assign({}, row, {mediaPath: paths[row.id]}) : row;
        });
        const now = Date.now();
        Object.keys(receipts).forEach(id => {
            if (now - receipts[id].receivedAt < 120000) rows.push(receipts[id].message);
            else delete receipts[id];
        });
        confirmedMessages = Object.assign({}, confirmedMessages, {[key]: receipts});
        rows.sort((a, b) => a.timestamp - b.timestamp);
        return rows;
    }
    function acceptSentMessage(chat, result) {
        if (!result.message?.id) return;
        const receipt = Object.assign({}, confirmedMessages[chat.key] || {}, {[result.message.id]: {message: result.message, receivedAt: Date.now()}});
        confirmedMessages = Object.assign({}, confirmedMessages, {[chat.key]: receipt});
        const rows = (messageCache[chat.key] || []).filter(row => row.id !== result.message.id).concat([result.message]);
        cacheMessages(chat.key, rows);
        if (selectedChat?.key === chat.key && !historyContext) { messagesReplacing(); messages = rows; }
    }
    property var activePlayer: null
    property string filter: "all"
    property string query: ""
    property bool unreadOnly: false
    property string errorText: ""
    property string qrPath: ""
    property var accountBusy: ({})
    property bool accountsOpen: false
    property bool writing: false
    property bool loadingMessages: false
    property int nextRequest: 0
    property int configurationEpoch: 0
    property var pending: ({})
    readonly property int unread: chats.filter(chat => chat.unread > 0).length
    readonly property int unreadMessages: chats.reduce((sum, chat) => sum + chat.unread, 0)
    readonly property bool surfaceOpen: popout.shouldBeVisible || app.visible
    readonly property var matchingChats: chats.filter(chat => (filter === "all" || chat.provider === filter)
        && (accountFilter === "all" || accountKey(chat.provider, chat.account) === accountFilter)
        && (chat.name + " " + chat.preview).toLowerCase().includes(query.trim().toLowerCase()))
    readonly property int unreadChatCount: matchingChats.filter(chat => chat.unread > 0).length
    readonly property var visibleChats: unreadOnly ? matchingChats.filter(chat => chat.unread > 0) : matchingChats
    readonly property string draft: selectedChat ? (drafts[selectedChat.key] || "") : ""
    readonly property var reply: selectedChat ? (replies[selectedChat.key] || null) : null

    property var chatPresence: ({})
    property bool presenceBusy: false
    property double presenceClock: Date.now() / 1000
    readonly property string presenceText: {
        const p = chatPresence;
        if (p.activityExpiresAt > presenceClock) {
            if (p.activity === "recording") return I18n.trFor("dankChat", "Recording…");
            if (p.activity === "typing") return I18n.trFor("dankChat", "Typing…");
        }
        if (p.status === "online" && p.expiresAt > presenceClock) return I18n.trFor("dankChat", "Online");
        if (p.status === "offline" && p.lastSeen > 0) return I18n.trFor("dankChat", "Last seen") + " " + Qt.formatDateTime(new Date(p.lastSeen * 1000), "dd.MM.yyyy HH:mm");
        if (p.status === "recently") return I18n.trFor("dankChat", "Last seen recently");
        if (p.status === "last_week") return I18n.trFor("dankChat", "Last seen within a week");
        if (p.status === "last_month") return I18n.trFor("dankChat", "Last seen within a month");
        return "";
    }
    onSelectedChatChanged: { closeBrowse(); if (voiceState) discardVoice(); chatPresence = {}; Qt.callLater(loadPresence); }
    function loadPresence() {
        if (demo || !surfaceOpen || !selectedChat || presenceBusy) return;
        const chat = selectedChat;
        presenceBusy = true;
        if (!sendRequest(chat.provider, "presence", {chat: chat}, result => {
            presenceBusy = false;
            if (selectedChat?.key !== chat.key || !surfaceOpen) return;
            chatPresence = result.ok ? result.presence || {} : {};
            presenceClock = Date.now() / 1000;
        })) presenceBusy = false;
    }
    Timer {
        interval: 1500; repeat: true
        running: root.surfaceOpen && !!root.selectedChat && !root.demo
        onTriggered: { root.presenceClock = Date.now() / 1000; root.loadPresence(); }
    }
    function sendRequest(provider, action, payload, callback) {
        if (!bridge.running || demo) return false;
        const account = payload?.account ?? payload?.chat?.account ?? "";
        if (["status", "chats"].includes(action) && Object.values(pending).some(entry => entry.provider === provider && entry.account === account && entry.action === action)) return false;
        const id = ++nextRequest;
        const request = Object.assign({}, payload || {}, {provider: provider, account: account, action: action, requestId: id});
        const epoch = configurationEpoch;
        pending[id] = {provider: provider, account: account, action: action, started: Date.now(), callback: result => { if (epoch === configurationEpoch && callback) callback(result); }};
        bridge.write(JSON.stringify(request) + "\n");
        return true;
    }
    function configure() {
        voiceState = ""; voicePath = ""; attachmentDrafts = {};
        checkingUpdates = false; automaticReadAttempts = {}; readingLatest = false;
        markingRead = {}; reacting = {}; presenceBusy = false; chatPresence = {};
        configurationEpoch++; notificationSnapshots = {}; accountStatuses = {};
        downloads = {}; automaticMediaAttempts = {}; messageCache = {}; messageRequests = {}; messageReloads = {}; confirmedMessages = {}; visibleMediaIds = [];
        loadingMessages = false;
        chats = []; messages = []; selectedChat = null; statuses = {}; syncFailures = {}; lastChecks = {}; qrPath = "";
        if (demo) { loadDemo(); return; }
        const enabled = [];
        if (telegramEnabled) enabled.push("telegram");
        if (whatsappEnabled) enabled.push("whatsapp");
        sendRequest("", "configure", {enabled: enabled}, result => { if (result.accounts) accounts = result.accounts; refresh(); });
        sendRequest("", "app_info", {}, result => { if (result.ok) appInfo = result; });
    }
    function acceptProviderStatus(provider, result) {
        if (!result.ok) {
            syncFailures = Object.assign({}, syncFailures, {[provider]: true});
            if (selectedChat?.provider === provider) chatPresence = {};
            return false;
        }
        const failures = Object.assign({}, syncFailures); delete failures[provider]; syncFailures = failures;
        statuses = Object.assign({}, statuses, {[provider]: result});
        reconnectAttempts = 0; reconnecting = false;
        if (!interruptedWrite && errorText === I18n.trFor("dankChat", "The chat service stopped. Reconnecting; check the conversation before retrying a send.")) errorText = "";
        if (provider === "telegram") qrPath = result.qrPath || "";
        if (result.authorized === false) {
            const cache = Object.assign({}, messageCache), sent = Object.assign({}, confirmedMessages);
            Object.keys(cache).forEach(key => {
                let owner, account = "";
                try { const parts = JSON.parse(key); owner = parts[0]; account = parts[1]; } catch (e) { owner = key.startsWith(provider) ? provider : ""; }
                if (owner === provider && !account) { delete cache[key]; delete sent[key]; }
            });
            messageCache = cache; confirmedMessages = sent;
            chats = chats.filter(chat => chat.provider !== provider || !!chat.account);
            if (selectedChat?.provider === provider && !selectedChat.account) { selectedChat = null; messages = []; }
            return false;
        }
        return result.authorized === true;
    }
    function refreshProvider(provider) {
        if (demo || (provider === "telegram" && !telegramEnabled) || (provider === "whatsapp" && !whatsappEnabled)) return;
        accounts.filter(a => a.provider === provider).forEach(account => {
            const identity = accountKey(provider, account.id);
            if (accountBusy[identity]) return;
            sendRequest(provider, "status", {account: account.id}, result => {
                if (accountBusy[identity]) return;
                accountStatuses = Object.assign({}, accountStatuses, {[identity]: result});
                if (!account.id) {
                    if (!acceptProviderStatus(provider, result)) return;
                } else if (!result.ok) {
                    syncFailures = Object.assign({}, syncFailures, {[identity]: true}); return;
                } else {
                    const failures = Object.assign({}, syncFailures); delete failures[identity]; syncFailures = failures;
                    if (!result.authorized) {
                        chats = chats.filter(c => accountKey(c.provider, c.account) !== identity);
                        if (selectedChat && accountKey(selectedChat.provider, selectedChat.account) === identity) { selectedChat = null; messages = []; }
                        return;
                    }
                }
                sendRequest(provider, "chats", {account: account.id}, result => {
                    if (!result.ok) { syncFailures = Object.assign({}, syncFailures, {[identity]: true}); return; }
                    const incoming = (result.chats || []).map(chat => syncReadEnabled(chat) ? Object.assign({}, chat, {unread: chat.serverUnread ?? chat.unread}) : chat);
                    considerNotifications(incoming, identity);
                    const failures = Object.assign({}, syncFailures); delete failures[identity]; syncFailures = failures;
                    const updated = chats.filter(c => accountKey(c.provider, c.account) !== identity).concat(incoming)
                        .sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned) || b.timestamp - a.timestamp || a.key.localeCompare(b.key));
                    if (JSON.stringify(updated) !== JSON.stringify(chats)) chats = updated;
                    lastChecks = Object.assign({}, lastChecks, {[identity]: Date.now()});
                    if (surfaceOpen && selectedChat && accountKey(selectedChat.provider, selectedChat.account) === identity) loadMessages();
                    if (changedProviders[provider]) providerUpdateTimer.restart();
                });
            });
        });
    }
    function refresh() {
        if (demo) return;
        ["telegram", "whatsapp"].forEach(provider => refreshProvider(provider));
    }
    function selectChat(chat) {
        historyContext = false; readingLatest = false;
        const attempts = Object.assign({}, automaticReadAttempts); delete attempts[chat.key]; automaticReadAttempts = attempts;
        selectedChat = chat; messages = messageCache[chat.key] || []; errorText = "";
        visibleMediaIds = []; loadingMessages = false;
        if (demo) { demoMessages(); return; }
        loadMessages();
        if (chat.provider === "whatsapp" && !syncReadEnabled(chat))
            sendRequest("whatsapp", "acknowledge", {chat: chat}, result => { if (!result.ok) errorText = I18n.trFor("dankChat", result.error); else refreshProvider("whatsapp"); });
    }
    function loadMessages(force) {
        if (!selectedChat || historyContext || demo) return;
        const chat = selectedChat;
        if (messageRequests[chat.key]) {
            if (force) messageReloads[chat.key] = true;
            loadingMessages = true; return;
        }
        const token = nextRequest + 1;
        messageRequests[chat.key] = token;
        loadingMessages = true;
        if (!sendRequest(chat.provider, "messages", {chat: chat}, result => {
            if (messageRequests[chat.key] !== token) return;
            delete messageRequests[chat.key];
            const again = messageReloads[chat.key]; delete messageReloads[chat.key];
            const current = selectedChat?.key === chat.key;
            if (current) loadingMessages = false;
            if (result.ok) {
                const incoming = mergeMessages(chat.key, result.messages || []);
                cacheMessages(chat.key, incoming);
                if (current && !historyContext) {
                    if (JSON.stringify(incoming) !== JSON.stringify(messages)) { messagesReplacing(); messages = incoming; }
                    Qt.callLater(loadNextMedia);
                    Qt.callLater(readVisibleChat);
                }
            } else if (current) errorText = result.error ? I18n.trFor("dankChat", result.error) : "";
            if (again && current) loadMessages();
        })) { delete messageRequests[chat.key]; loadingMessages = false; }
        Qt.callLater(loadNextMedia);
    }
    function jumpToReply(messageId) {
        if (!selectedChat || !messageId) return;
        if (messages.some(message => message.id === messageId)) { focusMessageRequested(messageId); return; }
        const chat = selectedChat;
        sendRequest(chat.provider, "context", {chat: chat, messageId: messageId}, result => {
            if (selectedChat?.key !== chat.key) return;
            if (!result.ok || !result.messages?.some(message => message.id === messageId)) {
                errorText = I18n.trFor("dankChat", "The original message is unavailable."); return;
            }
            historyContext = true;
            messagesReplacing(); messages = result.messages;
            Qt.callLater(() => focusMessageRequested(messageId));
            Qt.callLater(loadNextMedia);
        });
    }
    function showLatest() {
        historyContext = false;
        loadMessages(true);
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
        transferState(chat.key + ":send", "Sending…");
        if (!sendRequest(chat.provider, path ? "file" : "send", {chat: chat, text: text, path: path || "", replyId: reply?.id || ""}, result => {
            writing = false;
            if (!result.ok) { transferState(chat.key + ":send", "Not confirmed — check the conversation"); errorText = I18n.trFor("dankChat", result.error); return; }
            transferState(chat.key + ":send", "Sent");
            acceptSentMessage(chat, result);
            const values = Object.assign({}, drafts);
            if (values[chat.key] === text) values[chat.key] = "";
            drafts = values;
            const replyValues = Object.assign({}, replies); delete replyValues[chat.key]; replies = replyValues;
            if (selectedChat?.key === chat.key) showLatest();
        })) writing = false;
    }
    property string voiceState: ""
    property string voicePath: ""
    property var voiceChat: null
    property string voiceReplyId: ""
    property int voiceSeconds: 0
    function startVoice() {
        if (!selectedChat || demo || writing || voiceState) return;
        if (activePlayer) activePlayer.pause();
        voiceChat = selectedChat; voiceReplyId = reply?.id || "";
        voiceSeconds = 0; voiceState = "starting"; errorText = "";
        if (!sendRequest(voiceChat.provider, "voice_start", {}, result => {
            if (!result.ok) { voiceState = ""; errorText = I18n.trFor("dankChat", result.error); return; }
            voiceState = "recording";
            if (!surfaceOpen || selectedChat?.key !== voiceChat.key) discardVoice();
        })) voiceState = "";
    }
    function stopVoice() {
        if (voiceState !== "recording") return;
        voiceState = "stopping";
        if (!sendRequest(voiceChat.provider, "voice_stop", {}, result => {
            voiceState = result.ok ? "ready" : "";
            voicePath = result.path || "";
            if (!result.ok) errorText = I18n.trFor("dankChat", result.error);
            if (selectedChat?.key !== voiceChat.key) discardVoice();
        })) voiceState = "";
    }
    function discardVoice() {
        if (!voiceState || voiceState === "sending" || voiceState === "starting" || voiceState === "stopping") return;
        voiceState = "discarding"; voicePath = "";
        if (!sendRequest(voiceChat.provider, "voice_discard", {}, result => {
            voiceState = "";
            if (!result.ok) errorText = I18n.trFor("dankChat", result.error);
        })) voiceState = "";
    }
    function sendVoice() {
        if (voiceState !== "ready" || writing || selectedChat?.key !== voiceChat.key) return;
        voiceState = "sending"; writing = true; errorText = "";
        const chat = voiceChat, replyId = voiceReplyId;
        if (!sendRequest(chat.provider, "voice", {chat: chat, path: voicePath, replyId: replyId}, result => {
            writing = false;
            if (!result.ok) { voiceState = "ready"; errorText = I18n.trFor("dankChat", "Voice message sending failed. Check the chat before retrying."); return; }
            voicePath = ""; voiceState = "";
            const values = Object.assign({}, replies);
            if (values[chat.key]?.id === replyId) delete values[chat.key];
            replies = values;
            if (selectedChat?.key === chat.key) showLatest();
        })) { writing = false; voiceState = "ready"; }
    }
    Timer {
        interval: 1000; repeat: true; running: root.voiceState === "recording"
        onTriggered: { root.voiceSeconds++; if (root.voiceSeconds >= 300) root.stopVoice(); }
    }
    function deleteMessage(message, forMe, expectedKey) {
        if (demo || writing || !selectedChat || selectedChat.key !== expectedKey) {
            errorText = I18n.trFor("dankChat", "The selected chat changed. Select the message again."); return;
        }
        const chat = selectedChat;
        writing = true; errorText = "";
        if (!sendRequest(chat.provider, "delete", {chat: chat, messageId: String(message.id), forMe: forMe}, result => {
            writing = false;
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); return; }
            const values = Object.assign({}, replies);
            if (values[chat.key]?.id === message.id) delete values[chat.key];
            replies = values;
            cacheMessages(chat.key, (messageCache[chat.key] || []).filter(row => row.id !== message.id));
            if (confirmedMessages[chat.key]) delete confirmedMessages[chat.key][message.id];
            if (selectedChat?.key === chat.key) messages = messages.filter(row => row.id !== message.id);
            refresh();
        })) writing = false;
    }
    function sendAttachments(paths, expectedKey, finished) {
        if (!selectedChat || writing || demo || !paths.length || paths.length > 10 || selectedChat.key !== expectedKey) {
            errorText = I18n.trFor("dankChat", "The selected chat changed. Choose the attachment again.");
            finished(0); return;
        }
        const chat = selectedChat, text = draft, replyId = reply?.id || "";
        writing = true; errorText = "";
        let sent = 0;
        const stop = () => { writing = false; finished(sent); if (selectedChat?.key === chat.key) showLatest(); };
        const states = Object.assign({}, transferStates);
        Object.keys(states).filter(key => key.startsWith(chat.key + ":file:")).forEach(key => delete states[key]);
        transferStates = states;
        paths.forEach((path, i) => transferState(chat.key + ":file:" + i, "Waiting"));
        const next = () => {
            transferState(chat.key + ":file:" + sent, "Uploading…");
            if (!sendRequest(chat.provider, "file", {chat: chat, path: paths[sent], text: sent === 0 ? text : "", replyId: replyId}, result => {
                if (!result.ok) {
                    transferState(chat.key + ":file:" + sent, "Not confirmed — check the conversation");
                    paths.slice(sent + 1).forEach((path, i) => transferState(chat.key + ":file:" + (sent + i + 1), "Not sent"));
                    errorText = I18n.trFor("dankChat", "Attachment sending stopped. Check the chat before retrying.") + " (" + sent + "/" + paths.length + ") " + (result.error ? I18n.trFor("dankChat", result.error) : "");
                    stop(); return;
                }
                transferState(chat.key + ":file:" + sent, "Sent");
                acceptSentMessage(chat, result);
                if (selectedChat?.key === chat.key) showLatest();
                sent++;
                if (sent === 1) {
                    const values = Object.assign({}, drafts);
                    if (values[chat.key] === text) values[chat.key] = "";
                    drafts = values;
                    const r = Object.assign({}, replies);
                    if (r[chat.key]?.id === replyId) delete r[chat.key];
                    replies = r;
                }
                if (sent === paths.length) stop(); else next();
            })) { errorText = I18n.trFor("dankChat", "The chat service stopped. Reload DankChat to reconnect."); stop(); }
        };
        next();
    }
    function accountAction(provider, action, account) {
        account = account || "";
        const identity = accountKey(provider, account);
        if (demo || accountBusy[identity]) return;
        errorText = "";
        const busy = Object.assign({}, accountBusy); busy[identity] = true; accountBusy = busy;
        const finish = () => { const busy = Object.assign({}, accountBusy); delete busy[identity]; accountBusy = busy; };
        if (!sendRequest(provider, action, {account: account}, result => {
            finish();
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); refresh(); return; }
            if (action === "logout") {
                messageCache = {}; confirmedMessages = {};
                const keys = chats.filter(chat => chat.provider === provider && (chat.account || "") === account).map(chat => chat.key);
                const d = Object.assign({}, drafts), r = Object.assign({}, replies);
                keys.forEach(key => { delete d[key]; delete r[key]; }); drafts = d; replies = r;
                chats = chats.filter(chat => chat.provider !== provider || (chat.account || "") !== account);
                if (selectedChat?.provider === provider && (selectedChat.account || "") === account) { selectedChat = null; messages = []; }
                const states = Object.assign({}, statuses); states[provider] = {authorized: false}; statuses = states;
            }
            refresh();
        })) finish();
    }
    function loginTelegram() { accountAction("telegram", "login"); }
    function submitPassword(password, account) {
        sendRequest("telegram", "password", {password: password, account: account || ""}, result => {
            if (!result.ok) errorText = I18n.trFor("dankChat", result.error);
            else refresh();
        });
    }
    Timer { interval: 3600000; running: !root.demo; repeat: true; onTriggered: root.storageAction(true, false) }
    onSurfaceOpenChanged: { if (surfaceOpen) { if (automaticUpdates) checkUpdates(false); Qt.callLater(loadNextMedia); Qt.callLater(loadPresence); } else { chatPresence = {}; if (voiceState === "recording") stopVoice(); } }
    function loadNextMedia() {
        if (!automaticMedia || !surfaceOpen || demo || !selectedChat || accountBusy[accountKey(selectedChat.provider, selectedChat.account)] || writing) return;
        const types = ["photo", "image", "video", "sticker", "gif", "audio", "voice", "ptt"];
        const limit = selectedChat.provider === "telegram" ? 2 : 1;
        let available = limit - Object.keys(downloads).filter(key => downloads[key] === selectedChat.provider).length;
        if (available <= 0) return;
        // Start visible attachments first, then the newest ones. A video must
        // not monopolize all Telegram slots while visible photos are waiting.
        const candidates = messages.slice().reverse().sort((a, b) => Number(visibleMediaIds.includes(b.id)) - Number(visibleMediaIds.includes(a.id)));
        for (const message of candidates) {
            const key = selectedChat.key + ":" + message.id;
            if (mediaTypes.includes(mediaGroup(message.mediaType)) && (message.mediaSize === undefined || (message.mediaSize > 0 && message.mediaSize <= mediaLimitMb * 1048576)) && !message.mediaPath && message.mediaDownloadable !== false && types.includes(message.mediaType) && !automaticMediaAttempts[key] && !downloads[key]) {
                automaticMediaAttempts[key] = true;
                while (Object.keys(automaticMediaAttempts).length > 1000) delete automaticMediaAttempts[Object.keys(automaticMediaAttempts)[0]];
                downloadMedia(message, true);
                if (--available <= 0) return;
            }
        }
    }
    onWritingChanged: if (!writing) Qt.callLater(loadNextMedia)
    function downloadMedia(message, automatic) {
        if (!selectedChat || demo) return;
        const chat = selectedChat;
        const key = chat.key + ":" + message.id;
        if (downloads[key]) return;
        transferState(key, "Downloading…");
        const active = Object.assign({}, downloads); active[key] = chat.provider; downloads = active;
        if (!automatic) errorText = "";
        if (!sendRequest(chat.provider, "download", {chat: chat, messageId: message.id, mediaType: message.mediaType}, result => {
            const active = Object.assign({}, downloads); delete active[key]; downloads = active;
            if (!result.ok) { transferState(key, "Download failed"); if (selectedChat?.key === chat.key && (!automatic || !errorText)) errorText = I18n.trFor("dankChat", result.error); Qt.callLater(loadNextMedia); return; }
            if (result.path) {
                transferState(key, "Downloaded");
                cacheMessages(chat.key, (messageCache[chat.key] || []).map(row => row.id === message.id ? Object.assign({}, row, {mediaPath: result.path}) : row));
                if (selectedChat?.key === chat.key) {
                    messagesReplacing();
                    messages = messages.map(row => row.id === message.id ? Object.assign({}, row, {mediaPath: result.path}) : row);
                }
                Qt.callLater(loadNextMedia);
            } else if (selectedChat?.key === chat.key && !historyContext) loadMessages();
            else Qt.callLater(loadNextMedia);
        })) {
            const active = Object.assign({}, downloads); delete active[key]; downloads = active;
        }
    }
    function saveMedia(chat, message, destination) {
        if (demo || !chat || !message) return;
        errorText = "";
        sendRequest(chat.provider, "export", {chat: chat, messageId: message.id, destination: destination}, result => {
            if (!result.ok) errorText = I18n.trFor("dankChat", result.error);
            else ToastService.showInfo(I18n.trFor("dankChat", "Media saved"), destination);
        });
    }
    property var reacting: ({})
    function reactToMessage(message, emoji, chat) {
        if (demo || !chat || selectedChat?.key !== chat.key || message.canReact === false) return;
        const key = chat.key + ":" + message.id;
        if (reacting[key]) return;
        reacting = Object.assign({}, reacting, {[key]: true});
        const finish = () => { const active = Object.assign({}, reacting); delete active[key]; reacting = active; };
        if (!sendRequest(chat.provider, "reaction", {chat: chat, messageId: message.id, emoji: emoji}, result => {
            finish();
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); return; }
            if (selectedChat?.key !== chat.key) return;
            sendRequest(chat.provider, "context", {chat: chat, messageId: message.id}, update => {
                if (selectedChat?.key !== chat.key || !update.ok) return;
                const current = update.messages?.find(row => row.id === message.id);
                if (!current) return;
                messagesReplacing();
                messages = messages.map(row => row.id === message.id ? Object.assign({}, row, {reactions: current.reactions || []}) : row);
            });
        })) finish();
    }
    property var markingRead: ({})
    function markChatRead(chat, messageId) {
        if (demo || !chat || markingRead[chat.key]) return;
        markingRead = Object.assign({}, markingRead, {[chat.key]: true});
        const finish = () => {
            const active = Object.assign({}, markingRead);
            delete active[chat.key]; markingRead = active;
        };
        if (!sendRequest(chat.provider, "read", {chat: chat, messageId: messageId || ""}, result => {
            finish();
            if (!result.ok) { errorText = I18n.trFor("dankChat", result.error); return; }
            chats = chats.map(row => row.key === chat.key ? Object.assign({}, row, {unread: 0, serverUnread: 0}) : row);
            refresh();
        })) finish();
    }
    function togglePin(chat) {
        if (demo) return;
        sendRequest(chat.provider, "pin", {chat: chat, pinned: !chat.pinned}, result => {
            if (!result.ok) errorText = I18n.trFor("dankChat", result.error);
            else refresh();
        });
    }
    function closeDropdown() { popout.close(); }
    function closeWindow() { app.visible = false; }
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

    onDemoChanged: { reconnectTimer.stop(); reconnectAttempts = 0; bridge.running = !demo; pending = {}; writing = false; loadingMessages = false; configure(); }
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
                    if (result.event === "provider_changed") { root.providerChanged(result.provider); return; }
                    const entry = root.pending[result.requestId];
                    delete root.pending[result.requestId];
                    if (entry) {
                        root.diagnosticRequests = root.diagnosticRequests.concat([{provider: entry.provider, action: entry.action, ok: !!result.ok, durationMs: Date.now() - entry.started}]).slice(-50);
                        entry.callback(result);
                    }
                } catch (e) { root.errorText = I18n.trFor("dankChat", "Could not read the service response."); }
            }
        }
        stderr: StdioCollector {}
        onExited: {
            root.interruptedWrite = root.writing;
            root.voiceState = ""; root.voicePath = ""; root.attachmentDrafts = {};
            root.pending = {}; root.writing = false; root.loadingMessages = false; root.markingRead = {}; root.reacting = {}; root.presenceBusy = false; root.chatPresence = {};
            if (!root.demo) {
                root.syncFailures = {telegram: true, whatsapp: true};
                root.reconnecting = true;
                root.errorText = I18n.trFor("dankChat", "The chat service stopped. Reconnecting; check the conversation before retrying a send.");
                if (root.reconnectAttempts < 5) reconnectTimer.start();
            }
        }
    }
    Timer {
        interval: 1500; repeat: true
        running: !root.demo && root.surfaceOpen && root.selectedChat?.provider === "whatsapp" && !root.accountBusy.whatsapp
        onTriggered: root.loadMessages()
    }
    Timer { interval: root.accountsOpen ? 2000 : root.surfaceOpen ? 5000 : 30000; running: !root.demo; repeat: true; onTriggered: root.refresh() }
    DankPopout {
        id: popout
        popupWidth: 760
        popupHeight: 590
        contentHandlesKeys: true
        backgroundInteractive: true
        onBackgroundClicked: close()
        customKeyboardFocus: WlrKeyboardFocus.OnDemand
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
        function settings(): void { root.settingsOpen = true; root.accountsOpen = false; root.openWindow(); }
        function syncReadState(enabled: bool): void { root.savePreference("telegramReadReceipts", enabled); root.savePreference("whatsappReadState", enabled); }
        function accounts(): void { root.settingsOpen = false; root.accountsOpen = true; root.openWindow(); }
        function preview(): string {
            if (!root.demo || !app.visible) return "Demo window must be open.";
            windowView.item.grabToImage(result => result.saveToFile(Quickshell.env("HOME") + "/.cache/dankchat-preview.png"));
            return "Capturing demo view to ~/.cache/dankchat-preview.png";
        }
        function demo(enabled: bool): void { root.pluginService?.savePluginData("dankChat", "demoMode", enabled); }
        function previewAttachmentPicker(opened: bool): void { if (windowView.item) windowView.item.previewAttachmentPicker(opened); }
        function viewStatus(): string {
            const component = Qt.createComponent(Qt.resolvedUrl("ChatView.qml") + "?revision=" + root.viewRevision);
            return JSON.stringify({status: windowView.status, width: windowView.width, height: windowView.height, loaded: !!windowView.item, error: component.errorString(), mediaErrors: ["MediaPreview.qml", "MediaPlayerView.qml"].map(file => Qt.createComponent(Qt.resolvedUrl(file) + "?revision=" + root.viewRevision).errorString())});
        }
        function diagnostics(): string { return JSON.stringify(root.diagnosticRequests); }
        function status(): string { return JSON.stringify({demo: root.demo, window: app.visible, dropdown: popout.shouldBeVisible, bridge: bridge.running, pending: Object.keys(root.pending).length, telegram: !!root.statuses.telegram?.authorized, whatsapp: !!root.statuses.whatsapp?.authorized, telegramAuthState: root.statuses.telegram?.authState || "", accounts: root.accounts.length, readSync: {telegram: root.readReceipts, whatsapp: root.whatsappReadState}}); }
    }
}
