#!/usr/bin/env python3
import contextlib
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

API_URL = "https://ws.audioscrobbler.com/2.0/"
YOUTUBE_MUSIC_SEARCH_URL = "https://music.youtube.com/search"
REQUEST_TIMEOUT = 15

# Last.fm error codes that are transient and worth retrying later.
# 8: operation failed, 11: service offline, 16: temporarily unavailable, 29: rate limit.
RETRYABLE_LFM_CODES = {8, 11, 16, 29}

def make_signature(params, secret):
    keys = sorted(params.keys())
    sig_str = ""
    for k in keys:
        if k in ('api_sig', 'format', 'callback'):
            continue
        sig_str += f"{k}{params[k]}"
    sig_str += secret
    return hashlib.md5(sig_str.encode('utf-8')).hexdigest()

def call_api(method, params, secret=None, is_post=False):
    params = params.copy()
    params['method'] = method
    params['format'] = 'json'
    
    if secret:
        params['api_sig'] = make_signature(params, secret)
    
    try:
        if is_post:
            data = urllib.parse.urlencode(params).encode('utf-8')
            req = urllib.request.Request(API_URL, data=data, method='POST')
        else:
            url = f"{API_URL}?{urllib.parse.urlencode(params)}"
            req = urllib.request.Request(url, method='GET')
        
        req.add_header('User-Agent', 'DMS-Scrobbler/1.4')
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            res_data = response.read().decode('utf-8')
            parsed = json.loads(res_data) if res_data.strip() else {}
            if isinstance(parsed, dict):
                http_status = getattr(response, "status", None)
                if http_status is None:
                    http_status = response.getcode()
                parsed.setdefault("http_status", http_status)
            return parsed
    except urllib.error.HTTPError as e:
        try:
            err_data = e.read().decode('utf-8')
            parsed = json.loads(err_data)
            if isinstance(parsed, dict):
                parsed.setdefault("error", e.code)
                parsed.setdefault("message", str(e))
                parsed["http_status"] = e.code
                return parsed
            return {"error": e.code, "message": err_data}
        except (UnicodeDecodeError, ValueError):
            return {"error": e.code, "message": str(e)}
        finally:
            e.close()
    except Exception as e:
        return {"error": -1, "message": str(e)}

def print_json(data):
    print(json.dumps(data))


def confirmed_write_result(result, operation):
    if not isinstance(result, dict):
        return {
            "error": -1,
            "message": f"Last.fm returned an invalid response for {operation}",
        }
    if result.get("error") is not None:
        return result
    lfm = result.get("lfm")
    if isinstance(lfm, dict) and lfm.get("status") is not None:
        if lfm.get("status") == "ok":
            return result
        return {
            "error": -1,
            "message": f"Last.fm did not confirm {operation}",
        }
    http_status = result.get("http_status")
    if isinstance(http_status, int) and 200 <= http_status < 300:
        return result
    return {
        "error": -1,
        "message": f"Last.fm did not confirm {operation}",
    }


def queue_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    directory = os.path.join(base, "dms-scrobbler")
    if os.path.islink(directory):
        raise OSError(f"Refusing symlinked queue directory: {directory}")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    directory_stat = os.stat(directory, follow_symlinks=False)
    if not os.path.isdir(directory) or directory_stat.st_uid != os.getuid():
        raise OSError(f"Unsafe queue directory: {directory}")
    os.chmod(directory, 0o700)

    path = os.path.join(directory, "queue.json")
    if os.path.lexists(path) and (os.path.islink(path) or not os.path.isfile(path)):
        raise OSError(f"Unsafe queue path: {path}")
    return path

