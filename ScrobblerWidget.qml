import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import Quickshell.Services.Mpris

PluginComponent {
    id: root
    readonly property int barLabelSize: Theme.barTextSize(barThickness, barConfig ? barConfig.fontScale : undefined, barConfig ? barConfig.maximizeWidgetText : undefined)

    // Token-derived sizing (dux-plugin-registry review notes): the popout and
    // the bar pill avoid hardcoded pixel sizes so font/density scale applies.
    readonly property real popoutArtSize: Theme.spacingXL * 8 - Theme.spacingS
    readonly property real actionButtonSize: Theme.avatarSize
    readonly property real actionIconSize: Theme.iconSizeSmall + Theme.spacingXXS
    readonly property real chipHeight: Theme.iconSizeSmall + Theme.spacingS
    readonly property real chipIconSize: Theme.iconSizeSmall - Theme.spacingXS
    readonly property real progressBarHeight: Theme.spacingXS
    readonly property real pillTextMaxWidth: Theme.spacingXL * 6 - Theme.spacingXS

    popoutWidth: 304
    readonly property var service: (pluginService && pluginId)
        ? (pluginService.pluginDaemonInstances[pluginId] || pluginService.pluginInstances[pluginId])
        : null

    readonly property bool isLoved: service ? service.isLoved : false
    readonly property bool hasActiveMedia: !!(service && service.hasTrack && service.trackTitle)
    readonly property string trackDisplay: service ? service.trackArtist + " - " + service.trackTitle : ""

    // Control Center integration
    ccWidgetIcon: root.isLoved ? "favorite" : "music_note"
    ccWidgetPrimaryText: root.hasActiveMedia ? root.trackDisplay : "Scrobbler"
    ccWidgetSecondaryText: {
        if (!service) return "Inactive";
        if (root.hasActiveMedia) {
            if (service.isPartiallyLoved) return "Loved (1/2)";
            if (root.isLoved) return "Loved";
            if (service.scrobbleStatus === "accepted") return "Scrobbled";
            if (service.scrobbleStatus === "queued") return "Queued";
            if (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial") return "Delivery error";
            return service.sourceLabel;
        }
        if (service.pendingScrobbles > 0)
            return service.pendingScrobbles + " queued";
        if (service.anyServiceConfigured)
            return "Ready";
        return "Not configured";
    }
    ccWidgetIsActive: !!(root.hasActiveMedia && (root.isLoved || (service && service.scrobbledThisTrack)))
    onCcWidgetToggled: {
        if (root.hasActiveMedia)
            root.toggleLove();
        else if (service && service.pendingScrobbles > 0)
            service.flushQueue();
    }

    // Vertical-bar tooltip Y offset, mirroring DMS's native bar widgets:
    // when the vertical bar sits below a top bar (parentScreen.y > 0), shift down.
    readonly property real minTooltipY: {
        if (!parentScreen || !isVertical) return 0;
        if (parentScreen.y > 0) {
            var spacing = (barConfig && barConfig.spacing !== undefined) ? barConfig.spacing : Theme.spacingXS;
            return barThickness + spacing;
        }
        return 0;
    }

    function toggleLove() {
        if (service) service.toggleLoveCurrentTrack();
    }

    function openLastFmArtist() {
        if (!service || !service.trackArtist) return;
        Qt.openUrlExternally("https://www.last.fm/music/" + encodeURIComponent(service.trackArtist).replace(/%20/g, "+"));
    }

    function openLastFmTrack() {
        if (!service || !service.trackArtist || !service.trackTitle) return;
        Qt.openUrlExternally("https://www.last.fm/music/"
            + encodeURIComponent(service.trackArtist).replace(/%20/g, "+")
            + "/_/" + encodeURIComponent(service.trackTitle).replace(/%20/g, "+"));
    }

    function openListenBrainzProfile() {
        if (!service) return;
        if (service.listenbrainzUsername) {
            Qt.openUrlExternally("https://listenbrainz.org/user/" + encodeURIComponent(service.listenbrainzUsername) + "/");
        } else {
            Qt.openUrlExternally("https://listenbrainz.org/");
        }
    }

    function openListenBrainzTrack() {
        if (!service) return;
        if (service.lbRecordingMbid) {
            Qt.openUrlExternally("https://musicbrainz.org/recording/" + encodeURIComponent(service.lbRecordingMbid));
        } else if (service.trackArtist && service.trackTitle) {
            var q = service.trackArtist + " " + service.trackTitle;
            Qt.openUrlExternally("https://musicbrainz.org/search?type=recording&query=" + encodeURIComponent(q));
        } else {
            openListenBrainzProfile();
        }
    }

    function tooltipSummary() {
        if (!service) return "";
        var lines = [root.trackDisplay];
        if (service.trackAlbum)
            lines.push(service.trackAlbum);

        var loveLabel = "Not loved";
        if (service.isPartiallyLoved) {
            loveLabel = service.lastfmLoved ? "Loved on Last.fm only" : "Loved on ListenBrainz only";
        } else if (root.isLoved) {
            loveLabel = "Loved";
        }

        var statusLabel = "";
        if (service.scrobbleStatus === "accepted") statusLabel = " · Scrobbled";
        else if (service.scrobbleStatus === "queued") statusLabel = " · Queued offline";
        else if (service.scrobbleStatus === "partial") statusLabel = " · Partial scrobble";
        else if (service.scrobbleStatus === "error") statusLabel = " · Scrobble failed";
        if (service.pendingScrobbles > 0)
            statusLabel += " · " + service.pendingScrobbles + " queued";

        lines.push(loveLabel + statusLabel);
        return lines.join("\n");
    }

    // Run a named pill action (configured per mouse button in settings).
    function doAction(name) {
        if (!service) return;
        switch (name) {
        case "popout":
            if (typeof root.triggerPopout === "function") root.triggerPopout();
            break;
        case "love":
            root.toggleLove();
            break;
        case "refresh":
            service.checkTrackInfo();
            break;
        case "lastfm_artist":
            openLastFmArtist();
            break;
        case "lastfm_track":
            openLastFmTrack();
            break;
        case "listenbrainz_profile":
            openListenBrainzProfile();
            break;
        case "listenbrainz_track":
            openListenBrainzTrack();
            break;
        case "flush_queue":
            service.flushQueue();
            break;
        case "none":
        default:
            break;
        }
    }

    function dispatchPillClick(button) {
        if (!service) return;
        if (button === Qt.LeftButton) doAction(service.pillLeftAction);
        else if (button === Qt.MiddleButton) doAction(service.pillMiddleAction);
        else if (button === Qt.RightButton) doAction(service.pillRightAction);
    }

    function statusIconName(status) {
        switch (status) {
        case "accepted": return "check_circle";
        case "queued": return "schedule";
        case "sending": return "sync";
        case "error": return "error";
        default: return "radio_button_unchecked";
        }
    }

    function statusIconColor(status) {
        switch (status) {
        case "accepted": return Theme.success;
        case "queued": return Theme.warning;
        case "sending": return Theme.primary;
        case "error": return Theme.error;
        default: return Theme.surfaceVariantText;
        }
    }

    ccDetailContent: Component {
        Rectangle {
            id: ccDetailRoot
            implicitHeight: ccCol.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: ccCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: root.hasActiveMedia ? root.service.trackTitle : "Nothing playing"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    visible: root.hasActiveMedia && !!(root.service && root.service.trackArtist)
                    text: root.service ? (root.service.trackArtist + (root.service.trackAlbum ? " · " + root.service.trackAlbum : "")) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                    text: {
                        if (!root.service) return "";
                        var bits = [];
                        if (root.service.lastfmConfigured)
                            bits.push("Last.fm: " + (root.service.username || "ok") + (root.service.lastfmLoved ? " ♥" : ""));
                        if (root.service.listenbrainzConfigured)
                            bits.push("LB: " + (root.service.listenbrainzUsername || "ok") + (root.service.listenbrainzLoved ? " ♥" : ""));
                        if (bits.length === 0) return "Configure Last.fm or ListenBrainz in plugin settings.";
                        if (root.service.pendingScrobbles > 0)
                            bits.push(root.service.pendingScrobbles + " queued");
                        return bits.join(" · ");
                    }
                    wrapMode: Text.WordWrap
                }

                Row {
                    spacing: Theme.spacingS

                    DButton {
                        text: root.isLoved ? "Unlove" : "Love"
                        enabled: root.hasActiveMedia && !(root.service && root.service.lovePending)
                        onClicked: root.toggleLove()
                    }

                    DButton {
                        text: (root.service && root.service.scrobbleStatus === "error") ? "Retry" : "Refresh"
                        enabled: root.hasActiveMedia || !!(root.service && root.service.pendingScrobbles > 0)
                        onClicked: {
                            if (!root.service) return;
                            if (root.service.scrobbleStatus === "error" || root.service.scrobbleStatus === "partial")
                                root.service.retryScrobble();
                            else if (root.hasActiveMedia)
                                root.service.checkTrackInfo();
                            else
                                root.service.flushQueue();
                        }
                    }
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "DMS Scrobbler"
            showCloseButton: true

            Column {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingM
                topPadding: Theme.spacingS
                bottomPadding: Theme.spacingM

                // Empty State when no media is active
                StyledRect {
                    visible: !root.hasActiveMedia
                    width: parent.width
                    height: emptyCol.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainer

                    Column {
                        id: emptyCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.spacingL
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DIcon {
                            name: "music_off"
                            size: Theme.iconSizeLarge
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            width: parent.width
                            text: "Nothing playing"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledText {
                            width: parent.width
                            text: (service && service.anyServiceConfigured)
                                ? "Start playback on a whitelisted player or wait for remote Now Playing."
                                : "Configure Last.fm or ListenBrainz in plugin settings to begin."
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // Service connection summary pills
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.spacingS
                            visible: !!(service && (service.lastfmConfigured || service.listenbrainzConfigured))

                            StyledRect {
                                visible: !!(service && service.lastfmConfigured)
                                width: emptyLfmRow.implicitWidth + Theme.spacingS * 2
                                height: root.chipHeight
                                radius: Theme.cornerRadiusSmall
                                color: Theme.surfaceContainerHigh

                                Row {
                                    id: emptyLfmRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS
                                    DIcon {
                                        name: "check_circle"
                                        size: root.chipIconSize
                                        color: Theme.success
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "Last.fm"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            StyledRect {
                                visible: !!(service && service.listenbrainzConfigured)
                                width: emptyLbRow.implicitWidth + Theme.spacingS * 2
                                height: root.chipHeight
                                radius: Theme.cornerRadiusSmall
                                color: Theme.surfaceContainerHigh

                                Row {
                                    id: emptyLbRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS
                                    DIcon {
                                        name: "check_circle"
                                        size: root.chipIconSize
                                        color: Theme.success
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "ListenBrainz"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        DButton {
                            visible: !!(service && service.pendingScrobbles > 0)
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Flush " + (service ? service.pendingScrobbles : 0) + " queued"
                            onClicked: if (service) service.flushQueue()
                        }
                    }
                }

                // Active Media View
                Column {
                    visible: root.hasActiveMedia
                    width: parent.width
                    spacing: Theme.spacingM

                    // 1. Album Cover Art (Centered, Framed)
                    Rectangle {
                        width: root.popoutArtSize
                        height: root.popoutArtSize
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16)
                        border.width: 1
                        anchors.horizontalCenter: parent.horizontalCenter

                        Image {
                            id: popoutArt
                            anchors.fill: parent
                            asynchronous: true
                            source: service ? service.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: popoutArt
                            maskEnabled: true
                            maskSource: artMask
                            visible: !!(service && service.trackArtUrl) && popoutArt.status === Image.Ready
                            opacity: popoutArt.status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }

                        Item {
                            id: artMask
                            anchors.fill: parent
                            layer.enabled: true
                            layer.smooth: true
                            visible: false

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.cornerRadius
                                color: "black"
                                antialiasing: true
                            }
                        }

                        DIcon {
                            visible: !(service && service.trackArtUrl) || popoutArt.status !== Image.Ready
                            name: "music_note"
                            size: Theme.iconSizeLarge * 2
                            color: Theme.surfaceVariantText
                            anchors.centerIn: parent
                        }
                    }

                    // 1b. Source Badge
                    StyledRect {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, sourceBadgeRow.implicitWidth + Theme.spacingM)
                        height: root.chipHeight
                        radius: Theme.cornerRadiusSmall
                        color: Theme.surfaceContainerHigh

                        Row {
                            id: sourceBadgeRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DIcon {
                                name: (service && service.isRemoteSource) ? "podcasts" : "album"
                                size: root.chipIconSize
                                color: (service && service.isRemoteSource) ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: service ? service.sourceLabel : ""
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // 2. Track Metadata (Title, Artist, Album)
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        anchors.horizontalCenter: parent.horizontalCenter

                        StyledText {
                            width: parent.width
                            text: root.service ? root.service.trackTitle : ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.service ? root.service.trackArtist : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.primary
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.service && root.service.trackAlbum ? root.service.trackAlbum : ""
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                    }

                    // 2b. Scrobble Progress
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: !!(service && service.canScrobbleCurrent && service.trackTitle && service.scrobbleTargetSeconds > 0 && service.anyServiceConfigured)

                        Rectangle {
                            width: parent.width
                            height: root.progressBarHeight
                            radius: Theme.cornerRadius
                            color: Theme.surfaceVariant

                            Rectangle {
                                height: parent.height
                                radius: Theme.cornerRadius
                                width: parent.width * Math.max(0, Math.min(1,
                                    (service ? service.playtimeCounter : 0) /
                                    Math.max(1, service ? service.scrobbleTargetSeconds : 1)))
                                color: {
                                    if (!service) return Theme.primary;
                                    if (service.scrobbleStatus === "error") return Theme.error;
                                    if (service.scrobbleStatus === "queued" || service.scrobbleStatus === "partial") return Theme.warning;
                                    if (service.scrobbledThisTrack) return Theme.success;
                                    return Theme.primary;
                                }
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }

                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: {
                                if (!service) return Theme.surfaceVariantText;
                                if (service.scrobbleStatus === "error") return Theme.error;
                                if (service.scrobbleStatus === "queued" || service.scrobbleStatus === "partial") return Theme.warning;
                                if (service.scrobbledThisTrack) return Theme.success;
                                return Theme.surfaceVariantText;
                            }
                            text: {
                                if (!service) return "";
                                if (service.scrobbleStatus === "accepted") return "Scrobbled ✓";
                                if (service.scrobbleStatus === "queued") return "Queued offline ✓";
                                if (service.scrobbleStatus === "partial") return "Partial delivery — retry below";
                                if (service.scrobbleStatus === "sending") return "Sending…";
                                if (service.scrobbleStatus === "error") return "Scrobble failed";
                                var rem = Math.max(0, service.scrobbleTargetSeconds - service.playtimeCounter);
                                return "Scrobbles in " + rem + "s";
                            }
                        }
                    }

                    // 2c. Per-service status & love chips
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingS
                        visible: !!(service && (service.lastfmConfigured || service.listenbrainzConfigured
                            || (service.isRemoteSource && service.remoteService !== "")))

                        // Last.fm chip
                        StyledRect {
                            visible: !!(service && (service.lastfmConfigured || (service.isRemoteSource && service.remoteService === "lastfm")))
                            width: lfmChipRow.implicitWidth + Theme.spacingM
                            height: root.chipHeight
                            radius: Theme.cornerRadiusSmall
                            color: lfmChipMouse.containsPress ? Theme.surfaceVariant : (lfmChipMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.14)
                            border.width: 1

                            Row {
                                id: lfmChipRow
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DIcon {
                                    name: root.statusIconName(service ? service.lastfmScrobbleStatus : "idle")
                                    size: root.chipIconSize
                                    color: root.statusIconColor(service ? service.lastfmScrobbleStatus : "idle")
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "Last.fm"
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DIcon {
                                    visible: !!(service && service.lastfmLoved)
                                    name: "favorite"
                                    size: root.chipIconSize
                                    color: Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: lfmChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openLastFmTrack()
                            }
                        }

                        // ListenBrainz chip
                        StyledRect {
                            visible: !!(service && (service.listenbrainzConfigured || (service.isRemoteSource && service.remoteService === "listenbrainz")))
                            width: lbChipRow.implicitWidth + Theme.spacingM
                            height: root.chipHeight
                            radius: Theme.cornerRadiusSmall
                            color: lbChipMouse.containsPress ? Theme.surfaceVariant : (lbChipMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.14)
                            border.width: 1

                            Row {
                                id: lbChipRow
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DIcon {
                                    name: root.statusIconName(service ? service.listenbrainzScrobbleStatus : "idle")
                                    size: root.chipIconSize
                                    color: root.statusIconColor(service ? service.listenbrainzScrobbleStatus : "idle")
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "ListenBrainz"
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DIcon {
                                    visible: !!(service && service.listenbrainzLoved)
                                    name: "favorite"
                                    size: root.chipIconSize
                                    color: Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: lbChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openListenBrainzTrack()
                            }
                        }
                    }

                    // 3. Companion Action Row (Love + Sync + Artist + Track + Refresh)
                    Row {
                        spacing: Theme.spacingS
                        anchors.horizontalCenter: parent.horizontalCenter

                        // Primary Love pill button
                        StyledRect {
                            width: loveBtnRow.implicitWidth + Theme.spacingM * 1.5
                            height: root.actionButtonSize
                            radius: Theme.cornerRadius
                            opacity: (service && service.lovePending) ? 0.6 : 1.0
                            color: {
                                if (root.isLoved) {
                                    return loveMouseP.containsPress
                                        ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.28)
                                        : (loveMouseP.containsMouse
                                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.22)
                                            : Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.14));
                                }
                                return loveMouseP.containsPress
                                    ? Theme.surfaceVariant
                                    : (loveMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer);
                            }
                            border.color: root.isLoved
                                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.45)
                                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.14)
                            border.width: 1

                            Row {
                                id: loveBtnRow
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DIcon {
                                    name: root.isLoved ? "favorite" : "favorite_border"
                                    size: root.actionIconSize
                                    color: root.isLoved ? Theme.error : Theme.widgetIconColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: (service && service.isPartiallyLoved)
                                        ? "Loved (1/2)"
                                        : (root.isLoved ? "Loved" : "Love")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: root.isLoved ? Theme.error : Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: loveMouseP
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleLove()
                            }
                        }

                        // Sync missing love across services when partially loved
                        StyledRect {
                            visible: !!(service && service.isPartiallyLoved)
                            width: root.actionButtonSize
                            height: root.actionButtonSize
                            radius: Theme.cornerRadius
                            color: syncLoveMouseP.containsPress ? Theme.surfaceVariant : (syncLoveMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                            border.width: 1

                            DIcon {
                                name: "sync"
                                size: root.actionIconSize
                                color: Theme.primary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: syncLoveMouseP
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (service) service.loveCurrentTrack()
                            }
                        }

                        // Open Artist
                        StyledRect {
                            width: root.actionButtonSize
                            height: root.actionButtonSize
                            radius: Theme.cornerRadius
                            color: artistMouseP.containsPress ? Theme.surfaceVariant : (artistMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                            border.width: 1

                            DIcon {
                                name: "person"
                                size: root.actionIconSize
                                color: Theme.widgetIconColor
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: artistMouseP
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (service && (service.lastfmConfigured || !service.listenbrainzConfigured))
                                        root.openLastFmArtist();
                                    else
                                        root.openListenBrainzTrack();
                                }
                            }
                        }

                        // Open Track
                        StyledRect {
                            width: root.actionButtonSize
                            height: root.actionButtonSize
                            radius: Theme.cornerRadius
                            color: trackMouseP.containsPress ? Theme.surfaceVariant : (trackMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                            border.width: 1

                            DIcon {
                                name: "open_in_new"
                                size: root.actionIconSize
                                color: Theme.primary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: trackMouseP
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (service && !service.lastfmConfigured && service.listenbrainzConfigured)
                                        root.openListenBrainzTrack();
                                    else
                                        root.openLastFmTrack();
                                }
                            }
                        }

                        // Refresh track info
                        StyledRect {
                            width: root.actionButtonSize
                            height: root.actionButtonSize
                            radius: Theme.cornerRadius
                            color: refreshMouseP.containsPress ? Theme.surfaceVariant : (refreshMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                            border.width: 1

                            DIcon {
                                name: "refresh"
                                size: root.actionIconSize
                                color: Theme.widgetIconColor
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: refreshMouseP
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.doAction("refresh")
                            }
                        }
                    }

                    // 3b. Retry / Queue Banner
                    StyledRect {
                        visible: !!(service && (service.pendingScrobbles > 0 || service.scrobbleStatus === "error" || service.scrobbleStatus === "partial"))
                        width: parent.width
                        height: bannerRow.implicitHeight + Theme.spacingM
                        radius: Theme.cornerRadius
                        color: (service && (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial"))
                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                            : Theme.surfaceContainerHigh
                        border.color: (service && (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial"))
                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.35)
                            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)
                        border.width: 1

                        Row {
                            id: bannerRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width - bannerActionBtn.width - Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: (service && (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial"))
                                    ? Theme.error
                                    : Theme.surfaceText
                                wrapMode: Text.WordWrap
                                text: {
                                    if (!service) return "";
                                    var msgs = [];
                                    if (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial") {
                                        if (service.lastfmScrobbleError) msgs.push("Last.fm: " + service.lastfmScrobbleError);
                                        if (service.listenbrainzScrobbleError) msgs.push("LB: " + service.listenbrainzScrobbleError);
                                    }
                                    if (service.pendingScrobbles > 0)
                                        msgs.push(service.pendingScrobbles + " queued offline");
                                    return msgs.join(" · ");
                                }
                            }

                            StyledRect {
                                id: bannerActionBtn
                                width: bannerBtnTxt.implicitWidth + Theme.spacingM
                                height: root.chipHeight
                                radius: Theme.cornerRadiusSmall
                                anchors.verticalCenter: parent.verticalCenter
                                color: bannerBtnMouse.containsPress ? Theme.surfaceVariant : Theme.surfaceContainer

                                StyledText {
                                    id: bannerBtnTxt
                                    anchors.centerIn: parent
                                    text: (service && (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial")) ? "Retry" : "Flush"
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                }

                                MouseArea {
                                    id: bannerBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!service) return;
                                        if (service.scrobbleStatus === "error" || service.scrobbleStatus === "partial")
                                            service.retryScrobble();
                                        else
                                            service.flushQueue();
                                    }
                                }
                            }
                        }
                    }

                    // 4. Footer (Accounts summary)
                    StyledText {
                        width: parent.width
                        text: {
                            if (!service) return "";
                            var acctParts = [];
                            if (service.lastfmEnabled && service.username)
                                acctParts.push("Last.fm: <b>" + service.username + "</b>");
                            if (service.listenbrainzEnabled && service.listenbrainzUsername)
                                acctParts.push("LB: <b>" + service.listenbrainzUsername + "</b>");
                            else if (service.listenbrainzConfigured)
                                acctParts.push("LB: <b>connected</b>");
                            var str = acctParts.join(" · ");
                            if (service.isRemoteSource)
                                str += (str ? "<br/>" : "") + "Scrobble managed by external source";
                            return str;
                        }
                        visible: text !== ""
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    horizontalBarPill: Component {
        Item {
            id: hPill
            visible: root.hasActiveMedia
            implicitWidth: root.hasActiveMedia ? pillRow.implicitWidth : 0
            implicitHeight: root.hasActiveMedia ? (pillRow.implicitHeight || Theme.iconSize) : 0

            // Use DMS's native DTooltip (a separate layer-shell window) like the
            // built-in bar widgets, so the tooltip is never clipped by the bar window.
            property bool anyHover: pillMouse.containsMouse || heartMouse.containsMouse
            onAnyHoverChanged: {
                if (anyHover && root.hasActiveMedia) {
                    hTipLoader.active = true;
                    hTipDelay.restart();
                } else {
                    hTipDelay.stop();
                    if (hTipLoader.item) hTipLoader.item.hide();
                    hTipLoader.active = false;
                }
            }

            Loader {
                id: hTipLoader
                active: false
                sourceComponent: DTooltip {}
            }

            Timer {
                id: hTipDelay
                interval: 600
                repeat: false
                onTriggered: {
                    if (!hTipLoader.item) return;
                    var currentScreen = root.parentScreen || Screen;
                    var localPos = hPill.mapToItem(null, hPill.width / 2, 0);
                    var isBottom = root.axis && root.axis.edge === "bottom";
                    var tooltipY;
                    if (isBottom) {
                        var tooltipHeight = Theme.fontSizeSmall * 1.5 + Theme.spacingS * 2;
                        tooltipY = currentScreen.height - root.barThickness - root.barSpacing - Theme.spacingXS - tooltipHeight;
                    } else {
                        tooltipY = root.barThickness + root.barSpacing + Theme.spacingXS;
                    }
                    hTipLoader.item.show(root.tooltipSummary(),
                                         localPos.x, tooltipY, currentScreen, false, false);
                }
            }

            // Pill-wide MouseArea for configurable mouse actions. Sits behind the Row,
            // so the visible control buttons keep their own click handling and this
            // catches clicks on empty pill areas (and middle/right on the buttons).
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: function(mouse) {
                    root.dispatchPillClick(mouse.button);
                }
            }

            Row {
                id: pillRow
                spacing: Theme.spacingXS
                anchors.centerIn: parent

                // 1. Album Art Thumbnail
                Rectangle {
                    id: hArtRect
                    width: root.iconSize
                    height: root.iconSize
                    radius: Theme.cornerRadius / 2
                    color: Theme.surfaceVariant
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!(service && service.showAlbumArt && service.trackArtUrl)

                    Image {
                        anchors.fill: parent
                        asynchronous: true
                        source: service ? service.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // 2. Music Playing Wave / Live Audio Visualizer
                MediaVisualizer {
                    id: animRow
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconSize
                    height: root.iconSize
                    barSpan: root.iconSize
                    barCount: 5
                    stretchToWidth: false
                    sourceMode: "mediaOnly"
                    showWhenIdle: false
                    visualizerStyle: "bars"
                    barAlignment: "center"
                    solidColor: Theme.primary
                    activePlayer: service ? service.activePlayer : null
                    visible: !!(service && service.showMusicAnimation && service.activePlayer && service.playbackState === MprisPlaybackState.Playing)
                }

                // 3. Track Info (Artist - Title) — scrolls through the DMS
                // ScrollingText widget, which honors SettingsData.scrollTitleEnabled,
                // Theme.reduceMotion and window visibility, and only animates while
                // the text actually overflows the pill.
                Item {
                    id: trackTextClip
                    visible: !!(service && service.showTrackInfo && root.trackDisplay !== "")
                    width: trackScroller.implicitTextWidth > root.pillTextMaxWidth
                        ? root.pillTextMaxWidth
                        : trackScroller.implicitTextWidth
                    height: Math.max(root.iconSize, trackScroller.implicitTextHeight)
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    ScrollingText {
                        id: trackScroller
                        anchors.fill: parent
                        text: root.trackDisplay
                        color: Theme.surfaceText
                        font.pixelSize: root.barLabelSize
                    }
                }

                // 4. Heart Control
                Item {
                    id: heartContainer
                    width: root.iconSize
                    height: width
                    visible: !!(service && service.showLoveButton)
                    opacity: (service && service.lovePending) ? 0.55 : 1.0
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        name: root.isLoved ? "favorite" : "favorite_border"
                        size: parent.width
                        color: root.isLoved ? Theme.error : Theme.widgetIconColor
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: heartMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                root.toggleLove();
                            } else {
                                root.dispatchPillClick(mouse.button);
                            }
                        }
                    }
                }

                StyledText {
                    id: hLovedText
                    visible: root.isLoved && !!(service && service.showLoveButton)
                    text: root.isLoved ? "Loved" : ""
                    color: Theme.error
                    font.pixelSize: root.barLabelSize
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Fallback icon if all optional elements are disabled so pill stays visible
                DIcon {
                    visible: !hArtRect.visible && !animRow.visible && !trackTextClip.visible && !heartContainer.visible
                    name: "music_note"
                    size: root.iconSize
                    color: Theme.widgetIconColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            id: vPill
            visible: root.hasActiveMedia
            implicitWidth: root.hasActiveMedia ? root.barThickness : 0
            implicitHeight: root.hasActiveMedia ? pillCol.implicitHeight : 0

            // The bar window is too narrow on a vertical panel for an in-window tooltip
            // (it gets clipped/wrapped). DTooltip is a separate layer-shell window
            // positioned by global screen coordinates, so it renders fully and readable.
            property bool anyHover: pillMouseV.containsMouse || heartMouseV.containsMouse
            onAnyHoverChanged: {
                if (anyHover && root.hasActiveMedia) {
                    vTipLoader.active = true;
                    vTipDelay.restart();
                } else {
                    vTipDelay.stop();
                    if (vTipLoader.item) vTipLoader.item.hide();
                    vTipLoader.active = false;
                }
            }

            Loader {
                id: vTipLoader
                active: false
                sourceComponent: DTooltip {}
            }

            Timer {
                id: vTipDelay
                interval: 600
                repeat: false
                onTriggered: {
                    if (!vTipLoader.item) return;
                    var currentScreen = root.parentScreen || Screen;
                    var localPos = vPill.mapToItem(null, vPill.width / 2, vPill.height / 2);
                    var adjustedY = localPos.y + root.minTooltipY;
                    var isLeft = root.axis && root.axis.edge === "left";
                    var tooltipX = isLeft
                        ? (root.barThickness + root.barSpacing + Theme.spacingXS)
                        : (currentScreen.width - root.barThickness - root.barSpacing - Theme.spacingXS);
                    vTipLoader.item.show(root.tooltipSummary(),
                                         tooltipX, adjustedY, currentScreen, isLeft, !isLeft);
                }
            }

            // Pill-wide MouseArea for configurable mouse actions (sits behind the Column).
            MouseArea {
                id: pillMouseV
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: function(mouse) {
                    root.dispatchPillClick(mouse.button);
                }
            }

            Column {
                id: pillCol
                spacing: Theme.spacingXS
                anchors.horizontalCenter: parent.horizontalCenter

                // 1. Album Art Thumbnail (vertical)
                Rectangle {
                    id: vArtRect
                    width: root.iconSize
                    height: root.iconSize
                    radius: Theme.cornerRadius / 2
                    color: Theme.surfaceVariant
                    clip: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!(service && service.showAlbumArt && service.trackArtUrl)

                    Image {
                        anchors.fill: parent
                        asynchronous: true
                        source: service ? service.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // 2. Music Playing Wave / Live Audio Visualizer (vertical)
                MediaVisualizer {
                    id: animCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    verticalMode: true
                    width: root.iconSize
                    height: root.iconSize
                    barSpan: root.iconSize
                    barCount: 5
                    stretchToWidth: false
                    sourceMode: "mediaOnly"
                    showWhenIdle: false
                    visualizerStyle: "bars"
                    barAlignment: "center"
                    solidColor: Theme.primary
                    activePlayer: service ? service.activePlayer : null
                    visible: !!(service && service.showMusicAnimation && service.activePlayer && service.playbackState === MprisPlaybackState.Playing)
                }

                // Heart Control (vertical)
                Item {
                    id: heartContainerV
                    width: root.iconSize
                    height: width
                    visible: !!(service && service.showLoveButton)
                    opacity: (service && service.lovePending) ? 0.55 : 1.0
                    anchors.horizontalCenter: parent.horizontalCenter

                    DIcon {
                        name: root.isLoved ? "favorite" : "favorite_border"
                        size: parent.width
                        color: root.isLoved ? Theme.error : Theme.widgetIconColor
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: heartMouseV
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                root.toggleLove();
                            } else {
                                root.dispatchPillClick(mouse.button);
                            }
                        }
                    }
                }

                // Fallback icon if all optional elements are disabled
                DIcon {
                    visible: !vArtRect.visible && !animCol.visible && !heartContainerV.visible
                    name: "music_note"
                    size: root.iconSize
                    color: Theme.widgetIconColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
