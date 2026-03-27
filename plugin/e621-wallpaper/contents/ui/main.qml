import QtQuick
import QtMultimedia
import QtQuick.Effects
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    // Visual settings: read from config on load, then kept live via onValueChanged.
    property string mediaPath:      wallpaper.configuration.MediaPath      || ""
    property real   blurRadius:     wallpaper.configuration.BlurRadius     || 64
    property real   blurMultiplier: wallpaper.configuration.BlurMultiplier || 2.0
    property real   backgroundDim:  wallpaper.configuration.BackgroundDim  || 0.3
    property real   fgBlurRadius:   wallpaper.configuration.FgBlurRadius   || 0.0
    property real   rgbOffset:      wallpaper.configuration.RgbOffset      || 0.0

    property bool   isVideo:     false
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

    // Keep visual settings in sync when config changes (live slider preview).
    Connections {
        target: wallpaper.configuration
        function onValueChanged(key, value) {
            root.dbg(key + " = " + value)
            if      (key === "BlurRadius")     root.blurRadius     = value || 64
            else if (key === "BlurMultiplier") root.blurMultiplier = value || 2.0
            else if (key === "BackgroundDim")  root.backgroundDim  = value || 0.3
            else if (key === "FgBlurRadius")   root.fgBlurRadius   = value || 0.0
            else if (key === "RgbOffset")      root.rgbOffset      = value || 0.0
            else if (key === "MediaPath")      root.mediaPath      = value || ""
        }
    }


    onMediaPathChanged: {
        if (mediaPath === "") return
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

    // Animate fgFadeLayer so the opacity binding on fgContainer isn't clobbered
    SequentialAnimation {
        id: fadeOut
        NumberAnimation { target: fgFadeLayer; property: "opacity"; to: 0.0; duration: 600; easing.type: Easing.InQuad }
        ScriptAction { script: root.applyMedia() }
    }
    NumberAnimation {
        id: fadeIn
        target: fgFadeLayer; property: "opacity"; to: 1.0; duration: 600; easing.type: Easing.OutQuad
    }

    readonly property int screenIdx: {
        try { return wallpaper.containment.screen } catch(e) { return 0 }
    }

    // ── Scene root — layered for chromatic aberration when RgbOffset > 0 ─────

    Item {
        id: sceneRoot
        anchors.fill: parent
        layer.enabled: root.rgbOffset > 0.0
        layer.effect:  root.rgbOffset > 0.0 ? chromabEffect : null

        // ── Background ───────────────────────────────────────────────────────
        // opacity:0 hides direct compositing while layer stays renderable

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

        MultiEffect {
            source: bgSourceItem
            anchors.fill: parent
            blurEnabled: true
            blur: 1.0
            blurMax: root.blurRadius
            blurMultiplier: root.blurMultiplier
            brightness: -root.backgroundDim
        }

        // ── Foreground ───────────────────────────────────────────────────────
        // fgFadeLayer is the crossfade target; fgContainer handles the
        // direct/layered split depending on whether fg blur is active.

        Item {
            id: fgFadeLayer
            anchors.fill: parent

            Item {
                id: fgContainer
                anchors.fill: parent
                // When fg blur active: render to layer only (opacity:0 hides direct compositing)
                opacity: root.fgBlurRadius > 0 ? 0 : 1
                layer.enabled: root.fgBlurRadius > 0

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

            // Foreground blur — renders the fgContainer layer with blur applied
            MultiEffect {
                source: fgContainer
                anchors.fill: parent
                visible: root.fgBlurRadius > 0
                blurEnabled: true
                blur: 1.0
                blurMax: root.fgBlurRadius
            }

        } // end fgFadeLayer

        Rectangle {
            anchors.fill: parent
            color: "#111118"
            visible: root.mediaPath === ""
            z: -1
        }

        // ── Debug overlay ────────────────────────────────────────────────────

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

    } // end sceneRoot

    // ── Chromatic aberration applied via layer.effect ─────────────────────────
    // source is automatically bound to sceneRoot's layer texture.
    // rgbOffset is in pixels; divide by width to get normalised UV offset.

    Component {
        id: chromabEffect
        ShaderEffect {
            property real rgbOffset: root.rgbOffset / width
            vertexShader:   Qt.resolvedUrl("../shaders/chromab.vert.qsb")
            fragmentShader: Qt.resolvedUrl("../shaders/chromab.frag.qsb")
        }
    }
}
