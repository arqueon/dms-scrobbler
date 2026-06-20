import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import Quickshell.Services.Mpris

PluginComponent {
    id: root

    pluginId: "lastfmScrobbler"

    // Configuration loaded from pluginData (reactive)
    readonly property string apiKey: pluginData.apiKey || ""
    readonly property string apiSecret: pluginData.apiSecret || ""
    readonly property string sessionKey: pluginData.sessionKey || ""
    readonly property string username: pluginData.username || ""
    readonly property string playerWhitelist: pluginData.playerWhitelist || "spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop"
    readonly property int scrobbleThreshold: pluginData.scrobbleThreshold !== undefined ? pluginData.scrobbleThreshold : 50
    readonly property bool showPlaybackControls: pluginData.showPlaybackControls === true
    readonly property bool showMusicAnimation: pluginData.showMusicAnimation !== false
    readonly property bool showAlbumArt: pluginData.showAlbumArt !== false
    readonly property bool showTrackInfo: pluginData.showTrackInfo !== false

    // State properties
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string playerIdentity: activePlayer ? (activePlayer.identity || "") : ""
    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string trackAlbum: activePlayer ? (activePlayer.trackAlbum || "") : ""
    readonly property int trackLength: activePlayer ? (activePlayer.length || 0) : 0
    readonly property var playbackState: activePlayer ? activePlayer.playbackState : null

    property bool scrobbledThisTrack: false
    property bool isLoved: false
    property int playtimeCounter: 0
    property int trackStartTime: 0
    property string scrobblerPath: ""
    property string tempToken: ""

    onTrackTitleChanged: handleTrackChange()
    onTrackArtistChanged: handleTrackChange()
    onActivePlayerChanged: handleTrackChange()

    Component.onCompleted: {
        var url = Qt.resolvedUrl("scrobbler.py").toString();
        root.scrobblerPath = url.indexOf("file://") === 0 ? url.substring(7) : url;
    }

    function isPlayerWhitelisted(identity) {
        if (!identity) return false;
        var list = root.playerWhitelist.split(",").map(function(item) {
            return item.trim().toLowerCase();
        });
        return list.indexOf(identity.toLowerCase()) !== -1;
    }

    function handleTrackChange() {
        playTimer.stop();
        playtimeCounter = 0;
        scrobbledThisTrack = false;
        isLoved = false;
        trackStartTime = Math.floor(Date.now() / 1000);

        if (!activePlayer || !trackTitle || !trackArtist) {
            return;
        }

        if (!isPlayerWhitelisted(playerIdentity)) {
            return;
        }

        // Restart timer
        playTimer.start();

        // 1. Update Now Playing on Last.fm
        updateNowPlaying();

        // 2. Fetch track info from Last.fm to check if loved
        checkTrackInfo();
    }

    Timer {
        id: playTimer
        interval: 1000
        repeat: true
        running: activePlayer && playbackState === MprisPlaybackState.Playing && isPlayerWhitelisted(playerIdentity)
        onTriggered: {
            playtimeCounter += 1;
            checkScrobbleThreshold();
        }
    }

    function checkScrobbleThreshold() {
        if (scrobbledThisTrack) return;
        if (!activePlayer || !trackTitle || !trackArtist) return;

        var threshold = 240; // 4 minutes default / fallback
        var minLength = 30;

        if (trackLength > 0) {
            if (trackLength < minLength) {
                return; // Song is too short to scrobble according to Last.fm guidelines
            }
            var percentageThreshold = Math.floor(trackLength * (scrobbleThreshold / 100));
            threshold = Math.min(percentageThreshold, 240);
        }

        if (playtimeCounter >= threshold) {
            scrobbleTrack();
        }
    }

    function runScrobbler(args, callback) {
        if (!root.scrobblerPath) return;
        var fullArgs = [root.scrobblerPath].concat(args);
        var proc = processComponent.createObject(root, {
            procCommand: ["python3"].concat(fullArgs),
            callback: callback
        });
        proc.running = true;
    }

    function updateNowPlaying() {
        if (!apiKey || !apiSecret || !sessionKey) return;
        runScrobbler([
            "now-playing",
            apiKey,
            apiSecret,
            sessionKey,
            trackArtist,
            trackTitle,
            trackAlbum
        ], function(code, output) {
            // Quiet update
        });
    }

    function scrobbleTrack() {
        if (!apiKey || !apiSecret || !sessionKey) return;
        
        var artist = trackArtist;
        var title = trackTitle;
        var album = trackAlbum;
        var timestamp = trackStartTime.toString();

        scrobbledThisTrack = true; // Set early to prevent double execution

        runScrobbler([
            "scrobble",
            apiKey,
            apiSecret,
            sessionKey,
            artist,
            title,
            timestamp,
            album
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.scrobbles && json.scrobbles["@attr"] && json.scrobbles["@attr"].accepted > 0) {
                    ToastService.showInfo("Scrobbled to Last.fm: " + artist + " - " + title);
                } else if (json.error) {
                    scrobbledThisTrack = false;
                    ToastService.showError("Last.fm scrobble failed: " + (json.message || json.error));
                }
            } catch(e) {
                scrobbledThisTrack = false;
                ToastService.showError("Failed to parse scrobble response");
            }
        });
    }

    function checkTrackInfo() {
        if (!apiKey || !username) return;
        runScrobbler([
            "get-info",
            apiKey,
            trackArtist,
            trackTitle,
            username
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.loved !== undefined) {
                    isLoved = json.loved;
                }
            } catch(e) {
                // Ignore parsing errors for get-info
            }
        });
    }

    function loveCurrentTrack() {
        if (!apiKey || !apiSecret || !sessionKey || !trackArtist || !trackTitle) {
            ToastService.showError("Last.fm plugin is not configured or no track is playing.");
            return;
        }
        var artist = trackArtist;
        var title = trackTitle;
        runScrobbler([
            "love",
            apiKey,
            apiSecret,
            sessionKey,
            artist,
            title
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.error) {
                    ToastService.showError("Last.fm love failed: " + (json.message || json.error));
                } else {
                    isLoved = true;
                    ToastService.showInfo("Loved: " + artist + " - " + title);
                }
            } catch(e) {
                isLoved = true;
                ToastService.showInfo("Loved: " + artist + " - " + title);
            }
        });
    }

    function unloveCurrentTrack() {
        if (!apiKey || !apiSecret || !sessionKey || !trackArtist || !trackTitle) {
            ToastService.showError("Last.fm plugin is not configured or no track is playing.");
            return;
        }
        var artist = trackArtist;
        var title = trackTitle;
        runScrobbler([
            "unlove",
            apiKey,
            apiSecret,
            sessionKey,
            artist,
            title
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.error) {
                    ToastService.showError("Last.fm unlove failed: " + (json.message || json.error));
                } else {
                    isLoved = false;
                    ToastService.showInfo("Unloved: " + artist + " - " + title);
                }
            } catch(e) {
                isLoved = false;
                ToastService.showInfo("Unloved: " + artist + " - " + title);
            }
        });
    }

    function toggleLoveCurrentTrack() {
        if (isLoved) {
            unloveCurrentTrack();
        } else {
            loveCurrentTrack();
        }
    }

    // Auth flows triggered from Settings
    function startAuthFlow() {
        if (!apiKey || !apiSecret) {
            ToastService.showError("API Key and Shared Secret are required for authentication.");
            return;
        }
        ToastService.showInfo("Getting authentication token...");
        runScrobbler([
            "get-token",
            apiKey,
            apiSecret
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.token && json.url) {
                    tempToken = json.token;
                    Qt.openUrlExternally(json.url);
                    ToastService.showInfo("Please authorize the app in your browser, then click 'Confirm Authentication'.");
                } else {
                    ToastService.showError("Auth error: " + (json.message || json.error || "Unknown"));
                }
            } catch(e) {
                ToastService.showError("Failed to parse auth token response.");
            }
        });
    }

    function completeAuthFlow() {
        if (!tempToken) {
            ToastService.showError("No active authentication flow. Click 'Authenticate' first.");
            return;
        }
        ToastService.showInfo("Confirming session...");
        runScrobbler([
            "get-session",
            apiKey,
            apiSecret,
            tempToken
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.session_key && json.username) {
                    pluginService.savePluginData(pluginId, "sessionKey", json.session_key);
                    pluginService.savePluginData(pluginId, "username", json.username);
                    tempToken = "";
                    ToastService.showInfo("Successfully authenticated as " + json.username + "!");
                } else {
                    ToastService.showError("Session exchange failed: " + (json.message || json.error || "Unknown"));
                }
            } catch(e) {
                ToastService.showError("Failed to parse session response.");
            }
        });
    }

    // IPC Interface
    IpcHandler {
        target: "lastfmScrobbler"

        function love(): string {
            if (!activePlayer || !trackTitle) return "No track playing";
            root.loveCurrentTrack();
            return "Loving track: " + root.trackArtist + " - " + root.trackTitle;
        }

        function unlove(): string {
            if (!activePlayer || !trackTitle) return "No track playing";
            root.unloveCurrentTrack();
            return "Unloving track: " + root.trackArtist + " - " + root.trackTitle;
        }

        function toggleLove(): string {
            if (!activePlayer || !trackTitle) return "No track playing";
            var oldState = root.isLoved;
            root.toggleLoveCurrentTrack();
            return "Toggled love: " + (oldState ? "Unloving" : "Loving") + " " + root.trackArtist + " - " + root.trackTitle;
        }

        function status(): string {
            if (!activePlayer) return "No player active";
            if (!trackTitle) return "No track playing";
            return "Playing: " + root.trackArtist + " - " + root.trackTitle + 
                   " [" + playerIdentity + "]" +
                   " (Loved: " + root.isLoved + 
                   ", Scrobbled: " + root.scrobbledThisTrack + 
                   ", Whitelisted: " + isPlayerWhitelisted(playerIdentity) + ")";
        }
    }

    Component {
        id: processComponent
        Process {
            property var procCommand: []
            property var callback: null
            property string outputBuffer: ""
            command: procCommand
            stdout: SplitParser { splitMarker: ""; onRead: data => outputBuffer += data }
            onExited: function(exitCode) {
                if (callback) callback(exitCode, outputBuffer);
                destroy();
            }
        }
    }
}
