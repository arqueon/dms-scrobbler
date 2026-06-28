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
    readonly property bool showMusicAnimation: pluginData.showMusicAnimation !== false
    readonly property bool showAlbumArt: pluginData.showAlbumArt !== false
    readonly property bool showTrackInfo: pluginData.showTrackInfo !== false
    readonly property bool debugLogging: pluginData.debugLogging === true
    readonly property bool remoteFallbackEnabled: pluginData.remoteFallbackEnabled !== false
    readonly property bool publishRemoteMpris: pluginData.publishRemoteMpris !== false

    readonly property bool showLoveButton: pluginData.showLoveButton !== false

    function companionAction(value, fallback) {
        // Migrate settings from pre-1.3 releases, when the plugin duplicated
        // transport controls that now belong exclusively to DMS.
        if (value === "playpause" || value === "next" || value === "previous")
            return fallback;
        return value || fallback;
    }

    // Companion-only mouse actions on the bar pill.
    readonly property string pillLeftAction: companionAction(pluginData.pillLeftAction, "popout")
    readonly property string pillMiddleAction: companionAction(pluginData.pillMiddleAction, "love")
    readonly property string pillRightAction: companionAction(pluginData.pillRightAction, "lastfm_track")

    // Gated logger: only emits when the user enables Debug Logging in settings.
    // Never pass secrets (API key/secret/session key) to this.
    function dlog() {
        if (!root.debugLogging) return;
        var parts = [];
        for (var i = 0; i < arguments.length; i++) parts.push(arguments[i]);
        console.log("ScrobblerService:", parts.join(" "));
    }

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

    function isRemoteBridgePlayer(player) {
        return !!(player && (player.identity || "") === "DMS Last.fm Remote");
    }

    readonly property MprisPlayer canonicalPlayer: MprisController.activePlayer
    readonly property MprisPlayer realPlayingPlayer: {
        var players = MprisController.availablePlayers;
        for (var i = 0; i < players.length; i++) {
            var player = players[i];
            if (player && !isRemoteBridgePlayer(player) && player.isPlaying && isPlayerWhitelisted(player))
                return player;
        }
        return null;
    }
    readonly property MprisPlayer bridgePlayer: {
        var players = MprisController.availablePlayers;
        for (var i = 0; i < players.length; i++) {
            if (isRemoteBridgePlayer(players[i])) return players[i];
        }
        return null;
    }
    // Follow the source selected in DMS. The bridge itself is represented by
    // the Last.fm fallback properties below, not consumed again as local MPRIS.
    readonly property MprisPlayer activePlayer: canonicalPlayer
        && !isRemoteBridgePlayer(canonicalPlayer) ? canonicalPlayer : null

    property bool updatingRemote: false
    property bool remoteNowPlaying: false
    property string remoteArtist: ""
    property string remoteTitle: ""
    property string remoteAlbum: ""
    property string remoteArtUrl: ""
    property string remoteTrackUrl: ""
    property bool remoteLoved: false
    property bool remotePollRunning: false
    property string mprisBridgePath: ""
    property bool mprisBridgeAvailable: false
    readonly property bool shouldPublishRemoteMpris: publishRemoteMpris
        && remoteFallbackEnabled && remoteNowPlaying

    readonly property bool hasLocalMetadata: !!(activePlayer
        && isPlayerWhitelisted(activePlayer)
        && cleanTitleSuffix(activePlayer.trackTitle || ""))
    readonly property bool hasUsableLocalTrack: hasLocalMetadata
        && activePlayer.playbackState !== MprisPlaybackState.Stopped
        && (activePlayer.playbackState === MprisPlaybackState.Playing || !remoteNowPlaying)
    readonly property bool isRemoteSource: !hasUsableLocalTrack && remoteNowPlaying
    readonly property bool hasTrack: hasUsableLocalTrack || isRemoteSource
    readonly property bool canScrobbleCurrent: hasUsableLocalTrack
    readonly property string sourceLabel: isRemoteSource ? "Last.fm Now Playing (remote)" : (activePlayer ? (activePlayer.identity || "MPRIS") : "None")
    readonly property string playerIdentity: isRemoteSource ? "lastfm-remote" : (activePlayer ? (activePlayer.identity || "") : "")
    readonly property int trackLength: hasUsableLocalTrack ? (activePlayer.length || 0) : 0
    readonly property var playbackState: hasUsableLocalTrack ? activePlayer.playbackState : null

    // Cleaned/parsed track details for robust scrobbling.
    // Native MPRIS metadata (Spotify, mpd, ...) is trusted as-is; only web sources
    // (browsers exposing "Artist - Title" in the window title) are parsed/cleaned.
    readonly property string trackArtist: {
        if (isRemoteSource) return remoteArtist;
        if (!hasUsableLocalTrack) return "";
        var artist = activePlayer.trackArtist || "";
        if (artist.trim() !== "") return artist.trim();
        return splitWebTitle(activePlayer.trackTitle || "").artist;
    }

    readonly property string trackTitle: {
        if (isRemoteSource) return remoteTitle;
        if (!hasUsableLocalTrack) return "";
        var rawTitle = activePlayer.trackTitle || "";
        var artist = activePlayer.trackArtist || "";
        if (artist.trim() !== "") return cleanTitleSuffix(rawTitle);
        return splitWebTitle(rawTitle).title;
    }

    property string lastfmArtUrl: ""
    property string lastfmAlbum: ""

    readonly property string trackArtUrl: {
        if (isRemoteSource && remoteArtUrl) return remoteArtUrl;
        if (hasUsableLocalTrack && activePlayer.trackArtUrl && activePlayer.trackArtUrl.trim() !== "") {
            return activePlayer.trackArtUrl;
        }
        return lastfmArtUrl;
    }

    readonly property string trackAlbum: {
        if (isRemoteSource && remoteAlbum) return remoteAlbum;
        if (hasUsableLocalTrack && activePlayer.trackAlbum && activePlayer.trackAlbum.trim() !== "") {
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

    // Remove bracketed video/web decorations like "(Official Video)", "[Lyrics]", "(HD)".
    // Deliberately conservative: keeps meaningful parentheticals such as
    // "(feat. X)", "(Remastered)", "(Live)", "(Acoustic)" intact for accurate scrobbles.
    function stripDecorations(s) {
        if (!s) return "";
        var deco = /\s*[\(\[][^\)\]]*\b(official|lyric|lyrics|visualizer|video|mv|hd|hq|4k)\b[^\)\]]*[\)\]]/gi;
        return s.replace(deco, "").replace(/\s{2,}/g, " ").trim();
    }

    // Parse a web/browser window title of the form "Artist - Title" into components.
    // Splits on the FIRST " - " so titles containing extra hyphens stay intact.
    function splitWebTitle(rawTitle) {
        var title = cleanTitleSuffix(rawTitle);
        var idx = title.indexOf(" - ");
        if (idx === -1) {
            return { "artist": "", "title": stripDecorations(title) };
        }
        var artist = title.substring(0, idx).trim();
        var rest = title.substring(idx + 3).trim();
        return { "artist": artist, "title": stripDecorations(rest) };
    }

    property bool scrobbledThisTrack: false
    property bool isLoved: false
    property int playtimeCounter: 0
    property int trackStartTime: 0
    property real lastPosition: 0
    property int pendingScrobbles: 0
    property string scrobblerPath: ""
    property string tempToken: ""

    onTrackTitleChanged: if (!updatingRemote) handleTrackChange()
    onTrackArtistChanged: if (!updatingRemote) handleTrackChange()
    onActivePlayerChanged: handleTrackChange()
    onApiKeyChanged: handleTrackChange()
    onUsernameChanged: handleTrackChange()
    onShouldPublishRemoteMprisChanged: syncRemoteMprisBridge()
    onRealPlayingPlayerChanged: selectAutomaticMprisSource()
    onBridgePlayerChanged: selectAutomaticMprisSource()

    Component.onCompleted: {
        var url = Qt.resolvedUrl("scrobbler.py").toString();
        root.scrobblerPath = url.indexOf("file://") === 0 ? url.substring(7) : url;
        var bridgeUrl = Qt.resolvedUrl("mpris-bridge").toString();
        root.mprisBridgePath = bridgeUrl.indexOf("file://") === 0 ? bridgeUrl.substring(7) : bridgeUrl;
        bridgeCheckProcess.running = true;
        handleTrackChange();
        // Drain anything that was queued while DMS was closed / offline.
        refreshQueueCount();
        flushQueue();
    }

    // Periodically retry sending any scrobbles queued while offline.
    Timer {
        id: flushTimer
        interval: 300000 // 5 minutes
        repeat: true
        running: true
        onTriggered: flushQueue()
    }

    // Protocol-independent fallback for Chromecast, AirPlay, DLNA, Spotify
    // Connect and other remote sessions. It only mirrors an existing Last.fm
    // Now Playing report; it never scrobbles that report again.
    Timer {
        interval: 15000
        repeat: true
        running: !!(root.remoteFallbackEnabled && root.apiKey && root.username)
        triggeredOnStart: true
        onTriggered: root.pollRemoteNowPlaying()
    }

    function pollRemoteNowPlaying() {
        if (remotePollRunning || !remoteFallbackEnabled || !apiKey || !username || !scrobblerPath) return;
        remotePollRunning = true;
        runScrobbler(["recent-now-playing", apiKey, username], function(code, output) {
            remotePollRunning = false;
            try {
                var json = JSON.parse(output);
                if (json.error !== undefined) return;
                var oldKey = remoteArtist + "\n" + remoteTitle;
                updatingRemote = true;
                remoteNowPlaying = json.now_playing === true;
                remoteArtist = remoteNowPlaying ? (json.artist || "") : "";
                remoteTitle = remoteNowPlaying ? (json.track || "") : "";
                remoteAlbum = remoteNowPlaying ? (json.album || "") : "";
                remoteArtUrl = remoteNowPlaying ? (json.album_art || "") : "";
                remoteTrackUrl = remoteNowPlaying ? (json.url || "") : "";
                remoteLoved = remoteNowPlaying && json.loved === true;
                updatingRemote = false;
                syncRemoteMprisBridge();
                var newKey = remoteArtist + "\n" + remoteTitle;
                if (isRemoteSource && oldKey !== newKey) handleTrackChange();
                else if (isRemoteSource) {
                    isLoved = remoteLoved;
                    if (remoteArtUrl) lastfmArtUrl = remoteArtUrl;
                    if (remoteAlbum) lastfmAlbum = remoteAlbum;
                }
                else if (!hasTrack) handleTrackChange();
            } catch (e) {
                updatingRemote = false;
                dlog("failed to parse recent Now Playing:", e);
            }
        });
    }

    function syncRemoteMprisBridge() {
        if (!mprisBridgeAvailable || !mprisBridgeProcess.running) return;
        if (!shouldPublishRemoteMpris || !remoteArtist || !remoteTitle) {
            mprisBridgeProcess.write(JSON.stringify({ "command": "clear" }) + "\n");
            return;
        }
        mprisBridgeProcess.write(JSON.stringify({
            "command": "set",
            "artist": remoteArtist,
            "title": remoteTitle,
            "album": remoteAlbum,
            "artUrl": remoteArtUrl,
            "trackUrl": remoteTrackUrl
        }) + "\n");
    }

    function selectAutomaticMprisSource() {
        // A transition to a real playing source wins automatically. Manual
        // selection of the bridge is then respected until playback state changes.
        if (realPlayingPlayer) {
            MprisController.setActivePlayer(realPlayingPlayer);
        } else if (bridgePlayer && remoteNowPlaying) {
            MprisController.setActivePlayer(bridgePlayer);
        }
    }

    Process {
        id: bridgeCheckProcess
        command: ["test", "-x", root.mprisBridgePath]
        running: false
        onExited: function(exitCode) {
            root.mprisBridgeAvailable = exitCode === 0;
            if (root.mprisBridgeAvailable) mprisBridgeProcess.running = true;
        }
    }

    Process {
        id: mprisBridgeProcess
        command: [root.mprisBridgePath]
        stdinEnabled: true
        running: false
        onStarted: root.syncRemoteMprisBridge()
        onExited: root.mprisBridgeAvailable = false
    }



    function handleTrackChange() {
        dlog("handleTrackChange called. activePlayer:", activePlayer ? activePlayer.identity : "null", "title:", trackTitle, "artist:", trackArtist, "configured:", apiKey ? "yes" : "no", "username:", username);
        playTimer.stop();
        playtimeCounter = 0;
        scrobbledThisTrack = false;
        isLoved = false;
        lastfmArtUrl = "";
        lastfmAlbum = "";
        lastPosition = 0;
        trackStartTime = Math.floor(Date.now() / 1000);

        if (!hasTrack || !trackTitle || !trackArtist) {
            dlog("handleTrackChange early return: no usable track metadata");
            return;
        }

        if (isRemoteSource) {
            isLoved = remoteLoved;
            lastfmArtUrl = remoteArtUrl;
            lastfmAlbum = remoteAlbum;
            dlog("using external Last.fm Now Playing fallback; scrobbling disabled to prevent duplicates");
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
            checkForRepeat();
            playtimeCounter += 1;
            checkScrobbleThreshold();
        }
    }

    // Detect a track being replayed from the start (position jumps back near 0
    // while the same title/artist is loaded). MPRIS reports position in seconds.
    function checkForRepeat() {
        if (!activePlayer || !activePlayer.positionSupported) return;
        var pos = activePlayer.position;
        if (lastPosition > 15 && pos < 3) {
            dlog("detected track repeat (position", lastPosition.toFixed(1), "->", pos.toFixed(1), "), resetting scrobble state");
            playtimeCounter = 0;
            scrobbledThisTrack = false;
            trackStartTime = Math.floor(Date.now() / 1000);
            updateNowPlaying();
        }
        lastPosition = pos;
    }

    // Seconds of playback required before this track scrobbles.
    // 0 means the track is too short to scrobble (Last.fm guideline: skip < 30s).
    readonly property int scrobbleTargetSeconds: {
        var minLength = 30;
        if (trackLength > 0) {
            if (trackLength < minLength) return 0;
            var percentageThreshold = Math.floor(trackLength * (scrobbleThreshold / 100));
            return Math.min(percentageThreshold, 240);
        }
        return 240; // unknown length: fall back to the 4-minute cap
    }

    function checkScrobbleThreshold() {
        if (scrobbledThisTrack) return;
        if (!activePlayer || !trackTitle || !trackArtist) return;

        var target = scrobbleTargetSeconds;
        if (target <= 0) return; // too short to scrobble

        if (playtimeCounter >= target) {
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
            // A successful now-playing means the network is reachable again,
            // so opportunistically drain any queued scrobbles.
            try {
                var json = JSON.parse(output);
                if (!json.error && pendingScrobbles > 0) flushQueue();
            } catch(e) {}
        });
    }

    function refreshQueueCount() {
        runScrobbler(["queue-count"], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.count !== undefined) pendingScrobbles = json.count;
            } catch(e) {}
        });
    }

    function flushQueue() {
        if (!apiKey || !apiSecret || !sessionKey) return;
        runScrobbler([
            "flush-queue",
            apiKey,
            apiSecret,
            sessionKey
        ], function(code, output) {
            try {
                var json = JSON.parse(output);
                if (json.flushed > 0) {
                    dlog("flushed", json.flushed, "queued scrobbles, remaining", json.remaining);
                    ToastService.showInfo("Sent " + json.flushed + " queued scrobble(s) to Last.fm");
                }
                if (json.remaining !== undefined) pendingScrobbles = json.remaining;
            } catch(e) {}
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
                if (json.queued) {
                    // Network was down: it's safely persisted and will be retried.
                    // Keep scrobbledThisTrack=true so we don't enqueue duplicates.
                    pendingScrobbles = json.queue_size !== undefined ? json.queue_size : pendingScrobbles;
                    ToastService.showInfo("Offline — scrobble queued: " + artist + " - " + title);
                } else if (json.scrobbles && json.scrobbles["@attr"] && json.scrobbles["@attr"].accepted > 0) {
                    ToastService.showInfo("Scrobbled to Last.fm: " + artist + " - " + title);
                    flushQueue(); // network is up; drain anything pending
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
        dlog("running get-info for:", trackArtist, "-", trackTitle);
        runScrobbler([
            "get-info",
            apiKey,
            trackArtist,
            trackTitle,
            username
        ], function(code, output) {
            dlog("get-info exited with code:", code);
            try {
                var json = JSON.parse(output);
                if (json.loved !== undefined) {
                    isLoved = json.loved;
                    dlog("loved state is:", isLoved);
                }
                if (json.album_art !== undefined) {
                    lastfmArtUrl = json.album_art;
                    dlog("cover art URL set");
                }
                if (json.album !== undefined) {
                    lastfmAlbum = json.album;
                }
            } catch(e) {
                dlog("failed to parse get-info output:", e);
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
            if (!hasTrack || !trackTitle) return "No track playing";
            root.loveCurrentTrack();
            return "Loving track: " + root.trackArtist + " - " + root.trackTitle;
        }

        function unlove(): string {
            if (!hasTrack || !trackTitle) return "No track playing";
            root.unloveCurrentTrack();
            return "Unloving track: " + root.trackArtist + " - " + root.trackTitle;
        }

        function toggleLove(): string {
            if (!hasTrack || !trackTitle) return "No track playing";
            var oldState = root.isLoved;
            root.toggleLoveCurrentTrack();
            return "Toggled love: " + (oldState ? "Unloving" : "Loving") + " " + root.trackArtist + " - " + root.trackTitle;
        }

        function status(): string {
            if (!hasTrack || !trackTitle) return "No track playing";
            return "Playing: " + root.trackArtist + " - " + root.trackTitle +
                   " [" + sourceLabel + "]" +
                   " (Loved: " + root.isLoved + 
                   ", Scrobbled: " + root.scrobbledThisTrack + 
                   ", Scrobble source: " + (canScrobbleCurrent ? "this plugin" : "external") + ")";
        }

        function getArtUrls(): string {
            return "trackArtUrl: '" + root.trackArtUrl + "' | lastfmArtUrl: '" + root.lastfmArtUrl + "' | path: '" + root.scrobblerPath + "'";
        }
    }

    Component {
        id: processComponent
        Process {
            property var procCommand: []
            property var callback: null
            property string outputBuffer: ""
            command: procCommand
            stdout: SplitParser { 
                splitMarker: ""
                onRead: function(data) {
                    outputBuffer += data;
                }
            }
            onExited: function(exitCode) {
                root.dlog("process exited with code:", exitCode, "buffered output length:", outputBuffer.length);
                if (callback) callback(exitCode, outputBuffer);
                destroy();
            }
        }
    }
}
