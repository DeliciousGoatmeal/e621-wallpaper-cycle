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
    property bool   showDebug:   !mediaLoaded || (showPostInfo && mediaLoaded && _postInfoTimer.running)
    property string debugLog:    ""

    // Post metadata — written into KConfig by the Rust daemon via qdbus on each rotation.
    // The daemon writes PostArtist/PostId/PostUrl for each screen's config group so
    // onValueChanged picks them up with no file-reading required.
    property bool   showPostInfo: wallpaper.configuration.ShowPostInfo !== false
    property string metaArtist:  wallpaper.configuration.PostArtist || ""
    property int    metaPostId:  wallpaper.configuration.PostId     || 0
    property string metaPostUrl: wallpaper.configuration.PostUrl    || ""
    property string metaDesc:    ""

    function fetchDesc() {
        if (metaPostId <= 0) return
        var req = new XMLHttpRequest()
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                try {
                    var p = JSON.parse(req.responseText).post
                    if (p && p.description)
                        root.metaDesc = p.description.trim().replace(/\r?\n+/g, " ").substring(0, 300)
                } catch(e) {}
            }
        }
        req.open("GET", "https://e621.net/posts/" + metaPostId + ".json")
        req.setRequestHeader("User-Agent", "e621-plasma-wallpaper/0.3 (by zombiedoggie on e621)")
        req.send()
    }

    // Audio: AudioScreen holds the connector name of the screen that plays audio ("" = none).
    // Rust propagates changes to all screens so every instance re-evaluates.
    property string audioScreen: wallpaper.configuration.AudioScreen || ""

    // Screen name written by the Rust daemon via writeConfig("ScreenName", ...).
    // Daemon sorts screens by x-position and writes the connector name to each
    // containment directly — no index guessing needed.
    property string screenName: wallpaper.configuration.ScreenName || ""

    property bool isAudioEnabled: audioScreen !== "" && audioScreen === screenName

    AudioOutput {
        id: fgAudioOut
        volume: root.isAudioEnabled ? 1.0 : 0.0
    }

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
            else if (key === "ShowPostInfo") root.showPostInfo = (value !== false && value !== "false")
            else if (key === "PostArtist")  root.metaArtist  = value || ""
            else if (key === "PostId")      {
                root.metaPostId = parseInt(value, 10) || 0
                root.metaDesc   = ""
                if (root.metaPostId > 0) Qt.callLater(root.fetchDesc)
            }
            else if (key === "PostUrl")     root.metaPostUrl = value || ""
            else if (key === "AudioScreen") root.audioScreen = value || ""
            else if (key === "ScreenName")  root.screenName  = value || ""
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

    // Keep overlay visible for postInfoDuration seconds after each new wallpaper
    property int postInfoDuration: 6
    Timer {
        id: _postInfoTimer
        interval: root.postInfoDuration * 1000
        running: false
        repeat: false
        onTriggered: { /* showDebug binding re-evaluates automatically */ }
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
                        audioOutput: fgAudioOut
                        videoOutput: fgVideo
                        onPlaybackStateChanged: {
                            if (playbackState === MediaPlayer.PlayingState) {
                                root.mediaLoaded = true
                                root.dbg("Video playing")
                                if (root.showPostInfo) _postInfoTimer.restart()
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
                            if (root.showPostInfo) _postInfoTimer.restart()
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

    } // end sceneRoot

    // ── Info overlay — outside sceneRoot so the chromatic aberration shader ────
    // ── does not apply to it.                                                ────

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

            // ── Now playing: shown only once media is loaded ───────────────
            Column {
                visible: root.mediaLoaded
                spacing: 4
                width: parent.width

                Text {
                    text: root.screenName + (root.isAudioEnabled ? "  🔊" : "")
                    color: "#666688"; font.pixelSize: 10; font.family: "monospace"
                    width: parent.width
                }

                Text {
                    text: root.metaArtist !== "" ? root.metaArtist : "unknown artist"
                    color: "#aaddff"
                    font.pixelSize: 15
                    font.bold: true
                    wrapMode: Text.Wrap
                    width: parent.width
                }
                Text {
                    visible: root.metaPostUrl !== ""
                    text: root.metaPostUrl
                    color: "#6688bb"
                    font.pixelSize: 11
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    width: parent.width
                }
                Text {
                    visible: root.metaDesc !== ""
                    text: root.metaDesc
                    color: "#aaaaaa"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 3
                    width: parent.width
                }
            }

            // ── Pre-load state: title + debug log ─────────────────────────
            Text {
                visible: !root.mediaLoaded
                text: "e621 Wallpaper  ·  " + root.screenName + " (idx " + root.screenIdx + ")"
                color: "#ffffff"; font.bold: true; font.pixelSize: 14
            }
            Text {
                visible: !root.mediaLoaded && root.mediaPath === ""
                text: "waiting for Rust daemon..."
                color: "#ffcc44"; font.pixelSize: 11
            }
            Rectangle {
                visible: !root.mediaLoaded
                width: parent.width; height: 1; color: "#444"
            }
            Text {
                visible: !root.mediaLoaded
                text: root.debugLog
                color: "#888"; font.pixelSize: 10
                font.family: "monospace"; wrapMode: Text.Wrap; width: parent.width
            }
        }
    }

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
