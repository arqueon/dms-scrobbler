import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import Quickshell.Services.Mpris

PluginComponent {
    id: root

    popoutWidth: 280
    readonly property var service: (pluginService && pluginId)
        ? (pluginService.pluginDaemonInstances[pluginId] || pluginService.pluginInstances[pluginId])
        : null

    readonly property bool isLoved: service ? service.isLoved : false
    readonly property bool hasActiveMedia: !!(service && service.hasTrack && service.trackTitle)
    readonly property string trackDisplay: service ? service.trackArtist + " - " + service.trackTitle : ""

    // Vertical-bar tooltip Y offset, mirroring DMS's native bar widgets:
    // when the vertical bar sits below a top bar (parentScreen.y > 0), shift down.
    readonly property real minTooltipY: {
        if (!parentScreen || !isVertical) return 0;
        if (parentScreen.y > 0) {
            var spacing = (barConfig && barConfig.spacing !== undefined) ? barConfig.spacing : 4;
            return barThickness + spacing;
        }
        return 0;
    }

    readonly property bool isCavaActive: {
        if (!CavaService || !CavaService.values || CavaService.values.length === 0) return false;
        for (var i = 0; i < CavaService.values.length; i++) {
            if (CavaService.values[i] > 0) return true;
        }
        return false;
    }

    function toggleLove() {
        if (service) service.toggleLoveCurrentTrack();
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
            if (service.trackArtist && service.trackArtist.length > 0) {
                Qt.openUrlExternally("https://www.last.fm/music/" + encodeURIComponent(service.trackArtist).replace(/%20/g, "+"));
            }
            break;
        case "lastfm_track":
            if (service.trackArtist && service.trackTitle) {
                Qt.openUrlExternally("https://www.last.fm/music/"
                    + encodeURIComponent(service.trackArtist).replace(/%20/g, "+")
                    + "/_/" + encodeURIComponent(service.trackTitle).replace(/%20/g, "+"));
            }
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

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "DMS Last.fm Scrobbler"
            showCloseButton: true

            Column {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingM
                topPadding: Theme.spacingM
                bottomPadding: Theme.spacingM

                // 1. Album Cover Art (Large, Centered)
                Rectangle {
                    width: 180
                    height: 180
                    radius: Theme.cornerRadius
                    color: Theme.surfaceVariant
                    anchors.horizontalCenter: parent.horizontalCenter

                    Image {
                        id: popoutArt
                        anchors.fill: parent
                        source: service ? service.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: popoutArt
                        maskEnabled: true
                        maskSource: artMask
                        visible: !!(service && service.trackArtUrl)
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

                    // Placeholder if no cover art
                    DankIcon {
                        visible: !(service && service.trackArtUrl)
                        name: "music_note"
                        size: 64
                        color: Theme.surfaceVariantText
                        anchors.centerIn: parent
                    }
                }

                // 2. Track Metadata (Title, Artist, Album)
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    anchors.horizontalCenter: parent.horizontalCenter

                    StyledText {
                        width: parent.width
                        text: root.service ? root.service.trackTitle : "No song playing"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root.service ? root.service.trackArtist : ""
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
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
                    visible: !!(service && service.canScrobbleCurrent && service.trackTitle && service.scrobbleTargetSeconds > 0)

                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.surfaceVariant

                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: parent.width * Math.max(0, Math.min(1,
                                (service ? service.playtimeCounter : 0) /
                                Math.max(1, service ? service.scrobbleTargetSeconds : 1)))
                            color: (service && service.scrobbleStatus === "error")
                                ? Theme.error
                                : ((service && service.scrobbledThisTrack) ? "#1db954" : Theme.primary)
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: (service && service.scrobbleStatus === "error")
                            ? Theme.error
                            : ((service && service.scrobbledThisTrack) ? "#1db954" : Theme.surfaceVariantText)
                        text: {
                            if (!service) return "";
                            if (service.scrobbleStatus === "accepted") return "Scrobbled ✓";
                            if (service.scrobbleStatus === "queued") return "Queued offline ✓";
                            if (service.scrobbleStatus === "sending") return "Sending…";
                            if (service.scrobbleStatus === "error") return "Scrobble failed";
                            var rem = Math.max(0, service.scrobbleTargetSeconds - service.playtimeCounter);
                            return "Scrobbles in " + rem + "s";
                        }
                    }
                }

                // 3. Last.fm actions. Playback remains in DMS's native player.
                Row {
                    spacing: Theme.spacingM
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Love / Heart button
                    StyledRect {
                        width: 38
                        height: 38
                        radius: 19
                        color: loveMouseP.containsPress ? Theme.surfaceVariant : (loveMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)

                        DankIcon {
                            name: root.isLoved ? "favorite" : "favorite_border"
                            size: 20
                            color: root.isLoved ? "#ff4b72" : Theme.widgetIconColor
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: loveMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleLove()
                        }
                    }

                    // Open artist on Last.fm
                    StyledRect {
                        width: 38
                        height: 38
                        radius: 19
                        color: prevMouseP.containsPress ? Theme.surfaceVariant : (prevMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        visible: !!(service && service.hasTrack)

                        DankIcon {
                            name: "person"
                            size: 20
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: prevMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.doAction("lastfm_artist")
                        }
                    }

                    // Open track on Last.fm
                    StyledRect {
                        width: 44
                        height: 44
                        radius: 22
                        color: playMouseP.containsPress ? Theme.surfaceVariant : (playMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        visible: !!(service && service.hasTrack)

                        DankIcon {
                            name: "open_in_new"
                            size: 24
                            color: Theme.primary
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: playMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.doAction("lastfm_track")
                        }
                    }

                    // Refresh Last.fm information
                    StyledRect {
                        width: 38
                        height: 38
                        radius: 19
                        color: nextMouseP.containsPress ? Theme.surfaceVariant : (nextMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        visible: !!(service && service.hasTrack)

                        DankIcon {
                            name: "refresh"
                            size: 20
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: nextMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.doAction("refresh")
                        }
                    }
                }

                // 4. Source & Username footer
                StyledText {
                    width: parent.width
                    text: {
                        var str = "";
                        if (service && service.username) {
                            str += "Scrobbling as: <b>" + service.username + "</b><br/>";
                        }
                        if (service && service.hasTrack) {
                            str += "Source: " + service.sourceLabel;
                            if (service.isRemoteSource) str += "<br/>Scrobble managed by external source";
                        }
                        if (service && service.pendingScrobbles > 0) {
                            str += "<br/>⏳ " + service.pendingScrobbles + " scrobble(s) pending (offline)";
                        }
                        return str;
                    }
                    font.pixelSize: Theme.fontSizeSmall - 2
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.StyledText
                }
            }
        }
    }

    horizontalBarPill: Component {
        Item {
            id: hPill
            visible: root.hasActiveMedia
            implicitWidth: root.hasActiveMedia ? pillRow.implicitWidth : 0
            implicitHeight: root.hasActiveMedia ? (pillRow.implicitHeight || 24) : 0

            // Use DMS's native DankTooltip (a separate layer-shell window) like the
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
                sourceComponent: DankTooltip {}
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
                    hTipLoader.item.show(root.trackDisplay + (root.isLoved ? " (Loved)" : " (Unloved)"),
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
                spacing: Theme.spacingS
                anchors.centerIn: parent

                // 1. Album Art Thumbnail
                Rectangle {
                    width: 20
                    height: 20
                    radius: 4
                    color: Theme.surfaceVariant
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!(service && service.showAlbumArt && service.trackArtUrl)

                    Image {
                        anchors.fill: parent
                        source: service ? service.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // 2. Music Playing Wave / Live Audio Visualizer
                MediaVisualizer {
                    id: animRow
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    barSpan: 20
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

                // 3. Track Info (Artist - Title) with marquee/scrolling animation
                Item {
                    id: trackTextClip
                    visible: !!(service && service.showTrackInfo && root.trackDisplay !== "")
                    width: trackText.needsScrolling ? 140 : trackText.implicitWidth
                    height: 20
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        id: trackText
                        property bool needsScrolling: implicitWidth > 140
                        property real scrollOffset: 0

                        text: root.trackDisplay
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.NoWrap
                        elide: needsScrolling ? Text.ElideNone : Text.ElideRight
                        x: needsScrolling ? -scrollOffset : 0
                        width: needsScrolling ? implicitWidth : parent.width

                        onTextChanged: {
                            scrollOffset = 0;
                            scrollAnim.restart();
                        }

                        SequentialAnimation {
                            id: scrollAnim
                            running: trackText.needsScrolling && trackTextClip.visible
                            loops: Animation.Infinite

                            PauseAnimation { duration: 1500 }

                            NumberAnimation {
                                target: trackText
                                property: "scrollOffset"
                                from: 0
                                to: Math.max(0, trackText.implicitWidth - 140 + 8)
                                duration: Math.max(1000, Math.round((trackText.implicitWidth - 140 + 8) / 30 * 1000))
                                easing.type: Easing.Linear
                            }

                            PauseAnimation { duration: 1500 }

                            NumberAnimation {
                                target: trackText
                                property: "scrollOffset"
                                to: 0
                                duration: Math.max(1000, Math.round((trackText.implicitWidth - 140 + 8) / 30 * 1000))
                                easing.type: Easing.Linear
                            }
                        }
                    }
                }

                // 4. Heart Control
                Item {
                    id: heartContainer
                    width: Theme.barIconSize(root.barThickness, -2)
                    height: width
                    visible: !!(service && service.showLoveButton)
                    anchors.verticalCenter: parent.verticalCenter

                    DankIcon {
                        name: root.isLoved ? "favorite" : "favorite_border"
                        size: parent.width
                        color: root.isLoved ? "#ff4b72" : Theme.widgetIconColor
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
                    visible: root.isLoved && !!(service && service.showLoveButton)
                    text: root.isLoved ? "Loved" : ""
                    color: "#ff4b72"
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.weight: Font.Bold
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
            // (it gets clipped/wrapped). DankTooltip is a separate layer-shell window
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
                sourceComponent: DankTooltip {}
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
                    vTipLoader.item.show(root.trackDisplay + (root.isLoved ? " (Loved)" : " (Unloved)"),
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
                spacing: Theme.spacingS
                anchors.horizontalCenter: parent.horizontalCenter

                // 1. Album Art Thumbnail (vertical)
                Rectangle {
                    width: 20
                    height: 20
                    radius: 4
                    color: Theme.surfaceVariant
                    clip: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!(service && service.showAlbumArt && service.trackArtUrl)

                    Image {
                        anchors.fill: parent
                        source: service ? service.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // 2. Music Playing Wave / Live Audio Visualizer (vertical)
                MediaVisualizer {
                    id: animCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    verticalMode: true
                    width: 20
                    height: 20
                    barSpan: 20
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
                    width: Theme.barIconSize(root.barThickness, -2)
                    height: width
                    visible: !!(service && service.showLoveButton)
                    anchors.horizontalCenter: parent.horizontalCenter

                    DankIcon {
                        name: root.isLoved ? "favorite" : "favorite_border"
                        size: parent.width
                        color: root.isLoved ? "#ff4b72" : Theme.widgetIconColor
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

            }
        }
    }
}
