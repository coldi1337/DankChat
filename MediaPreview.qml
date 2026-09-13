import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "linkify.js" as Links

ColumnLayout {
    id: root
    required property var message
    required property var service
    property color foregroundColor: Theme.surfaceVariantText
    signal imageRequested(string path)
    readonly property string path: message.mediaPath || ""
    readonly property string mediaType: message.mediaType || ""
    readonly property bool movie: mediaType === "video" || String(message.mimeType || "").toLowerCase().startsWith("video/") || /\.(mp4|f4v|m4v|mov|3gp|webm|mkv)$/i.test(path)
    readonly property bool sound: ["audio", "voice", "ptt"].includes(mediaType) || /\.(ogg|opus|mp3|m4a|wav)$/i.test(path)
    readonly property bool picture: !movie && !sound && (["image", "photo", "sticker", "gif"].includes(mediaType) || /\.(png|jpe?g|webp|gif)$/i.test(path))
    readonly property bool downloading: !!service.downloads[service.selectedChat?.key + ":" + message.id]
    spacing: Theme.spacingXS
    AnimatedImage {
        id: imagePreview
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? (root.mediaType === "sticker" ? 150 : 190) : 0
        visible: root.picture && root.path.length > 0
        source: visible ? Links.localFileUrl(root.path) : ""
        fillMode: Image.PreserveAspectFit
        playing: visible
        asynchronous: true
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.imageRequested(root.path) }
    }
    Loader {
        id: playerLoader
        Layout.fillWidth: true
        Layout.preferredHeight: root.sound ? 48 : 228
        active: root.path.length > 0 && (root.movie || root.sound)
        visible: active
        property url loadedMediaUrl: ""
        function loadPlayer() {
            if (!active) { source = ""; loadedMediaUrl = ""; return; }
            const mediaUrl = Links.localFileUrl(root.path);
            if (source.toString().length && loadedMediaUrl.toString() === mediaUrl) return;
            loadedMediaUrl = mediaUrl;
            setSource(Qt.resolvedUrl("MediaPlayerView.qml") + "?revision=" + root.service.viewRevision, {sourceUrl: mediaUrl, service: root.service, audioOnly: root.sound});
        }
        onActiveChanged: loadPlayer()
        Component.onCompleted: loadPlayer()
        Connections { target: root; function onPathChanged() { playerLoader.loadPlayer(); } }
    }
    StyledText {
        Layout.fillWidth: true
        visible: (imagePreview.visible && imagePreview.status === Image.Error) || (playerLoader.visible && playerLoader.status === Loader.Error)
        text: I18n.trFor("dankChat", "Preview unavailable. Open this file externally.")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.foregroundColor
        font.pixelSize: Theme.fontSizeSmall
    }
    DankButton {
        visible: !root.path && root.mediaType !== "webpage"
        text: root.downloading ? I18n.trFor("dankChat", "Loading media…") : I18n.trFor("dankChat", "Load media")
        iconName: root.downloading ? "hourglass_empty" : "download"
        enabled: !root.downloading && !root.service.demo
        onClicked: root.service.downloadMedia(root.message)
    }
    StyledText {
        Layout.fillWidth: true
        visible: !!root.message.filename
        text: root.message.filename || ""
        textFormat: Text.PlainText
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        color: root.foregroundColor
        font.pixelSize: Theme.fontSizeSmall
    }
}
