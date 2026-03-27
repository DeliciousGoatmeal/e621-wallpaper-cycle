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
    property string cfg_ForceNextAt

    // Write a config key immediately to KConfig (bypasses the cfg_ Apply buffer).
    function writeNow(key, value) {
        if (wallpaperConfiguration)
            wallpaperConfiguration.writeConfig(key, value)
    }

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

    QQC2.Button {
        text: "Skip to Next"
        // Write directly to KConfig so the daemon picks it up immediately
        // without requiring the user to click Apply.
        onClicked: {
            var ts = new Date().toISOString()
            cfg_ForceNextAt = ts
            writeNow("ForceNextAt", ts)
        }
    }

    Item { Layout.fillHeight: true }
}
