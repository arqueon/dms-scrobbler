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
    readonly property string playerWhitelist: pluginData.playerWhitelist || "spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop, chrome, firefox, chromium"
    readonly property int scrobbleThreshold: pluginData.scrobbleThreshold !== undefined ? pluginData.scrobbleThreshold : 50
    readonly property bool showPlaybackControls: pluginData.showPlaybackControls === true
    readonly property bool showMusicAnimation: pluginData.showMusicAnimation !== false
    readonly property bool showAlbumArt: pluginData.showAlbumArt !== false
    readonly property bool showTrackInfo: pluginData.showTrackInfo !== false

    function isPlayerWhitelisted(player) {
        if (!player) return false;
        var identity = "";
        var title = "";
        
        if (typeof player === "string") {
            identity = player.toLowerCase();
        } else {
            identity = (player.identity || "").toLowerCase();
            title = (player.trackTitle || "").toLowerCase();
        }
        
        var list = root.playerWhitelist.split(",").map(function(item) {
            return item.trim().toLowerCase();
        });
        
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            if (!item) continue;
            
            // 1. Substring match on identity (e.g., "chrome" matches "Google Chrome")
            if (identity.indexOf(item) !== -1 || item.indexOf(identity) !== -1) {
                return true;
            }
            
            // 2. Substring match on track title for web streams (e.g., "youtube music" whitelist item matches "Song | YouTube Music")
            if (item === "youtube music" || item === "youtube" || item === "ytmusic") {
                if (title.indexOf("youtube music") !== -1 || title.indexOf("youtube") !== -1) {
                    return true;
                }
            }
            if (item === "spotify") {
                if (title.indexOf("spotify") !== -1) {
                    return true;
                }
            }
        }
        return false;
    }

    // Smart player selection: find the best player among all available players
    readonly property MprisPlayer activePlayer: {
        var players = MprisController.availablePlayers;
        var defaultActive = MprisController.activePlayer;
        
        var best = null;
        for (var i = 0; i < players.length; i++) {
            var p = players[i];
            if (!p) continue;
            if (!isPlayerWhitelisted(p)) continue;
            
            var hasArtist = p.trackArtist && p.trackArtist.trim() !== "";
            var isPlaying = p.playbackState === MprisPlaybackState.Playing;
            
            // If currently playing and has rich metadata, it's the perfect target!
            if (isPlaying && hasArtist) {
                return p;
            }
            
            if (!best) {
                best = p;
            } else {
                var bestIsPlaying = best.playbackState === MprisPlaybackState.Playing;
                var pIsPlaying = p.playbackState === MprisPlaybackState.Playing;
                if (!bestIsPlaying && pIsPlaying) {
                    best = p;
                } else if (bestIsPlaying === pIsPlaying) {
                    var bestHasArtist = best.trackArtist && best.trackArtist.trim() !== "";
                    var pHasArtist = p.trackArtist && p.trackArtist.trim() !== "";
                    if (!bestHasArtist && pHasArtist) {
                        best = p;
                    }
                }
            }
        }
        return best || defaultActive;
    }

    readonly property string playerIdentity: activePlayer ? (activePlayer.identity || "") : ""
    readonly property int trackLength: activePlayer ? (activePlayer.length || 0) : 0
    readonly property var playbackState: activePlayer ? activePlayer.playbackState : null

    // Cleaned/parsed track details for robust scrobbling
    readonly property string trackArtist: {
        if (!activePlayer) return "";
        var artist = activePlayer.trackArtist || "";
        if (artist.trim() !== "") return artist.trim();
        
        var title = activePlayer.trackTitle || "";
        if (title.indexOf(" - YouTube Music") !== -1) {
            title = title.replace(" - YouTube Music", "");
            var parts = title.split(" - ");
            if (parts.length >= 2) return parts[1].trim();
        }
        var parts = title.split(" - ");
        if (parts.length === 2) return parts[1].trim();
        return "";
    }

    readonly property string trackTitle: {
        if (!activePlayer) return "";
        var title = activePlayer.trackTitle || "";
        var artist = activePlayer.trackArtist || "";
        if (artist.trim() !== "") return cleanTitleSuffix(title);
        
        if (title.indexOf(" - YouTube Music") !== -1) {
            title = title.replace(" - YouTube Music", "");
            var parts = title.split(" - ");
            if (parts.length >= 2) return parts[0].trim();
        }
        var parts = title.split(" - ");
        if (parts.length === 2) return parts[0].trim();
        return cleanTitleSuffix(title);
    }

    property string lastfmArtUrl: ""
    property string lastfmAlbum: ""

    readonly property string trackArtUrl: {
        if (activePlayer && activePlayer.trackArtUrl && activePlayer.trackArtUrl.trim() !== "") {
            return activePlayer.trackArtUrl;
        }
        return lastfmArtUrl;
    }

    readonly property string trackAlbum: {
        if (activePlayer && activePlayer.trackAlbum && activePlayer.trackAlbum.trim() !== "") {
            return cleanTitleSuffix(activePlayer.trackAlbum);
        }
        return lastfmAlbum;
    }

    function cleanTitleSuffix(title) {
        if (!title) return "";
        title = title.replace(" | YouTube Music", "");
        title = title.replace(" - YouTube Music", "");
        title = title.replace(" - YouTube", "");
        title = title.replace(" | YouTube", "");
        title = title.replace(" | Spotify", "");
        title = title.replace(" - Spotify", "");
        return title.trim();
    }

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



    function handleTrackChange() {
        playTimer.stop();
        playtimeCounter = 0;
        scrobbledThisTrack = false;
        isLoved = false;
        lastfmArtUrl = "";
        lastfmAlbum = "";
        trackStartTime = Math.floor(Date.now() / 1000);

        if (!activePlayer || !trackTitle || !trackArtist) {
            return;
        }

        if (!isPlayerWhitelisted(activePlayer)) {
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
        running: activePlayer && playbackState === MprisPlaybackState.Playing && isPlayerWhitelisted(activePlayer)
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
                if (json.album_art !== undefined) {
                    lastfmArtUrl = json.album_art;
                }
                if (json.album !== undefined) {
                    lastfmAlbum = json.album;
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
                   ", Whitelisted: " + isPlayerWhitelisted(activePlayer) + ")";
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