@contextlib.contextmanager
def queue_lock():
    lock_path = queue_path() + ".lock"
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(lock_path, flags, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "r+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

def _load_queue_unlocked():
    try:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(queue_path(), flags)
        with os.fdopen(fd, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except (FileNotFoundError, ValueError, OSError):
        return []

def _save_queue_unlocked(queue):
    path = queue_path()
    directory = os.path.dirname(path)
    fd, temporary_path = tempfile.mkstemp(prefix=".queue-", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(queue, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary_path, path)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)

def load_queue():
    with queue_lock():
        return _load_queue_unlocked()

def save_queue(queue):
    with queue_lock():
        _save_queue_unlocked(queue)

def enqueue(entry):
    with queue_lock():
        queue = _load_queue_unlocked()
        queue.append(entry)
        if len(queue) > 1000:
            queue = queue[-1000:]
        _save_queue_unlocked(queue)
        return len(queue)

def is_retryable(res):
    """True if a failed API result is transient (network/server) and worth queueing."""
    err = res.get("error")
    if err is None:
        return False
    try:
        code = int(err)
    except (TypeError, ValueError):
        return False
    if code == -1:       # connection-level failure (no network, timeout, DNS)
        return True
    if code >= 500:      # HTTP server error
        return True
    return code in RETRYABLE_LFM_CODES

def largest_image(images):
    if not isinstance(images, list):
        return ""
    by_size = {}
    last_url = ""
    for image in images:
        if not isinstance(image, dict):
            continue
        candidate = image.get("#text", "")
        if not candidate:
            continue
        last_url = candidate
        by_size[image.get("size", "")] = candidate
    for size in ("mega", "extralarge", "large", "medium", "small"):
        if by_size.get(size):
            return by_size[size]
    return last_url


def _normalize_search_text(value):
    value = (value or "").translate(str.maketrans({
        "Œ": "OE",
        "œ": "oe",
        "Æ": "AE",
        "æ": "ae",
        "Ø": "O",
        "ø": "o",
        "Ł": "L",
        "ł": "l",
        "ß": "ss",
    }))
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(char for char in value if not unicodedata.combining(char))
    return re.sub(r"[^\w]+", " ", value.casefold()).strip()


def _decode_youtube_initial_data(value):
    value = re.sub(
        r"\\x([0-9a-fA-F]{2})",
        lambda match: chr(int(match.group(1), 16)),
        value,
    )
    return value.replace("\\/", "/").replace("\\\\", "\\")


def _walk_responsive_renderers(value):
    if isinstance(value, dict):
        renderer = value.get("musicResponsiveListItemRenderer")
        if isinstance(renderer, dict):
            yield renderer
        for child in value.values():
            yield from _walk_responsive_renderers(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_responsive_renderers(child)


def _runs_text(value):
    if not isinstance(value, dict):
        return ""
    runs = value.get("runs", [])
    if not isinstance(runs, list):
        return ""
    return "".join(
        run.get("text", "")
        for run in runs
        if isinstance(run, dict)
    )


def _renderer_text(renderer):
    columns = renderer.get("flexColumns", [])
    texts = []
    if isinstance(columns, list):
        for column in columns:
            data = column.get("musicResponsiveListItemFlexColumnRenderer", {})
            text = _runs_text(data.get("text", {}))
            if text:
                texts.append(text)
    title = texts[0] if texts else ""
    return title, " ".join(texts[1:])


def _core_search_title(value, artist):
    title_tokens = _normalize_search_text(value).split()
    artist_tokens = _normalize_search_text(artist).split()
    if artist_tokens and title_tokens[:len(artist_tokens)] == artist_tokens:
        title_tokens = title_tokens[len(artist_tokens):]
    decorations = {
        "audio",
        "edit",
        "lyric",
        "lyrics",
        "music",
        "official",
        "video",
        "visualizer",
    }
    return " ".join(token for token in title_tokens if token not in decorations)


def _allowed_youtube_art_url(url):
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return False
    host = (parsed.hostname or "").lower()
    return parsed.scheme == "https" and (
        host == "img.youtube.com"
        or host.endswith(".ytimg.com")
        or host.endswith(".googleusercontent.com")
    )


def _best_renderer_thumbnail(value):
    candidates = []

    def collect(node):
        if isinstance(node, dict):
            thumbnails = node.get("thumbnails")
            if isinstance(thumbnails, list):
                for thumbnail in thumbnails:
                    if not isinstance(thumbnail, dict):
                        continue
                    url = thumbnail.get("url", "")
                    if _allowed_youtube_art_url(url):
                        width = int(thumbnail.get("width", 0) or 0)
                        height = int(thumbnail.get("height", 0) or 0)
                        candidates.append((width * height, width, height, url))
            for child in node.values():
                collect(child)
        elif isinstance(node, list):
            for child in node:
                collect(child)

    collect(value)
    return max(candidates, default=(0, 0, 0, ""))


def _largest_renderer_thumbnail(value):
    return _best_renderer_thumbnail(value)[3]


def extract_youtube_music_art(html, artist, title, album_hint=""):
    match = re.search(
        r"initialData\.push\(\{path:\s*'\\/search'.*?"
        r"data:\s*'((?:\\.|[^'])*)'\}\);",
        html,
        flags=re.DOTALL,
    )
    if not match:
        return ""
    try:
        data = json.loads(_decode_youtube_initial_data(match.group(1)))
    except (UnicodeDecodeError, ValueError):
        return ""

    expected_title = _normalize_search_text(title)
    expected_core_title = _core_search_title(title, artist)
    expected_album = _normalize_search_text(album_hint)
    expected_artist_tokens = {
        token for token in _normalize_search_text(artist).split() if len(token) >= 3
    }
    if not expected_title or not expected_artist_tokens:
        return ""

    best = (0, "")
    for renderer in _walk_responsive_renderers(data):
        candidate_title, candidate_text = _renderer_text(renderer)
        normalized_title = _normalize_search_text(candidate_title)
        normalized_text = _normalize_search_text(candidate_text)
        if not normalized_title:
            continue
        is_album_result = bool(expected_album and normalized_title == expected_album)
        if normalized_title == expected_title:
            score = 100
        elif expected_title in normalized_title or normalized_title in expected_title:
            score = 70
        elif expected_core_title and _core_search_title(candidate_title, artist) == expected_core_title:
            score = 60
        elif is_album_result:
            score = 120
        else:
            continue

        metadata_tokens = set(normalized_text.split())
        artist_matches = len(expected_artist_tokens & metadata_tokens)
        minimum_artist_ratio = 0.5 if is_album_result else 0.6
        if artist_matches / len(expected_artist_tokens) < minimum_artist_ratio:
            continue
        score += artist_matches * 10
        _, width, height, art_url = _best_renderer_thumbnail(renderer)
        if width > 0 and height > 0:
            aspect_ratio = max(width, height) / min(width, height)
            if aspect_ratio <= 1.2:
                score += 25
            elif aspect_ratio >= 1.5:
                score -= 5
        if art_url and score > best[0]:
            best = (score, art_url)
    return best[1]


def get_youtube_music_art(artist, title, album_hint=""):
    terms = " ".join(value for value in (artist, title, album_hint) if value)
    query = urllib.parse.urlencode({"q": terms})
    request = urllib.request.Request(
        f"{YOUTUBE_MUSIC_SEARCH_URL}?{query}",
        headers={
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) "
                "AppleWebKit/537.36 Chrome/131.0 Safari/537.36"
            )
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            html = response.read().decode("utf-8")
    except (OSError, UnicodeDecodeError, urllib.error.URLError):
        return ""
    return extract_youtube_music_art(html, artist, title, album_hint)


def get_track_info(api_key, artist, title, username, album_hint=""):
    track_result = call_api("track.getInfo", {
        "api_key": api_key,
        "artist": artist,
        "track": title,
        "username": username,
        "autocorrect": "1",
    })
    info = {"loved": False}
    track = track_result.get("track", {})
    if isinstance(track, dict):
        if "userloved" in track:
            info["loved"] = track["userloved"] == "1"
        album_data = track.get("album", {})
        if isinstance(album_data, dict):
            if album_data.get("title"):
                info["album"] = album_data["title"]
            art_url = largest_image(album_data.get("image", []))
            if art_url:
                info["album_art"] = art_url

    album_name = info.get("album") or album_hint
    if not info.get("album_art") and album_name:
        album_result = call_api("album.getInfo", {
            "api_key": api_key,
            "artist": artist,
            "album": album_name,
            "autocorrect": "1",
        })
        album_data = album_result.get("album", {})
        if isinstance(album_data, dict):
            if album_data.get("name"):
                info["album"] = album_data["name"]
            art_url = largest_image(album_data.get("image", []))
            if art_url:
                info["album_art"] = art_url

    if not info.get("album_art"):
        art_url = get_youtube_music_art(artist, title, album_name)
        if art_url:
            info["album_art"] = art_url
            info["art_source"] = "youtube_music"

    if "error" in track_result and len(info) == 1:
        return track_result
    return info

def expand_stdin_request():
    if sys.argv[1:] != ["--stdin-json"]:
        return
    try:
        payload = json.loads(sys.stdin.readline())
        args = payload.get("args")
        if not isinstance(args, list):
            raise ValueError("args must be a list")
        if any(isinstance(arg, (dict, list)) for arg in args):
            raise ValueError("args must contain scalar values")
        sys.argv = [sys.argv[0]] + [str(arg) for arg in args]
    except (AttributeError, TypeError, ValueError) as exc:
        print_json({"error": -1, "message": f"Invalid stdin request: {exc}"})
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print_json({"error": -1, "message": "No command specified"})
        sys.exit(1)
        
    cmd = sys.argv[1]
    
    if cmd == "get-token":
        if len(sys.argv) < 4:
            print_json({"error": -1, "message": "Usage: get-token <api_key> <secret>"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        res = call_api("auth.getToken", {"api_key": api_key}, secret=secret)
        if "token" in res:
            token = res["token"]
            url = f"https://www.last.fm/api/auth/?api_key={api_key}&token={token}"
            print_json({"token": token, "url": url})
        else:
            print_json(res)
            
    elif cmd == "get-session":
        if len(sys.argv) < 5:
            print_json({"error": -1, "message": "Usage: get-session <api_key> <secret> <token>"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        token = sys.argv[4]
        res = call_api("auth.getSession", {"api_key": api_key, "token": token}, secret=secret)
        if "session" in res:
            print_json({
                "session_key": res["session"]["key"],
                "username": res["session"]["name"]
            })
        else:
            print_json(res)
            
    elif cmd == "now-playing":
        if len(sys.argv) < 7:
            print_json({"error": -1, "message": "Usage: now-playing <api_key> <secret> <session_key> <artist> <title> [album]"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]
        artist = sys.argv[5]
        title = sys.argv[6]
        album = sys.argv[7] if len(sys.argv) > 7 else ""
        
        params = {
            "api_key": api_key,
            "sk": sk,
            "artist": artist,
            "track": title,
        }
        if album:
            params["album"] = album
            
        res = call_api("track.updateNowPlaying", params, secret=secret, is_post=True)
        print_json(res)
        
    elif cmd == "scrobble":
        if len(sys.argv) < 8:
            print_json({"error": -1, "message": "Usage: scrobble <api_key> <secret> <session_key> <artist> <title> <timestamp> [album]"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]
        artist = sys.argv[5]
        title = sys.argv[6]
        ts = sys.argv[7]
        album = sys.argv[8] if len(sys.argv) > 8 else ""
        
        params = {
            "api_key": api_key,
            "sk": sk,
            "artist": artist,
            "track": title,
            "timestamp": ts,
        }
        if album:
            params["album"] = album

        res = call_api("track.scrobble", params, secret=secret, is_post=True)
        if "error" in res and is_retryable(res):
            entry = {"artist": artist, "track": title, "timestamp": ts}
            if album:
                entry["album"] = album
            try:
                size = enqueue(entry)
                print_json({"queued": True, "queue_size": size})
            except OSError as exc:
                print_json({"error": -1, "message": f"Failed to persist offline scrobble: {exc}"})
        else:
            print_json(res)

    elif cmd == "flush-queue":
        if len(sys.argv) < 5:
            print_json({"error": -1, "message": "Usage: flush-queue <api_key> <secret> <session_key>"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]

        with queue_lock():
            queue = _load_queue_unlocked()
            if not queue:
                print_json({"flushed": 0, "remaining": 0})
                return

            flushed = 0
            remaining = []
            index = 0
            while index < len(queue):
                batch = queue[index:index + 50]
                params = {"api_key": api_key, "sk": sk}
                for j, item in enumerate(batch):
                    params["artist[%d]" % j] = item.get("artist", "")
                    params["track[%d]" % j] = item.get("track", "")
                    params["timestamp[%d]" % j] = item.get("timestamp", "")
                    if item.get("album"):
                        params["album[%d]" % j] = item["album"]

                res = call_api("track.scrobble", params, secret=secret, is_post=True)
                if "error" in res:
                    remaining.extend(queue[index:])
                    break
                flushed += len(batch)
                index += 50

            _save_queue_unlocked(remaining)
        print_json({"flushed": flushed, "remaining": len(remaining)})

    elif cmd == "queue-count":
        print_json({"count": len(load_queue())})

    elif cmd == "recent-now-playing":
        if len(sys.argv) < 4:
            print_json({"error": -1, "message": "Usage: recent-now-playing <api_key> <username>"})
            sys.exit(1)
        api_key = sys.argv[2]
        username = sys.argv[3]
        res = call_api("user.getRecentTracks", {
            "api_key": api_key,
            "user": username,
            "limit": "1",
            "extended": "1",
        })
        if "error" in res:
            print_json(res)
            return
        tracks = res.get("recenttracks", {}).get("track", [])
        if isinstance(tracks, dict):
            tracks = [tracks]
        if not tracks or tracks[0].get("@attr", {}).get("nowplaying") != "true":
            print_json({"now_playing": False})
        else:
            track = tracks[0]
            artist_data = track.get("artist", {})
            artist = artist_data.get("name", "") if isinstance(artist_data, dict) else artist_data
            album_data = track.get("album", {})
            album = album_data.get("#text", "") if isinstance(album_data, dict) else album_data
            art_url = ""
            for image in track.get("image", []):
                candidate = image.get("#text", "")
                if candidate:
                    art_url = candidate
            print_json({
                "now_playing": True,
                "artist": artist,
                "track": track.get("name", ""),
                "album": album,
                "album_art": art_url,
                "loved": str(track.get("loved", "0")) == "1",
                "url": track.get("url", ""),
            })

    elif cmd == "love":
        if len(sys.argv) < 7:
            print_json({"error": -1, "message": "Usage: love <api_key> <secret> <session_key> <artist> <title>"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]
        artist = sys.argv[5]
        title = sys.argv[6]
        
        params = {
            "api_key": api_key,
            "sk": sk,
            "artist": artist,
            "track": title,
        }
        res = call_api("track.love", params, secret=secret, is_post=True)
        print_json(confirmed_write_result(res, "track.love"))
        
    elif cmd == "unlove":
        if len(sys.argv) < 7:
            print_json({"error": -1, "message": "Usage: unlove <api_key> <secret> <session_key> <artist> <title>"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]
        artist = sys.argv[5]
        title = sys.argv[6]
        
        params = {
            "api_key": api_key,
            "sk": sk,
            "artist": artist,
            "track": title,
        }
        res = call_api("track.unlove", params, secret=secret, is_post=True)
        print_json(confirmed_write_result(res, "track.unlove"))
        
    elif cmd == "get-info":
        if len(sys.argv) < 6:
            print_json({"error": -1, "message": "Usage: get-info <api_key> <artist> <title> <username> [album]"})
            sys.exit(1)
        api_key = sys.argv[2]
        artist = sys.argv[3]
        title = sys.argv[4]
        username = sys.argv[5]
        album = sys.argv[6] if len(sys.argv) > 6 else ""
        print_json(get_track_info(api_key, artist, title, username, album))
            
    else:
        print_json({"error": -1, "message": f"Unknown command: {cmd}"})
        sys.exit(1)

if __name__ == "__main__":
    expand_stdin_request()
    main()
