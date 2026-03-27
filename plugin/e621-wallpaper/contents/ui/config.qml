import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: 16

    // Plasma 6 injects these two properties into the config page root item.
    // Declaring them here allows the injection to succeed and gives us access
    // to writeConfig() for immediate (no-Apply) live writes.
    property var configDialog
    property var wallpaperConfiguration

    // Plasma auto-binds cfg_* properties to KConfig XT entries in main.xml.
    // For live preview (no Apply needed), visual sliders write directly via
    // wallpaperConfiguration.writeConfig() in their onMoved handlers.
    property string cfg_Tags
    property int    cfg_ImageDuration
    property int    cfg_DownloadBatch
    property int    cfg_FetchLimit
    property bool   cfg_VideoOnly
    property real   cfg_BlurRadius
    property real   cfg_BlurMultiplier
    property real   cfg_BackgroundDim
    property int    cfg_FgBlurRadius
    property int    cfg_RgbOffset
    property bool   cfg_ShowPostInfo
    property string cfg_AudioScreen       // "" = none, screen connector name = that screen plays
    property string cfg_ForceNextAt
    // Read-only: written by daemon, displayed here only (not user-editable)
    property string cfg_PostArtist
    property int    cfg_PostId
    property string cfg_PostUrl

    // Fetched from e621 API — separate from cfg_ so Apply never writes them back
    property string _nowDesc:    ""
    property bool   _nowFetching: false

    function fetchNowPlaying() {
        if (cfg_PostId <= 0 || _nowFetching) return
        _nowFetching = true
        _nowDesc = ""
        var req = new XMLHttpRequest()
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            _nowFetching = false
            if (req.status === 200) {
                try {
                    var p = JSON.parse(req.responseText).post
                    if (p && p.description)
                        _nowDesc = p.description.trim().replace(/\r?\n/g, " ").substring(0, 300)
                } catch(e) {}
            }
        }
        req.open("GET", "https://e621.net/posts/" + cfg_PostId + ".json")
        req.setRequestHeader("User-Agent", "e621-plasma-wallpaper/0.3 (by zombiedoggie on e621)")
        req.send()
    }

    Component.onCompleted: Qt.callLater(fetchNowPlaying)
    onCfg_PostIdChanged: Qt.callLater(fetchNowPlaying)

    // Pick up live updates written by the Rust daemon via qdbus while the
    // dialog is open — cfg_* properties are set once on load and don't
    // auto-update from external KConfig writes.
    Connections {
        target: wallpaperConfiguration
        function onValueChanged(key, value) {
            if      (key === "PostId")     { cfg_PostId     = parseInt(value, 10) || 0 }
            else if (key === "PostArtist") { cfg_PostArtist = value || "" }
            else if (key === "PostUrl")    { cfg_PostUrl    = value || "" }
        }
    }

    // Write a config key immediately.
    // wallpaperConfiguration[key] = value goes through QQmlPropertyMap which
    // emits the valueChanged signal that main.qml listens to — this is what
    // drives live preview. writeConfig() only writes to the KConfig group
    // without emitting valueChanged, so we don't use it here.
    function writeNow(key, value) {
        if (wallpaperConfiguration)
            wallpaperConfiguration[key] = value
    }

    // ── Now Playing ───────────────────────────────────────────────────────────

    Rectangle {
        Layout.fillWidth: true
        visible: cfg_PostId > 0
        color: "#1a1a2e"
        radius: 8
        implicitHeight: nowCol.implicitHeight + 24

        Column {
            id: nowCol
            anchors { fill: parent; margins: 12 }
            spacing: 5

            QQC2.Label {
                width: parent.width
                text: {
                    try {
                        var idx = configDialog.wallpaper.containment.screen
                        if (idx >= 0 && idx < Qt.application.screens.length)
                            return Qt.application.screens[idx].name
                    } catch(e) {}
                    return ""
                }
                color: "#666688"
                font.pixelSize: 10
                font.family: "monospace"
                visible: text !== ""
            }
            QQC2.Label {
                width: parent.width
                text: cfg_PostArtist !== "" ? cfg_PostArtist : "unknown artist"
                font.bold: true
                font.pixelSize: 15
                color: "#e0e0ff"
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
            QQC2.Label {
                width: parent.width
                text: cfg_PostUrl
                color: "#6699cc"
                font.pixelSize: 11
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
            QQC2.Label {
                width: parent.width
                visible: _nowDesc !== ""
                text: _nowDesc
                color: "#999999"
                font.pixelSize: 10
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 3
            }
            QQC2.Label {
                visible: _nowFetching
                text: "fetching..."
                color: "#666688"
                font.pixelSize: 10
            }
        }
    }

    // Shown while no post is loaded yet
    QQC2.Label {
        visible: cfg_PostId <= 0
        text: "No wallpaper loaded yet"
        color: "#888"
        font.pixelSize: 11
    }

    QQC2.MenuSeparator { Layout.fillWidth: true }

    // ── Search ────────────────────────────────────────────────────────────────

    GridLayout {
        columns: 2
        columnSpacing: 12
        rowSpacing: 8
        Layout.fillWidth: true

        QQC2.Label { text: "Tags:" }
        QQC2.TextField {
            Layout.fillWidth: true
            text: cfg_Tags
            placeholderText: "e.g. rating:e gay male -female"
            onTextEdited: cfg_Tags = text
        }

        QQC2.Label { text: "Image duration (s):" }
        QQC2.SpinBox {
            from: 5; to: 3600; stepSize: 5
            value: cfg_ImageDuration
            onValueModified: cfg_ImageDuration = value
        }

        QQC2.Label { text: "Download batch:" }
        QQC2.SpinBox {
            from: 1; to: 50
            value: cfg_DownloadBatch
            onValueModified: cfg_DownloadBatch = value
        }

        QQC2.Label { text: "Fetch limit:" }
        QQC2.SpinBox {
            from: 1; to: 320
            value: cfg_FetchLimit
            onValueModified: cfg_FetchLimit = value
        }

        QQC2.Label { text: "Videos only:" }
        QQC2.CheckBox {
            checked: cfg_VideoOnly
            onToggled: cfg_VideoOnly = checked
        }
    }

    QQC2.MenuSeparator { Layout.fillWidth: true }

    // ── Visuals (live preview — no Apply needed) ──────────────────────────────

    QQC2.Label { text: "Visuals"; font.bold: true }

    GridLayout {
        columns: 2
        columnSpacing: 12
        rowSpacing: 8
        Layout.fillWidth: true

        QQC2.Label { text: "Blur radius:" }
        RowLayout {
            QQC2.Slider {
                id: blurRadiusSlider
                from: 0; to: 128; stepSize: 1
                value: cfg_BlurRadius
                onMoved: { cfg_BlurRadius = value; writeNow("BlurRadius", value) }
                Layout.preferredWidth: 180
            }
            QQC2.Label { text: Math.round(blurRadiusSlider.value) }
        }

        QQC2.Label { text: "Blur multiplier:" }
        RowLayout {
            QQC2.Slider {
                id: blurMultSlider
                from: 0.5; to: 4.0; stepSize: 0.1
                value: cfg_BlurMultiplier
                onMoved: { cfg_BlurMultiplier = value; writeNow("BlurMultiplier", value) }
                Layout.preferredWidth: 180
            }
            QQC2.Label { text: blurMultSlider.value.toFixed(1) }
        }

        QQC2.Label { text: "Background dim:" }
        RowLayout {
            QQC2.Slider {
                id: bgDimSlider
                from: 0.0; to: 1.0; stepSize: 0.05
                value: cfg_BackgroundDim
                onMoved: { cfg_BackgroundDim = value; writeNow("BackgroundDim", value) }
                Layout.preferredWidth: 180
            }
            QQC2.Label { text: bgDimSlider.value.toFixed(2) }
        }

        QQC2.Label { text: "Video blur:" }
        RowLayout {
            QQC2.Slider {
                id: fgBlurSlider
                from: 0; to: 128; stepSize: 1
                value: cfg_FgBlurRadius
                onMoved: { cfg_FgBlurRadius = value; writeNow("FgBlurRadius", value) }
                Layout.preferredWidth: 180
            }
            QQC2.Label { text: fgBlurSlider.value > 0 ? Math.round(fgBlurSlider.value) : "off" }
        }

        QQC2.Label { text: "RGB offset (px):" }
        RowLayout {
            QQC2.Slider {
                id: rgbSlider
                from: 0; to: 50; stepSize: 1
                value: cfg_RgbOffset
                onMoved: { cfg_RgbOffset = value; writeNow("RgbOffset", value) }
                Layout.preferredWidth: 180
            }
            QQC2.Label { text: rgbSlider.value > 0 ? rgbSlider.value + "px" : "off" }
        }
    }

    QQC2.MenuSeparator { Layout.fillWidth: true }

    // ── Audio ──────────────────────────────────────────────────────────────────

    QQC2.Label { text: "Audio"; font.bold: true }

    RowLayout {
        spacing: 12
        QQC2.Label { text: "Play audio from:" }
        QQC2.ComboBox {
            // Build model: "None" + connector name for each detected screen.
            // Store the screen name (not an index) so matching is unambiguous.
            id: audioCombo
            model: {
                var items = ["None"]
                for (var i = 0; i < Qt.application.screens.length; i++)
                    items.push(Qt.application.screens[i].name)
                return items
            }
            currentIndex: {
                if (cfg_AudioScreen === "") return 0
                for (var i = 0; i < Qt.application.screens.length; i++) {
                    if (Qt.application.screens[i].name === cfg_AudioScreen)
                        return i + 1
                }
                return 0
            }
            onActivated: {
                var name = currentIndex === 0 ? "" : Qt.application.screens[currentIndex - 1].name
                cfg_AudioScreen = name
                // writeNow triggers onValueChanged in main.qml on this containment immediately.
                // writeConfig writes to KConfig on disk so the Rust daemon picks it up and
                // propagates the change to the OTHER monitor's containment as well.
                writeNow("AudioScreen", name)
                if (wallpaperConfiguration)
                    wallpaperConfiguration.writeConfig("AudioScreen", name)
            }
        }
    }

    QQC2.Label {
        text: "Plays audio from that monitor's wallpaper video. Only one at a time."
        color: "#888"
        font.pixelSize: 10
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    QQC2.MenuSeparator { Layout.fillWidth: true }

    // ── Post info overlay ──────────────────────────────────────────────────────

    QQC2.Label { text: "Post Info Overlay"; font.bold: true }

    RowLayout {
        spacing: 8
        QQC2.CheckBox {
            id: showPostInfoCheck
            checked: cfg_ShowPostInfo
            onToggled: { cfg_ShowPostInfo = checked; writeNow("ShowPostInfo", checked) }
        }
        QQC2.Label { text: "Show artist & post ID on wallpaper change" }
    }

    QQC2.MenuSeparator { Layout.fillWidth: true }

    QQC2.Button {
        text: "Skip to Next"
        // writeConfig writes directly to the KConfig file on disk so the Rust
        // daemon picks it up on its next tick without requiring Apply.
        onClicked: {
            var ts = new Date().toISOString()
            cfg_ForceNextAt = ts
            if (wallpaperConfiguration)
                wallpaperConfiguration.writeConfig("ForceNextAt", ts)
        }
    }

    Item { Layout.fillHeight: true }
}
