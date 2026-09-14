import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Modals.FileBrowser
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
    function previewAttachmentPicker(opened) { if (opened) fileDialog.open(); else fileDialog.close(); }
    readonly property bool narrow: width < 620
    signal expandRequested()
    signal closeRequested()
    property bool receivedKeyboardFocus: false
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (!root.compact) return;
            if (root.Window.window.active) root.receivedKeyboardFocus = true;
            else if (root.receivedKeyboardFocus && !fileDialog.visible && !attachmentConfirm.visible && !mediaDialog.visible && !disconnectConfirm.visible) root.service.closeDropdown();
        }
    }
    focus: true
    Keys.onEscapePressed: {
        if (service.accountsOpen) service.accountsOpen = false;
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
        width: 210
        padding: Theme.spacingXS
        popupType: Controls.Popup.Item
        background: Rectangle { radius: Theme.cornerRadius; color: Theme.surfaceContainer; border.color: Theme.outline; border.width: 1 }
        MenuEntry { visible: textMenu.allowReply; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Reply"); onTriggered: textMenu.replyRequested() }
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
            Action { iconName: "manage_accounts"; onClicked: root.service.accountsOpen = !root.service.accountsOpen }
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

        Controls.ScrollView {
            id: accountsScroll
            visible: root.service.accountsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ColumnLayout {
                width: accountsScroll.availableWidth
                spacing: Theme.spacingM
                Label { text: I18n.trFor("dankChat", "Accounts"); font.pixelSize: Theme.fontSizeLarge }
                Label { text: "Telegram"; font.weight: Font.Medium }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: root.service.statuses.telegram?.authorized ? I18n.trFor("dankChat", "Connected")
                        : I18n.trFor("dankChat", "Scan the QR code in Telegram → Settings → Devices.")
                }
                DankButton {
                    text: root.service.statuses.telegram?.authorized ? I18n.trFor("dankChat", "Disconnect account") : I18n.trFor("dankChat", "Link Telegram")
                    enabled: !root.service.demo && root.service.telegramEnabled && !root.service.accountBusy.telegram
                    onClicked: {
                        if (root.service.statuses.telegram?.authorized) { root.disconnectProvider = "telegram"; disconnectConfirm.open(); }
                        else root.service.loginTelegram();
                    }
                }
                Image {
                    visible: root.service.qrPath.length > 0
                    source: visible ? "file://" + root.service.qrPath : ""
                    sourceSize: Qt.size(220, 220)
                    Layout.preferredWidth: 220; Layout.preferredHeight: visible ? 220 : 0
                    cache: false
                }
                Label {
                    visible: root.service.statuses.telegram?.authState === "expired"
                    text: I18n.trFor("dankChat", "QR code expired. Link Telegram again.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.service.statuses.telegram?.authorized && root.service.statuses.telegram?.authState === "password"
                    DankTextField {
                        id: password
                        Layout.fillWidth: true
                        Layout.minimumWidth: 100
                        Layout.maximumWidth: 360
                        Layout.preferredHeight: 44
                        echoMode: TextInput.Password
                        usePopupTransparency: root.compact
                        backgroundColor: Theme.surfaceContainerHigh
                        placeholderColor: Theme.surfaceVariantText
                        textColor: Theme.surfaceText
                        placeholderText: I18n.trFor("dankChat", "Telegram password")
                    }
                    DankButton { text: I18n.trFor("dankChat", "Sign in"); onClicked: { root.service.submitPassword(password.text); password.text = ""; } }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline; opacity: 0.3 }
                Label { text: "WhatsApp"; font.weight: Font.Medium }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: root.service.statuses.whatsapp?.authorized ? I18n.trFor("dankChat", "Connected")
                        : I18n.trFor("dankChat", "Scan the QR code in WhatsApp → Linked devices → Link a device.")
                }
                DankButton {
                    text: root.service.statuses.whatsapp?.authorized ? I18n.trFor("dankChat", "Disconnect account") : I18n.trFor("dankChat", "Link WhatsApp")
                    enabled: !root.service.demo && root.service.whatsappEnabled && !root.service.accountBusy.whatsapp && (!root.service.statuses.whatsapp?.linking || root.service.statuses.whatsapp?.authorized)
                    onClicked: {
                        if (root.service.statuses.whatsapp?.authorized) { root.disconnectProvider = "whatsapp"; disconnectConfirm.open(); }
                        else root.service.accountAction("whatsapp", "login");
                    }
                }
                Image {
                    visible: !!root.service.statuses.whatsapp?.qrPath
                    source: visible ? Links.localFileUrl(root.service.statuses.whatsapp.qrPath) : ""
                    sourceSize: Qt.size(220, 220)
                    Layout.preferredWidth: 220; Layout.preferredHeight: visible ? 220 : 0
                    cache: false
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    visible: ["waiting", "failed", "expired"].includes(root.service.statuses.whatsapp?.authState)
                    text: root.service.statuses.whatsapp?.authState === "waiting" ? I18n.trFor("dankChat", "Waiting for scan…") : I18n.trFor("dankChat", "Linking failed or expired. Please try again.")
                }
                DankButton {
                    visible: !!root.service.statuses.whatsapp?.linking && !root.service.statuses.whatsapp?.authorized
                    text: I18n.trFor("dankChat", "Cancel")
                    enabled: !root.service.accountBusy.whatsapp
                    onClicked: root.service.accountAction("whatsapp", "cancel_login")
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: I18n.trFor("dankChat", "Account sessions stay on this device. Closing the window preserves your drafts until DankChat is reloaded.")
                    color: Theme.surfaceVariantText
                }
            }
        }

        RowLayout {
            visible: !root.service.accountsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingM
            ColumnLayout {
                visible: !root.narrow || !root.service.selectedChat
                Layout.preferredWidth: root.narrow ? root.width : root.compact ? 240 : 285
                Layout.fillWidth: root.narrow
                Layout.fillHeight: true
                spacing: Theme.spacingS
                RowLayout {
                    Repeater {
                        model: ["all", "telegram", "whatsapp"]
                        DankButton {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalPadding: Theme.spacingS
                            buttonHeight: 34
                            text: modelData === "all" ? I18n.trFor("dankChat", "All") : modelData === "telegram" ? "TG" : "WA"
                            backgroundColor: root.service.filter === modelData ? Theme.primary : Theme.surfaceContainerHigh
                            textColor: root.service.filter === modelData ? Theme.primaryText : Theme.surfaceText
                            onClicked: root.service.filter = modelData
                        }
                    }
                }
                DankTextField {
                    Layout.fillWidth: true
                    placeholderText: I18n.trFor("dankChat", "Search chats")
                    leftIconName: "search"
                    showClearButton: true
                    text: root.service.query
                    onTextChanged: if (text !== root.service.query) root.service.query = text
                }
                DankButton {
                    objectName: "unreadFilter"
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
                            : (root.service.statuses.telegram?.authorized || root.service.statuses.whatsapp?.authorized)
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
                        Label { text: root.service.selectedChat ? (root.service.selectedChat.provider === "telegram" ? "Telegram" : "WhatsApp") : I18n.trFor("dankChat", "Choose a chat"); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline; opacity: 0.25 }
                ListView {
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
                    property string highlightedMessage: ""
                    Timer { id: highlightTimer; interval: 1800; onTriggered: messageList.highlightedMessage = "" }
                    property bool followTail: true
                    property real savedScroll: 0
                    property string displayedChat: ""
                    function settleScroll() {
                        if (!followTail) return;
                        positionViewAtEnd();
                    }
                    function openAtLatest() {
                        followTail = true;
                        highlightedMessage = "";
                        Qt.callLater(settleScroll);
                    }
                    Component.onCompleted: { syncMessages(); displayedChat = root.service.selectedChat?.key || ""; openAtLatest(); }
                    onVisibleChanged: if (visible) openAtLatest()
                    onContentHeightChanged: if (followTail) Qt.callLater(settleScroll)
                    onHeightChanged: if (followTail) Qt.callLater(settleScroll)
                    onMovementStarted: followTail = false
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
                                        onReplyRequested: root.service.setReply(messageRow.modelData)
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
                                    Action { iconName: "reply"; width: 26; height: 26; iconSize: 16; onClicked: root.service.setReply(messageRow.modelData) }
                                }
                            }
                        }
                    }
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
                    visible: !!root.service.selectedChat
                    Layout.fillWidth: true
                    implicitHeight: Math.min(130, Math.max(52, composer.implicitHeight + 12))
                    radius: Theme.cornerRadius; color: Theme.surfaceContainer
                    border.color: composer.activeFocus ? Theme.primary : Theme.outline
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 6; spacing: 4
                        Action { iconName: "attach_file"; enabled: !root.service.demo && !root.service.writing; onClicked: { root.discardClipboardPaths(root.attachmentPaths); root.attachmentChatKey = root.service.selectedChat.key; root.attachmentPaths = []; root.savingMedia = false; fileDialog.open(); } }
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
                        Action { iconName: "send"; enabled: !root.service.demo && !root.service.writing && root.service.draft.trim().length > 0; onClicked: root.service.sendMessage("") }
                    }
                }
            }
        }
    }
    property bool pastingClipboard: false
    property var attachmentPaths: []
    function discardClipboardPaths(paths) {
        if (!service.demo && service.selectedChat)
            service.sendRequest(service.selectedChat.provider, "discard_clipboard", {paths: paths}, () => {});
    }
    function addAttachments(paths) {
        const combined = Array.from(new Set(attachmentPaths.concat(paths)));
        if (combined.length > 10) { discardClipboardPaths(paths.filter(path => !attachmentPaths.includes(path))); service.errorText = I18n.trFor("dankChat", "Choose up to 10 attachments."); return; }
        attachmentPaths = combined;
        attachmentConfirm.open();
    }
    function attachmentIsImage(path) { return /\.(png|jpe?g|webp|gif|bmp)$/i.test(path); }

    function pasteClipboard() {
        if (service.demo) { composer.paste(); return; }
        if (pastingClipboard || service.writing || !service.selectedChat) return;
        const chatKey = service.selectedChat.key;
        const provider = service.selectedChat.provider;
        pastingClipboard = true;
        if (!service.sendRequest(provider, "clipboard_image", {}, result => {
            pastingClipboard = false;
            if (service.selectedChat?.key !== chatKey) { if (result.paths) service.sendRequest(provider, "discard_clipboard", {paths: result.paths}, () => {}); return; }
            if (result.error) service.errorText = I18n.trFor("dankChat", result.error);
            if (result.textFallback) { composer.paste(); return; }
            if (!result.ok || !result.paths?.length) return;
            if (attachmentChatKey !== chatKey) { discardClipboardPaths(attachmentPaths); attachmentPaths = []; }
            attachmentChatKey = chatKey;
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
    property bool savingMedia: false
    property var exportMessage: null
    property var exportChat: null
    Controls.Popup {
        id: fileDialog
        anchors.centerIn: parent
        width: Math.min(root.width - 24, 860)
        height: root.height - 24
        modal: true
        focus: true
        popupType: Controls.Popup.Item
        padding: 0
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        contentItem: Loader {
            active: fileDialog.visible
            sourceComponent: FileBrowserContent {
                browserTitle: root.savingMedia ? I18n.trFor("dankChat", "Save media as…") : I18n.trFor("dankChat", "Choose an attachment to send")
                browserType: root.savingMedia ? "dankchat_export" : "dankchat_attachment"
                saveMode: root.savingMedia
                defaultFileName: root.savingMedia ? (root.exportMessage?.filename || root.exportMessage?.mediaPath?.split("/").pop() || "media") : ""
                fileExtensions: ["*"]
                showSidebar: width >= 620
                Component.onCompleted: { initialize(); forceActiveFocus(); }
                onFileSelected: path => {
                    const value = path.toString();
                    const selectedPath = value.startsWith("file://") ? decodeURIComponent(value.slice(7)) : value;
                    fileDialog.close();
                    if (root.savingMedia) root.service.saveMedia(root.exportChat, root.exportMessage, selectedPath);
                    else { root.addAttachments([selectedPath]); }
                }
                onCloseRequested: { fileDialog.close(); if (!root.savingMedia && root.attachmentPaths.length) attachmentConfirm.open(); }
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
    property string attachmentChatKey: ""
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
                            Action { iconName: "close"; onClicked: { root.discardClipboardPaths([modelData]); root.attachmentPaths = root.attachmentPaths.filter((_, i) => i !== index); } }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                DankButton { text: I18n.trFor("dankChat", "Add files"); onClicked: { attachmentConfirm.close(); root.savingMedia = false; fileDialog.open(); } }
                DankButton { text: I18n.trFor("dankChat", "Paste"); enabled: !root.pastingClipboard; onClicked: root.pasteClipboard() }
            }
        }
        onAccepted: {
            const paths = root.attachmentPaths.slice();
            root.service.sendAttachments(paths, root.attachmentChatKey, sent => { root.discardClipboardPaths(paths.slice(0, sent)); root.attachmentPaths = paths.slice(sent); });
        }
        onRejected: { root.discardClipboardPaths(root.attachmentPaths); root.attachmentPaths = []; }
    }
}
