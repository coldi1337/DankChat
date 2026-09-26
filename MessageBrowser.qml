import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import qs.Common
import qs.Widgets

ColumnLayout {
    id: root
    required property var service
    spacing: Theme.spacingS
    onVisibleChanged: if (!visible) searchTimer.stop()
    RowLayout {
        Layout.fillWidth: true
        DankTextField {
            id: search
            objectName: "messageSearch"
            Layout.fillWidth: true
            placeholderText: I18n.trFor("dankChat", "Search messages")
            showClearButton: true
            text: root.service.messageQuery || ""
            onTextEdited: searchTimer.restart()
            Timer { id: searchTimer; interval: 300; onTriggered: root.service.browse(root.service.browseMode || "search", search.text, false) }
        }
        DankActionButton { iconName: "close"; tooltipText: I18n.trFor("dankChat", "Close"); onClicked: root.service.closeBrowse() }
    }
    Flow {
        Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: Theme.spacingXS
        Repeater {
            model: [{key:"search", label:"All"}, {key:"images", label:"Images"}, {key:"videos", label:"Videos"}, {key:"files", label:"Files"}, {key:"links", label:"Links"}, {key:"audio", label:"Audio"}]
            delegate: DankButton {
                required property var modelData
                text: I18n.trFor("dankChat", modelData.label)
                backgroundColor: root.service.browseMode === modelData.key ? Theme.primary : Theme.surfaceContainerHigh
                textColor: root.service.browseMode === modelData.key ? Theme.primaryText : Theme.surfaceText
                onClicked: root.service.browse(modelData.key, search.text, false)
            }
        }
    }
    StyledText {
        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.surfaceVariantText
        text: I18n.trFor("dankChat", root.service.browsing ? "Searching…" : root.service.browseResults.length ? "Select a result to open it in the conversation." : "No messages found.")
    }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Theme.spacingXS
        model: root.service.browseResults
        delegate: Controls.ItemDelegate {
            required property var modelData
            width: ListView.view.width
            height: Math.max(60, contentItem.implicitHeight + 16)
            background: Rectangle { color: parent.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer; radius: Theme.cornerRadius }
            contentItem: StyledText {
                textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; color: Theme.surfaceText
                text: (parent.modelData.timestamp ? Qt.formatDateTime(new Date(parent.modelData.timestamp * 1000), "dd.MM.yyyy HH:mm") + " · " : "") + (parent.modelData.text || parent.modelData.filename || I18n.trFor("dankChat", "Media"))
            }
            onClicked: { const id = modelData.id; root.service.closeBrowse(); root.service.jumpToReply(id); }
        }
    }
    DankButton { Layout.fillWidth: true; visible: !!root.service.browseNext; enabled: !root.service.browsing; text: I18n.trFor("dankChat", "Load more"); onClicked: root.service.browse(root.service.browseMode, search.text, true) }
}
