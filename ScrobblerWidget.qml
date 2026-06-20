import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import Quickshell.Services.Mpris

PluginComponent {
    id: root

    popoutWidth: 240

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

                // 1. Album Cover Art (Large)
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

                // 3. Love & Playback Controls Row
                Row {
                    spacing: Theme.spacingM
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Previous Track
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

                    // Play / Pause / Love (middle)
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

                    // Next Track
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

                // 4. Source & Username footer
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
                Row {
                    id: animRow
                    spacing: 2
                    width: 18
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!(service && service.showMusicAnimation && service.activePlayer && service.playbackState === MprisPlaybackState.Playing)

                    Repeater {
                        model: 5
                        Rectangle {
                            width: 2
                            // Use live Cava frequencies if available, fallback to scale animation
                            height: (root.isCavaActive && CavaService.values.length > index) 
                                    ? Math.max(3, Math.min(16, CavaService.values[index] / 100 * 13 + 3))
                                    : 16
                            radius: 1
                            color: Theme.primary
                            anchors.bottom: parent.bottom
                            
                            transform: Scale {
                                id: scaleTransformH
                                origin.y: 16
                                yScale: 1.0
                            }

                            SequentialAnimation {
                                loops: Animation.Infinite
                                running: !!(service && service.playbackState === MprisPlaybackState.Playing && service.showMusicAnimation && !root.isCavaActive)
                                
                                PropertyAnimation {
                                    target: scaleTransformH
                                    property: "yScale"
                                    to: index === 0 ? 0.2 : (index === 1 ? 0.9 : (index === 2 ? 0.4 : (index === 3 ? 0.7 : 0.3)))
                                    duration: index === 0 ? 350 : (index === 1 ? 250 : (index === 2 ? 450 : (index === 3 ? 300 : 400)))
                                    easing.type: Easing.InOutQuad
                                }
                                PropertyAnimation {
                                    target: scaleTransformH
                                    property: "yScale"
                                    to: index === 0 ? 0.8 : (index === 1 ? 0.3 : (index === 2 ? 0.9 : (index === 3 ? 0.5 : 0.7)))
                                    duration: index === 0 ? 250 : (index === 1 ? 450 : (index === 2 ? 350 : (index === 3 ? 400 : 300)))
                                    easing.type: Easing.InOutQuad
                                }
                                PropertyAnimation {
                                    target: scaleTransformH
                                    property: "yScale"
                                    to: index === 0 ? 0.5 : (index === 1 ? 0.7 : (index === 2 ? 0.2 : (index === 3 ? 0.9 : 0.4)))
                                    duration: index === 0 ? 450 : (index === 1 ? 350 : (index === 2 ? 250 : (index === 3 ? 350 : 450)))
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }
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
                Row {
                    spacing: 2
                    width: 18
                    height: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!(service && service.showMusicAnimation && service.activePlayer && service.playbackState === MprisPlaybackState.Playing)

                    Repeater {
                        model: 5
                        Rectangle {
                            width: 2
                            height: (root.isCavaActive && CavaService.values.length > index) 
                                    ? Math.max(3, Math.min(16, CavaService.values[index] / 100 * 13 + 3))
                                    : 16
                            radius: 1
                            color: Theme.primary
                            anchors.bottom: parent.bottom
                            
                            transform: Scale {
                                id: scaleTransformV
                                origin.y: 16
                                yScale: 1.0
                            }

                            SequentialAnimation {
                                loops: Animation.Infinite
                                running: !!(service && service.playbackState === MprisPlaybackState.Playing && service.showMusicAnimation && !root.isCavaActive)
                                
                                PropertyAnimation {
                                    target: scaleTransformV
                                    property: "yScale"
                                    to: index === 0 ? 0.2 : (index === 1 ? 0.9 : (index === 2 ? 0.4 : (index === 3 ? 0.7 : 0.3)))
                                    duration: index === 0 ? 350 : (index === 1 ? 250 : (index === 2 ? 450 : (index === 3 ? 300 : 400)))
                                    easing.type: Easing.InOutQuad
                                }
                                PropertyAnimation {
                                    target: scaleTransformV
                                    property: "yScale"
                                    to: index === 0 ? 0.8 : (index === 1 ? 0.3 : (index === 2 ? 0.9 : (index === 3 ? 0.5 : 0.7)))
                                    duration: index === 0 ? 250 : (index === 1 ? 450 : (index === 2 ? 350 : (index === 3 ? 400 : 300)))
                                    easing.type: Easing.InOutQuad
                                }
                                PropertyAnimation {
                                    target: scaleTransformV
                                    property: "yScale"
                                    to: index === 0 ? 0.5 : (index === 1 ? 0.7 : (index === 2 ? 0.2 : (index === 3 ? 0.9 : 0.4)))
                                    duration: index === 0 ? 450 : (index === 1 ? 350 : (index === 2 ? 250 : (index === 3 ? 350 : 450)))
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }
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
