import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import Quickshell.Services.Mpris

PluginComponent {
    id: root

    popoutWidth: 440

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

                Row {
                    width: parent.width - Theme.spacingM * 2
                    spacing: Theme.spacingL

                    // Left Column: Album Art + Player Selector
                    Column {
                        width: 150
                        spacing: Theme.spacingS

                        Rectangle {
                            width: 150
                            height: 150
                            radius: Theme.cornerRadius
                            color: Theme.surfaceVariant
                            clip: true

                            Image {
                                id: popoutArt
                                anchors.fill: parent
                                source: service ? service.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: !!(service && service.trackArtUrl)
                            }

                            DankIcon {
                                visible: !popoutArt.visible
                                name: "music_note"
                                size: 48
                                color: Theme.surfaceVariantText
                                anchors.centerIn: parent
                            }
                        }

                        StyledText {
                            text: "Media Sources"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            width: parent.width
                        }

                        ScrollView {
                            width: 150
                            height: 110
                            clip: true

                            Column {
                                width: 150
                                spacing: 4

                                Rectangle {
                                    width: 150
                                    height: 28
                                    radius: Theme.cornerRadius - 2
                                    color: (service && service.manualPlayerIdentity === "") 
                                            ? Theme.primary 
                                            : (autoMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                                    border.color: (service && service.manualPlayerIdentity === "") ? Theme.primary : "transparent"
                                    border.width: 1

                                    StyledText {
                                        text: "Auto (Smart)"
                                        anchors.centerIn: parent
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        color: (service && service.manualPlayerIdentity === "") ? Theme.onPrimary : Theme.surfaceText
                                        font.weight: (service && service.manualPlayerIdentity === "") ? Font.Bold : Font.Normal
                                    }

                                    MouseArea {
                                        id: autoMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (service) service.manualPlayerIdentity = ""
                                    }
                                }

                                Repeater {
                                    model: MprisController.availablePlayers

                                    Rectangle {
                                        required property var modelData
                                        width: 150
                                        height: 28
                                        radius: Theme.cornerRadius - 2
                                        
                                        readonly property bool isActive: service && service.activePlayer === modelData
                                        readonly property bool isSelectedManually: service && service.manualPlayerIdentity === modelData.identity
                                        
                                        color: isSelectedManually 
                                                ? Theme.primary 
                                                : (isActive ? Theme.surfaceContainerHigh : (playerItemMouse.containsMouse ? Theme.surfaceContainer : Theme.surfaceContainerLow))
                                        border.color: isActive ? Theme.primary : "transparent"
                                        border.width: 1

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 4
                                            clip: true

                                            DankIcon {
                                                name: "music_note"
                                                size: 12
                                                color: isSelectedManually ? Theme.onPrimary : (isActive ? Theme.primary : Theme.surfaceText)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                text: modelData.identity || "Player"
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                                color: isSelectedManually ? Theme.onPrimary : Theme.surfaceText
                                                font.weight: isActive ? Font.Bold : Font.Normal
                                                elide: Text.ElideRight
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 18
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
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right Column: Metadata, Controls, Scrobbler info
                    Column {
                        width: parent.width - 150 - parent.spacing
                        spacing: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: root.service ? root.service.trackTitle : "No song playing"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: root.service ? root.service.trackArtist : ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.primary
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: root.service && root.service.trackAlbum ? root.service.trackAlbum : ""
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }

                        Row {
                            spacing: Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter

                            StyledRect {
                                width: 36
                                height: 36
                                radius: 18
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

                            StyledRect {
                                width: 44
                                height: 44
                                radius: 22
                                color: loveMouseP.containsPress ? Theme.surfaceVariant : (loveMouseP.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)

                                DankIcon {
                                    name: root.isLoved ? "favorite" : "favorite_border"
                                    size: 24
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

                            StyledRect {
                                width: 36
                                height: 36
                                radius: 18
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

                // 3. Track Info (Artist - Title)
                StyledText {
                    id: trackText
                    visible: !!(service && service.showTrackInfo && root.trackDisplay !== "")
                    text: root.trackDisplay
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    width: Math.min(implicitWidth, 140)
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
