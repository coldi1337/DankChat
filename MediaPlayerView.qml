import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import QtMultimedia
import qs.Common
import qs.Widgets

Item {
    id: root
    required property url sourceUrl
    required property var service
    property bool audioOnly: false
    implicitHeight: audioOnly ? 48 : 228
    Component.onDestruction: { player.stop(); if (service.activePlayer === player) service.activePlayer = null; }
    Connections {
        target: root.service
        function onSurfaceOpenChanged() { if (!root.service.surfaceOpen) { player.pause(); expanded.close(); } }
    }
    MediaPlayer {
        id: player
        source: root.sourceUrl
        videoOutput: video
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: {
            if (playbackState !== MediaPlayer.PlayingState) return;
            if (root.service.activePlayer && root.service.activePlayer !== player) root.service.activePlayer.pause();
            root.service.activePlayer = player;
        }
    }
    Controls.Popup {
        id: expanded
        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: parent ? parent.width - 24 : root.width
        height: parent ? parent.height - 24 : root.height
        modal: false
        focus: true
        popupType: Controls.Popup.Item
        background: Rectangle { color: Theme.surface; radius: Theme.cornerRadius; border.color: Theme.outline }
    }
    ColumnLayout {
        id: playerContent
        parent: expanded.visible ? expanded.contentItem : root
        anchors.fill: parent
        spacing: Theme.spacingXS
        VideoOutput {
            id: video
            visible: !root.audioOnly
            Layout.fillWidth: true
            Layout.fillHeight: true
            fillMode: VideoOutput.PreserveAspectFit
        }
        RowLayout {
            Layout.fillWidth: true
            DankActionButton {
                iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            }
            DankActionButton {
                visible: !root.audioOnly
                iconName: expanded.visible ? "close_fullscreen" : "open_in_full"
                onClicked: expanded.visible ? expanded.close() : expanded.open()
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                textFormat: Text.PlainText
                text: player.error !== MediaPlayer.NoError ? I18n.trFor("dankChat", "Playback unavailable")
                    : Math.floor(player.position / 60000) + ":" + String(Math.floor(player.position / 1000) % 60).padStart(2, "0")
                      + " / " + Math.floor(player.duration / 60000) + ":" + String(Math.floor(player.duration / 1000) % 60).padStart(2, "0")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
