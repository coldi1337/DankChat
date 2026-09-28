import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.Common
import qs.Widgets
import "linkify.js" as Links
import "emoji-data.js" as Emojis

Item {
    id: root
    anchors.fill: parent
    required property var service
    Rectangle { anchors.fill: parent; color: Theme.surface; z: -1 }
    property bool compact: false
    function previewAttachmentImage(path) { attachmentConfirm.contentItem.grabToImage(result => result.saveToFile(path)); }
    function attachmentPreviewStatus() { return JSON.stringify({visible: attachmentConfirm.visible, count: attachmentPaths.length, height: attachmentConfirm.height}); }
    function previewAttachments(opened) { if (opened) attachmentConfirm.open(); else attachmentConfirm.reject(); }
    readonly property alias attachmentPicker: filePickerLoader.item
    function previewAttachmentPicker(opened) { if (opened) fileDialog.open(); else fileDialog.close(); }
    readonly property bool narrow: width < 620
    signal expandRequested()
    signal closeRequested()
    property bool receivedKeyboardFocus: false
    Connections {
        target: root.service
        function onReconnectingChanged() {
            if (!root.service.reconnecting) return;
            root.pastingClipboard = false;
            attachmentConfirm.close();
        }
    }
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (!root.compact || root.service.closeOnBlur === false) return;
            if (root.Window.window.active) root.receivedKeyboardFocus = true;
            else if (root.receivedKeyboardFocus && !fileDialog.visible && !attachmentConfirm.visible && !mediaDialog.visible && !disconnectConfirm.visible && !deleteConfirm.visible) root.service.closeDropdown();
        }
    }
    focus: true
    Keys.onEscapePressed: {
        if (service.settingsOpen) service.settingsOpen = false;
        else if (service.browseMode) service.closeBrowse();
        else if (service.accountsOpen) service.accountsOpen = false;
        else if (narrow && service.selectedChat) service.selectedChat = null;
        else closeRequested();
    }
    component ChatWheel: WheelHandler {
        required property var view
        signal scrolled()
        target: null
        onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 96;
            if (!delta) { event.accepted = false; return; }
            view.cancelFlick();
            const low = view.originY;
            const high = low + Math.max(0, view.contentHeight - view.height);
            view.contentY = Math.max(low, Math.min(high, view.contentY - delta));
            scrolled();
            event.accepted = true;
        }
    }
    DankTooltipV2 { id: deliveryTooltip }
    component Label: StyledText { textFormat: Text.PlainText; color: Theme.surfaceText }
    component Action: DankActionButton { circular: false; iconColor: Theme.surfaceText }
    component MenuEntry: Controls.MenuItem {
        id: entry
        implicitHeight: 36
        leftPadding: Theme.spacingM
        rightPadding: Theme.spacingM
        contentItem: Label {
            text: entry.text
            color: entry.enabled ? Theme.surfaceText : Theme.surfaceVariantText
            opacity: entry.enabled ? 1 : 0.5
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.NoWrap
        }
        background: Rectangle { radius: Theme.cornerRadius; color: entry.highlighted ? Theme.surfaceContainerHigh : "transparent" }
    }
    component TextMenu: Controls.Menu {
        id: textMenu
        required property var editor
        property bool allowReply: false
        property bool composerPaste: false
        signal replyRequested()
        signal deleteRequested()
        signal editRequested()
        property bool allowEdit: false
        width: 210
        padding: Theme.spacingXS
        popupType: Controls.Popup.Item
        background: Rectangle { radius: Theme.cornerRadius; color: Theme.surfaceContainer; border.color: Theme.outline; border.width: 1 }
        MenuEntry { visible: textMenu.allowReply; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Reply"); onTriggered: textMenu.replyRequested() }
        MenuEntry { visible: textMenu.allowReply; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Delete message…"); enabled: !root.service.demo && !root.service.writing; onTriggered: textMenu.deleteRequested() }
        MenuEntry { visible: textMenu.allowEdit; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Edit message"); onTriggered: textMenu.editRequested() }
        MenuEntry { text: I18n.trFor("dankChat", "Copy"); enabled: textMenu.editor.selectedText.length > 0; onTriggered: textMenu.editor.copy() }
        MenuEntry { visible: !textMenu.editor.readOnly; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Cut"); enabled: textMenu.editor.selectedText.length > 0; onTriggered: textMenu.editor.cut() }
        MenuEntry { visible: !textMenu.editor.readOnly; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Paste"); enabled: textMenu.composerPaste || textMenu.editor.canPaste; onTriggered: textMenu.composerPaste ? root.pasteClipboard() : textMenu.editor.paste() }
        MenuEntry { text: I18n.trFor("dankChat", "Select all"); enabled: textMenu.editor.length > 0; onTriggered: textMenu.editor.selectAll() }
    }
    component Avatar: Rectangle {
        required property string label
        width: 38; height: 38; radius: width / 2
        color: Theme.surfaceContainerHigh
        Label { anchors.centerIn: parent; text: parent.label.slice(0, 2).toUpperCase(); color: Theme.primary; font.weight: Font.Medium }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS
        RowLayout {
            Layout.fillWidth: true
            DankIcon { name: "forum"; color: Theme.primary; size: 22 }
            Label { text: "DankChat"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium }
            Label { visible: root.service.demo; text: I18n.trFor("dankChat", "Demo"); color: Theme.primary; font.pixelSize: Theme.fontSizeSmall }
            Item { Layout.fillWidth: true }
            Action { iconName: "settings"; tooltipText: I18n.trFor("dankChat", "Settings"); onClicked: { root.service.settingsOpen = !root.service.settingsOpen; root.service.accountsOpen = false; } }
            Action { iconName: "manage_accounts"; onClicked: { root.service.accountsOpen = !root.service.accountsOpen; root.service.settingsOpen = false; } }
            Action { visible: root.compact; iconName: "open_in_new"; tooltipText: I18n.trFor("dankChat", "Open in window"); onClicked: root.expandRequested() }
            Action { iconName: "close"; onClicked: root.closeRequested() }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline; opacity: 0.3 }
        Label {
            Layout.fillWidth: true
            visible: root.service.errorText.length > 0
            text: root.service.errorText
            color: Theme.error
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.service.demo && (!!root.service.reconnecting || Object.keys(root.service.syncFailures || {}).length > 0)
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: I18n.trFor("dankChat", "Connection interrupted — retrying"); color: Theme.surfaceVariantText }
            DankButton { text: I18n.trFor("dankChat", "Reconnect"); onClicked: root.service.retryConnection() }
        }
        AppSettings {
            service: root.service
            onExportRequested: { root.savingDiagnostics = true; root.savingMedia = true; fileDialog.open(); }
            visible: !!root.service.settingsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
        AccountView {
            service: root.service
            visible: root.service.accountsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        RowLayout {
            visible: !root.service.accountsOpen && !root.service.settingsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingM
            ColumnLayout {
                id: chatSidebar
                visible: !root.narrow || !root.service.selectedChat
                Layout.preferredWidth: root.narrow ? root.width : root.compact ? 240 : 285
                Layout.fillWidth: root.narrow
                Layout.fillHeight: true
                spacing: Theme.spacingS
                Column {
                    id: accountSelectors
                    objectName: "accountSelectors"
                    Layout.fillWidth: true
                    spacing: Theme.spacingXS
                    DankButton {
                        objectName: "accountFilterButton"
                        width: accountSelectors.width
                        buttonHeight: 34
                        text: I18n.trFor("dankChat", "All")
                        backgroundColor: root.service.accountFilter === "all" ? Theme.primary : Theme.surfaceContainerHigh
                        textColor: root.service.accountFilter === "all" ? Theme.primaryText : Theme.surfaceText
                        onClicked: { root.service.accountFilter = "all"; root.service.filter = "all"; }
                    }
                    Repeater {
                        model: (root.service.accounts || []).filter(a => a.provider === "telegram" ? root.service.telegramEnabled : root.service.whatsappEnabled)
                        delegate: DankButton {
                            id: accountButton
                            required property var modelData
                            objectName: "accountFilterButton"
                            width: accountSelectors.width
                            buttonHeight: 34
                            readonly property string identity: root.service.accountKey(modelData.provider, modelData.id)
                            readonly property string serviceSuffix: " · " + (modelData.provider === "telegram" ? "TG" : "WA")
                            text: accountNameMetrics.elidedText + serviceSuffix
                            Accessible.name: modelData.label + serviceSuffix
                            TextMetrics {
                                id: accountNameMetrics
                                text: accountButton.modelData.label
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium
                                elide: Qt.ElideRight
                                elideWidth: Math.max(0, accountButton.width - accountButton.horizontalPadding * 2 - serviceMetrics.advanceWidth)
                            }
                            TextMetrics { id: serviceMetrics; text: accountButton.serviceSuffix; font: accountNameMetrics.font }
                            HoverHandler { onHoveredChanged: hovered ? deliveryTooltip.show(accountButton.Accessible.name, accountButton, 0, 0, "top") : deliveryTooltip.hide() }
                            backgroundColor: root.service.accountFilter === identity ? Theme.primary : Theme.surfaceContainerHigh
                            textColor: root.service.accountFilter === identity ? Theme.primaryText : Theme.surfaceText
                            onClicked: { root.service.accountFilter = identity; root.service.filter = "all"; }
                        }
                    }
                }
                DankTextField {
                    id: chatSearch
                    Layout.fillWidth: true
                    placeholderText: I18n.trFor("dankChat", "Search chats")
                    leftIconName: "search"
                    showClearButton: true
                    text: root.service.query
                    onTextChanged: if (text !== root.service.query) root.service.query = text
                }
                DankButton {
                    objectName: "unreadFilter"
                    width: chatSidebar.width
                    Layout.fillWidth: true
                    buttonHeight: 34
                    iconName: "mark_chat_unread"
                    text: I18n.trFor("dankChat", "Unread chats") + " (" + root.service.unreadChatCount + ")"
                    backgroundColor: root.service.unreadOnly ? Theme.primary : Theme.surfaceContainerHigh
                    textColor: root.service.unreadOnly ? Theme.primaryText : Theme.surfaceText
                    Accessible.checkable: true
                    Accessible.checked: root.service.unreadOnly
                    onClicked: root.service.unreadOnly = !root.service.unreadOnly
                }
                ListView {
                    id: chatList
                    ChatWheel { view: chatList }
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: Theme.spacingXS
                    model: root.service.visibleChats
                    delegate: Rectangle {
                        id: chatRow
                        required property var modelData
                        width: chatList.width; height: Math.max(76, chatRowContent.implicitHeight + 2 * Theme.spacingS)
                        radius: Theme.cornerRadius
                        color: root.service.selectedChat?.key === modelData.key ? Theme.surfaceContainerHigh
                            : chatMouse.containsMouse ? Theme.surfaceContainer : "transparent"
                        RowLayout {
                            id: chatRowContent
                            anchors.fill: parent; anchors.margins: Theme.spacingS; spacing: Theme.spacingS
                            Avatar { label: chatRow.modelData.name; Layout.minimumWidth: 38; Layout.maximumWidth: 38; Layout.preferredHeight: 38 }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    DankIcon { visible: !!chatRow.modelData.pinned; name: "push_pin"; size: 14; color: Theme.primary }
                                    Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: chatRow.modelData.name; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; font.weight: Font.Medium }
                                    Label { text: chatRow.modelData.provider === "telegram" ? "TG" : "WA"; wrapMode: Text.NoWrap; color: Theme.primary; font.pixelSize: Theme.fontSizeSmall }
                                }
                                Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: chatRow.modelData.preview; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                            }
                            Rectangle {
                                visible: chatRow.modelData.unread > 0
                                Layout.minimumWidth: Math.max(23, badgeText.implicitWidth + 10)
                                Layout.preferredWidth: Layout.minimumWidth
                                Layout.preferredHeight: Math.max(23, badgeText.implicitHeight + 4)
                                radius: height / 2; color: Theme.primary
                                Label { id: badgeText; anchors.centerIn: parent; text: chatRow.modelData.unread > 99 ? "99+" : String(chatRow.modelData.unread); wrapMode: Text.NoWrap; color: Theme.primaryText; font.pixelSize: Theme.fontSizeSmall }
                            }
                        }
                        MouseArea {
                            id: chatMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: event => {
                                if (event.button === Qt.RightButton) chatMenu.popup();
                                else root.service.selectChat(chatRow.modelData);
                            }
                        }
                        Controls.Menu {
                            id: chatMenu
                            popupType: Controls.Popup.Item
                            width: 220
                            padding: Theme.spacingXS
                            background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
                            MenuEntry {
                                text: I18n.trFor("dankChat", "Mark as read")
                                enabled: !root.service.demo && !root.service.markingRead?.[chatRow.modelData.key]
                                onTriggered: root.service.markChatRead(chatRow.modelData)
                            }
                            MenuEntry {
                                text: I18n.trFor("dankChat", "Notifications") + ": " + I18n.trFor("dankChat", root.service.notificationPolicy(chatRow.modelData) === "off" ? "Off" : root.service.notificationPolicy(chatRow.modelData) === "mentions" ? "Mentions only" : "All messages")
                                onTriggered: root.service.cycleChatNotifications(chatRow.modelData)
                            }
                            MenuEntry {
                                text: chatRow.modelData.pinned ? I18n.trFor("dankChat", "Unpin chat") : I18n.trFor("dankChat", "Pin chat")
                                enabled: !root.service.demo
                                onTriggered: root.service.togglePin(chatRow.modelData)
                            }
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        visible: chatList.count === 0
                        text: root.service.query.trim().length > 0 ? I18n.trFor("dankChat", "No chats found.")
                            : (root.service.statuses.telegram?.authorized || root.service.statuses.whatsapp?.authorized || Object.values(root.service.accountStatuses || {}).some(s => s.authorized))
                                ? (root.service.unreadOnly ? I18n.trFor("dankChat", "No unread chats.") : I18n.trFor("dankChat", "No chats available yet."))
                                : I18n.trFor("dankChat", "No chats yet. Link an account to get started.")
                        color: Theme.surfaceVariantText
                    }
                }
                DankButton { Layout.fillWidth: true; visible: root.service.chats.length === 0; text: I18n.trFor("dankChat", "Accounts"); onClicked: root.service.accountsOpen = true }
            }
            Rectangle { visible: !root.narrow; Layout.fillHeight: true; width: 1; color: Theme.outline; opacity: 0.25 }
            ColumnLayout {
                visible: !root.narrow || !!root.service.selectedChat
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Theme.spacingS
                RowLayout {
                    Layout.fillWidth: true
                    Action { visible: root.narrow; iconName: "arrow_back"; onClicked: root.service.selectedChat = null }
                    Avatar { visible: !!root.service.selectedChat; label: root.service.selectedChat?.name || "" }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { Layout.fillWidth: true; text: root.service.selectedChat?.name || I18n.trFor("dankChat", "Your conversations"); elide: Text.ElideRight; font.weight: Font.Medium }
                        Label {
                            objectName: "chatPresenceLabel"
                            Layout.fillWidth: true
                            text: root.service.selectedChat ? root.service.accountLabel(root.service.selectedChat) + " · " + (root.service.selectedChat.provider === "telegram" ? "TG" : "WA") + (root.service.presenceText ? " · " + root.service.presenceText : "") : I18n.trFor("dankChat", "Choose a chat")
                            elide: Text.ElideRight
                            color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                    Action { objectName: "searchMessagesAction"; visible: !!root.service.selectedChat; iconName: "search"; tooltipText: I18n.trFor("dankChat", "Search messages"); Accessible.name: tooltipText; onClicked: root.service.browse("search", "", false) }
                    Action { objectName: "browseMediaAction"; visible: !!root.service.selectedChat; iconName: "photo_library"; tooltipText: I18n.trFor("dankChat", "Media"); Accessible.name: tooltipText; onClicked: root.service.browse("images", "", false) }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline; opacity: 0.25 }
                MessageBrowser { service: root.service; visible: !!root.service.browseMode; Layout.fillWidth: true; Layout.fillHeight: true }
                ListView {
                    visible: !root.service.browseMode
                    id: messageList
                    objectName: "messageList"
                    ChatWheel { view: messageList; onScrolled: messageList.followTail = messageList.atYEnd }
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: Theme.spacingS
                    model: ListModel { id: messageRows; dynamicRoles: true }
                    function syncMessages() {
                        const incoming = root.service.messages;
                        const key = root.service.selectedChat?.key || "";
                        if (key !== displayedChat) messageRows.clear();
                        for (let i = 0; i < incoming.length; i++) {
                            const row = incoming[i];
                            const signature = JSON.stringify(row);
                            if (i < messageRows.count && messageRows.get(i).entry.id !== row.id) {
                                let existing = -1;
                                for (let j = i + 1; j < messageRows.count; j++) {
                                    if (messageRows.get(j).entry.id === row.id) { existing = j; break; }
                                }
                                if (existing >= 0) messageRows.move(existing, i, 1);
                                else messageRows.insert(i, {entry: row, signature: signature});
                            }
                            if (i >= messageRows.count) messageRows.append({entry: row, signature: signature});
                            else if (messageRows.get(i).signature !== signature) {
                                messageRows.setProperty(i, "entry", row);
                                messageRows.setProperty(i, "signature", signature);
                            }
                        }
                        if (messageRows.count > incoming.length) messageRows.remove(incoming.length, messageRows.count - incoming.length);
                    }
                    function reportViewport() {
                        if (!visible || !root.Window.window?.visible || !root.service.surfaceOpen || typeof root.service.loadNextMedia !== "function") return;
                        root.service.readingLatest = atYEnd && !root.service.historyContext;
                        root.service.readVisibleChat();
                        const ids = [];
                        for (let i = 0; i < count; i++) {
                            const row = itemAtIndex(i);
                            if (row && row.y + row.height >= contentY && row.y <= contentY + height) ids.push(row.entry.id);
                        }
                        root.service.visibleMediaIds = ids;
                        root.service.loadNextMedia();
                    }
                    Timer { id: viewportTimer; interval: 80; onTriggered: messageList.reportViewport() }
                    onContentYChanged: viewportTimer.restart()
                    property string highlightedMessage: ""
                    Timer { id: highlightTimer; interval: 1800; onTriggered: messageList.highlightedMessage = "" }
                    property bool followTail: true
                    property real savedScroll: 0
                    property string displayedChat: ""
                    function settleScroll() {
                        if (!followTail) return;
                        forceLayout();
                        positionViewAtEnd();
                        viewportTimer.restart();
                    }
                    function openAtLatest() {
                        cancelFlick();
                        followTail = true;
                        highlightedMessage = "";
                        Qt.callLater(settleScroll);
                        tailTimer.restart();
                    }
                    Timer { id: tailTimer; interval: 50; onTriggered: messageList.settleScroll() }
                    Component.onCompleted: { syncMessages(); displayedChat = root.service.selectedChat?.key || ""; openAtLatest(); }
                    onVisibleChanged: if (visible) { viewportTimer.restart(); if (followTail && !root.service.historyContext) openAtLatest(); }
                    onContentHeightChanged: { viewportTimer.restart(); if (followTail) tailTimer.restart(); }
                    onHeightChanged: if (followTail) tailTimer.restart()
                    onDraggingChanged: if (dragging) followTail = false
                    onMovementEnded: followTail = atYEnd
                    Connections {
                        target: root.service
                        ignoreUnknownSignals: true
                        function onFocusMessageRequested(messageId) {
                            Qt.callLater(() => {
                                const index = root.service.messages.findIndex(message => message.id === messageId);
                                if (index < 0) return;
                                messageList.followTail = false;
                                messageList.positionViewAtIndex(index, ListView.Center);
                                messageList.highlightedMessage = messageId;
                                highlightTimer.restart();
                            });
                        }
                        function onSelectedChatChanged() { messageList.openAtLatest(); }
                        function onMessagesReplacing() {
                            messageList.followTail = messageList.followTail || messageList.count === 0 || messageList.atYEnd;
                            messageList.savedScroll = messageList.contentY;
                        }
                        function onMessagesChanged() {
                            const key = root.service.selectedChat?.key || "";
                            const changedChat = key !== messageList.displayedChat;
                            messageList.syncMessages();
                            messageList.displayedChat = key;
                            if (changedChat || root.service.messages.length === 0) messageList.openAtLatest();
                            viewportTimer.restart();
                            Qt.callLater(() => {
                                messageList.forceLayout();
                                if (messageList.followTail) messageList.settleScroll();
                                else messageList.contentY = messageList.savedScroll;
                            });
                        }
                    }
                    Action {
                        parent: messageList
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Theme.spacingS
                        z: 20
                        visible: messageList.count > 0 && (!!root.service.historyContext || !messageList.atYEnd)
                        iconName: "arrow_downward"
                        tooltipText: I18n.trFor("dankChat", "Jump to latest message")
                        onClicked: { messageList.openAtLatest(); root.service.showLatest(); }
                        Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.surfaceContainerHigh; border.color: Theme.outline; z: -1 }
                    }
                    delegate: Item {
                        id: messageRow
                        required property var entry
                        readonly property var modelData: entry
                        width: messageList.width
                        height: bubble.height + 4
                        onHeightChanged: if (messageList.followTail) tailTimer.restart()
                        Rectangle {
                            id: bubble
                            readonly property color readableText: Links.readable(color, Theme.surfaceText, Theme.primaryText)
                            readonly property color readableSecondary: Links.readable(color, Theme.surfaceVariantText, readableText)
                            readonly property color readableAccent: Links.readable(color, Theme.primary, readableText)
                            width: Math.min(parent.width - 12, Math.max(130, parent.width * 0.86))
                            height: bubbleContent.implicitHeight + 2 * Theme.spacingS
                            anchors.right: messageRow.modelData.out ? parent.right : undefined
                            anchors.left: messageRow.modelData.out ? undefined : parent.left
                            radius: Theme.cornerRadius
                            color: messageRow.modelData.out ? Theme.primaryContainer : Theme.surfaceContainerHigh
                            border.width: messageList.highlightedMessage === messageRow.modelData.id ? 2 : messageRow.modelData.out ? 0 : 1
                            border.color: messageList.highlightedMessage === messageRow.modelData.id ? bubble.readableAccent : Theme.outline
                            ColumnLayout {
                                id: bubbleContent
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: Theme.spacingS; spacing: Theme.spacingXS
                                Label { Layout.fillWidth: true; wrapMode: Text.NoWrap; elide: Text.ElideRight; visible: !messageRow.modelData.out && !!messageRow.modelData.sender; text: messageRow.modelData.sender; color: bubble.readableAccent; font.pixelSize: Theme.fontSizeSmall }
                                Label {
                                    Layout.fillWidth: true
                                    visible: !!messageRow.modelData.replyText || !!messageRow.modelData.replyId
                                    text: "↳ " + (messageRow.modelData.replyText || I18n.trFor("dankChat", "Original message"))
                                    maximumLineCount: 2; elide: Text.ElideRight; wrapMode: Text.Wrap
                                    color: bubble.readableSecondary; font.pixelSize: Theme.fontSizeSmall
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !!messageRow.modelData.replyId
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.service.jumpToReply(messageRow.modelData.replyId)
                                    }
                                }
                                Loader {
                                    id: mediaPreviewLoader
                                    Layout.fillWidth: true
                                    active: !!messageRow.modelData.mediaType && messageRow.modelData.mediaType !== "webpage"
                                    visible: active
                                    Component.onCompleted: {
                                        setSource(Qt.resolvedUrl("MediaPreview.qml") + "?revision=" + root.service.viewRevision, {
                                            message: Qt.binding(() => messageRow.modelData),
                                            service: root.service,
                                            foregroundColor: Qt.binding(() => bubble.readableSecondary)
                                        });
                                    }
                                    Connections {
                                        target: mediaPreviewLoader.item
                                        function onImageRequested(path) { root.galleryPath = path; mediaDialog.open(); }
                                    }
                                }
                                Controls.TextArea {
                                    id: messageText
                                    Layout.fillWidth: true
                                    visible: !!messageRow.modelData.text
                                    text: Links.render(messageRow.modelData.text, bubble.readableAccent)
                                    textFormat: TextEdit.RichText
                                    onLinkActivated: link => { if (Links.isWebUrl(link)) Qt.openUrlExternally(link); }
                                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                                    padding: 0; color: bubble.readableText; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMedium
                                    background: null
                                    selectionColor: Theme.primary
                                    selectedTextColor: Theme.primaryText
                                    Controls.ContextMenu.menu: TextMenu {
                                        editor: messageText
                                        allowReply: true
                                        allowEdit: messageRow.modelData.out && !!messageRow.modelData.text
                                        onEditRequested: root.openEdit(messageRow.modelData)
                                        onReplyRequested: root.service.setReply(messageRow.modelData)
                                        onDeleteRequested: root.openDeleteMessage(messageRow.modelData)
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    visible: (messageRow.modelData.reactions || []).length > 0
                                    spacing: 4
                                    Repeater {
                                        model: messageRow.modelData.reactions || []
                                        delegate: Controls.ItemDelegate {
                                            id: reactionChip
                                            required property var modelData
                                            objectName: "reactionChip"
                                            width: implicitWidth; height: 30
                                            padding: 5
                                            enabled: !root.service.demo && messageRow.modelData.canReact !== false && !modelData.custom && !root.service.reacting?.[root.service.selectedChat?.key + ":" + messageRow.modelData.id]
                                            Accessible.name: modelData.emoji + " " + modelData.count + (modelData.chosen ? " " + I18n.trFor("dankChat", "Your reaction") : "")
                                            background: Rectangle { radius: Theme.cornerRadius; color: reactionChip.modelData.chosen ? Theme.primary : Theme.surfaceContainer; border.color: reactionChip.modelData.chosen ? Theme.primary : Theme.outline }
                                            contentItem: Label { text: reactionChip.modelData.emoji + " " + reactionChip.modelData.count; color: reactionChip.modelData.chosen ? Theme.primaryText : Theme.surfaceText; elide: Text.ElideNone; wrapMode: Text.NoWrap }
                                            onClicked: root.service.reactToMessage(messageRow.modelData, modelData.chosen ? "" : modelData.emoji, root.service.selectedChat)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Action {
                                        visible: !!messageRow.modelData.mediaPath
                                        iconName: "open_in_new"; width: 26; height: 26; iconSize: 16
                                        iconColor: bubble.readableText
                                        tooltipText: I18n.trFor("dankChat", "Open media")
                                        onClicked: Qt.openUrlExternally(Links.localFileUrl(messageRow.modelData.mediaPath))
                                    }
                                    Action {
                                        visible: !!messageRow.modelData.mediaPath
                                        enabled: !root.service.demo
                                        iconName: "download"; width: 26; height: 26; iconSize: 16
                                        iconColor: bubble.readableText
                                        tooltipText: I18n.trFor("dankChat", "Save media as…")
                                        onClicked: {
                                            root.exportMessage = messageRow.modelData;
                                            root.exportChat = root.service.selectedChat;
                                            root.savingMedia = true;
                                            fileDialog.open();
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label { visible: !!messageRow.modelData.edited; text: I18n.trFor("dankChat", "Edited"); font.pixelSize: Theme.fontSizeSmall; color: bubble.readableSecondary }
                                    Label { text: messageRow.modelData.time || (messageRow.modelData.timestamp ? Qt.formatDateTime(new Date(messageRow.modelData.timestamp * 1000), "hh:mm") : ""); color: bubble.readableSecondary; font.pixelSize: Theme.fontSizeSmall }
                                    DankIcon {
                                        id: deliveryIcon
                                        readonly property string statusText: messageRow.modelData.deliveryPartial
                                            ? I18n.trFor("dankChat", "Confirmed by at least one group participant")
                                            : messageRow.modelData.deliveryStatus === "read" ? I18n.trFor("dankChat", "Read")
                                            : messageRow.modelData.deliveryStatus === "delivered" ? I18n.trFor("dankChat", "Delivered")
                                            : I18n.trFor("dankChat", "Sent")
                                        HoverHandler { onHoveredChanged: hovered ? deliveryTooltip.show(deliveryIcon.statusText, deliveryIcon, 0, 0, "top") : deliveryTooltip.hide() }
                                        visible: messageRow.modelData.out && !!messageRow.modelData.deliveryStatus
                                        name: ["read", "delivered"].includes(messageRow.modelData.deliveryStatus) ? "done_all" : "check"
                                        size: 16
                                        color: messageRow.modelData.deliveryStatus === "read" ? bubble.readableAccent : bubble.readableSecondary
                                    }
                                    Action {
                                        iconName: "add_reaction"; width: 26; height: 26; iconSize: 16
                                        tooltipText: I18n.trFor("dankChat", "React with emoji")
                                        visible: messageRow.modelData.canReact !== false
                                        enabled: !root.service.demo && !root.service.reacting?.[root.service.selectedChat?.key + ":" + messageRow.modelData.id]
                                        onClicked: root.openReactionPicker(messageRow.modelData)
                                    }
                                    Action { iconName: "delete_outline"; width: 26; height: 26; iconSize: 16; tooltipText: I18n.trFor("dankChat", "Delete message…"); enabled: !root.service.demo && !root.service.writing; onClicked: root.openDeleteMessage(messageRow.modelData) }
                                    Action { iconName: "reply"; width: 26; height: 26; iconSize: 16; onClicked: root.service.setReply(messageRow.modelData) }
                                }
                            }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
                    readonly property var states: Object.keys(root.service.transferStates || {}).filter(k => k.startsWith(root.service.selectedChat?.key + ":file:") || k === root.service.selectedChat?.key + ":send").map(k => root.service.transferStates[k])
                    visible: states.length > 0
                    text: states.map((state, i) => (i + 1) + ": " + I18n.trFor("dankChat", state)).join(" · ")
                }
                Rectangle {
                    objectName: "replyComposerPreview"
                    visible: !!root.service.reply
                    Layout.fillWidth: true
                    implicitHeight: replyPreviewRow.implicitHeight + 20
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: Theme.outline
                    RowLayout {
                        id: replyPreviewRow
                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 3; radius: 2; color: Theme.primary }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 3
                            Label { Layout.fillWidth: true; text: root.service.reply?.out ? I18n.trFor("dankChat", "You") : root.service.reply?.sender || I18n.trFor("dankChat", "Reply"); color: Links.readable(Theme.surfaceContainerHigh, Theme.primary, Theme.surfaceText); font.weight: Font.Medium; elide: Text.ElideRight }
                            Label { Layout.fillWidth: true; text: root.service.reply?.text || root.service.reply?.filename || I18n.trFor("dankChat", "Attachment"); maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight }
                        }
                        Action { iconName: "close"; tooltipText: I18n.trFor("dankChat", "Cancel reply"); onClicked: root.service.setReply(null) }
                    }
                }
                Rectangle {
                    objectName: "voiceComposer"
                    visible: !!root.service.voiceState
                    Layout.fillWidth: true
                    implicitHeight: voiceHeading.implicitHeight + voiceActions.implicitHeight + 26 + (voicePreview.active ? 94 : 0)
                    radius: Theme.cornerRadius; color: Theme.surfaceContainerHigh; border.color: Theme.outline
                    ColumnLayout {
                        id: voiceColumn
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                        spacing: 6
                        Label {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            id: voiceHeading
                            text: root.service.voiceState === "recording" ? I18n.trFor("dankChat", "Recording voice message…") + " " + Math.floor(root.service.voiceSeconds / 60) + ":" + String(root.service.voiceSeconds % 60).padStart(2, "0") + " / 5:00"
                                : root.service.voiceState === "ready" ? I18n.trFor("dankChat", "Preview voice message") : I18n.trFor("dankChat", "Please wait…")
                        }
                        Loader {
                            id: voicePreview
                            Layout.fillWidth: true; Layout.preferredHeight: active ? 88 : 0
                            active: !!root.service.voicePath && root.service.voiceState === "ready"
                            sourceComponent: MediaPlayerView { sourceUrl: "file://" + root.service.voicePath; service: root.service; audioOnly: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            id: voiceActions
                            DankButton { text: I18n.trFor("dankChat", "Discard"); enabled: ["recording", "ready"].includes(root.service.voiceState); onClicked: root.service.discardVoice() }
                            Item { Layout.fillWidth: true }
                            DankButton { visible: root.service.voiceState === "recording"; text: I18n.trFor("dankChat", "Stop recording"); onClicked: root.service.stopVoice() }
                            DankButton { visible: root.service.voiceState !== "recording"; text: I18n.trFor("dankChat", "Send"); enabled: root.service.voiceState === "ready" && !root.service.writing; onClicked: root.service.sendVoice() }
                        }
                    }
                }
                Rectangle {
                    visible: !!root.service.selectedChat
                    Layout.fillWidth: true
                    implicitHeight: Math.min(130, Math.max(52, composer.implicitHeight + 12))
                    radius: Theme.cornerRadius; color: Theme.surfaceContainer
                    border.color: composer.activeFocus ? Theme.primary : Theme.outline
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 6; spacing: 4
                        Action { iconName: "attach_file"; tooltipText: root.attachmentPaths.length ? I18n.trFor("dankChat", "Pending attachments") + " (" + root.attachmentPaths.length + ")" : I18n.trFor("dankChat", "Add files"); enabled: !root.service.demo && !root.service.writing; onClicked: { if (root.attachmentPaths.length) attachmentConfirm.open(); else { root.savingMedia = false; fileDialog.open(); } } }
                        Action {
                            iconName: "sentiment_satisfied"
                            tooltipText: I18n.trFor("dankChat", "Emoji")
                            onClicked: {
                                root.openEmojiPicker();
                            }
                        }
                        Controls.ScrollView {
                            id: composerScroll
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            Controls.TextArea {
                                id: composer
                                objectName: "messageComposer"
                                width: composerScroll.availableWidth
                                height: Math.max(composerScroll.availableHeight, implicitHeight)
                                text: root.service.draft
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.Wrap; selectByMouse: true
                                verticalAlignment: TextEdit.AlignVCenter
                                padding: 6
                                selectionColor: Theme.primary
                                selectedTextColor: Theme.primaryText
                                placeholderText: root.service.demo ? I18n.trFor("dankChat", "Demo — sending disabled") : I18n.trFor("dankChat", "Write a message")
                                color: Theme.surfaceText; placeholderTextColor: Theme.surfaceVariantText
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMedium
                                background: null
                                Controls.ContextMenu.menu: TextMenu { editor: composer; composerPaste: true }
                                onTextChanged: if (text !== root.service.draft) root.service.setDraft(text)
                                Keys.onPressed: event => {
                                    if (event.matches(StandardKey.Paste)) { event.accepted = true; root.pasteClipboard(); }
                                }
                                Keys.onReturnPressed: event => {
                                    if (!(event.modifiers & Qt.ShiftModifier)) { root.service.sendMessage(""); event.accepted = true; }
                                    else event.accepted = false;
                                }
                            }
                        }
                        Action { objectName: "recordVoiceButton"; iconName: "mic"; tooltipText: I18n.trFor("dankChat", "Record voice message"); enabled: !root.service.demo && !root.service.writing && !root.service.voiceState; onClicked: root.service.startVoice() }
                        Action { iconName: "send"; enabled: !root.service.demo && !root.service.writing && root.service.draft.trim().length > 0; onClicked: root.service.sendMessage("") }
                    }
                }
            }
        }
    }
    property bool pastingClipboard: false
    readonly property var attachmentPaths: service.attachmentDrafts[attachmentChatKey] || []
    function discardClipboardPaths(paths) {
        if (!service.demo && service.selectedChat)
            service.sendRequest(service.selectedChat.provider, "discard_clipboard", {paths: paths}, () => {});
    }
    function addAttachments(paths) {
        const combined = Array.from(new Set(attachmentPaths.concat(paths)));
        if (combined.length > 10) { discardClipboardPaths(paths.filter(path => !attachmentPaths.includes(path))); service.errorText = I18n.trFor("dankChat", "Choose up to 10 attachments."); return; }
        service.setAttachmentPaths(combined, attachmentChatKey);
        attachmentConfirm.open();
    }
    function attachmentIsImage(path) { return /\.(png|jpe?g|webp|gif|bmp)$/i.test(path); }

    function pasteClipboard() {
        if (service.demo) { composer.paste(); return; }
        if (pastingClipboard || service.writing || !service.selectedChat) return;
        const chatKey = service.selectedChat.key;
        const provider = service.selectedChat.provider;
        pastingClipboard = true; service.errorText = "";
        if (!service.sendRequest(provider, "clipboard_image", {}, result => {
            pastingClipboard = false;
            if (service.selectedChat?.key !== chatKey) { if (result.paths) service.sendRequest(provider, "discard_clipboard", {paths: result.paths}, () => {}); return; }
            if (result.error) service.errorText = I18n.trFor("dankChat", result.error);
            if (result.textFallback) { composer.paste(); return; }
            if (!result.ok || !result.paths?.length) return;
            addAttachments(result.paths);
        })) pastingClipboard = false;
    }
    property var reactionMessage: null
    property var reactionChat: null
    function openReactionPicker(message) {
        openEmojiPicker();
        reactionMessage = message;
        reactionChat = service.selectedChat;
    }
    function openEmojiPicker() {
        reactionMessage = null; reactionChat = null;
        emojiChatKey = service.selectedChat?.key || "";
        emojiSelectionStart = composer.selectionStart;
        emojiSelectionEnd = composer.selectionEnd;
        emojiSearch.text = "";
        emojiPicker.category = -1;
        emojiPicker.open();
        emojiSearch.forceActiveFocus();
    }
    function emojiLayoutStatus() {
        return JSON.stringify({width: emojiGrid.width, height: emojiGrid.height, count: emojiGrid.count, firstWidth: emojiGrid.itemAtIndex(0)?.width, firstHeight: emojiGrid.itemAtIndex(0)?.height, visible: emojiGrid.itemAtIndex(0)?.visible, text: emojiGrid.itemAtIndex(0)?.contentItem.text, labelWidth: emojiGrid.itemAtIndex(0)?.contentItem.width, labelHeight: emojiGrid.itemAtIndex(0)?.contentItem.height, padding: emojiGrid.itemAtIndex(0)?.padding, labelOpacity: emojiGrid.itemAtIndex(0)?.contentItem.opacity});
    }
    function previewEmojiSearch(query) { emojiSearch.text = query; }
    function previewEmojiImage(path) { emojiPicker.contentItem.grabToImage(result => result.saveToFile(path)); }
    function insertEmoji(value) {
        if (reactionMessage) {
            if (service.selectedChat?.key === reactionChat?.key) {
                const current = service.messages.find(row => row.id === reactionMessage.id);
                if (current) {
                    const own = (current.reactions || []).some(reaction => reaction.chosen && !reaction.custom && reaction.emoji.replace(/\ufe0f/g, "") === value.replace(/\ufe0f/g, ""));
                    service.reactToMessage(current, own ? "" : value, reactionChat);
                }
            }
        } else if (service.selectedChat?.key === emojiChatKey) {
            composer.remove(emojiSelectionStart, emojiSelectionEnd);
            composer.insert(emojiSelectionStart, value);
            composer.cursorPosition = emojiSelectionStart + value.length;
        }
        emojiPicker.close();
        composer.forceActiveFocus();
    }
    DankTooltipV2 { id: emojiTooltip }
    property string emojiChatKey: ""
    property int emojiSelectionStart: 0
    property int emojiSelectionEnd: 0
    Controls.Popup {
        id: emojiPicker
        objectName: "emojiPicker"
        onClosed: emojiTooltip.hide()
        width: Math.min(root.width - 24, 320)
        height: Math.min(root.height - 24, 440)
        x: Math.max(12, root.width - width - 12)
        y: Math.max(12, root.height - height - 70)
        focus: true
        popupType: Controls.Popup.Item
        property int category: -1
        readonly property var categories: [
            ["✨", "All emoji"], ["😀", "Smileys & Emotion"], ["👋", "People & Body"],
            ["🏽", "Component"], ["🐻", "Animals & Nature"], ["🍔", "Food & Drink"],
            ["🚗", "Travel & Places"], ["⚽", "Activities"], ["💡", "Objects"],
            ["❤️", "Symbols"], ["🏳️", "Flags"]
        ]
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        contentItem: ColumnLayout {
            RowLayout {
                Layout.fillWidth: true
                DankTextField {
                    id: emojiSearch
                    objectName: "emojiSearch"
                    Layout.fillWidth: true
                    placeholderText: I18n.trFor("dankChat", "Search emoji…")
                    hidePlaceholderOnFocus: false
                    leftIconName: "search"
                    showClearButton: true
                }
                Action { iconName: "close"; onClicked: emojiPicker.close() }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 6
                rowSpacing: 4; columnSpacing: 4
                Repeater {
                    model: emojiPicker.categories
                    delegate: Controls.ItemDelegate {
                        id: categoryButton
                        required property var modelData
                        readonly property int categoryId: Emojis.groups.indexOf(modelData[1])
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 32
                        padding: 0
                        Accessible.name: I18n.trFor("dankChat", modelData[1])
                        contentItem: Label { text: categoryButton.modelData[0]; font.pixelSize: 18; elide: Text.ElideNone; wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: Theme.cornerRadius; color: emojiPicker.category === categoryButton.categoryId ? Theme.primaryContainer : Theme.surfaceContainerHigh }
                        HoverHandler { onHoveredChanged: hovered ? emojiTooltip.show(I18n.trFor("dankChat", modelData[1]), parent, 0, 0, "top") : emojiTooltip.hide() }
                        onClicked: { emojiPicker.category = categoryId; emojiSearch.text = ""; }
                    }
                }
            }
            GridView {
                id: emojiGrid
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                cellWidth: width / 7; cellHeight: 40
                model: emojiPicker.visible ? Emojis.search(emojiSearch.text, emojiPicker.category) : []
                onModelChanged: positionViewAtBeginning()
                boundsBehavior: Flickable.StopAtBounds
                ChatWheel { view: emojiGrid }
                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Theme.outline }
                }
                Label {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: emojiGrid.count === 0
                    text: I18n.trFor("dankChat", "No emoji found.")
                    color: Theme.surfaceVariantText
                }
                delegate: Controls.ItemDelegate {
                    required property var modelData
                    width: GridView.view.cellWidth; height: 40
                    padding: 0
                    leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                    background: Rectangle { radius: Theme.cornerRadius; color: parent.hovered || parent.activeFocus ? Theme.surfaceContainerHigh : "transparent" }
                    contentItem: Label { text: modelData[0]; font.pixelSize: 24; elide: Text.ElideNone; wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    HoverHandler { onHoveredChanged: hovered ? emojiTooltip.show(modelData[2], parent, 0, 0, "top") : emojiTooltip.hide() }
                    onClicked: { emojiTooltip.hide(); root.insertEmoji(modelData[0]); }
                }
            }
        }
    }
    property var editTarget: null
    property var editChat: null
    function openEdit(message) { editTarget = message; editChat = service.selectedChat; editText.text = message.text; editDialog.open(); }
    Controls.Popup {
        id: editDialog
        anchors.centerIn: parent; width: Math.min(root.width - 24, 560); modal: true; focus: true
        popupType: Controls.Popup.Item
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        contentItem: ColumnLayout {
            Label { text: I18n.trFor("dankChat", "Edit message"); Layout.fillWidth: true }
            DankTextField { id: editText; Layout.fillWidth: true; maximumLength: 4096 }
            DankButton { text: I18n.trFor("dankChat", "Save"); enabled: !!editText.text.trim() && !root.service.writing; onClicked: { root.service.editMessage(root.editTarget, editText.text, root.editChat); editDialog.close(); } }
            DankButton { text: I18n.trFor("dankChat", "Cancel"); onClicked: editDialog.close() }
        }
    }
    Shortcut { sequence: "Ctrl+K"; enabled: !!root.Window.window?.active; onActivated: { root.service.settingsOpen = false; root.service.accountsOpen = false; if (root.narrow) root.service.selectedChat = null; chatSearch.forceActiveFocus(); } }
    Shortcut { sequence: "Ctrl+F"; enabled: !!root.Window.window?.active && !!root.service.selectedChat; onActivated: root.service.browse("search", "", false) }
    Shortcut { sequence: "Ctrl+R"; enabled: !!root.Window.window?.active && root.service.messages.length > 0; onActivated: { root.service.setReply(root.service.messages[root.service.messages.length - 1]); composer.forceActiveFocus(); } }
    function adjacentChat(delta) { const chats = service.visibleChats; const index = chats.findIndex(c => c.key === service.selectedChat?.key); if (chats.length) service.selectChat(chats[(index + delta + chats.length) % chats.length]); }
    Shortcut { sequence: "Alt+Up"; enabled: !!root.Window.window?.active; onActivated: root.adjacentChat(-1) }
    Shortcut { sequence: "Alt+Down"; enabled: !!root.Window.window?.active; onActivated: root.adjacentChat(1) }
    property bool savingDiagnostics: false
    property bool savingMedia: false
    property var exportMessage: null
    property var exportChat: null
    Controls.Popup {
        id: fileDialog
        onClosed: root.savingDiagnostics = false
        anchors.centerIn: parent
        width: Math.min(root.width - 24, 860)
        height: root.height - 24
        modal: true
        focus: true
        popupType: Controls.Popup.Item
        padding: 0
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        contentItem: Loader {
            id: filePickerLoader
            active: fileDialog.visible
            sourceComponent: FilePickerCompat {
                pickerTitle: root.savingDiagnostics ? I18n.trFor("dankChat", "Save diagnostic report…") : root.savingMedia ? I18n.trFor("dankChat", "Save media as…") : I18n.trFor("dankChat", "Choose an attachment to send")
                saveMode: root.savingMedia
                defaultFileName: root.savingDiagnostics ? "dankchat-diagnostics.json" : root.savingMedia ? (root.exportMessage?.filename || root.exportMessage?.mediaPath?.split("/").pop() || "media") : ""
                onLoadErrorChanged: if (loadError) {
                    root.service.errorText = I18n.trFor("dankChat", loadError);
                    root.savingDiagnostics = false;
                    fileDialog.close();
                }
                onFilesSelected: paths => {
                    const selectedPaths = paths.map(path => {
                        const value = path.toString();
                        return value.startsWith("file://") ? decodeURIComponent(value.slice(7)) : value;
                    });
                    if (!selectedPaths.length) return;
                    const diagnostics = root.savingDiagnostics;
                    fileDialog.close();
                    if (diagnostics) root.service.exportDiagnostics(selectedPaths[0]);
                    else if (root.savingMedia) root.service.saveMedia(root.exportChat, root.exportMessage, selectedPaths[0]);
                    else root.addAttachments(selectedPaths);
                }
                onCancelled: { root.savingDiagnostics = false; fileDialog.close(); if (!root.savingMedia && root.attachmentPaths.length) attachmentConfirm.open(); }
            }
        }
    }
    property string galleryPath: ""
    Controls.Popup {
        id: mediaDialog
        anchors.centerIn: parent
        width: root.width - 24
        height: root.height - 24
        modal: false
        popupType: Controls.Popup.Item
        background: Rectangle { color: Theme.surface; radius: Theme.cornerRadius; border.color: Theme.outline }
        focus: true
        onOpened: imageViewport.setZoom(1)
        contentItem: Item {
            Flickable {
                id: imageViewport
                anchors.fill: parent
                anchors.topMargin: 44
                clip: true
                property real zoom: 1
                contentWidth: width * zoom
                contentHeight: height * zoom
                boundsBehavior: Flickable.StopAtBounds
                function setZoom(value, px, py) {
                    const old = zoom;
                    const x = px === undefined ? width / 2 : px;
                    const y = py === undefined ? height / 2 : py;
                    const targetX = (contentX + x) / old;
                    const targetY = (contentY + y) / old;
                    zoom = Math.max(1, Math.min(8, value));
                    contentX = Math.max(0, Math.min(contentWidth - width, targetX * zoom - x));
                    contentY = Math.max(0, Math.min(contentHeight - height, targetY * zoom - y));
                }
                AnimatedImage {
                    width: imageViewport.contentWidth
                    height: imageViewport.contentHeight
                    source: mediaDialog.visible ? Links.localFileUrl(root.galleryPath) : ""
                    fillMode: Image.PreserveAspectFit
                    playing: mediaDialog.visible
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onDoubleClicked: event => imageViewport.setZoom(imageViewport.zoom > 1 ? 1 : 2, event.x - imageViewport.contentX, event.y - imageViewport.contentY)
                        onWheel: event => {
                            imageViewport.setZoom(imageViewport.zoom * (event.angleDelta.y > 0 ? 1.2 : 1 / 1.2), event.x - imageViewport.contentX, event.y - imageViewport.contentY);
                            event.accepted = true;
                        }
                    }
                }
            }
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                Action { iconName: "zoom_out"; enabled: imageViewport.zoom > 1; onClicked: imageViewport.setZoom(imageViewport.zoom / 1.25) }
                Label { text: Math.round(imageViewport.zoom * 100) + "%" }
                Action { iconName: "zoom_in"; enabled: imageViewport.zoom < 8; onClicked: imageViewport.setZoom(imageViewport.zoom * 1.25) }
                Action { iconName: "fit_screen"; onClicked: imageViewport.setZoom(1) }
                Item { Layout.fillWidth: true }
                Action { iconName: "close"; onClicked: mediaDialog.close() }
            }
        }
    }
    readonly property alias deleteMessageDialog: deleteConfirm
    property var deleteTarget: null
    property var deleteChat: null
    Connections { target: root.service; function onSelectedChatChanged() { deleteConfirm.reject(); attachmentConfirm.close(); fileDialog.close(); } }
    function openDeleteMessage(message) {
        if (!service.selectedChat || service.demo || service.writing) return;
        deleteTarget = message; deleteChat = service.selectedChat;
        deleteScope.checked = false;
        deleteConfirm.open();
    }
    Controls.Dialog {
        id: deleteConfirm
        objectName: "deleteMessageDialog"
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 460)
        modal: true; popupType: Controls.Popup.Item
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        header: Label { text: I18n.trFor("dankChat", "Delete message?"); padding: Theme.spacingM; wrapMode: Text.Wrap }
        contentItem: ColumnLayout {
            spacing: Theme.spacingM
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.deleteTarget?.text || root.deleteTarget?.filename || I18n.trFor("dankChat", "Attachment"); maximumLineCount: 3; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.deleteChat?.deleteForMe === false || deleteScope.checked ? I18n.trFor("dankChat", "This deletes the message for everyone. This cannot be undone.") : I18n.trFor("dankChat", "This deletes the message for you. Other participants keep their copy.") }
            Controls.CheckBox {
                id: deleteScope
                objectName: "deleteForEveryone"
                visible: root.deleteChat?.deleteForMe !== false && (root.deleteChat?.provider === "telegram" || !!root.deleteTarget?.out)
                text: I18n.trFor("dankChat", "Delete for everyone")
                contentItem: Label { text: deleteScope.text; leftPadding: 32; wrapMode: Text.Wrap; verticalAlignment: Text.AlignVCenter }
                indicator: Rectangle { width: 22; height: 22; y: (deleteScope.height - height) / 2; radius: 4; border.color: Theme.primary; color: deleteScope.checked ? Theme.primary : Theme.surfaceContainer; Label { anchors.centerIn: parent; text: "✓"; visible: deleteScope.checked; color: Theme.primaryText } }
                Layout.fillWidth: true
            }
        }
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            DankButton { text: I18n.trFor("dankChat", "Cancel"); onClicked: deleteConfirm.reject() }
            DankButton { text: I18n.trFor("dankChat", "Delete"); enabled: !root.service.writing && root.service.selectedChat?.key === root.deleteChat?.key; onClicked: deleteConfirm.accept() }
        }
        onAccepted: root.service.deleteMessage(root.deleteTarget, root.deleteChat.deleteForMe !== false && !deleteScope.checked, root.deleteChat.key)
    }
    property string disconnectProvider: ""
    Controls.Dialog {
        id: disconnectConfirm
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 420)
        modal: true
        popupType: Controls.Popup.Item
        title: (root.disconnectProvider === "telegram" ? "Telegram" : "WhatsApp") + " — " + I18n.trFor("dankChat", "Disconnect account")
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        header: Label { text: disconnectConfirm.title; padding: Theme.spacingM; wrapMode: Text.Wrap }
        contentItem: Label {
            text: I18n.trFor("dankChat", "Sign out this DankChat device and remove its cached chats, media and drafts? Messages on your phone stay intact. Linking again requires a new QR code.")
            wrapMode: Text.Wrap
        }
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            DankButton { text: I18n.trFor("dankChat", "Cancel"); onClicked: disconnectConfirm.reject() }
            DankButton { text: I18n.trFor("dankChat", "Disconnect account"); onClicked: disconnectConfirm.accept() }
        }
        onAccepted: root.service.accountAction(root.disconnectProvider, "logout")
    }
    readonly property string attachmentChatKey: service.selectedChat?.key || ""
    Controls.Dialog {
        id: attachmentConfirm
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 400)
        modal: true
        popupType: Controls.Popup.Item
        title: I18n.trFor("dankChat", "Send attachments")
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        header: Label { text: attachmentConfirm.title; padding: Theme.spacingM; font.weight: Font.Medium }
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            DankButton { text: I18n.trFor("dankChat", "Cancel"); onClicked: attachmentConfirm.reject() }
            DankButton { text: I18n.trFor("dankChat", "Send") + " (" + root.attachmentPaths.length + ")"; enabled: root.attachmentPaths.length > 0 && !root.service.demo && !root.service.writing; onClicked: attachmentConfirm.accept() }
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacingS
            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(260, root.height * 0.4)
                clip: true
                ColumnLayout {
                    width: parent.width
                    Repeater {
                        model: root.attachmentPaths
                        delegate: RowLayout {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            Image {
                                visible: root.attachmentIsImage(modelData)
                                Layout.preferredWidth: 72; Layout.preferredHeight: 64
                                source: visible ? Links.localFileUrl(modelData) : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true; sourceSize.width: 240
                            }
                            Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: modelData.split("/").pop(); wrapMode: Text.WrapAnywhere }
                            Action { iconName: "close"; enabled: !root.service.writing; onClicked: { root.discardClipboardPaths([modelData]); root.service.setAttachmentPaths(root.attachmentPaths.filter((_, i) => i !== index), root.attachmentChatKey); } }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                DankButton { text: I18n.trFor("dankChat", "Add files"); enabled: !root.service.writing; onClicked: { attachmentConfirm.close(); root.savingMedia = false; fileDialog.open(); } }
                DankButton { text: I18n.trFor("dankChat", "Paste"); enabled: !root.pastingClipboard; onClicked: root.pasteClipboard() }
            }
        }
        onAccepted: {
            const paths = root.attachmentPaths.slice(), key = root.attachmentChatKey;
            root.service.sendAttachments(paths, key, sent => {
                root.discardClipboardPaths(paths.slice(0, sent));
                root.service.setAttachmentPaths(paths.slice(sent), key);
                if (sent < paths.length && root.service.surfaceOpen && root.service.selectedChat?.key === key) attachmentConfirm.open();
            });
        }
        onRejected: { if (root.service.writing) return; root.discardClipboardPaths(root.attachmentPaths); root.service.setAttachmentPaths([], root.attachmentChatKey); }
    }
}
