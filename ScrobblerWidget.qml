import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import Quickshell.Services.Mpris

PluginComponent {
    id: root

    popoutWidth: 280
    property bool showPlayerList: false

    readonly property var service: (pluginService && pluginId) ? pluginService.pluginInstances[pluginId] : null

    readonly property bool isLoved: service ? service.isLoved : false
    readonly property bool hasActiveMedia: !!(service && service.activePlayer && service.trackTitle && service.isPlayerWhitelisted(service.playerIdentity))
    readonly property string trackDisplay: service ? service.trackArtist + " - " + service.trackTitle : ""

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

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Last.fm Scrobbler"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM
                leftPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                bottomPadding: Theme.spacingM

                // 1. Album Cover Art (Large, Centered)
                Rectangle {
                    width: 180
                    height: 180
                    radius: Theme.cornerRadius
                    color: Theme.surfaceVariant
                    clip: true
                    anchors.horizontalCenter: parent.horizontalCenter

                    Image {
                        id: popoutArt
                        anchors.fill: parent
                        source: service ? service.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: !!(service && service.trackArtUrl)
                    }

                    // Placeholder if no cover art
                    DankIcon {
                        visible: !popoutArt.visible
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

                // 3. Playback & Love Controls Row
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

                    // Previous Track
                    StyledRect {
                        width: 38
                        height: 38
                        radius: 19
                        color: prevMouseP.containsPress ? Theme.surfaceVariant : (prevMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        visible: !!(service && service.activePlayer)

                        DankIcon {
                            name: "skip_previous"
                            size: 20
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: prevMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.previous()
                        }
                    }

                    // Play / Pause (middle)
                    StyledRect {
                        width: 44
                        height: 44
                        radius: 22
                        color: playMouseP.containsPress ? Theme.surfaceVariant : (playMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        visible: !!(service && service.activePlayer)

                        DankIcon {
                            name: service && service.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                            size: 24
                            color: Theme.primary
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: playMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.togglePlaying()
                        }
                    }

                    // Next Track
                    StyledRect {
                        width: 38
                        height: 38
                        radius: 19
                        color: nextMouseP.containsPress ? Theme.surfaceVariant : (nextMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        visible: !!(service && service.activePlayer)

                        DankIcon {
                            name: "skip_next"
                            size: 20
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: nextMouseP
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.next()
                        }
                    }
                }

                // 4. Source Selector Dropdown Button
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: Theme.cornerRadius
                    color: sourceMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2)
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "assistant_device"
                            size: 18
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: service && service.manualPlayerIdentity !== ""
                                    ? "Source: " + service.manualPlayerIdentity
                                    : "Source: Auto (Smart)"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 48
                        }

                        DankIcon {
                            name: root.showPlayerList ? "keyboard_arrow_up" : "keyboard_arrow_down"
                            size: 18
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: sourceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showPlayerList = !root.showPlayerList
                    }
                }

                // 5. Expandable Player List
                Column {
                    width: parent.width
                    spacing: 4
                    visible: root.showPlayerList

                    Rectangle {
                        width: parent.width
                        height: 32
                        radius: 4
                        color: (service && service.manualPlayerIdentity === "") 
                                ? (Theme.primary ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent") 
                                : (autoMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                        border.color: (service && service.manualPlayerIdentity === "") ? (Theme.primary || "transparent") : "transparent"
                        border.width: 1

                        StyledText {
                            text: "Auto (Smart Selection)"
                            anchors.centerIn: parent
                            font.pixelSize: Theme.fontSizeSmall
                            color: (service && service.manualPlayerIdentity === "") ? (Theme.primary || Theme.surfaceText) : Theme.surfaceText
                            font.weight: (service && service.manualPlayerIdentity === "") ? Font.Bold : Font.Normal
                        }

                        MouseArea {
                            id: autoMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (service) service.manualPlayerIdentity = "";
                                root.showPlayerList = false;
                            }
                        }
                    }

                    Repeater {
                        model: MprisController.availablePlayers

                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 32
                            radius: 4
                            
                            readonly property bool isActive: service && service.activePlayer === modelData
                            readonly property bool isSelectedManually: service && service.manualPlayerIdentity === modelData.identity
                            
                            color: isSelectedManually 
                                    ? (Theme.primary ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent") 
                                    : (isActive ? Theme.surfaceContainerHigh : (playerItemMouse.containsMouse ? Theme.surfaceContainer : Theme.surfaceContainerLow))
                            border.color: isSelectedManually ? (Theme.primary || "transparent") : (isActive && Theme.primary ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : "transparent")
                            border.width: 1

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingS
                                clip: true

                                DankIcon {
                                    name: "music_note"
                                    size: 14
                                    color: isActive ? Theme.primary : Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: modelData.identity || "Player"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: isActive ? Theme.primary : Theme.surfaceText
                                    font.weight: isActive ? Font.Bold : Font.Normal
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24
                                }
                            }

                            MouseArea {
                                id: playerItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (service) {
                                        service.manualPlayerIdentity = modelData.identity;
                                    }
                                    root.showPlayerList = false;
                                }
                            }
                        }
                    }
                }

                // 6. Source & Username footer
                StyledText {
                    width: parent.width
                    text: {
                        var str = "";
                        if (service && service.username) {
                            str += "Scrobbling as: <b>" + service.username + "</b><br/>";
                        }
                        if (service && service.activePlayer) {
                            str += "Source: " + service.playerIdentity;
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
            visible: root.hasActiveMedia
            implicitWidth: root.hasActiveMedia ? pillRow.implicitWidth : 0
            implicitHeight: root.hasActiveMedia ? (pillRow.implicitHeight || 24) : 0

            ToolTip.visible: root.hasActiveMedia && (pillMouse.containsMouse || prevMouse.containsMouse || playMouse.containsMouse || nextMouse.containsMouse || heartMouse.containsMouse)
            ToolTip.delay: 600
            ToolTip.text: root.trackDisplay + (root.isLoved ? " (Loved)" : " (Unloved)")

            // Failsafe MouseArea when controls are hidden so the whole pill is easy to click to Love.
            // Placed outside Row so it doesn't break Row layout positioning.
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                visible: service ? !service.showPlaybackControls : true
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        if (typeof root.triggerPopout === "function") {
                            root.triggerPopout();
                        } else {
                            root.toggleLove();
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        if (root.service) root.service.checkTrackInfo();
                    }
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

                // 4. Playback controls (visible conditionally)
                Row {
                    spacing: Theme.spacingXS
                    visible: service ? service.showPlaybackControls : false
                    anchors.verticalCenter: parent.verticalCenter

                    Item {
                        width: Theme.barIconSize(root.barThickness, -2)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        DankIcon {
                            name: "skip_previous"
                            size: parent.width
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.previous()
                        }
                    }

                    Item {
                        width: Theme.barIconSize(root.barThickness, -2)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        DankIcon {
                            name: service && service.activePlayer && service.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                            size: parent.width
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.togglePlaying()
                        }
                    }

                    Item {
                        width: Theme.barIconSize(root.barThickness, -2)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        DankIcon {
                            name: "skip_next"
                            size: parent.width
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.next()
                        }
                    }

                    // A subtle separator
                    StyledRect {
                        width: 1
                        height: Theme.barIconSize(root.barThickness, -4)
                        color: Theme.surfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // 5. Heart Control
                Item {
                    id: heartContainer
                    width: Theme.barIconSize(root.barThickness, -2)
                    height: width
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
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                root.toggleLove();
                            } else if (mouse.button === Qt.RightButton) {
                                if (root.service) root.service.checkTrackInfo(); // Force refresh
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.isLoved
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
            visible: root.hasActiveMedia
            implicitWidth: root.hasActiveMedia ? root.barThickness : 0
            implicitHeight: root.hasActiveMedia ? pillCol.implicitHeight : 0

            ToolTip.visible: root.hasActiveMedia && (pillMouseV.containsMouse || prevMouseV.containsMouse || playMouseV.containsMouse || nextMouseV.containsMouse || heartMouseV.containsMouse)
            ToolTip.delay: 600
            ToolTip.text: root.trackDisplay + (root.isLoved ? " (Loved)" : " (Unloved)")

            // Failsafe MouseArea when controls are hidden so the whole pill is easy to click to Love.
            // Placed outside Column so it doesn't break Column layout positioning.
            MouseArea {
                id: pillMouseV
                anchors.fill: parent
                visible: service ? !service.showPlaybackControls : true
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        if (typeof root.triggerPopout === "function") {
                            root.triggerPopout();
                        } else {
                            root.toggleLove();
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        if (root.service) root.service.checkTrackInfo();
                    }
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

                // 3. Playback controls (visible conditionally, vertical)
                Column {
                    spacing: Theme.spacingXS
                    visible: service ? service.showPlaybackControls : false
                    anchors.horizontalCenter: parent.horizontalCenter

                    Item {
                        width: Theme.barIconSize(root.barThickness, -2)
                        height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        DankIcon {
                            name: "skip_previous"
                            size: parent.width
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: prevMouseV
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.previous()
                        }
                    }

                    Item {
                        width: Theme.barIconSize(root.barThickness, -2)
                        height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        DankIcon {
                            name: service && service.activePlayer && service.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                            size: parent.width
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: playMouseV
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.togglePlaying()
                        }
                    }

                    Item {
                        width: Theme.barIconSize(root.barThickness, -2)
                        height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        DankIcon {
                            name: "skip_next"
                            size: parent.width
                            color: Theme.widgetIconColor
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: nextMouseV
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (service && service.activePlayer) service.activePlayer.next()
                        }
                    }

                    // A subtle separator
                    StyledRect {
                        width: Theme.barIconSize(root.barThickness, -4)
                        height: 1
                        color: Theme.surfaceVariant
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 4. Heart Control (vertical)
                Item {
                    id: heartContainerV
                    width: Theme.barIconSize(root.barThickness, -2)
                    height: width
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
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                root.toggleLove();
                            } else if (mouse.button === Qt.RightButton) {
                                if (root.service) root.service.checkTrackInfo(); // Force refresh
                            }
                        }
                    }
                }

            }
        }
    }
}
