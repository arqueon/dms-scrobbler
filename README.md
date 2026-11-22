# DMS Last.fm & ListenBrainz Scrobbler

A [Dank Material Shell (DMS)](https://github.com/AvengeMedia/DankMaterialShell) companion for the official media player built into DMS. It follows DMS's canonical MPRIS selection, updates **Last.fm** and **ListenBrainz** "Now Playing", submits scrobbles/listens, toggles love/unlove feedback on both services, and opens the current artist or recording on Last.fm or MusicBrainz/ListenBrainz. Its optional read-only MPRIS bridge supplies enriched artwork for the same local track and republishes remote tracks reported to Last.fm or ListenBrainz.

The plugin is deliberately subordinate to DMS's native media controls: playback, previous/next, seeking, volume and player selection remain exclusively in the official DMS media player. This plugin adds only scrobbling and favorite state/actions.

## Responsibilities

**DMS owns:**

- MPRIS player discovery and active-source selection
- play/pause, previous/next, seeking and volume
- the canonical media-player layout and source menu

**This companion owns:**

- Last.fm and ListenBrainz Now Playing and scrobbling / listen submission
- love/unlove sync (`track.love` / `track.unlove` on Last.fm; `/1/feedback/recording-feedback` on ListenBrainz)
- MusicBrainz MBID lookup and MessyBrainz MSID fallback so unmapped tracks can still be loved on ListenBrainz
- per-service delivery states (`sending`, `accepted`, `queued`, `partial`, `error`) and an isolated multi-service offline retry queue
- Control Center quick-tile and expandable detail card
- artwork enrichment from DMS and Last.fm metadata, with an optional YouTube Music search
- optional publication of enriched local metadata and remote Now Playing through a read-only MPRIS source

## System Dependencies
The core plugin has **zero external package dependencies** (no `pip install` required) and runs completely out-of-the-box.
- **Python 3**: Installed on your system (uses only standard libraries: `urllib`, `json`, `hashlib`, `urllib.parse`).
- **Quickshell / Dank Material Shell**: Version `>= 1.5.0` (provides composite daemon plugins and native MPRIS tracking).
- **MPRIS-compatible player**: Any media player implementing the MPRIS D-Bus interface (e.g. Spotify, mpd, Cider, Audacious, VLC, Chrome, Firefox, Feishin, Aonsoku).

The optional synthetic MPRIS bridge is a small native helper. Building it requires a C compiler plus the development headers for `libsystemd` and `json-c`.

If `mpris-bridge` is absent, scrobbling, ListenBrainz/Last.fm actions and the in-plugin remote fallback continue working; only metadata enrichment/publication into DMS's native media player is disabled.

## Installation

Clone the plugin and link or place it into DMS. The `make` step is optional and enables publication of remote playback and enriched artwork in DMS's official media player:

```bash
git clone https://github.com/arqueon/dms-scrobbler.git ~/.config/DankMaterialShell/plugins/lastfmScrobbler
make -C ~/.config/DankMaterialShell/plugins/lastfmScrobbler
dms ipc plugin-scan reload lastfmScrobbler
```

---

## Configuration & Authentication Flow

You can enable **Last.fm**, **ListenBrainz**, or **both simultaneously**.

### Last.fm Setup
1. Go to the [Last.fm API Account Creation Page](https://www.last.fm/api/account/create) and create an API application to obtain your **API Key** and **Shared Secret**.
2. Open **DMS Settings → Plugins → DMS Last.fm Scrobbler**.
3. Ensure **Enable Last.fm** is on, paste your **API Key** and **Shared Secret**.
4. Click **1. Authenticate**, approve access in your browser, then return and click **2. Confirm Auth**.

### ListenBrainz Setup
1. Visit [listenbrainz.org/settings/](https://listenbrainz.org/settings/) while logged in and copy your **User Token**.
2. Open **DMS Settings → Plugins → DMS Last.fm Scrobbler → ListenBrainz**.
3. Enable **Enable ListenBrainz** and paste your **ListenBrainz User Token**.
4. Click **Validate Token** — your ListenBrainz username will be resolved automatically and shown as `Connected as: <username>`.
5. Optionally adjust **ListenBrainz API URL** if using a self-hosted ListenBrainz-compatible server (defaults to `https://api.listenbrainz.org`).

> Credentials are saved locally in `~/.config/DankMaterialShell/plugin_settings.json` and passed to the Python helper over `stdin`, never on process command lines or in logs.

---

## Features & Customization (Settings)

- **Show Love Button / Album Art / Music Playing Animation / Track Info**: Customize what appears in the bar pill.
- **Music Player Whitelist**: Comma-separated list of MPRIS identities to scrobble.
- **Scrobble Threshold**: Percentage of track duration required before scrobbling (`50%`, `75%`, or `100%`, capped at 4 minutes, on tracks longer than 30 seconds).
- **Scrobble Notifications**: Toggle routine scrobble-success toasts (errors, offline queueing, and love actions always notify).
- **Remote Playback Fallback**: Poll Last.fm and/or ListenBrainz `Now Playing` when no local player is active (every 60s during remote playback, backing off to 10m when idle). Never re-scrobbles remote tracks.
- **Search YouTube Music for missing artwork**: Opt-in cover art lookup on `music.youtube.com` when DMS and Last.fm lack artwork.
- **Enable MPRIS Metadata Bridge**: Publish the current local track with enriched artwork, or remote Now Playing when idle, as `org.mpris.MediaPlayer2.dms_lastfm_remote`.
- **Debug Logging**: Verbose diagnostics in DMS logs (never logs secrets).

### Mouse Actions
Each mouse button on the bar pill is configurable in settings (**Left Click**, **Middle Click / Three-Finger Tap**, **Right Click**): *Open Popout, Toggle Love, Refresh Info, Open Artist on Last.fm, Open Track on Last.fm, Open Track on ListenBrainz, Open ListenBrainz Profile, Flush Offline Queue,* and *Nothing*.

### Offline Queue
If a scrobble or listen cannot reach Last.fm or ListenBrainz (no network, server error, or rate limit `429`), it is saved to an inter-process locked, atomic local queue (`$XDG_CACHE_HOME/dms-scrobbler/queue.json`) tagged per service (`lastfm` / `listenbrainz`). Queued items are automatically flushed in batches on startup, on successful online activity, and every 5 minutes — or manually via Settings, the Popout banner, or IPC.

---

## Niri / Compositor Keybinds (IPC)
The plugin keeps the immutable IPC target `lastfmScrobbler`.

### Available IPC Commands
- `dms ipc call lastfmScrobbler toggleLove` — Toggle love/unlove on all enabled services
- `dms ipc call lastfmScrobbler love` — Love current song on all enabled services
- `dms ipc call lastfmScrobbler loveListenBrainz` — Love current song on ListenBrainz only
- `dms ipc call lastfmScrobbler unlove` — Unlove current song on all enabled services
- `dms ipc call lastfmScrobbler refresh` — Refresh track metadata and love states
- `dms ipc call lastfmScrobbler flushQueue` — Flush pending offline scrobbles/listens
- `dms ipc call lastfmScrobbler status` — Print current track, source, love state, and per-service delivery status
- `dms ipc call lastfmScrobbler currentTrackJson` — JSON snapshot (includes `lastfmLoved`, `listenbrainzLoved`, `recordingMbid`, `recordingMsid`, `durationMs`)

### Niri Keybind Example
```kdl
binds {
    Mod+Alt+G { spawn-sh "dms ipc call lastfmScrobbler love"; }
    Mod+Alt+Shift+G { spawn-sh "notify-send -a 'Scrobbler' 'Status' \"$(dms ipc call lastfmScrobbler status)\""; }
}
```
