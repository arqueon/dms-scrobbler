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
   - The session key is saved securely inside `~/.config/DankMaterialShell/plugin_settings.json` (no passwords or credentials are exposed in plain text or pushed to repository history).

---

## Features & Customization (Settings)

You can customize the widget layout directly inside the settings page:
- **Show Playback Controls**: Adds previous/play-pause/next buttons to the left of the heart icon, allowing you to use this plugin as a media controller replacement.
- **Show Album Art**: Renders a small square cover art thumbnail with rounded corners next to the playing track.
- **Show Music Playing Animation**: Renders a dynamic, 3-bar animated sound wave representation that moves reactively when a song is playing.
- **Show Track Information**: Renders the `"Artist - Title"` text (capped at 140px with automatic elision). *Note: Text is hidden on vertical panels for layout stability but remains available in the hover tooltip.*
- **Music Player Whitelist**: Comma-separated list of MPRIS identities to scrobble (default: `spotify, mpd, cider, audacious, strawberry, clementine, rhythmbox, lollypop`). This avoids scrobbling YouTube videos or browser audio.
- **Scrobble Threshold**: Select the percentage of track duration that must elapse before a scrobble is sent to Last.fm (defaults to `50%` or 4 minutes, whichever comes first, on tracks longer than 30 seconds).

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
