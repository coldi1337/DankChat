import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import QtMultimedia
import qs.Common
import qs.Widgets

Item {
    id: root
    objectName: "inlineMediaPlayer"
    required property url sourceUrl
    required property var service
    property bool audioOnly: false
    implicitHeight: audioOnly ? 88 : 228
    function togglePlayback() { player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play(); }
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
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
                tooltipText: I18n.trFor("dankChat", root.playing ? "Pause" : "Play")
                onClicked: root.togglePlayback()
            }
            DankActionButton {
                visible: !root.audioOnly
                iconName: expanded.visible ? "close_fullscreen" : "open_in_full"
                onClicked: expanded.visible ? expanded.close() : expanded.open()
            }
            Controls.Button {
                id: speedButton
                objectName: "audioPlaybackSpeed"
                visible: root.audioOnly
                text: player.playbackRate === 1 ? "1×" : player.playbackRate === 1.5 ? I18n.trFor("dankChat", "1.5×") : "2×"
                Accessible.name: I18n.trFor("dankChat", "Playback speed") + " " + text
                implicitWidth: 52; implicitHeight: 32
                background: Rectangle { radius: Theme.cornerRadius; color: Theme.surfaceContainerHigh; border.color: Theme.outline }
                contentItem: StyledText { text: speedButton.text; color: Theme.surfaceText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: player.playbackRate = player.playbackRate === 1 ? 1.5 : player.playbackRate === 1.5 ? 2 : 1
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
        Controls.Slider {
            id: progress
            objectName: "audioPlaybackPosition"
            visible: root.audioOnly
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            from: 0; to: Math.max(1, player.duration)
            value: player.position
            enabled: player.seekable && player.duration > 0
            Accessible.name: I18n.trFor("dankChat", "Playback position")
            onMoved: player.setPosition(Math.round(value))
            background: Rectangle {
                x: progress.leftPadding; y: progress.topPadding + progress.availableHeight / 2 - height / 2
                width: progress.availableWidth; height: 4; radius: 2; color: Theme.outline
                Rectangle { width: progress.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.primary }
            }
            handle: Rectangle {
                x: progress.leftPadding + progress.visualPosition * (progress.availableWidth - width)
                y: progress.topPadding + progress.availableHeight / 2 - height / 2
                width: 14; height: 14; radius: 7; color: Theme.primary
            }
        }
    }
}
