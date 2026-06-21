# Dank Material Shell — Last.fm Scrobbler Plugin

A custom [Dank Material Shell (DMS)](https://github.com/AvengeMedia/DankMaterialShell) plugin that monitors your music playback via MPRIS, automatically updates your "Now Playing" status, scrobbles to Last.fm, and allows you to "Love" tracks directly from the bar or via IPC (e.g. for Niri/Hyprland keybinds).

It includes play, pause, and skip controls, making it a complete lightweight replacement for standard media controller plugins.

## System Dependencies
This plugin has **zero external package dependencies** (no `pip install` required) and runs completely out-of-the-box.
- **Python 3**: Installed on your system (uses only standard libraries: `urllib`, `json`, `hashlib`, `urllib.parse`).
- **Quickshell / Dank Material Shell**: Version `>= 1.2.0` (provides native MPRIS tracking).
- **MPRIS-compatible player**: Any media player implementing the MPRIS D-Bus interface (e.g. Spotify, mpd, Cider, Audacious, VLC, etc.).

## Installation
The plugin repository resides in `~/Projects/dms-scrobbler` and is symlinked to `~/.config/DankMaterialShell/plugins/lastfmScrobbler`.

To install it manually, run:
```bash
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
   - **Application description**: A short description (e.g. *Scrobbler and media controller plugin for Dank Material Shell*).
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

You can customize the widget layout directly inside the settings page:
- **Show Playback Controls**: Master switch for the previous/play-pause/next buttons next to the heart icon, turning the plugin into a media controller replacement.
  - **Previous / Play-Pause / Next Button**: Individually toggle which transport buttons appear (each requires *Show Playback Controls*).
- **Show Love Button**: Toggle the heart (love/unlove) button on the bar. Love stays available via the popout and IPC even when hidden.
- **Show Album Art**: Renders a small square cover art thumbnail with rounded corners next to the playing track.
- **Show Music Playing Animation**: Renders a dynamic, animated sound wave representation that moves reactively when a song is playing.
- **Show Track Information**: Renders the `"Artist - Title"` text (capped at 140px with a scrolling marquee). *Note: Text is hidden on vertical panels for layout stability but remains available in the hover tooltip.*
- **Music Player Whitelist**: Comma-separated list of MPRIS identities to scrobble (default: `spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop`). This avoids scrobbling YouTube videos or browser audio.
- **Scrobble Threshold**: Select the percentage of track duration that must elapse before a scrobble is sent to Last.fm (defaults to `50%` or 4 minutes, whichever comes first, on tracks longer than 30 seconds).
- **Debug Logging** (Advanced): Print verbose diagnostics to the DMS logs for troubleshooting. Off by default; credentials are never logged.

### Mouse Actions
Each mouse button on the bar pill is configurable in settings (**Left Click**, **Middle Click / Three-Finger Tap**, **Right Click**). Available actions: *Open Popout, Play/Pause, Toggle Love, Next Track, Previous Track, Refresh Info, Nothing*.

Defaults:
- **Left Click** → Open Popout
- **Middle Click** (mouse wheel button, or a three-finger touchpad tap) → Toggle Love
- **Right Click** → Play / Pause

### Offline Queue
If a scrobble can't reach Last.fm (no network, server error, or rate limit), it is **saved to a local queue** instead of being lost (`$XDG_CACHE_HOME/dms-scrobbler/queue.json`). Queued scrobbles are automatically resent (in batches) on startup, every few minutes, and whenever connectivity is detected again. The popout shows a "scrobble(s) pending" indicator while the queue is non-empty.

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
- **Check scrobbler status** (prints current track, love state, scrobble state, whitelist validation):
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
