import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lastfmScrobbler"

    readonly property var service: (pluginService && pluginId) ? pluginService.pluginInstances[pluginId] : null

    StyledText {
        width: parent.width
        text: "DMS Last.fm Scrobbler Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Configure your Last.fm API credentials and players. Get your API Key at: last.fm/api/accounts"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    // 1. API Credentials
    StringSetting {
        settingKey: "apiKey"
        label: "API Key"
        placeholder: "Enter Last.fm API Key"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "apiSecret"
        label: "Shared Secret"
        placeholder: "Enter Last.fm API Secret"
        defaultValue: ""
    }

    // 2. Auth Flow Buttons
    StyledText {
        text: "Authentication"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Click 'Authenticate' to open Last.fm in your browser and authorize this app. Once authorized, click 'Confirm Authentication' to complete the process."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Row {
        spacing: Theme.spacingM
        width: parent.width

        StyledRect {
            id: authBtn
            width: 160
            height: 38
            radius: Theme.cornerRadius
            color: authMouse.containsPress ? Theme.primaryHover : (authMouse.containsMouse ? Theme.primaryContainer : Theme.primary)
            
            MouseArea {
                id: authMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.service) root.service.startAuthFlow();
                }
            }

            StyledText {
                anchors.centerIn: parent
                text: "1. Authenticate"
                color: Theme.onPrimary
                font.weight: Font.Bold
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        StyledRect {
            id: confirmBtn
            width: 180
            height: 38
            radius: Theme.cornerRadius
            color: confirmMouse.containsPress ? Theme.primaryHover : (confirmMouse.containsMouse ? Theme.primaryContainer : Theme.secondary)
            
            MouseArea {
                id: confirmMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.service) root.service.completeAuthFlow();
                }
            }

            StyledText {
                anchors.centerIn: parent
                text: "2. Confirm Authentication"
                color: Theme.onSecondary
                font.weight: Font.Bold
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // Displays session status
    StyledRect {
        width: parent.width
        height: sessionCol.height + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: sessionCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            StyledText {
                text: "Session Status:"
                font.weight: Font.Bold
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }

            StyledText {
                text: root.service && root.service.username 
                      ? "Authenticated as: <b>" + root.service.username + "</b>" 
                      : "Not authenticated. Token/Session Key is missing."
                color: root.service && root.service.username ? Theme.primary : Theme.errorText
                font.pixelSize: Theme.fontSizeSmall
                textFormat: Text.StyledText
            }
        }
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    // 3. Behavior settings
    StringSetting {
        settingKey: "playerWhitelist"
        label: "Music Player Whitelist"
        description: "Comma-separated list of MPRIS player identities to scrobble (e.g. spotify, mpd, cider, audacious)."
        placeholder: "spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop, chrome, firefox, chromium"
        defaultValue: "spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop, chrome, firefox, chromium"
    }

    SelectionSetting {
        settingKey: "scrobbleThreshold"
        label: "Scrobble Threshold"
        description: "Percentage of the track that must play before scrobbling (capped at 4 min)"
        options: [
            { label: "50% (Standard)", value: "50" },
            { label: "75%", value: "75" },
            { label: "100%", value: "100" }
        ]
        defaultValue: "50"
    }

    ToggleSetting {
        settingKey: "showPlaybackControls"
        label: "Show Playback Controls"
        description: "Master switch for the play/pause and skip buttons on the bar (functions as a media controller replacement). Pick which ones below."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showPrevButton"
        label: "    • Previous Button"
        description: "Show the skip-previous button (requires Show Playback Controls)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showPlayButton"
        label: "    • Play/Pause Button"
        description: "Show the play/pause button (requires Show Playback Controls)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showNextButton"
        label: "    • Next Button"
        description: "Show the skip-next button (requires Show Playback Controls)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showLoveButton"
        label: "Show Love Button"
        description: "Show the heart (love/unlove) button on the bar. Love is still available via the popout and IPC when hidden."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showAlbumArt"
        label: "Show Album Art"
        description: "Display a small thumbnail of the track's cover art on the bar"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showMusicAnimation"
        label: "Show Music Playing Animation"
        description: "Show a subtle animated sound wave representation when music is playing"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showTrackInfo"
        label: "Show Track Information (Text)"
        description: "Show the Artist - Title text on horizontal bars"
        defaultValue: true
    }

    // 3b. Mouse Actions
    StyledText {
        text: "Mouse Actions"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Assign an action to each mouse button on the bar pill. Middle click is also triggered by a three-finger tap on most touchpads."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    SelectionSetting {
        settingKey: "pillLeftAction"
        label: "Left Click"
        options: [
            { label: "Open Popout", value: "popout" },
            { label: "Play / Pause", value: "playpause" },
            { label: "Toggle Love", value: "love" },
            { label: "Next Track", value: "next" },
            { label: "Previous Track", value: "previous" },
            { label: "Refresh Info", value: "refresh" },
            { label: "Nothing", value: "none" }
        ]
        defaultValue: "popout"
    }

    SelectionSetting {
        settingKey: "pillMiddleAction"
        label: "Middle Click / Three-Finger Tap"
        options: [
            { label: "Toggle Love", value: "love" },
            { label: "Play / Pause", value: "playpause" },
            { label: "Open Popout", value: "popout" },
            { label: "Next Track", value: "next" },
            { label: "Previous Track", value: "previous" },
            { label: "Refresh Info", value: "refresh" },
            { label: "Nothing", value: "none" }
        ]
        defaultValue: "love"
    }

    SelectionSetting {
        settingKey: "pillRightAction"
        label: "Right Click"
        options: [
            { label: "Play / Pause", value: "playpause" },
            { label: "Toggle Love", value: "love" },
            { label: "Open Popout", value: "popout" },
            { label: "Next Track", value: "next" },
            { label: "Previous Track", value: "previous" },
            { label: "Refresh Info", value: "refresh" },
            { label: "Nothing", value: "none" }
        ]
        defaultValue: "playpause"
    }

    // 4. Advanced
    StyledText {
        text: "Advanced"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "debugLogging"
        label: "Debug Logging"
        description: "Print verbose diagnostics to the DMS logs. Leave off unless troubleshooting (credentials are never logged)."
        defaultValue: false
    }

    // 5. Instructions
    StyledText {
        text: "Niri Keybinds & IPC Commands"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledRect {
        width: parent.width
        height: ipcCol.height + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: ipcCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingL
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: "• Toggle love/unlove: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler toggleLove</font><br/>" +
                      "• Love current song: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler love</font><br/>" +
                      "• Unlove current song: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler unlove</font><br/>" +
                      "• Check scrobbler status: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler status</font>"
                font.pixelSize: Theme.fontSizeSmall
                font.family: "monospace"
                color: Theme.surfaceText
                wrapMode: Text.WrapAnywhere
                textFormat: Text.StyledText
            }
        }
    }
}
