import QtQuick
import QtMultimedia
import QtQuick.Effects
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    // Config values — set via System Settings or qdbus writeConfig
    property string mediaPath:          wallpaper.configuration.MediaPath       || ""
    property real   blurRadius:         wallpaper.configuration.BlurRadius      || 64
    property real   blurMultiplier:     wallpaper.configuration.BlurMultiplier  || 2.0
    property real   backgroundDim:      wallpaper.configuration.BackgroundDim   || 0.3

    property bool   isVideo:     false  // set explicitly in applyMedia
    property bool   mediaLoaded: false
    property bool   showDebug:   !mediaLoaded
    property string debugLog:    ""

    function dbg(msg) {
        debugLog = "[" + new Date().toLocaleTimeString() + "] " + msg + "\n" + debugLog
        console.log("[e621-wallpaper] " + msg)
    }

    Component.onCompleted: {
        dbg("Screen " + screenIdx)
        dbg("MediaPath: '" + root.mediaPath + "'")
    }

    Connections {
        target: wallpaper.configuration
        function onValueChanged(key, value) { root.dbg(key + " = " + value) }
    }

    onMediaPathChanged: {
        if (mediaPath === "") return
        // Crossfade: fade out, swap media, fade back in
        fadeOut.start()
    }

    function applyMedia() {
        var url = "file://" + mediaPath
        var vid = mediaPath.endsWith(".webm") || mediaPath.endsWith(".mp4")
        root.isVideo = vid
        dbg((vid ? "video" : "image") + ": " + mediaPath)
        if (vid) {
            bgImage.source = ""
            fgImage.source = ""
            bgPlayer.source = url
            fgPlayer.source = url
            bgPlayer.play()
            fgPlayer.play()
        } else {
            bgPlayer.stop(); bgPlayer.source = ""
            fgPlayer.stop(); fgPlayer.source = ""
            bgImage.source = url
            fgImage.source = url
        }
        fadeIn.start()
    }

    // Fade out → swap → fade in
    SequentialAnimation {
        id: fadeOut
        NumberAnimation { target: fgContainer; property: "opacity"; to: 0.0; duration: 600; easing.type: Easing.InQuad }
        ScriptAction { script: root.applyMedia() }
    }
    NumberAnimation {
        id: fadeIn
        target: fgContainer; property: "opacity"; to: 1.0; duration: 600; easing.type: Easing.OutQuad
    }

    readonly property int screenIdx: {
        try { return wallpaper.containment.screen } catch(e) { return 0 }
    }

    // ── Background source ─────────────────────────────────────────────────────
    // Item is opacity:0 not visible:false — MultiEffect needs it in the render tree

    Item {
        id: bgSourceItem
        anchors.fill: parent
        opacity: 0
        layer.enabled: true

        VideoOutput {
            id: bgVideo
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: root.isVideo
            MediaPlayer {
                id: bgPlayer
                loops: MediaPlayer.Infinite
                audioOutput: null
                // Prevent FFmpeg from decoding audio (stops Opus error spam)
                onActiveTracksChanged: { activeAudioTracks = [] }
                videoOutput: bgVideo
                onErrorOccurred: function(err, msg) { root.dbg("bgPlayer: " + msg) }
            }
        }

        Image {
            id: bgImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            visible: !root.isVideo
            cache: false
            asynchronous: true
        }
    }

    // Blur + darken background using MultiEffect (no .qsb needed)
    MultiEffect {
        source: bgSourceItem
        anchors.fill: parent
        blurEnabled: true
        blur: 1.0
        blurMax: root.blurRadius
        blurMultiplier: root.blurMultiplier
        brightness: -root.backgroundDim
    }

    // ── Foreground: fitted, centered (wrapped for crossfade opacity) ──────────

    Item {
        id: fgContainer
        anchors.fill: parent

        VideoOutput {
            id: fgVideo
            anchors.centerIn: parent
            visible: root.isVideo && root.mediaPath !== ""
            fillMode: VideoOutput.PreserveAspectFit
            width: {
                if (implicitWidth <= 0 || implicitHeight <= 0) return parent.width
                var s = Math.min(parent.width / implicitWidth, parent.height / implicitHeight)
                return implicitWidth * s
            }
            height: {
                if (implicitWidth <= 0 || implicitHeight <= 0) return parent.height
                var s = Math.min(parent.width / implicitWidth, parent.height / implicitHeight)
                return implicitHeight * s
            }
            MediaPlayer {
                id: fgPlayer
                loops: MediaPlayer.Infinite
                audioOutput: null
                onActiveTracksChanged: { activeAudioTracks = [] }
                videoOutput: fgVideo
                onPlaybackStateChanged: {
                    if (playbackState === MediaPlayer.PlayingState) {
                        root.mediaLoaded = true
                        root.dbg("Video playing")
                    }
                }
                onErrorOccurred: function(err, msg) { root.dbg("fgPlayer: " + msg) }
            }
        }

        Image {
            id: fgImage
            anchors.centerIn: parent
            visible: !root.isVideo && root.mediaPath !== ""
            fillMode: Image.PreserveAspectFit
            width: parent.width
            height: parent.height
            cache: false
            asynchronous: true
            onStatusChanged: {
                if (status === Image.Ready) {
                    root.mediaLoaded = true
                    root.dbg("Image ready")
                } else if (status === Image.Error) {
                    root.dbg("Image error: " + source)
                }
            }
        }
    } // end fgContainer

    Rectangle {
        anchors.fill: parent
        color: "#111118"
        visible: root.mediaPath === ""
        z: -1
    }

    // ── Debug overlay ─────────────────────────────────────────────────────────

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 24
        width: 600
        height: col.implicitHeight + 24
        color: "#dd000000"
        radius: 8
        opacity: root.showDebug ? 1.0 : 0.0
        visible: opacity > 0
        z: 100
        Behavior on opacity { NumberAnimation { duration: 1000 } }
        Column {
            id: col
            anchors { fill: parent; margins: 12 }
            spacing: 6
            Text { text: "e621 Wallpaper"; color: "#fff"; font.bold: true; font.pixelSize: 15 }
            Text { text: "Screen: " + root.screenIdx; color: "#aaa"; font.pixelSize: 12 }
            Text {
                text: "MediaPath: " + (root.mediaPath || "(none — run the Rust binary)")
                color: root.mediaPath ? "#88ff88" : "#ffcc44"
                font.pixelSize: 11
            wrapMode: Text.Wrap
            width: parent.width
            }
            Rectangle { width: parent.width; height: 1; color: "#333" }
            Text {
                text: root.debugLog; color: "#ccc"; font.pixelSize: 11
                font.family: "monospace"; wrapMode: Text.Wrap; width: parent.width
            }
        }
    }
}
