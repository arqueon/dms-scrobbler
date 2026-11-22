import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lastfmScrobbler"

    readonly property var service: (pluginService && pluginId)
        ? (pluginService.pluginDaemonInstances[pluginId] || pluginService.pluginInstances[pluginId])
        : null

    readonly property var actionOptions: [
        { label: "Open Popout", value: "popout" },
        { label: "Toggle Love", value: "love" },
        { label: "Refresh Info", value: "refresh" },
        { label: "Open Artist on Last.fm", value: "lastfm_artist" },
        { label: "Open Track on Last.fm", value: "lastfm_track" },
        { label: "Open Track on ListenBrainz", value: "listenbrainz_track" },
        { label: "Open ListenBrainz Profile", value: "listenbrainz_profile" },
        { label: "Flush Offline Queue", value: "flush_queue" },
        { label: "Nothing", value: "none" }
    ]

    StyledText {
        width: parent.width
        text: "DMS Last.fm & ListenBrainz Scrobbler"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Configure Last.fm and ListenBrainz scrobbling, favorites sync, playback detection, and bar appearance."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    // ── Section 1: Last.fm ──
    StyledRect {
        width: parent.width
        height: lfmHdrRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: lfmHdrRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "radio"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - Theme.iconSize - Theme.spacingS
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: "Last.fm"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Get your API Key and Shared Secret at last.fm/api/account/create."
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    ToggleSetting {
        settingKey: "lastfmEnabled"
        label: "Enable Last.fm"
        description: "Send Now Playing updates, scrobbles, and love/unlove actions to Last.fm."
        defaultValue: true
    }

    StringSetting {
        settingKey: "apiKey"
        label: "Last.fm API Key"
        placeholder: "Enter Last.fm API Key"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "apiSecret"
        label: "Last.fm Shared Secret"
        placeholder: "Enter Last.fm API Secret"
        defaultValue: ""
    }

    Row {
        spacing: Theme.spacingM
        width: parent.width

        DankButton {
            width: (parent.width - Theme.spacingM * 2) / 3
            text: "1. Authenticate"
            enabled: !!root.service
            onClicked: root.service.startAuthFlow()
        }

        DankButton {
            width: (parent.width - Theme.spacingM * 2) / 3
            text: "2. Confirm Auth"
            enabled: !!root.service
            onClicked: root.service.completeAuthFlow()
        }

        DankButton {
            width: (parent.width - Theme.spacingM * 2) / 3
            text: "Disconnect"
            enabled: !!(root.service && root.service.username)
            onClicked: root.service.disconnectLastFm()
        }
    }

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
                text: "Last.fm Session:"
                font.weight: Font.Bold
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }

            StyledText {
                text: root.service && root.service.username
                      ? "Authenticated as: <b>" + root.service.username + "</b>"
                      : "Not authenticated. API session key is missing."
                color: root.service && root.service.username ? Theme.primary : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                textFormat: Text.StyledText
            }
        }
    }

    // ── Section 2: ListenBrainz ──
    StyledRect {
        width: parent.width
        height: lbHdrRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: lbHdrRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "graphic_eq"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - Theme.iconSize - Theme.spacingS
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: "ListenBrainz"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Copy your User Token from listenbrainz.org/settings/ and click Validate Token."
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    ToggleSetting {
        settingKey: "listenbrainzEnabled"
        label: "Enable ListenBrainz"
        description: "Submit playing_now, single listens, and recording feedback (love/unlove) to ListenBrainz."
        defaultValue: false
    }

    StringSetting {
        settingKey: "listenbrainzToken"
        label: "ListenBrainz User Token"
        description: "Found in your profile page at listenbrainz.org/settings/."
        placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "listenbrainzUrl"
        label: "ListenBrainz API URL"
        description: "Leave default unless using a self-hosted ListenBrainz-compatible server."
        placeholder: "https://api.listenbrainz.org"
        defaultValue: "https://api.listenbrainz.org"
    }

    Row {
        spacing: Theme.spacingM
        width: parent.width

        DankButton {
            width: (parent.width - Theme.spacingM) * 0.6
            text: (root.service && root.service.lbTokenValidationRunning) ? "Validating…" : "Validate Token"
            enabled: !!(root.service && root.service.listenbrainzToken && !root.service.lbTokenValidationRunning)
            onClicked: root.service.validateListenBrainzToken(false)
        }

        DankButton {
            width: (parent.width - Theme.spacingM) * 0.4
            text: "Disconnect"
            enabled: !!(root.service && (root.service.listenbrainzToken || root.service.listenbrainzUsername))
            onClicked: root.service.disconnectListenBrainz()
        }
    }

    StyledRect {
        width: parent.width
        height: lbStatusCol.height + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: lbStatusCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            StyledText {
                text: "ListenBrainz Status:"
                font.weight: Font.Bold
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }

            StyledText {
                text: {
                    if (root.service && root.service.listenbrainzUsername)
                        return "Connected as: <b>" + root.service.listenbrainzUsername + "</b>" + (root.service.listenbrainzEnabled ? "" : " (disabled)");
                    if (root.service && root.service.listenbrainzToken)
                        return "Token entered — click Validate Token to verify username.";
                    return "Not configured. Paste your User Token above.";
                }
                color: (root.service && root.service.listenbrainzUsername)
                    ? Theme.primary
                    : ((root.service && root.service.listenbrainzToken) ? Theme.warning : Theme.surfaceVariantText)
                font.pixelSize: Theme.fontSizeSmall
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
    }

    // ── Section 3: Scrobbling & Playback ──
    StyledRect {
        width: parent.width
        height: scrobbleHdrRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: scrobbleHdrRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "tune"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "Scrobbling & Playback"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

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
        description: "Percentage of the track that must play before scrobbling (capped at 4 min)."
        options: [
            { label: "50% (Standard)", value: "50" },
            { label: "75%", value: "75" },
            { label: "100%", value: "100" }
        ]
        defaultValue: "50"
    }

    ToggleSetting {
        settingKey: "remoteFallbackEnabled"
        label: "Remote Playback Fallback"
        description: "Show Now Playing from Last.fm or ListenBrainz when no local player is active. External tracks are never scrobbled twice."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "youtubeArtEnabled"
        label: "Search YouTube Music for missing artwork"
        description: "When Last.fm has no cover, send the artist, title and album to music.youtube.com to search for artwork."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "publishRemoteMpris"
        label: "Enable MPRIS Metadata Bridge"
        description: "Publish enriched artwork for the local DMS track and expose remote Now Playing when no local source is active. Requires mpris-bridge."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showNotifications"
        label: "Scrobble Notifications"
        description: "Show a desktop toast when a track finishes scrobbling. Errors, offline queueing, and love actions always notify."
        defaultValue: true
    }

    // ── Section 4: Bar Appearance ──
    StyledRect {
        width: parent.width
        height: barHdrRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: barHdrRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "palette"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "Bar Appearance"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    ToggleSetting {
        settingKey: "showLoveButton"
        label: "Show Love Button"
        description: "Show the heart (love/unlove) button on the bar. Love stays available via popout, Control Center, and IPC."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showAlbumArt"
        label: "Show Album Art"
        description: "Display a small thumbnail of the track's cover art on the bar."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showMusicAnimation"
        label: "Show Music Playing Animation"
        description: "Show a subtle animated sound wave representation when music is playing."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showTrackInfo"
        label: "Show Track Information (Text)"
        description: "Show the Artist - Title text on horizontal bars."
        defaultValue: true
    }

    // ── Section 5: Mouse Actions ──
    StyledRect {
        width: parent.width
        height: mouseHdrRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: mouseHdrRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "mouse"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - Theme.iconSize - Theme.spacingS
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: "Mouse Actions"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Middle click is also triggered by a three-finger tap on most touchpads."
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    SelectionSetting {
        settingKey: "pillLeftAction"
        label: "Left Click"
        options: root.actionOptions
        defaultValue: "popout"
    }

    SelectionSetting {
        settingKey: "pillMiddleAction"
        label: "Middle Click / Three-Finger Tap"
        options: root.actionOptions
        defaultValue: "love"
    }

    SelectionSetting {
        settingKey: "pillRightAction"
        label: "Right Click"
        options: root.actionOptions
        defaultValue: "lastfm_track"
    }

    // ── Section 6: Offline Queue & Advanced ──
    StyledRect {
        width: parent.width
        height: advHdrRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: advHdrRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "settings_applications"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "Offline Queue & Advanced"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    StyledRect {
        width: parent.width
        height: queueRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Row {
            id: queueRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingM

            Column {
                width: parent.width - flushQueueBtn.width - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    text: "Offline Queue"
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: {
                        if (!root.service) return "Service unavailable";
                        return "Pending: " + root.service.pendingScrobbles
                            + " (Last.fm: " + root.service.pendingLastfmScrobbles
                            + ", ListenBrainz: " + root.service.pendingListenBrainzScrobbles + ")";
                    }
                    color: (root.service && root.service.pendingScrobbles > 0) ? Theme.warning : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            DankButton {
                id: flushQueueBtn
                text: "Flush Queue Now"
                anchors.verticalCenter: parent.verticalCenter
                enabled: !!(root.service && root.service.pendingScrobbles > 0 && root.service.anyServiceConfigured)
                onClicked: root.service.flushQueue()
            }
        }
    }

    ToggleSetting {
        settingKey: "debugLogging"
        label: "Debug Logging"
        description: "Print verbose diagnostics to the DMS logs. Leave off unless troubleshooting (credentials are never logged)."
        defaultValue: false
    }

    // ── Section 7: Niri Keybinds & IPC ──
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
                      "• Love on enabled services: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler love</font><br/>" +
                      "• Love on ListenBrainz only: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler loveListenBrainz</font><br/>" +
                      "• Unlove on enabled services: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler unlove</font><br/>" +
                      "• Refresh track metadata: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler refresh</font><br/>" +
                      "• Flush offline queue: <font color='" + Theme.primary + "'>dms ipc call lastfmScrobbler flushQueue</font><br/>" +
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
