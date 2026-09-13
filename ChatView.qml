import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.Common
import qs.Widgets

Item {
    id: root
    anchors.fill: parent
    required property var service
    property bool compact: false
    readonly property bool narrow: width < 620
    signal expandRequested()
    signal closeRequested()
    focus: true
    Keys.onEscapePressed: {
        if (service.accountsOpen) service.accountsOpen = false;
        else if (narrow && service.selectedChat) service.selectedChat = null;
        else closeRequested();
    }
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
        signal replyRequested()
        width: 210
        padding: Theme.spacingXS
        popupType: Controls.Popup.Item
        background: Rectangle { radius: Theme.cornerRadius; color: Theme.surfaceContainer; border.color: Theme.outline; border.width: 1 }
        MenuEntry { visible: textMenu.allowReply; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Reply"); onTriggered: textMenu.replyRequested() }
        MenuEntry { text: I18n.trFor("dankChat", "Copy"); enabled: textMenu.editor.selectedText.length > 0; onTriggered: textMenu.editor.copy() }
        MenuEntry { visible: !textMenu.editor.readOnly; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Cut"); enabled: textMenu.editor.selectedText.length > 0; onTriggered: textMenu.editor.cut() }
        MenuEntry { visible: !textMenu.editor.readOnly; height: visible ? implicitHeight : 0; text: I18n.trFor("dankChat", "Paste"); enabled: textMenu.editor.canPaste; onTriggered: textMenu.editor.paste() }
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
                    text: I18n.trFor("dankChat", "Link Telegram")
                    enabled: !root.service.demo && root.service.telegramEnabled
                    onClicked: root.service.loginTelegram()
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
                        : I18n.trFor("dankChat", "Link WhatsApp in a terminal, then scan its QR code under Linked devices on your phone.")
                }
                DankButton {
                    text: I18n.trFor("dankChat", "Link WhatsApp")
                    enabled: !root.service.demo && root.service.whatsappEnabled
                    onClicked: Quickshell.execDetached(["sh", Qt.resolvedUrl("scripts/open-link-terminal").toString().replace("file://", "")])
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
                    text: root.service.query
                    onTextChanged: if (text !== root.service.query) root.service.query = text
                }
                ListView {
                    id: chatList
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
                        MouseArea { id: chatMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.service.selectChat(chatRow.modelData) }
                    }
                    Label {
                        anchors.centerIn: parent
                        width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        visible: chatList.count === 0
                        text: I18n.trFor("dankChat", "No chats yet. Link an account to get started.")
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
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: Theme.spacingS
                    model: root.service.messages
                    onCountChanged: Qt.callLater(() => positionViewAtEnd())
                    delegate: Item {
                        id: messageRow
                        required property var modelData
                        width: messageList.width
                        height: bubble.height + 4
                        Rectangle {
                            id: bubble
                            width: Math.min(parent.width - 12, Math.max(130, parent.width * 0.86))
                            height: bubbleContent.implicitHeight + 2 * Theme.spacingS
                            anchors.right: messageRow.modelData.out ? parent.right : undefined
                            anchors.left: messageRow.modelData.out ? undefined : parent.left
                            radius: Theme.cornerRadius
                            color: messageRow.modelData.out ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                            ColumnLayout {
                                id: bubbleContent
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: Theme.spacingS; spacing: Theme.spacingXS
                                Label { visible: !messageRow.modelData.out && !!messageRow.modelData.sender; text: messageRow.modelData.sender; color: Theme.primary; font.pixelSize: Theme.fontSizeSmall }
                                Label { Layout.fillWidth: true; visible: !!messageRow.modelData.replyText; text: "↳ " + messageRow.modelData.replyText; maximumLineCount: 2; elide: Text.ElideRight; wrapMode: Text.Wrap; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                                Image {
                                    readonly property bool isImage: ["photo", "image", "sticker"].includes(messageRow.modelData.mediaType)
                                    visible: isImage && !!messageRow.modelData.mediaPath
                                    Layout.fillWidth: true; Layout.preferredHeight: visible ? 160 : 0
                                    source: visible ? "file://" + messageRow.modelData.mediaPath : ""
                                    fillMode: Image.PreserveAspectFit; asynchronous: true
                                }
                                Label { Layout.fillWidth: true; visible: !!messageRow.modelData.mediaType && !messageRow.modelData.mediaPath; text: "[" + messageRow.modelData.mediaType + "]"; color: Theme.surfaceVariantText }
                                Controls.TextArea {
                                    id: messageText
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: messageRow.modelData.text
                                    textFormat: TextEdit.PlainText
                                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                                    padding: 0; color: Theme.surfaceText; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMedium
                                    background: null
                                    selectionColor: Theme.primary
                                    selectedTextColor: Theme.primaryText
                                    Controls.ContextMenu.menu: TextMenu {
                                        editor: messageText
                                        allowReply: true
                                        onReplyRequested: root.service.setReply(messageRow.modelData)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    DankButton {
                                        visible: !!messageRow.modelData.mediaPath
                                        text: I18n.trFor("dankChat", "Open media"); buttonHeight: 26; horizontalPadding: 8
                                        onClicked: Qt.openUrlExternally("file://" + messageRow.modelData.mediaPath)
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label { text: messageRow.modelData.time || (messageRow.modelData.timestamp ? Qt.formatDateTime(new Date(messageRow.modelData.timestamp * 1000), "hh:mm") : ""); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                                    Action { iconName: "reply"; width: 26; height: 26; iconSize: 16; onClicked: root.service.setReply(messageRow.modelData) }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    visible: !!root.service.reply
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "↳ " + (root.service.reply?.text || ""); elide: Text.ElideRight; color: Theme.primary }
                    Action { iconName: "close"; onClicked: root.service.setReply(null) }
                }
                Rectangle {
                    visible: !!root.service.selectedChat
                    Layout.fillWidth: true
                    implicitHeight: Math.min(130, Math.max(52, composer.implicitHeight + 12))
                    radius: Theme.cornerRadius; color: Theme.surfaceContainer
                    border.color: composer.activeFocus ? Theme.primary : Theme.outline
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 6; spacing: 4
                        Action { iconName: "attach_file"; enabled: !root.service.demo && !root.service.writing; onClicked: { root.attachmentChatKey = root.service.selectedChat.key; fileDialog.open(); } }
                        Controls.ScrollView {
                            id: composerScroll
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            Controls.TextArea {
                                id: composer
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
                                Controls.ContextMenu.menu: TextMenu { editor: composer }
                                onTextChanged: if (text !== root.service.draft) root.service.setDraft(text)
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
    FileDialog {
        id: fileDialog
        title: I18n.trFor("dankChat", "Choose an attachment to send")
        fileMode: FileDialog.OpenFile
        onAccepted: {
            attachmentPath = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            attachmentConfirm.open();
        }
    }
    property string attachmentPath: ""
    property string attachmentChatKey: ""
    Controls.Dialog {
        id: attachmentConfirm
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 400)
        modal: true
        title: I18n.trFor("dankChat", "Send attachment")
        background: Rectangle { color: Theme.surfaceContainer; radius: Theme.cornerRadius; border.color: Theme.outline }
        header: Label { text: attachmentConfirm.title; padding: Theme.spacingM; font.weight: Font.Medium }
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            DankButton { text: I18n.trFor("dankChat", "Cancel"); onClicked: attachmentConfirm.reject() }
            DankButton { text: I18n.trFor("dankChat", "Send"); onClicked: attachmentConfirm.accept() }
        }
        contentItem: Label { text: root.attachmentPath.split("/").pop(); wrapMode: Text.Wrap }
        onAccepted: { root.service.sendMessage(root.attachmentPath, root.attachmentChatKey); root.attachmentPath = ""; }
        onRejected: root.attachmentPath = ""
    }
}
