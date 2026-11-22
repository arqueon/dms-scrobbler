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
    property var popoutService: null

    // Last.fm configuration loaded from pluginData (reactive)
    readonly property bool lastfmEnabled: pluginData.lastfmEnabled !== false
    readonly property string apiKey: pluginData.apiKey || ""
    readonly property string apiSecret: pluginData.apiSecret || ""
    readonly property string sessionKey: pluginData.sessionKey || ""
    readonly property string username: pluginData.username || ""
    readonly property bool lastfmReadConfigured: !!(lastfmEnabled && apiKey && username)
    readonly property bool lastfmConfigured: !!(lastfmEnabled && apiKey && apiSecret && sessionKey)

    // ListenBrainz configuration loaded from pluginData (reactive)
    readonly property bool listenbrainzEnabled: pluginData.listenbrainzEnabled === true
    readonly property string listenbrainzToken: (pluginData.listenbrainzToken || "").trim()
    readonly property string listenbrainzUsername: (pluginData.listenbrainzUsername || "").trim()
    readonly property string listenbrainzUrl: {
        var url = (pluginData.listenbrainzUrl || "").trim();
        return url !== "" ? url : "https://api.listenbrainz.org";
    }
    readonly property bool listenbrainzConfigured: !!(listenbrainzEnabled && listenbrainzToken)
    readonly property bool anyServiceConfigured: lastfmConfigured || listenbrainzConfigured

    // Behavior & UI configuration
    readonly property string playerWhitelist: pluginData.playerWhitelist || "spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop, chrome, firefox, chromium"
    readonly property int scrobbleThreshold: {
        var parsed = parseInt(pluginData.scrobbleThreshold, 10);
        return (!isNaN(parsed) && parsed > 0) ? parsed : 50;
    }
    readonly property bool showMusicAnimation: pluginData.showMusicAnimation !== false
    readonly property bool showAlbumArt: pluginData.showAlbumArt !== false
    readonly property bool showTrackInfo: pluginData.showTrackInfo !== false
    readonly property bool showLoveButton: pluginData.showLoveButton !== false
    readonly property bool showNotifications: pluginData.showNotifications !== false
    readonly property bool debugLogging: pluginData.debugLogging === true
    readonly property bool remoteFallbackEnabled: pluginData.remoteFallbackEnabled !== false
    readonly property bool youtubeArtEnabled: pluginData.youtubeArtEnabled === true
    readonly property bool publishRemoteMpris: pluginData.publishRemoteMpris !== false

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
    // Never pass secrets (API key/secret/session key/ListenBrainz token) to this.
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
            if (identity && (identity.indexOf(item) !== -1 || item.indexOf(identity) !== -1)) {
                return true;
            }

            // 2. Substring match on track title for web streams
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
    readonly property MprisPlayer activePlayer: canonicalPlayer
        && !isRemoteBridgePlayer(canonicalPlayer) ? canonicalPlayer : null

    property bool updatingRemote: false
    property bool remoteNowPlaying: false
    property string remoteService: ""
    property string remoteArtist: ""
    property string remoteTitle: ""
    property string remoteAlbum: ""
    property string remoteArtUrl: ""
    property string remoteTrackUrl: ""
    property string remoteRecordingMbid: ""
    property string remoteRecordingMsid: ""
    property bool remoteLoved: false
    property bool remotePollRunning: false
    property int remoteMisses: 0
    property string mprisBridgePath: ""
    property bool mprisBridgeAvailable: false
    property int bridgeRestartAttempts: 0

    readonly property string localArtist: {
        if (!activePlayer) return "";
        if (MprisController.stableArtist) return MprisController.stableArtist.trim();
        var artist = activePlayer.trackArtist || "";
        if (artist.trim() !== "") return artist.trim();
        return splitWebTitle(activePlayer.trackTitle || "").artist;
    }
    readonly property string localTitle: {
        if (!activePlayer) return "";
        if (MprisController.stableTitle) return MprisController.stableTitle.trim();
        var rawTitle = activePlayer.trackTitle || "";
        var artist = activePlayer.trackArtist || "";
        if (artist.trim() !== "") return cleanTitleSuffix(rawTitle);
        return splitWebTitle(rawTitle).title;
    }
    readonly property bool hasUsableLocalTrack: !!(activePlayer
        && isPlayerWhitelisted(activePlayer)
        && localTitle && localArtist)
        && activePlayer.playbackState !== MprisPlaybackState.Stopped
    readonly property bool isRemoteSource: !hasUsableLocalTrack && remoteNowPlaying
    readonly property bool hasTrack: hasUsableLocalTrack || isRemoteSource
    readonly property bool canScrobbleCurrent: hasUsableLocalTrack
    readonly property string sourceLabel: {
        if (isRemoteSource) {
            return remoteService === "listenbrainz"
                ? "ListenBrainz Now Playing (remote)"
                : "Last.fm Now Playing (remote)";
        }
        return activePlayer ? (activePlayer.identity || "MPRIS") : "None";
    }
    readonly property string playerIdentity: isRemoteSource
        ? (remoteService === "listenbrainz" ? "listenbrainz-remote" : "lastfm-remote")
        : (activePlayer ? (activePlayer.identity || "") : "")
    readonly property int trackLength: {
        if (!hasUsableLocalTrack || !activePlayer) return 0;
        var stable = ("activePlayerStableLength" in MprisController && MprisController.activePlayerStableLength > 0)
            ? MprisController.activePlayerStableLength
            : (activePlayer.length || 0);
        return Math.max(0, Math.round(stable));
    }
    readonly property int trackDurationMs: trackLength > 0 ? trackLength * 1000 : 0
    readonly property var playbackState: hasUsableLocalTrack ? activePlayer.playbackState : null

    readonly property string trackArtist: isRemoteSource ? remoteArtist : (hasUsableLocalTrack ? localArtist : "")
    readonly property string trackTitle: isRemoteSource ? remoteTitle : (hasUsableLocalTrack ? localTitle : "")

    property string lastfmArtUrl: ""
    property string lastfmAlbum: ""
    property string lbAlbum: ""
    property string lbRecordingMbid: ""
    property string lbRecordingMsid: ""
    property string lbReleaseMbid: ""
    property var lbArtistMbids: []

    readonly property string trackArtUrl: {
        if (isRemoteSource && remoteArtUrl) return remoteArtUrl;
        // The DMS result may initially be a thumbnail borrowed from this
        // plugin's own bridge. Once enrichment returns an album cover, publish
        // it so DMS can replace that provisional same-track artwork.
        if (lastfmArtUrl) return lastfmArtUrl;
        if (hasUsableLocalTrack && TrackArtService.artReadyFor(activePlayer)
                && TrackArtService.resolvedArtUrl)
            return TrackArtService.resolvedArtUrl;
        if (hasUsableLocalTrack && activePlayer.trackArtUrl && activePlayer.trackArtUrl.trim() !== "")
            return activePlayer.trackArtUrl;
        return "";
    }

    readonly property string trackAlbum: {
        if (isRemoteSource && remoteAlbum) return remoteAlbum;
        if (hasUsableLocalTrack && ("stableAlbum" in MprisController) && MprisController.stableAlbum)
            return MprisController.stableAlbum.trim();
        if (hasUsableLocalTrack && activePlayer.trackAlbum && activePlayer.trackAlbum.trim() !== "") {
            return cleanTitleSuffix(activePlayer.trackAlbum);
        }
        return lastfmAlbum || lbAlbum;
    }

    readonly property bool shouldPublishMpris: publishRemoteMpris
        && ((hasUsableLocalTrack && trackArtist && trackTitle)
            || (remoteFallbackEnabled && remoteNowPlaying && remoteArtist && remoteTitle))
    readonly property string bridgeArtist: hasUsableLocalTrack ? trackArtist : remoteArtist
    readonly property string bridgeTitle: hasUsableLocalTrack ? trackTitle : remoteTitle
    readonly property string bridgeAlbum: hasUsableLocalTrack ? trackAlbum : remoteAlbum
    readonly property string bridgeArtUrl: hasUsableLocalTrack ? trackArtUrl : remoteArtUrl
    // A local bridge is a metadata sidecar, never a competing playing source.
    // Remote Now Playing remains "Playing" so DMS can select it when
    // there is no local MPRIS player.
    readonly property string bridgePlaybackStatus: hasUsableLocalTrack ? "Paused" : "Playing"
    readonly property string bridgeTrackUrl: hasUsableLocalTrack
        ? ((activePlayer && activePlayer.metadata && activePlayer.metadata["xesam:url"])
            ? activePlayer.metadata["xesam:url"].toString() : "")
        : remoteTrackUrl

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

    // Per-service & aggregate playback/scrobble/love state
    property bool scrobbledThisTrack: false
    property bool scrobbleAttemptedThisTrack: false
    property string scrobbleStatus: "idle"
    property string lastfmScrobbleStatus: "idle"
    property string listenbrainzScrobbleStatus: "idle"
    property string lastfmScrobbleError: ""
    property string listenbrainzScrobbleError: ""

    property bool lastfmLoved: false
    property bool listenbrainzLoved: false
    property bool lovePending: false
    readonly property bool isLoved: {
        if (lastfmConfigured && lastfmLoved) return true;
        if (listenbrainzConfigured && listenbrainzLoved) return true;
        if (!lastfmConfigured && !listenbrainzConfigured && isRemoteSource && remoteLoved) return true;
        return false;
    }
    readonly property bool isFullyLoved: {
        if (!anyServiceConfigured) return isLoved;
        if (lastfmConfigured && !lastfmLoved) return false;
        if (listenbrainzConfigured && !listenbrainzLoved) return false;
        return true;
    }
    readonly property bool isPartiallyLoved: !!(lastfmConfigured && listenbrainzConfigured && (lastfmLoved !== listenbrainzLoved))

    property int playtimeCounter: 0
    property int trackStartTime: 0
    property real lastPosition: 0
    property int pendingScrobbles: 0
    property int pendingLastfmScrobbles: 0
    property int pendingListenBrainzScrobbles: 0
    property string scrobblerPath: ""
    property string tempToken: ""
    property string currentTrackKey: ""
    property bool lbTokenValidationRunning: false
    property bool flushRunning: false

    function updateAggregateScrobbleStatus() {
        var statuses = [];
        if (lastfmConfigured) statuses.push(lastfmScrobbleStatus);
        if (listenbrainzConfigured) statuses.push(listenbrainzScrobbleStatus);

        if (statuses.length === 0) {
            scrobbleStatus = "idle";
            return;
        }
        if (statuses.indexOf("sending") !== -1) {
            scrobbleStatus = "sending";
            return;
        }

        var hasAccepted = statuses.indexOf("accepted") !== -1;
        var hasQueued = statuses.indexOf("queued") !== -1;
        var hasError = statuses.indexOf("error") !== -1;

        if (hasAccepted || hasQueued)
            scrobbledThisTrack = true;

        if (hasError && (hasAccepted || hasQueued)) {
            scrobbleStatus = "partial";
        } else if (hasError) {
            scrobbleStatus = "error";
        } else if (hasQueued) {
            scrobbleStatus = "queued";
        } else if (hasAccepted) {
            scrobbleStatus = "accepted";
        } else {
            scrobbleStatus = "idle";
        }
    }

    onTrackTitleChanged: if (!updatingRemote) scheduleTrackChange()
    onTrackArtistChanged: if (!updatingRemote) scheduleTrackChange()
    onActivePlayerChanged: scheduleTrackChange()
    onApiKeyChanged: handleTrackChange(true)
    onUsernameChanged: handleTrackChange(true)
    onLastfmConfiguredChanged: {
        if (lastfmConfigured) {
            if (hasUsableLocalTrack) {
                updateLastFmNowPlaying();
                checkLastFmTrackInfo();
            }
            flushQueue();
        } else {
            lastfmLoved = false;
            lastfmScrobbleStatus = "idle";
            lastfmScrobbleError = "";
            updateAggregateScrobbleStatus();
        }
    }
    onListenbrainzConfiguredChanged: {
        if (listenbrainzConfigured) {
            if (!listenbrainzUsername)
                validateListenBrainzToken(true);
            if (hasUsableLocalTrack) {
                updateListenBrainzNowPlaying();
                checkListenBrainzTrackInfo();
            }
            flushQueue();
        } else {
            listenbrainzLoved = false;
            listenbrainzScrobbleStatus = "idle";
            listenbrainzScrobbleError = "";
            lbRecordingMbid = "";
            lbRecordingMsid = "";
            lbReleaseMbid = "";
            lbArtistMbids = [];
            lbAlbum = "";
            updateAggregateScrobbleStatus();
        }
    }
    onListenbrainzUsernameChanged: {
        if (listenbrainzConfigured && listenbrainzUsername && hasUsableLocalTrack)
            checkListenBrainzTrackInfo();
    }
    onShouldPublishMprisChanged: {
        if (shouldPublishMpris && mprisBridgeAvailable && !mprisBridgeProcess.running) {
            bridgeRestartAttempts = 0;
            mprisBridgeProcess.running = true;
        }
        syncRemoteMprisBridge();
    }
    onTrackArtUrlChanged: syncRemoteMprisBridge()
    onTrackAlbumChanged: {
        syncRemoteMprisBridge();
        if (hasUsableLocalTrack && trackAlbum && !lastfmArtUrl)
            trackInfoRetryTimer.restart();
    }
    onPlaybackStateChanged: syncRemoteMprisBridge()
    onHasUsableLocalTrackChanged: {
        scheduleTrackChange();
        syncRemoteMprisBridge();
    }

    Component.onCompleted: {
        var url = Qt.resolvedUrl("scrobbler.py").toString();
        root.scrobblerPath = url.indexOf("file://") === 0 ? url.substring(7) : url;
        var bridgeUrl = Qt.resolvedUrl("mpris-bridge").toString();
        root.mprisBridgePath = bridgeUrl.indexOf("file://") === 0 ? bridgeUrl.substring(7) : bridgeUrl;
        bridgeCheckProcess.running = true;
        scheduleTrackChange();
        // Auto-discover ListenBrainz username if token is configured without username
        if (listenbrainzConfigured && !listenbrainzUsername)
            validateListenBrainzToken(true);
        // Drain anything that was queued while DMS was closed / offline.
        refreshQueueCount();
        flushQueue();
    }

    Timer {
        id: trackChangeTimer
        interval: 250
        onTriggered: root.handleTrackChange()
    }

    Timer {
        id: trackInfoRetryTimer
        interval: 500
        onTriggered: root.checkTrackInfo()
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
    // Connect and other remote sessions. It only mirrors an existing
    // Now Playing report; it never scrobbles that report again.
    Timer {
        interval: root.remoteNowPlaying ? 60000 : Math.min(600000, 60000 * Math.pow(2, root.remoteMisses))
        repeat: true
        running: !!(root.remoteFallbackEnabled && !root.hasUsableLocalTrack
            && (root.lastfmReadConfigured || (root.listenbrainzEnabled && root.listenbrainzUsername)))
        triggeredOnStart: true
        onTriggered: root.pollRemoteNowPlaying()
    }

    function applyRemoteNowPlaying(serviceName, json) {
        var oldKey = remoteService + "\n" + remoteArtist + "\n" + remoteTitle;
        updatingRemote = true;
        remoteNowPlaying = json.now_playing === true;
        remoteService = remoteNowPlaying ? serviceName : "";
        remoteArtist = remoteNowPlaying ? (json.artist || "") : "";
        remoteTitle = remoteNowPlaying ? (json.track || "") : "";
        remoteAlbum = remoteNowPlaying ? (json.album || "") : "";
        remoteArtUrl = remoteNowPlaying ? (json.album_art || "") : "";
        remoteTrackUrl = remoteNowPlaying ? (json.url || "") : "";
        remoteRecordingMbid = remoteNowPlaying ? (json.recording_mbid || "") : "";
        remoteRecordingMsid = remoteNowPlaying ? (json.recording_msid || "") : "";
        remoteLoved = remoteNowPlaying && json.loved === true;
        updatingRemote = false;

        syncRemoteMprisBridge();
        var newKey = remoteService + "\n" + remoteArtist + "\n" + remoteTitle;
        if (isRemoteSource && oldKey !== newKey) {
            handleTrackChange();
        } else if (isRemoteSource) {
            if (serviceName === "lastfm") lastfmLoved = remoteLoved;
            else if (serviceName === "listenbrainz") {
                listenbrainzLoved = remoteLoved;
                lbRecordingMbid = remoteRecordingMbid;
                lbRecordingMsid = remoteRecordingMsid;
            }
            if (remoteArtUrl) lastfmArtUrl = remoteArtUrl;
            if (remoteAlbum) lastfmAlbum = remoteAlbum;
        } else if (!hasTrack) {
            handleTrackChange();
        }
    }

    function pollListenBrainzRemote(onDone) {
        if (!listenbrainzEnabled || !listenbrainzUsername) {
            if (onDone) onDone(false);
            return;
        }
        runScrobbler([
            "lb-recent-now-playing",
            listenbrainzUsername,
            listenbrainzToken,
            listenbrainzUrl
        ], function(code, output) {
            var json = parseScrobblerResult(code, output, "ListenBrainz Now Playing");
            if (json.error !== undefined) {
                dlog("LB recent Now Playing failed:", json.message || json.error);
                if (onDone) onDone(false, true);
                return;
            }
            if (json.now_playing === true) {
                applyRemoteNowPlaying("listenbrainz", json);
                if (onDone) onDone(true, false);
                return;
            }
            if (onDone) onDone(false, false);
        });
    }

    function pollRemoteNowPlaying() {
        if (remotePollRunning || !remoteFallbackEnabled || !scrobblerPath) return;
        var canLfm = lastfmReadConfigured;
        var canLb = !!(listenbrainzEnabled && listenbrainzUsername);
        if (!canLfm && !canLb) return;

        remotePollRunning = true;

        function finish(found, hadError) {
            remotePollRunning = false;
            if (found) {
                remoteMisses = 0;
            } else {
                remoteMisses = Math.min(4, remoteMisses + 1);
                if (!hadError)
                    applyRemoteNowPlaying("", { "now_playing": false });
            }
        }

        if (canLfm) {
            runScrobbler(["recent-now-playing", apiKey, username], function(code, output) {
                var json = parseScrobblerResult(code, output, "Last.fm Now Playing");
                if (json.error === undefined && json.now_playing === true) {
                    applyRemoteNowPlaying("lastfm", json);
                    finish(true, false);
                    return;
                }
                if (json.error !== undefined)
                    dlog("Last.fm recent Now Playing failed:", json.message || json.error);

                if (canLb) {
                    pollListenBrainzRemote(function(lbFound, lbErr) {
                        finish(lbFound, !!lbErr && json.error !== undefined);
                    });
                } else {
                    finish(false, json.error !== undefined);
                }
            });
        } else {
            pollListenBrainzRemote(function(lbFound, lbErr) {
                finish(lbFound, !!lbErr);
            });
        }
    }

    function syncRemoteMprisBridge() {
        if (!mprisBridgeAvailable || !mprisBridgeProcess.running) return;
        if (!shouldPublishMpris || !bridgeArtist || !bridgeTitle) {
            mprisBridgeProcess.write(JSON.stringify({ "command": "clear" }) + "\n");
            return;
        }
        mprisBridgeProcess.write(JSON.stringify({
            "command": "set",
            "artist": bridgeArtist,
            "title": bridgeTitle,
            "album": bridgeAlbum,
            "artUrl": bridgeArtUrl,
            "trackUrl": bridgeTrackUrl,
            "playbackStatus": bridgePlaybackStatus
        }) + "\n");
    }

    function scheduleTrackChange() {
        trackChangeTimer.restart();
    }

    Process {
        id: bridgeCheckProcess
        command: ["test", "-x", root.mprisBridgePath]
        running: false
        onExited: function(exitCode) {
            root.mprisBridgeAvailable = exitCode === 0;
            if (root.mprisBridgeAvailable) {
                root.bridgeRestartAttempts = 0;
                mprisBridgeProcess.running = true;
            }
        }
    }

    Timer {
        id: bridgeRestartTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.mprisBridgeAvailable && root.shouldPublishMpris && !mprisBridgeProcess.running)
                mprisBridgeProcess.running = true;
        }
    }

    Process {
        id: mprisBridgeProcess
        command: [root.mprisBridgePath]
        stdinEnabled: true
        running: false
        onStarted: {
            root.bridgeRestartAttempts = 0;
            root.syncRemoteMprisBridge();
        }
        onExited: function(exitCode) {
            root.dlog("mpris-bridge exited with code:", exitCode);
            if (root.shouldPublishMpris && root.mprisBridgeAvailable && root.bridgeRestartAttempts < 3) {
                root.bridgeRestartAttempts += 1;
                bridgeRestartTimer.restart();
            } else {
                root.mprisBridgeAvailable = false;
            }
        }
    }

    function handleTrackChange(force) {
        var nextKey = hasTrack && trackArtist && trackTitle
            ? (isRemoteSource ? ("remote:" + remoteService + "\n") : "local\n")
              + trackArtist.toLowerCase() + "\n" + trackTitle.toLowerCase()
            : "";
        if (!force && nextKey && nextKey === currentTrackKey) {
            syncRemoteMprisBridge();
            return;
        }
        currentTrackKey = nextKey;
        dlog("handleTrackChange called. activePlayer:", activePlayer ? activePlayer.identity : "null", "title:", trackTitle, "artist:", trackArtist, "lastfm:", lastfmConfigured ? "yes" : "no", "listenbrainz:", listenbrainzConfigured ? "yes" : "no");
        playtimeCounter = 0;
        scrobbledThisTrack = false;
        scrobbleAttemptedThisTrack = false;
        lastfmScrobbleStatus = "idle";
        listenbrainzScrobbleStatus = "idle";
        lastfmScrobbleError = "";
        listenbrainzScrobbleError = "";
        scrobbleStatus = "idle";

        lastfmLoved = false;
        listenbrainzLoved = false;
        lovePending = false;

        lastfmArtUrl = "";
        lastfmAlbum = "";
        lbAlbum = "";
        lbRecordingMbid = "";
        lbRecordingMsid = "";
        lbReleaseMbid = "";
        lbArtistMbids = [];

        lastPosition = 0;
        trackStartTime = Math.floor(Date.now() / 1000);

        if (!hasTrack || !trackTitle || !trackArtist) {
            dlog("handleTrackChange early return: no usable track metadata");
            return;
        }

        if (isRemoteSource) {
            if (remoteService === "listenbrainz") {
                listenbrainzLoved = remoteLoved;
                lbRecordingMbid = remoteRecordingMbid;
                lbRecordingMsid = remoteRecordingMsid;
                if (lastfmReadConfigured) checkLastFmTrackInfo();
            } else {
                lastfmLoved = remoteLoved;
                lastfmArtUrl = remoteArtUrl;
                lastfmAlbum = remoteAlbum;
                if (listenbrainzConfigured) checkListenBrainzTrackInfo();
            }
            dlog("using external Now Playing fallback; scrobbling disabled to prevent duplicates");
            return;
        }

        // 1. Update Now Playing on configured services
        updateNowPlaying();

        // 2. Fetch track metadata & love status from configured services
        checkTrackInfo();
    }

    Timer {
        id: playTimer
        interval: 1000
        repeat: true
        running: root.hasUsableLocalTrack && playbackState === MprisPlaybackState.Playing
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
        if (typeof MprisController.refreshPosition === "function")
            MprisController.refreshPosition(activePlayer);
        var pos = activePlayer.position;
        if (lastPosition > 15 && pos < 3) {
            dlog("detected track repeat (position", lastPosition.toFixed(1), "->", pos.toFixed(1), "), resetting scrobble state");
            playtimeCounter = 0;
            scrobbledThisTrack = false;
            scrobbleAttemptedThisTrack = false;
            lastfmScrobbleStatus = "idle";
            listenbrainzScrobbleStatus = "idle";
            lastfmScrobbleError = "";
            listenbrainzScrobbleError = "";
            updateAggregateScrobbleStatus();
            trackStartTime = Math.floor(Date.now() / 1000);
            updateNowPlaying();
        }
        lastPosition = pos;
    }

    // Seconds of playback required before this track scrobbles.
    // 0 means the track is too short to scrobble (Last.fm / LB guideline: skip < 30s).
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
        if (scrobbleAttemptedThisTrack) return;
        if (!activePlayer || !trackTitle || !trackArtist) return;

        var target = scrobbleTargetSeconds;
        if (target <= 0) return; // too short to scrobble

        if (playtimeCounter >= target) {
            scrobbleTrack();
        }
    }

    function runScrobbler(args, callback) {
        if (!root.scrobblerPath) {
            if (callback) callback(1, JSON.stringify({ "error": -1, "message": "Scrobbler helper is unavailable" }));
            return;
        }
        var proc = processComponent.createObject(root, {
            procCommand: ["python3", root.scrobblerPath, "--stdin-json"],
            procArgs: args,
            callback: callback
        });
        proc.running = true;
    }

    function parseScrobblerResult(code, output, context) {
        try {
            var result = JSON.parse(output);
            if (code !== 0 && result.error === undefined) {
                return { "error": code, "message": context + " failed" };
            }
            return result;
        } catch (e) {
            return {
                "error": code !== 0 ? code : -1,
                "message": context + " returned an invalid response"
            };
        }
    }

    function updateLastFmNowPlaying() {
        if (!lastfmConfigured || !trackArtist || !trackTitle) return;
        var args = [
            "now-playing",
            apiKey,
            apiSecret,
            sessionKey,
            trackArtist,
            trackTitle,
            trackAlbum
        ];
        if (trackLength > 0) args.push(trackLength.toString());
        runScrobbler(args, function(code, output) {
            var json = parseScrobblerResult(code, output, "Last.fm Now Playing update");
            if (json.error === undefined && pendingLastfmScrobbles > 0)
                flushQueue();
        });
    }

    function updateListenBrainzNowPlaying() {
        if (!listenbrainzConfigured || !trackArtist || !trackTitle) return;
        var requestKey = currentTrackKey;
        runScrobbler([
            "lb-now-playing",
            listenbrainzToken,
            trackArtist,
            trackTitle,
            trackAlbum,
            trackDurationMs.toString(),
            playerIdentity,
            listenbrainzUrl
        ], function(code, output) {
            var json = parseScrobblerResult(code, output, "ListenBrainz Now Playing update");
            if (json.error !== undefined) {
                dlog("LB now-playing failed:", json.message || json.error);
                return;
            }
            if (requestKey === currentTrackKey && json.recording_msid) {
                var hadMsid = !!lbRecordingMsid;
                lbRecordingMsid = json.recording_msid;
                if (!lbRecordingMbid && !hadMsid && listenbrainzUsername)
                    checkListenBrainzTrackInfo();
            }
            if (pendingListenBrainzScrobbles > 0)
                flushQueue();
        });
    }

    function updateNowPlaying() {
        updateLastFmNowPlaying();
        updateListenBrainzNowPlaying();
    }

    function refreshQueueCount() {
        runScrobbler(["queue-count"], function(code, output) {
            var json = parseScrobblerResult(code, output, "Queue count");
            if (json.error === undefined && json.count !== undefined) {
                pendingScrobbles = json.count;
                pendingLastfmScrobbles = json.lastfm !== undefined ? json.lastfm : json.count;
                pendingListenBrainzScrobbles = json.listenbrainz !== undefined ? json.listenbrainz : 0;
            }
        });
    }

    function flushQueue() {
        if (flushRunning) return;
        var doLfm = lastfmConfigured;
        var doLb = listenbrainzConfigured;
        if (!doLfm && !doLb) return;

        flushRunning = true;
        var remainingCalls = (doLfm ? 1 : 0) + (doLb ? 1 : 0);
        var flushedParts = [];

        function finishFlush() {
            remainingCalls -= 1;
            if (remainingCalls > 0) return;
            flushRunning = false;
            refreshQueueCount();
            if (flushedParts.length > 0) {
                ToastService.showInfo("Sent queued scrobbles to " + flushedParts.join(" & "));
            }
        }

        if (doLfm) {
            runScrobbler([
                "flush-queue",
                apiKey,
                apiSecret,
                sessionKey
            ], function(code, output) {
                var json = parseScrobblerResult(code, output, "Last.fm queue flush");
                if (json.flushed > 0) {
                    dlog("flushed", json.flushed, "Last.fm queued scrobbles, remaining", json.remaining);
                    flushedParts.push(json.flushed + " to Last.fm");
                } else if (json.error !== undefined) {
                    dlog("Last.fm queue flush failed:", json.message || json.error);
                }
                if (json.remaining !== undefined)
                    pendingLastfmScrobbles = json.remaining;
                if (json.total_remaining !== undefined)
                    pendingScrobbles = json.total_remaining;
                finishFlush();
            });
        }

        if (doLb) {
            runScrobbler([
                "lb-flush-queue",
                listenbrainzToken,
                listenbrainzUrl
            ], function(code, output) {
                var json = parseScrobblerResult(code, output, "ListenBrainz queue flush");
                if (json.flushed > 0) {
                    dlog("flushed", json.flushed, "ListenBrainz queued listens, remaining", json.remaining);
                    flushedParts.push(json.flushed + " to ListenBrainz");
                } else if (json.error !== undefined) {
                    dlog("ListenBrainz queue flush failed:", json.message || json.error);
                }
                if (json.remaining !== undefined)
                    pendingListenBrainzScrobbles = json.remaining;
                if (json.total_remaining !== undefined)
                    pendingScrobbles = json.total_remaining;
                finishFlush();
            });
        }
    }

    function _dispatchScrobble(onlyRetryFailed) {
        var wantLfm = lastfmConfigured && (!onlyRetryFailed || lastfmScrobbleStatus === "error" || lastfmScrobbleStatus === "idle");
        var wantLb = listenbrainzConfigured && (!onlyRetryFailed || listenbrainzScrobbleStatus === "error" || listenbrainzScrobbleStatus === "idle");
        if (!wantLfm && !wantLb) return;
        if (!trackArtist || !trackTitle) return;

        var artist = trackArtist;
        var title = trackTitle;
        var album = trackAlbum;
        var timestamp = trackStartTime > 0 ? trackStartTime.toString() : Math.floor(Date.now() / 1000).toString();
        var durationSec = trackLength;
        var durationMs = trackDurationMs;
        var player = playerIdentity;
        var recMbid = lbRecordingMbid;
        var relMbid = lbReleaseMbid;
        var artMbids = (lbArtistMbids || []).join(",");
        var requestKey = currentTrackKey;

        scrobbleAttemptedThisTrack = true;
        if (wantLfm) {
            lastfmScrobbleStatus = "sending";
            lastfmScrobbleError = "";
        }
        if (wantLb) {
            listenbrainzScrobbleStatus = "sending";
            listenbrainzScrobbleError = "";
        }
        updateAggregateScrobbleStatus();

        var tracker = {
            remaining: (wantLfm ? 1 : 0) + (wantLb ? 1 : 0),
            accepted: [],
            queued: [],
            failed: []
        };

        function onTargetFinished() {
            tracker.remaining -= 1;
            if (tracker.remaining > 0) return;

            refreshQueueCount();
            if (tracker.accepted.length > 0)
                flushQueue();

            if (tracker.failed.length > 0) {
                ToastService.showError("Scrobble failed (" + tracker.failed.join("; ") + ")");
            } else if (tracker.queued.length > 0 && tracker.accepted.length === 0) {
                ToastService.showInfo("Offline — queued for " + tracker.queued.join(" & ") + ": " + artist + " - " + title);
            } else if (tracker.queued.length > 0 && tracker.accepted.length > 0) {
                ToastService.showInfo("Scrobbled to " + tracker.accepted.join(" & ") + " (queued " + tracker.queued.join(" & ") + "): " + artist + " - " + title);
            } else if (tracker.accepted.length > 0 && root.showNotifications) {
                ToastService.showInfo("Scrobbled to " + tracker.accepted.join(" & ") + ": " + artist + " - " + title);
            }
        }

        if (wantLfm) {
            var lfmArgs = [
                "scrobble",
                apiKey,
                apiSecret,
                sessionKey,
                artist,
                title,
                timestamp,
                album
            ];
            if (durationSec > 0) lfmArgs.push(durationSec.toString());

            runScrobbler(lfmArgs, function(code, output) {
                var json = parseScrobblerResult(code, output, "Last.fm scrobble");
                if (json.queued) {
                    if (currentTrackKey === requestKey) {
                        lastfmScrobbleStatus = "queued";
                        lastfmScrobbleError = "";
                    }
                    tracker.queued.push("Last.fm");
                } else if (json.scrobbles && json.scrobbles["@attr"] && json.scrobbles["@attr"].accepted > 0) {
                    if (currentTrackKey === requestKey) {
                        lastfmScrobbleStatus = "accepted";
                        lastfmScrobbleError = "";
                    }
                    tracker.accepted.push("Last.fm");
                } else if (json.error !== undefined) {
                    var lfmMsg = json.message || String(json.error);
                    if (currentTrackKey === requestKey) {
                        lastfmScrobbleStatus = "error";
                        lastfmScrobbleError = lfmMsg;
                    }
                    tracker.failed.push("Last.fm: " + lfmMsg);
                } else {
                    if (currentTrackKey === requestKey) {
                        lastfmScrobbleStatus = "error";
                        lastfmScrobbleError = "Unexpected response";
                    }
                    tracker.failed.push("Last.fm: Unexpected response");
                }
                if (currentTrackKey === requestKey) updateAggregateScrobbleStatus();
                onTargetFinished();
            });
        }

        if (wantLb) {
            runScrobbler([
                "lb-scrobble",
                listenbrainzToken,
                artist,
                title,
                timestamp,
                album,
                durationMs.toString(),
                player,
                recMbid,
                relMbid,
                artMbids,
                listenbrainzUrl
            ], function(code, output) {
                var json = parseScrobblerResult(code, output, "ListenBrainz scrobble");
                if (json.queued) {
                    if (currentTrackKey === requestKey) {
                        listenbrainzScrobbleStatus = "queued";
                        listenbrainzScrobbleError = "";
                    }
                    tracker.queued.push("ListenBrainz");
                } else if (json.accepted === true || json.status === "ok") {
                    if (currentTrackKey === requestKey) {
                        listenbrainzScrobbleStatus = "accepted";
                        listenbrainzScrobbleError = "";
                    }
                    tracker.accepted.push("ListenBrainz");
                } else {
                    var lbMsg = json.message || (json.error !== undefined ? String(json.error) : "Unexpected response");
                    if (currentTrackKey === requestKey) {
                        listenbrainzScrobbleStatus = "error";
                        listenbrainzScrobbleError = lbMsg;
                    }
                    tracker.failed.push("ListenBrainz: " + lbMsg);
                }
                if (currentTrackKey === requestKey) updateAggregateScrobbleStatus();
                onTargetFinished();
            });
        }
    }

    function scrobbleTrack() {
        _dispatchScrobble(false);
    }

    function retryScrobble() {
        if (!hasUsableLocalTrack) return;
        _dispatchScrobble(true);
    }

    function checkLastFmTrackInfo() {
        if (!lastfmReadConfigured || !trackArtist || !trackTitle) return;
        var requestKey = currentTrackKey;
        dlog("running Last.fm get-info for:", trackArtist, "-", trackTitle);
        var args = [
            "get-info",
            apiKey,
            trackArtist,
            trackTitle,
            username,
            trackAlbum
        ];
        if (youtubeArtEnabled)
            args.push("--youtube-art");
        runScrobbler(args, function(code, output) {
            dlog("Last.fm get-info exited with code:", code);
            var json = parseScrobblerResult(code, output, "Last.fm track info");
            if (json.error !== undefined) {
                dlog("Last.fm get-info failed:", json.message || json.error);
                return;
            }
            if (requestKey !== currentTrackKey)
                return;
            if (json.loved !== undefined) {
                lastfmLoved = json.loved;
                dlog("Last.fm loved state is:", lastfmLoved);
            }
            if (json.album_art !== undefined) {
                lastfmArtUrl = json.album_art;
                dlog("cover art URL set");
            }
            if (json.album !== undefined)
                lastfmAlbum = json.album;
            syncRemoteMprisBridge();
        });
    }

    function checkListenBrainzTrackInfo() {
        if (!listenbrainzConfigured || !trackArtist || !trackTitle) return;
        var requestKey = currentTrackKey;
        dlog("running ListenBrainz get-info for:", trackArtist, "-", trackTitle);
        runScrobbler([
            "lb-get-info",
            listenbrainzToken,
            listenbrainzUsername,
            trackArtist,
            trackTitle,
            trackAlbum,
            lbRecordingMsid,
            listenbrainzUrl
        ], function(code, output) {
            var json = parseScrobblerResult(code, output, "ListenBrainz track info");
            if (json.error !== undefined) {
                dlog("LB get-info failed:", json.message || json.error);
                return;
            }
            if (requestKey !== currentTrackKey)
                return;
            if (json.loved !== undefined) {
                listenbrainzLoved = json.loved === true;
                dlog("LB loved state is:", listenbrainzLoved);
            }
            if (json.recording_mbid)
                lbRecordingMbid = json.recording_mbid;
            if (json.recording_msid && !lbRecordingMsid)
                lbRecordingMsid = json.recording_msid;
            if (json.release_mbid)
                lbReleaseMbid = json.release_mbid;
            if (json.artist_mbids && json.artist_mbids.length !== undefined)
                lbArtistMbids = json.artist_mbids;
            if (json.album && !lbAlbum)
                lbAlbum = json.album;
        });
    }

    function checkTrackInfo() {
        checkLastFmTrackInfo();
        checkListenBrainzTrackInfo();
    }

    function _setLoveState(loving, includeLastFm, includeListenBrainz) {
        if (!trackArtist || !trackTitle) {
            ToastService.showError("No track is currently playing.");
            return;
        }
        var doLfm = includeLastFm && lastfmConfigured;
        var doLb = includeListenBrainz && listenbrainzConfigured;
        if (!doLfm && !doLb) {
            ToastService.showError("No scrobbling service is configured in DMS Last.fm & ListenBrainz Scrobbler.");
            return;
        }
        if (lovePending) return;

        lovePending = true;
        var artist = trackArtist;
        var title = trackTitle;
        var album = trackAlbum;
        var mbid = lbRecordingMbid;
        var msid = lbRecordingMsid;
        var requestKey = currentTrackKey;
        var actionWord = loving ? "Loved" : "Unloved";

        var tracker = {
            remaining: (doLfm ? 1 : 0) + (doLb ? 1 : 0),
            succeeded: [],
            failed: []
        };

        function finishLove() {
            tracker.remaining -= 1;
            if (tracker.remaining > 0) return;

            lovePending = false;
            if (tracker.failed.length > 0 && tracker.succeeded.length === 0) {
                ToastService.showError((loving ? "Love" : "Unlove") + " failed: " + tracker.failed.join("; "));
            } else if (tracker.failed.length > 0) {
                ToastService.showError(actionWord + " on " + tracker.succeeded.join(" & ") + ", failed on " + tracker.failed.join("; "));
            } else {
                var targetSuffix = tracker.succeeded.length > 1 ? " (" + tracker.succeeded.join(" & ") + ")" : "";
                ToastService.showInfo(actionWord + targetSuffix + ": " + artist + " - " + title);
            }
        }

        if (doLfm) {
            runScrobbler([
                loving ? "love" : "unlove",
                apiKey,
                apiSecret,
                sessionKey,
                artist,
                title
            ], function(code, output) {
                var json = parseScrobblerResult(code, output, loving ? "Last.fm love" : "Last.fm unlove");
                if (json.error !== undefined) {
                    tracker.failed.push("Last.fm: " + (json.message || json.error));
                } else {
                    if (currentTrackKey === requestKey) {
                        lastfmLoved = loving;
                        if (isRemoteSource && remoteService === "lastfm")
                            remoteLoved = loving;
                    }
                    tracker.succeeded.push("Last.fm");
                }
                finishLove();
            });
        }

        if (doLb) {
            runScrobbler([
                loving ? "lb-love" : "lb-unlove",
                listenbrainzToken,
                listenbrainzUsername,
                artist,
                title,
                album,
                mbid,
                msid,
                listenbrainzUrl
            ], function(code, output) {
                var json = parseScrobblerResult(code, output, loving ? "ListenBrainz love" : "ListenBrainz unlove");
                if (json.error !== undefined) {
                    tracker.failed.push("ListenBrainz: " + (json.message || json.error));
                } else {
                    if (currentTrackKey === requestKey) {
                        listenbrainzLoved = loving;
                        if (json.recording_mbid) lbRecordingMbid = json.recording_mbid;
                        if (json.recording_msid) lbRecordingMsid = json.recording_msid;
                        if (isRemoteSource && remoteService === "listenbrainz")
                            remoteLoved = loving;
                    }
                    tracker.succeeded.push("ListenBrainz");
                }
                finishLove();
            });
        }
    }

    function loveCurrentTrack() {
        _setLoveState(true, true, true);
    }

    function unloveCurrentTrack() {
        _setLoveState(false, true, true);
    }

    function loveListenBrainzOnly() {
        _setLoveState(true, false, true);
    }

    function toggleLoveCurrentTrack() {
        if (isLoved) {
            unloveCurrentTrack();
        } else {
            loveCurrentTrack();
        }
    }

    // Auth & account helpers triggered from Settings
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
            var json = parseScrobblerResult(code, output, "Last.fm authentication");
            if (json.token && json.url) {
                tempToken = json.token;
                Qt.openUrlExternally(json.url);
                ToastService.showInfo("Please authorize the app in your browser, then click 'Confirm Authentication'.");
            } else {
                ToastService.showError("Auth error: " + (json.message || json.error || "Unknown"));
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
            var json = parseScrobblerResult(code, output, "Last.fm session exchange");
            if (json.session_key && json.username) {
                pluginService.savePluginData(pluginId, "sessionKey", json.session_key);
                pluginService.savePluginData(pluginId, "username", json.username);
                tempToken = "";
                ToastService.showInfo("Successfully authenticated on Last.fm as " + json.username + "!");
            } else {
                ToastService.showError("Session exchange failed: " + (json.message || json.error || "Unknown"));
            }
        });
    }

    function disconnectLastFm() {
        if (!pluginService) return;
        tempToken = "";
        pluginService.savePluginData(pluginId, "sessionKey", "");
        pluginService.savePluginData(pluginId, "username", "");
        lastfmLoved = false;
        ToastService.showInfo("Disconnected Last.fm session.");
    }

    function validateListenBrainzToken(silent) {
        if (!listenbrainzToken) {
            if (!silent)
                ToastService.showError("Enter your ListenBrainz User Token first.");
            return;
        }
        if (lbTokenValidationRunning) return;
        lbTokenValidationRunning = true;
        if (!silent)
            ToastService.showInfo("Validating ListenBrainz token...");
        runScrobbler([
            "lb-validate-token",
            listenbrainzToken,
            listenbrainzUrl
        ], function(code, output) {
            lbTokenValidationRunning = false;
            var json = parseScrobblerResult(code, output, "ListenBrainz token validation");
            if (json.valid === true && json.username) {
                if (pluginService)
                    pluginService.savePluginData(pluginId, "listenbrainzUsername", json.username);
                if (!silent)
                    ToastService.showInfo("ListenBrainz connected as " + json.username + "!");
            } else {
                if (pluginService && json.valid === false)
                    pluginService.savePluginData(pluginId, "listenbrainzUsername", "");
                if (!silent)
                    ToastService.showError("ListenBrainz token error: " + (json.message || json.error || "Invalid token"));
            }
        });
    }

    function disconnectListenBrainz() {
        if (!pluginService) return;
        pluginService.savePluginData(pluginId, "listenbrainzToken", "");
        pluginService.savePluginData(pluginId, "listenbrainzUsername", "");
        listenbrainzLoved = false;
        lbRecordingMbid = "";
        lbRecordingMsid = "";
        lbReleaseMbid = "";
        lbArtistMbids = [];
        ToastService.showInfo("Cleared ListenBrainz credentials.");
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

        function loveListenBrainz(): string {
            if (!hasTrack || !trackTitle) return "No track playing";
            if (!root.listenbrainzConfigured) return "ListenBrainz is not configured";
            root.loveListenBrainzOnly();
            return "Loving on ListenBrainz: " + root.trackArtist + " - " + root.trackTitle;
        }

        function refresh(): string {
            if (!hasTrack || !trackTitle) return "No track playing";
            root.checkTrackInfo();
            return "Refreshing metadata: " + root.trackArtist + " - " + root.trackTitle;
        }

        function flushQueue(): string {
            root.flushQueue();
            return "Flushing offline queue (" + root.pendingScrobbles + " pending)";
        }

        function status(): string {
            if (!hasTrack || !trackTitle) {
                return "No track playing" + (root.pendingScrobbles > 0 ? " (" + root.pendingScrobbles + " queued)" : "");
            }
            var parts = [];
            if (root.lastfmConfigured)
                parts.push("Last.fm: " + root.lastfmScrobbleStatus + (root.lastfmLoved ? " ♥" : ""));
            if (root.listenbrainzConfigured)
                parts.push("LB: " + root.listenbrainzScrobbleStatus + (root.listenbrainzLoved ? " ♥" : ""));
            var svcSummary = parts.length > 0 ? " | " + parts.join(", ") : "";
            return "Playing: " + root.trackArtist + " - " + root.trackTitle +
                   " [" + sourceLabel + "]" +
                   " (Loved: " + root.isLoved +
                   ", Scrobbled: " + root.scrobbledThisTrack +
                   ", Delivery: " + root.scrobbleStatus +
                   ", Queued: " + root.pendingScrobbles +
                   ", Scrobble source: " + (canScrobbleCurrent ? "this plugin" : "external") +
                   svcSummary + ")";
        }

        function currentTrackJson(): string {
            return JSON.stringify({
                "hasTrack": root.hasTrack,
                "artist": root.trackArtist,
                "track": root.trackTitle,
                "album": root.trackAlbum,
                "artwork": root.trackArtUrl,
                "loved": root.isLoved,
                "lastfmLoved": root.lastfmLoved,
                "listenbrainzLoved": root.listenbrainzLoved,
                "lastfmConfigured": root.lastfmConfigured,
                "listenbrainzConfigured": root.listenbrainzConfigured,
                "recordingMbid": root.lbRecordingMbid,
                "recordingMsid": root.lbRecordingMsid,
                "releaseMbid": root.lbReleaseMbid,
                "durationMs": root.trackDurationMs,
                "source": root.sourceLabel,
                "isLocal": root.hasUsableLocalTrack
            });
        }

        function getArtUrls(): string {
            return "trackArtUrl: '" + root.trackArtUrl
                + "' | dmsResolvedArtUrl: '" + TrackArtService.resolvedArtUrl
                + "' | dmsArtReady: " + (root.activePlayer ? TrackArtService.artReadyFor(root.activePlayer) : false)
                + " | enrichedArtUrl: '" + root.lastfmArtUrl
                + "' | path: '" + root.scrobblerPath + "'";
        }
    }

    Component {
        id: processComponent
        Item {
            id: procWrapper
            property var procCommand: []
            property var procArgs: []
            property var callback: null
            property string outputBuffer: ""
            property string stderrBuffer: ""
            property bool finished: false
            property alias running: procItem.running

            Process {
                id: procItem
                command: procWrapper.procCommand
                stdinEnabled: true

                stdout: SplitParser {
                    splitMarker: ""
                    onRead: function(data) {
                        procWrapper.outputBuffer += data;
                    }
                }

                stderr: SplitParser {
                    splitMarker: ""
                    onRead: function(data) {
                        procWrapper.stderrBuffer += data;
                    }
                }

                onStarted: write(JSON.stringify({ "args": procWrapper.procArgs }) + "\n")

                onExited: function(exitCode) {
                    if (procWrapper.finished) return;
                    procWrapper.finished = true;
                    timeoutTimer.stop();
                    root.dlog("process exited with code:", exitCode, "buffered output length:", procWrapper.outputBuffer.length);
                    if (procWrapper.stderrBuffer.length > 0)
                        root.dlog("helper stderr:", procWrapper.stderrBuffer.trim());
                    if (procWrapper.callback) procWrapper.callback(exitCode, procWrapper.outputBuffer);
                    procWrapper.destroy();
                }
            }

            Timer {
                id: timeoutTimer
                interval: 30000
                repeat: false
                running: procItem.running
                onTriggered: {
                    if (procWrapper.finished) return;
                    procWrapper.finished = true;
                    procItem.running = false;
                    root.dlog("helper process timed out");
                    if (procWrapper.callback)
                        procWrapper.callback(124, JSON.stringify({ "error": -1, "message": "Scrobbler helper timed out" }));
                    procWrapper.destroy();
                }
            }
        }
    }
}
