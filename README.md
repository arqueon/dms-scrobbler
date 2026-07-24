# DMS Last.fm Companion & Scrobbler

A [Dank Material Shell (DMS)](https://github.com/AvengeMedia/DankMaterialShell) companion for the official media player built into DMS. It follows DMS's canonical MPRIS selection, updates Last.fm "Now Playing", scrobbles tracks, toggles love/unlove, and opens the current artist or track on Last.fm. Its optional read-only MPRIS bridge supplies enriched artwork for the same local track and republishes remote tracks reported to the authenticated Last.fm account.

The plugin is deliberately subordinate to DMS's native media controls: playback, previous/next, seeking, volume and player selection remain exclusively in the official DMS media player. This plugin adds only Last.fm state and actions.

## Responsibilities

**DMS owns:**

- MPRIS player discovery and active-source selection
- play/pause, previous/next, seeking and volume
- the canonical media-player layout and source menu

**This companion owns:**

- Last.fm Now Playing and scrobbling
- love/unlove, artist/track links and offline queueing
- explicit scrobble delivery states: sending, accepted, queued or failed
- artwork enrichment from DMS, Last.fm track/album metadata and exact YouTube Music search matches
- optional publication of enriched local metadata and remote Last.fm playback through a read-only MPRIS source

## System Dependencies
The core plugin has **zero external package dependencies** (no `pip install` required) and runs completely out-of-the-box.
- **Python 3**: Installed on your system (uses only standard libraries: `urllib`, `json`, `hashlib`, `urllib.parse`).
- **Quickshell / Dank Material Shell**: Version `>= 1.5.0` (provides composite daemon plugins and native MPRIS tracking).
- **MPRIS-compatible player**: Any media player implementing the MPRIS D-Bus interface (e.g. Spotify, mpd, Cider, Audacious, VLC, etc.).

The optional synthetic MPRIS bridge is a small native helper. Building it requires a C compiler plus the development headers for `libsystemd` and `json-c`.

If `mpris-bridge` is absent, scrobbling, Last.fm actions and the in-plugin remote fallback continue working; only metadata enrichment/publication into DMS's native media player is disabled.

## Installation

Clone the plugin and link it into DMS. The `make` step is optional and enables publication of remote Last.fm playback in DMS's official media player:

```bash
git clone https://github.com/arqueon/dms-scrobbler.git ~/Projects/dms-scrobbler
make -C ~/Projects/dms-scrobbler
ln -s ~/Projects/dms-scrobbler ~/.config/DankMaterialShell/plugins/lastfmScrobbler
systemctl --user restart dms.service
```

---

## Configuration & Authentication Flow

Because Last.fm enforces strict rate-limits on shared API keys (which would cause scrobbling to fail randomly if all plugin users shared a single key), you must use your own free developer credentials.

### Step 1: Obtain Last.fm API Credentials
1. Go to the [Last.fm API Account Creation Page](https://www.last.fm/api/account/create).
2. Log in with your standard Last.fm account.
3. Fill in the API application form:
   - **Contact email**: Your email address.
   - **Application name**: E.g., `DMS Scrobbler` or `Dank Shell Scrobbler`.
   - **Application description**: A short description (e.g. *Last.fm companion and scrobbler for Dank Material Shell*).
   - **Callback URL** and **Homepage URL**: You can safely leave these blank.
4. Click **Submit**. Last.fm will display your **API Key** and **Shared Secret**.

### Step 2: Authenticate the Plugin
1. Open the **DMS Control Center** -> **Settings** -> **Last.fm Scrobbler**.
2. Paste your **API Key** and **Shared Secret** into the respective text fields.
3. Click **1. Authenticate**. 
   - This will automatically launch your default web browser and redirect you to the Last.fm authorization page.
4. In the browser, click **Yes, Allow Access** to grant permissions.
5. Return to the DMS Settings GUI and click **2. Confirm Authentication**.
   - The status panel will update to show: `Authenticated as: <your_username>`.
   - The session key is stored in `~/.config/DankMaterialShell/plugin_settings.json`. Note this file is **plain text** (it is not encrypted), but it lives only on your machine and is never committed to this repository. Your Last.fm password is never handled by the plugin — only the API key, shared secret, and a revocable session key are stored.

---

## Features & Customization (Settings)

You can customize the companion widget directly inside the settings page:
- **Show Love Button**: Toggle the heart (love/unlove) button on the bar. Love stays available via the popout and IPC even when hidden.
- **Show Album Art**: Renders a small square cover art thumbnail with rounded corners next to the playing track.
- **Show Music Playing Animation**: Renders a dynamic, animated sound wave representation that moves reactively when a song is playing.
- **Show Track Information**: Renders the `"Artist - Title"` text (capped at 140px with a scrolling marquee). *Note: Text is hidden on vertical panels for layout stability but remains available in the hover tooltip.*
- **Music Player Whitelist**: Comma-separated list of MPRIS identities to scrobble. The default includes common music players plus Chrome, Chromium and Firefox; browser media is accepted only when DMS can resolve both a title and an artist.
- **Scrobble Threshold**: Select the percentage of track duration that must elapse before a scrobble is sent to Last.fm (defaults to `50%` or 4 minutes, whichever comes first, on tracks longer than 30 seconds).
- **Remote Playback Fallback**: Read the authenticated account's Last.fm `Now Playing` when no usable local MPRIS source is active.
- **Enable MPRIS Metadata Bridge**: Publish the current local track with enriched artwork, or the remote Last.fm track when no local source is active, through the optional read-only bridge.
- **Debug Logging** (Advanced): Print verbose diagnostics to the DMS logs for troubleshooting. Off by default; credentials are never logged.

### Cast and remote playback

MPRIS carries controls and metadata, not the audio stream. Pavucontrol will therefore show no local application stream when playback is routed to Chromecast, AirPlay, DLNA, Spotify Connect or another remote target.

When no MPRIS player is actively playing, the optional **Remote Playback Fallback** polls the user's Last.fm `Now Playing` status every 15 seconds. This is protocol-independent and can display remote sessions reported by another scrobbler, including their loved state and Last.fm links. Tracks discovered this way are never submitted again by this plugin, preventing duplicate scrobbles. A playing MPRIS source always takes priority; remote `Now Playing` takes priority over paused or stale local metadata.

With **Enable MPRIS Metadata Bridge** enabled and the optional helper built, the bridge is exposed as `org.mpris.MediaPlayer2.dms_lastfm_remote`. While local media is active it mirrors the same canonical DMS track and contributes enriched artwork without taking over transport controls. It deliberately reports `Paused` while acting as a local metadata sidecar, so it cannot compete with the real playing source. When local media is absent it can publish remote Last.fm Now Playing as `Playing` instead. The synthetic player is informational: it publishes track, artist, album, artwork and playback status but intentionally reports play/pause, previous/next and seeking as unsupported.

DMS remains the sole authority for player selection. A control-capable local source wins over the bridge; an equivalent bridge mirror cannot displace the canonical player during pause/resume transitions.

For YouTube Music in a browser, the plugin takes artist, title and album from DMS's canonical track. If neither MPRIS nor Last.fm provides artwork, it queries the public YouTube Music search page and accepts a thumbnail only when title plus artist, or album plus artist, match. No YouTube cookies or credentials are read.

This mechanism still requires the emitting application, browser extension or service integration to send `Now Playing` to the authenticated Last.fm account. It republishes Last.fm state as MPRIS; it does not directly discover Chromecast, AirPlay, DLNA or other cast protocols.

### Mouse Actions
Each mouse button on the bar pill is configurable in settings (**Left Click**, **Middle Click / Three-Finger Tap**, **Right Click**). Available actions are limited to companion functions: *Open Popout, Toggle Love, Refresh Info, Open Artist on Last.fm, Open Track on Last.fm,* and *Nothing*. Transport actions intentionally live only in DMS.

Defaults:
- **Left Click** → Open Popout
- **Middle Click** (mouse wheel button, or a three-finger touchpad tap) → Toggle Love
- **Right Click** → Open Track on Last.fm

### Offline Queue
If a scrobble can't reach Last.fm (no network, server error, or rate limit), it is **saved to a local queue** instead of being lost (`$XDG_CACHE_HOME/dms-scrobbler/queue.json`). Queued scrobbles are automatically resent (in batches) on startup, every few minutes, and whenever connectivity is detected again. The popout shows a "scrobble(s) pending" indicator while the queue is non-empty.

Queue updates are protected by an inter-process lock and written atomically. API credentials are sent to the Python helper over standard input rather than exposed in process command lines, and malformed or failed API responses never count as successful love/unlove actions.

### Repeats & Now Playing
Replaying the same track (position jumping back to the start) is detected via MPRIS position and counts as a fresh listen, re-arming the scrobble and updating *Now Playing*. The scrobble progress bar in the popout shows how long until the current track scrobbles.

---

## Niri / Compositor Keybinds (IPC)
The plugin registers a global IPC target named `lastfmScrobbler`. You can invoke its methods from the terminal or bind them in window managers.

### Available IPC Commands
- **Toggle Love/Unlove** for the current song:
  ```bash
  dms ipc call lastfmScrobbler toggleLove
  ```
- **Love** the current song:
  ```bash
  dms ipc call lastfmScrobbler love
  ```
- **Unlove** the current song:
  ```bash
  dms ipc call lastfmScrobbler unlove
  ```
- **Check scrobbler status** (prints current track, selected source, love state and whether scrobbling is local or external):
  ```bash
  dms ipc call lastfmScrobbler status
  ```

### Niri Keybind Configuration
Add the following to your `~/.config/niri/config.kdl` to assign a shortcut (e.g., `Mod+Shift+L` to toggle Love):
```kdl
binds {
    Mod+Shift+L { spawn "dms" "ipc" "call" "lastfmScrobbler" "toggleLove"; }
}
```
