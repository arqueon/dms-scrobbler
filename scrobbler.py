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
LB_DEFAULT_URL = "https://api.listenbrainz.org"
YOUTUBE_MUSIC_SEARCH_URL = "https://music.youtube.com/search"
LASTFM_PLACEHOLDER_ART = "2a96cbd8b46e442fc41c2b86b821562f"
USER_AGENT = "DMS-Scrobbler/1.5"
CLIENT_NAME = "DMS Scrobbler"
CLIENT_VERSION = "1.5.0"
REQUEST_TIMEOUT = 15

# Last.fm error codes that are transient and worth retrying later.
# 8: operation failed, 11: service offline, 16: temporarily unavailable, 29: rate limit.
RETRYABLE_LFM_CODES = {8, 11, 16, 29}
# ListenBrainz transient HTTP/network error codes.
RETRYABLE_LB_CODES = {-1, 429}


def make_signature(params, secret):
    keys = sorted(params.keys())
    sig_str = ""
    for k in keys:
        if k in ("api_sig", "format", "callback"):
            continue
        sig_str += f"{k}{params[k]}"
    sig_str += secret
    return hashlib.md5(sig_str.encode("utf-8")).hexdigest()


def call_api(method, params, secret=None, is_post=False):
    params = params.copy()
    params["method"] = method
    params["format"] = "json"

    if secret:
        params["api_sig"] = make_signature(params, secret)

    try:
        if is_post:
            data = urllib.parse.urlencode(params).encode("utf-8")
            req = urllib.request.Request(API_URL, data=data, method="POST")
        else:
            url = f"{API_URL}?{urllib.parse.urlencode(params)}"
            req = urllib.request.Request(url, method="GET")

        req.add_header("User-Agent", USER_AGENT)
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            res_data = response.read().decode("utf-8")
            parsed = json.loads(res_data) if res_data.strip() else {}
            if isinstance(parsed, dict):
                http_status = getattr(response, "status", None)
                if http_status is None:
                    http_status = response.getcode()
                parsed.setdefault("http_status", http_status)
            return parsed
    except urllib.error.HTTPError as e:
        try:
            err_data = e.read().decode("utf-8")
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


def normalize_lb_url(base_url=None):
    cleaned = (base_url or "").strip().rstrip("/")
    if not cleaned:
        return LB_DEFAULT_URL
    parsed = urllib.parse.urlparse(cleaned)
    if parsed.scheme not in ("https", "http") or not parsed.hostname:
        raise ValueError(f"Invalid ListenBrainz URL: {base_url}")
    return cleaned


def _extract_ratelimit_headers(headers, target):
    if not headers:
        return
    for header_name, out_key in (
        ("X-RateLimit-Remaining", "ratelimit_remaining"),
        ("X-RateLimit-Reset-In", "ratelimit_reset_in"),
    ):
        raw = headers.get(header_name)
        if raw is None:
            continue
        try:
            target[out_key] = int(raw)
        except (TypeError, ValueError):
            pass


def call_lb_api(method, path, token=None, base_url=None, params=None, body=None):
    try:
        base = normalize_lb_url(base_url)
    except ValueError as e:
        return {"error": -1, "message": str(e)}

    if not path.startswith("/"):
        path = "/" + path
    url = f"{base}{path}"
    if params:
        filtered = {k: v for k, v in params.items() if v is not None and v != ""}
        if filtered:
            url = f"{url}?{urllib.parse.urlencode(filtered)}"

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url, data=data, method=method.upper())
    req.add_header("User-Agent", USER_AGENT)
    req.add_header("Accept", "application/json")
    if token:
        req.add_header("Authorization", f"Token {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            res_data = response.read().decode("utf-8")
            parsed = json.loads(res_data) if res_data.strip() else {}
            if not isinstance(parsed, dict):
                return {"error": -1, "message": "ListenBrainz returned an invalid response"}
            http_status = getattr(response, "status", None)
            if http_status is None:
                http_status = response.getcode()
            parsed.setdefault("http_status", http_status)
            _extract_ratelimit_headers(getattr(response, "headers", None), parsed)
            return parsed
    except urllib.error.HTTPError as e:
        try:
            err_data = e.read().decode("utf-8", errors="replace")
            parsed = json.loads(err_data) if err_data.strip() else {}
            if isinstance(parsed, dict):
                err_msg = parsed.get("error") if isinstance(parsed.get("error"), str) else None
                parsed["http_status"] = e.code
                parsed["error"] = e.code
                if not parsed.get("message"):
                    parsed["message"] = err_msg or str(e)
                _extract_ratelimit_headers(getattr(e, "headers", None), parsed)
                return parsed
            return {"error": e.code, "http_status": e.code, "message": err_data or str(e)}
        except (UnicodeDecodeError, ValueError):
            return {"error": e.code, "http_status": e.code, "message": str(e)}
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


def queue_stats(queue=None):
    if queue is None:
        queue = load_queue()
    lfm_count = 0
    lb_count = 0
    for item in queue:
        if not isinstance(item, dict):
            continue
        service = item.get("service", "lastfm")
        if service == "listenbrainz":
            lb_count += 1
        else:
            lfm_count += 1
    return {
        "count": len(queue),
        "lastfm": lfm_count,
        "listenbrainz": lb_count,
    }


def is_retryable(res):
    """True if a failed Last.fm API result is transient (network/server) and worth queueing."""
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


def is_lb_retryable(res):
    """True if a failed ListenBrainz API result is transient and worth queueing."""
    err = res.get("error")
    if err is None:
        return False
    try:
        code = int(err)
    except (TypeError, ValueError):
        return False
    if code in RETRYABLE_LB_CODES:
        return True
    return code >= 500


def largest_image(images):
    if not isinstance(images, list):
        return ""
    by_size = {}
    last_url = ""
    for image in images:
        if not isinstance(image, dict):
            continue
        candidate = image.get("#text", "")
        if not candidate or LASTFM_PLACEHOLDER_ART in candidate:
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


def get_track_info(api_key, artist, title, username, album_hint="", youtube_art=False):
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

    if youtube_art and not info.get("album_art"):
        art_url = get_youtube_music_art(artist, title, album_name)
        if art_url:
            info["album_art"] = art_url
            info["art_source"] = "youtube_music"

    if "error" in track_result and len(info) == 1:
        return track_result
    return info


def _parse_positive_int(value):
    try:
        parsed = int(float(value))
        return parsed if parsed > 0 else 0
    except (TypeError, ValueError):
        return 0


def lb_extract_recording_msid(res):
    if not isinstance(res, dict):
        return ""
    msid = res.get("recording_msid")
    if isinstance(msid, str) and msid:
        return msid
    payload = res.get("payload")
    if isinstance(payload, dict):
        msid = payload.get("recording_msid")
        if isinstance(msid, str) and msid:
            return msid
    return ""


def lb_build_track_metadata(
    artist,
    title,
    album="",
    duration_ms=0,
    player="",
    recording_mbid="",
    release_mbid="",
    artist_mbids=None,
):
    additional_info = {
        "submission_client": CLIENT_NAME,
        "submission_client_version": CLIENT_VERSION,
    }
    if player:
        additional_info["media_player"] = str(player)
    dur = _parse_positive_int(duration_ms)
    if dur > 0:
        additional_info["duration_ms"] = dur
    if recording_mbid:
        additional_info["recording_mbid"] = str(recording_mbid).strip()
    if release_mbid:
        additional_info["release_mbid"] = str(release_mbid).strip()
    if artist_mbids:
        cleaned_mbids = [m.strip() for m in artist_mbids if isinstance(m, str) and m.strip()]
        if cleaned_mbids:
            additional_info["artist_mbids"] = cleaned_mbids

    meta = {
        "artist_name": artist,
        "track_name": title,
        "additional_info": additional_info,
    }
    if album:
        meta["release_name"] = album
    return meta


def lb_validate_token(token, base_url=None):
    if not token:
        return {"error": 401, "valid": False, "message": "ListenBrainz token is required"}
    res = call_lb_api("GET", "/1/validate-token", token=token, base_url=base_url)
    if "error" in res:
        res["valid"] = False
        return res
    if res.get("valid") is True:
        return {
            "valid": True,
            "username": res.get("user_name", ""),
        }
    return {
        "error": 401,
        "valid": False,
        "message": res.get("message") or "Invalid ListenBrainz user token",
    }


def lb_now_playing(token, artist, title, album="", duration_ms=0, player="", base_url=None):
    if not token:
        return {"error": 401, "message": "ListenBrainz token is required"}
    meta = lb_build_track_metadata(
        artist=artist,
        title=title,
        album=album,
        duration_ms=duration_ms,
        player=player,
    )
    res = call_lb_api(
        "POST",
        "/1/submit-listens",
        token=token,
        base_url=base_url,
        params={"return_msid": "true"},
        body={"listen_type": "playing_now", "payload": [{"track_metadata": meta}]},
    )
    if "error" in res:
        return res
    out = {"status": res.get("status", "ok")}
    msid = lb_extract_recording_msid(res)
    if msid:
        out["recording_msid"] = msid
    return out


def lb_scrobble(
    token,
    artist,
    title,
    timestamp,
    album="",
    duration_ms=0,
    player="",
    recording_mbid="",
    release_mbid="",
    artist_mbids=None,
    base_url=None,
):
    if not token:
        return {"error": 401, "message": "ListenBrainz token is required"}
    ts = _parse_positive_int(timestamp)
    if ts <= 0:
        return {"error": 400, "message": "Invalid timestamp for ListenBrainz listen"}

    meta = lb_build_track_metadata(
        artist=artist,
        title=title,
        album=album,
        duration_ms=duration_ms,
        player=player,
        recording_mbid=recording_mbid,
        release_mbid=release_mbid,
        artist_mbids=artist_mbids,
    )
    res = call_lb_api(
        "POST",
        "/1/submit-listens",
        token=token,
        base_url=base_url,
        body={
            "listen_type": "single",
            "payload": [{"listened_at": ts, "track_metadata": meta}],
        },
    )
    if "error" in res:
        if is_lb_retryable(res):
            entry = {
                "service": "listenbrainz",
                "artist": artist,
                "track": title,
                "timestamp": ts,
            }
            if album:
                entry["album"] = album
            dur = _parse_positive_int(duration_ms)
            if dur > 0:
                entry["duration_ms"] = dur
            if player:
                entry["media_player"] = player
            if recording_mbid:
                entry["recording_mbid"] = recording_mbid
            if release_mbid:
                entry["release_mbid"] = release_mbid
            if artist_mbids:
                cleaned = [m.strip() for m in artist_mbids if isinstance(m, str) and m.strip()]
                if cleaned:
                    entry["artist_mbids"] = cleaned
            try:
                size = enqueue(entry)
                return {"queued": True, "queue_size": size, "service": "listenbrainz"}
            except OSError as exc:
                return {"error": -1, "message": f"Failed to persist offline scrobble: {exc}"}
        return res
    return {"status": res.get("status", "ok"), "accepted": True}


def lb_lookup_metadata(token, artist, title, album="", base_url=None):
    if not token:
        return {}
    params = {
        "artist_name": artist,
        "recording_name": title,
    }
    if album:
        params["release_name"] = album
    res = call_lb_api("GET", "/1/metadata/lookup/", token=token, base_url=base_url, params=params)
    if "error" in res:
        return res
    if album and not res.get("recording_mbid"):
        fallback_res = call_lb_api(
            "GET",
            "/1/metadata/lookup/",
            token=token,
            base_url=base_url,
            params={"artist_name": artist, "recording_name": title},
        )
        if "error" not in fallback_res and fallback_res.get("recording_mbid"):
            return fallback_res
    return res


def _lb_track_matches(meta, artist, title):
    if not isinstance(meta, dict):
        return False
    expected_title = _normalize_search_text(title)
    cand_title = _normalize_search_text(meta.get("track_name", ""))
    if not expected_title or cand_title != expected_title:
        return False
    expected_artist = _normalize_search_text(artist)
    cand_artist = _normalize_search_text(meta.get("artist_name", ""))
    if not expected_artist or not cand_artist:
        return False
    return (
        cand_artist == expected_artist
        or expected_artist in cand_artist
        or cand_artist in expected_artist
    )


def lb_find_msid_from_user_listens(username, artist, title, token=None, base_url=None):
    if not username:
        return {}
    quoted_user = urllib.parse.quote(username, safe="")
    endpoints = [
        f"/1/user/{quoted_user}/playing-now",
        f"/1/user/{quoted_user}/listens",
    ]
    for path in endpoints:
        params = {"count": "5"} if path.endswith("/listens") else None
        res = call_lb_api("GET", path, token=token, base_url=base_url, params=params)
        if "error" in res:
            continue
        listens = res.get("payload", {}).get("listens", [])
        if not isinstance(listens, list):
            continue
        for listen in listens:
            if not isinstance(listen, dict):
                continue
            meta = listen.get("track_metadata", {})
            if not _lb_track_matches(meta, artist, title):
                continue
            mapping = meta.get("mbid_mapping") if isinstance(meta.get("mbid_mapping"), dict) else {}
            return {
                "recording_msid": listen.get("recording_msid") or "",
                "recording_mbid": mapping.get("recording_mbid") or "",
                "release_mbid": mapping.get("release_mbid") or "",
                "artist_mbids": mapping.get("artist_mbids") or [],
                "release_name": meta.get("release_name") or "",
            }
    return {}


def lb_fetch_feedback(username, recording_mbid="", recording_msid="", token=None, base_url=None):
    if not username or (not recording_mbid and not recording_msid):
        return {"loved": False, "score": 0, "loved_mbids": [], "loved_msids": []}
    body = {}
    if recording_mbid:
        body["recording_mbids"] = [recording_mbid]
    if recording_msid:
        body["recording_msids"] = [recording_msid]
    res = call_lb_api(
        "POST",
        f"/1/feedback/user/{urllib.parse.quote(username, safe='')}/get-feedback-for-recordings",
        token=token,
        base_url=base_url,
        body=body,
    )
    if "error" in res:
        return res
    loved_mbids = []
    loved_msids = []
    score = 0
    feedback = res.get("feedback", [])
    if isinstance(feedback, list):
        for entry in feedback:
            if not isinstance(entry, dict):
                continue
            entry_score = entry.get("score", 0)
            if entry_score == 1:
                score = 1
                if entry.get("recording_mbid"):
                    loved_mbids.append(entry["recording_mbid"])
                if entry.get("recording_msid"):
                    loved_msids.append(entry["recording_msid"])
            elif entry_score == -1 and score == 0:
                score = -1
    return {
        "loved": bool(loved_mbids or loved_msids),
        "score": score,
        "loved_mbids": loved_mbids,
        "loved_msids": loved_msids,
    }


def lb_resolve_ids(
    token,
    username,
    artist,
    title,
    album="",
    recording_mbid="",
    recording_msid="",
    base_url=None,
    allow_playing_now_fallback=False,
):
    resolved = {
        "recording_mbid": (recording_mbid or "").strip(),
        "recording_msid": (recording_msid or "").strip(),
        "release_mbid": "",
        "artist_mbids": [],
        "album": "",
    }
    auth_error = None

    if not resolved["recording_mbid"] and token:
        lookup = lb_lookup_metadata(token, artist, title, album=album, base_url=base_url)
        if "error" in lookup:
            if lookup.get("error") in (401, 403):
                auth_error = lookup
        else:
            if lookup.get("recording_mbid"):
                resolved["recording_mbid"] = lookup["recording_mbid"]
            if lookup.get("release_mbid"):
                resolved["release_mbid"] = lookup["release_mbid"]
            if isinstance(lookup.get("artist_mbids"), list):
                resolved["artist_mbids"] = lookup["artist_mbids"]
            if lookup.get("release_name"):
                resolved["album"] = lookup["release_name"]

    if auth_error is not None:
        return auth_error

    if not resolved["recording_msid"] and username:
        found = lb_find_msid_from_user_listens(
            username, artist, title, token=token, base_url=base_url
        )
        if found.get("recording_msid"):
            resolved["recording_msid"] = found["recording_msid"]
        if not resolved["recording_mbid"] and found.get("recording_mbid"):
            resolved["recording_mbid"] = found["recording_mbid"]
        if not resolved["release_mbid"] and found.get("release_mbid"):
            resolved["release_mbid"] = found["release_mbid"]
        if not resolved["artist_mbids"] and found.get("artist_mbids"):
            resolved["artist_mbids"] = found["artist_mbids"]
        if not resolved["album"] and found.get("release_name"):
            resolved["album"] = found["release_name"]

    if not resolved["recording_mbid"] and not resolved["recording_msid"] and allow_playing_now_fallback and token:
        now_res = lb_now_playing(token, artist, title, album=album, base_url=base_url)
        if "error" in now_res:
            return now_res
        if now_res.get("recording_msid"):
            resolved["recording_msid"] = now_res["recording_msid"]

    return resolved


def lb_get_info(token, username, artist, title, album="", recording_msid="", base_url=None):
    ids = lb_resolve_ids(
        token=token,
        username=username,
        artist=artist,
        title=title,
        album=album,
        recording_msid=recording_msid,
        base_url=base_url,
        allow_playing_now_fallback=False,
    )
    if "error" in ids:
        return ids

    loved = False
    score = 0
    if username and (ids.get("recording_mbid") or ids.get("recording_msid")):
        fb = lb_fetch_feedback(
            username,
            recording_mbid=ids.get("recording_mbid", ""),
            recording_msid=ids.get("recording_msid", ""),
            token=token,
            base_url=base_url,
        )
        if "error" in fb:
            return fb
        loved = fb.get("loved", False)
        score = fb.get("score", 0)

    out = {
        "loved": loved,
        "score": score,
        "recording_mbid": ids.get("recording_mbid", ""),
        "recording_msid": ids.get("recording_msid", ""),
        "release_mbid": ids.get("release_mbid", ""),
        "artist_mbids": ids.get("artist_mbids", []),
    }
    if ids.get("album"):
        out["album"] = ids["album"]
    return out


def lb_love(token, username, artist, title, album="", recording_mbid="", recording_msid="", base_url=None):
    if not token:
        return {"error": 401, "message": "ListenBrainz token is required"}
    ids = lb_resolve_ids(
        token=token,
        username=username,
        artist=artist,
        title=title,
        album=album,
        recording_mbid=recording_mbid,
        recording_msid=recording_msid,
        base_url=base_url,
        allow_playing_now_fallback=True,
    )
    if "error" in ids:
        return ids

    body = {"score": 1}
    if ids.get("recording_mbid"):
        body["recording_mbid"] = ids["recording_mbid"]
    elif ids.get("recording_msid"):
        body["recording_msid"] = ids["recording_msid"]
    else:
        return {"error": -1, "message": "Could not resolve recording MBID or MSID on ListenBrainz"}

    res = call_lb_api(
        "POST",
        "/1/feedback/recording-feedback",
        token=token,
        base_url=base_url,
        body=body,
    )
    if "error" in res:
        return res
    return {
        "status": res.get("status", "ok"),
        "loved": True,
        "recording_mbid": ids.get("recording_mbid", ""),
        "recording_msid": ids.get("recording_msid", ""),
    }


def lb_unlove(token, username, artist, title, album="", recording_mbid="", recording_msid="", base_url=None):
    if not token:
        return {"error": 401, "message": "ListenBrainz token is required"}
    ids = lb_resolve_ids(
        token=token,
        username=username,
        artist=artist,
        title=title,
        album=album,
        recording_mbid=recording_mbid,
        recording_msid=recording_msid,
        base_url=base_url,
        allow_playing_now_fallback=False,
    )
    if "error" in ids:
        return ids

    targets = []
    if username and (ids.get("recording_mbid") or ids.get("recording_msid")):
        fb = lb_fetch_feedback(
            username,
            recording_mbid=ids.get("recording_mbid", ""),
            recording_msid=ids.get("recording_msid", ""),
            token=token,
            base_url=base_url,
        )
        if "error" in fb:
            return fb
        for mbid in fb.get("loved_mbids", []):
            targets.append({"recording_mbid": mbid, "score": 0})
        for msid in fb.get("loved_msids", []):
            targets.append({"recording_msid": msid, "score": 0})

    if not targets:
        if ids.get("recording_mbid"):
            targets.append({"recording_mbid": ids["recording_mbid"], "score": 0})
        if ids.get("recording_msid"):
            targets.append({"recording_msid": ids["recording_msid"], "score": 0})

    for target in targets:
        res = call_lb_api(
            "POST",
            "/1/feedback/recording-feedback",
            token=token,
            base_url=base_url,
            body=target,
        )
        if "error" in res:
            return res

    return {
        "status": "ok",
        "loved": False,
        "recording_mbid": ids.get("recording_mbid", ""),
        "recording_msid": ids.get("recording_msid", ""),
    }


def lb_recent_now_playing(username, token=None, base_url=None):
    if not username:
        return {"error": 400, "message": "ListenBrainz username is required"}
    quoted_user = urllib.parse.quote(username, safe="")
    res = call_lb_api(
        "GET",
        f"/1/user/{quoted_user}/playing-now",
        token=token or None,
        base_url=base_url,
    )
    if "error" in res:
        return res
    listens = res.get("payload", {}).get("listens", [])
    if not isinstance(listens, list) or not listens:
        return {"now_playing": False}

    listen = listens[0]
    meta = listen.get("track_metadata", {}) if isinstance(listen, dict) else {}
    mapping = meta.get("mbid_mapping") if isinstance(meta.get("mbid_mapping"), dict) else {}
    additional = meta.get("additional_info") if isinstance(meta.get("additional_info"), dict) else {}
    rec_mbid = mapping.get("recording_mbid") or additional.get("recording_mbid") or ""
    rec_msid = (listen.get("recording_msid") if isinstance(listen, dict) else "") or ""
    rel_mbid = mapping.get("release_mbid") or additional.get("release_mbid") or ""

    loved = False
    if rec_mbid or rec_msid:
        fb = lb_fetch_feedback(
            username,
            recording_mbid=rec_mbid,
            recording_msid=rec_msid,
            token=token or None,
            base_url=base_url,
        )
        if "error" not in fb:
            loved = fb.get("loved", False)

    url = f"https://musicbrainz.org/recording/{rec_mbid}" if rec_mbid else f"https://listenbrainz.org/user/{quoted_user}/"
    return {
        "now_playing": True,
        "artist": meta.get("artist_name", ""),
        "track": meta.get("track_name", ""),
        "album": meta.get("release_name", ""),
        "loved": loved,
        "recording_mbid": rec_mbid,
        "recording_msid": rec_msid,
        "release_mbid": rel_mbid,
        "url": url,
    }


def flush_lastfm_queue(api_key, secret, sk):
    with queue_lock():
        queue = _load_queue_unlocked()
        lfm_items = [
            item for item in queue
            if isinstance(item, dict) and item.get("service", "lastfm") == "lastfm"
        ]
        other_items = [
            item for item in queue
            if not (isinstance(item, dict) and item.get("service", "lastfm") == "lastfm")
        ]
        valid_lfm = [
            item for item in lfm_items
            if str(item.get("artist", "")).strip()
            and str(item.get("track", "")).strip()
            and str(item.get("timestamp", "")).strip()
        ]
        if not valid_lfm:
            if len(valid_lfm) != len(lfm_items):
                _save_queue_unlocked(other_items)
            return {"flushed": 0, "remaining": 0, "total_remaining": len(other_items)}

        flushed = 0
        remaining_lfm = []
        index = 0
        error_res = None
        while index < len(valid_lfm):
            batch = valid_lfm[index:index + 50]
            params = {"api_key": api_key, "sk": sk}
            for j, item in enumerate(batch):
                params[f"artist[{j}]"] = item.get("artist", "")
                params[f"track[{j}]"] = item.get("track", "")
                params[f"timestamp[{j}]"] = str(item.get("timestamp", ""))
                if item.get("album"):
                    params[f"album[{j}]"] = item["album"]
                dur = _parse_positive_int(item.get("duration", 0))
                if dur > 0:
                    params[f"duration[{j}]"] = str(dur)

            res = call_api("track.scrobble", params, secret=secret, is_post=True)
            if "error" in res:
                remaining_lfm = valid_lfm[index:]
                error_res = res
                break
            flushed += len(batch)
            index += 50

        all_remaining = remaining_lfm + other_items
        _save_queue_unlocked(all_remaining)

    out = {
        "flushed": flushed,
        "remaining": len(remaining_lfm),
        "total_remaining": len(all_remaining),
    }
    if flushed == 0 and error_res is not None:
        out["error"] = error_res.get("error")
        out["message"] = error_res.get("message", "Last.fm queue flush failed")
    return out


def flush_lb_queue(token, base_url=None):
    with queue_lock():
        queue = _load_queue_unlocked()
        lb_items = [
            item for item in queue
            if isinstance(item, dict) and item.get("service") == "listenbrainz"
        ]
        other_items = [
            item for item in queue
            if not (isinstance(item, dict) and item.get("service") == "listenbrainz")
        ]
        valid_lb = []
        for item in lb_items:
            ts = _parse_positive_int(item.get("timestamp"))
            if str(item.get("artist", "")).strip() and str(item.get("track", "")).strip() and ts > 0:
                valid_lb.append((ts, item))
        valid_lb.sort(key=lambda pair: pair[0])
        sorted_lb = [pair[1] for pair in valid_lb]

        if not sorted_lb:
            if len(lb_items) > 0:
                _save_queue_unlocked(other_items)
            return {"flushed": 0, "remaining": 0, "total_remaining": len(other_items)}

        flushed = 0
        remaining_lb = []
        index = 0
        error_res = None
        while index < len(sorted_lb):
            batch = sorted_lb[index:index + 100]
            payload = []
            for item in batch:
                meta = lb_build_track_metadata(
                    artist=item["artist"],
                    title=item["track"],
                    album=item.get("album", ""),
                    duration_ms=item.get("duration_ms", 0),
                    player=item.get("media_player", ""),
                    recording_mbid=item.get("recording_mbid", ""),
                    release_mbid=item.get("release_mbid", ""),
                    artist_mbids=item.get("artist_mbids"),
                )
                payload.append({
                    "listened_at": _parse_positive_int(item["timestamp"]),
                    "track_metadata": meta,
                })

            res = call_lb_api(
                "POST",
                "/1/submit-listens",
                token=token,
                base_url=base_url,
                body={"listen_type": "import", "payload": payload},
            )
            if "error" in res:
                remaining_lb = sorted_lb[index:]
                error_res = res
                break
            flushed += len(batch)
            index += len(batch)
            if res.get("ratelimit_remaining") == 0 and index < len(sorted_lb):
                remaining_lb = sorted_lb[index:]
                break

        all_remaining = other_items + remaining_lb
        _save_queue_unlocked(all_remaining)

    out = {
        "flushed": flushed,
        "remaining": len(remaining_lb),
        "total_remaining": len(all_remaining),
    }
    if flushed == 0 and error_res is not None:
        out["error"] = error_res.get("error")
        out["message"] = error_res.get("message", "ListenBrainz queue flush failed")
    return out


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
                "username": res["session"]["name"],
            })
        else:
            print_json(res)

    elif cmd == "now-playing":
        if len(sys.argv) < 7:
            print_json({"error": -1, "message": "Usage: now-playing <api_key> <secret> <session_key> <artist> <title> [album] [duration]"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]
        artist = sys.argv[5]
        title = sys.argv[6]
        album = sys.argv[7] if len(sys.argv) > 7 else ""
        duration = _parse_positive_int(sys.argv[8]) if len(sys.argv) > 8 else 0

        params = {
            "api_key": api_key,
            "sk": sk,
            "artist": artist,
            "track": title,
        }
        if album:
            params["album"] = album
        if duration > 0:
            params["duration"] = str(duration)

        res = call_api("track.updateNowPlaying", params, secret=secret, is_post=True)
        print_json(res)

    elif cmd == "scrobble":
        if len(sys.argv) < 8:
            print_json({"error": -1, "message": "Usage: scrobble <api_key> <secret> <session_key> <artist> <title> <timestamp> [album] [duration]"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]
        artist = sys.argv[5]
        title = sys.argv[6]
        ts = sys.argv[7]
        album = sys.argv[8] if len(sys.argv) > 8 else ""
        duration = _parse_positive_int(sys.argv[9]) if len(sys.argv) > 9 else 0

        params = {
            "api_key": api_key,
            "sk": sk,
            "artist": artist,
            "track": title,
            "timestamp": ts,
        }
        if album:
            params["album"] = album
        if duration > 0:
            params["duration"] = str(duration)

        res = call_api("track.scrobble", params, secret=secret, is_post=True)
        if "error" in res and is_retryable(res):
            entry = {"service": "lastfm", "artist": artist, "track": title, "timestamp": ts}
            if album:
                entry["album"] = album
            if duration > 0:
                entry["duration"] = duration
            try:
                size = enqueue(entry)
                print_json({"queued": True, "queue_size": size, "service": "lastfm"})
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
        print_json(flush_lastfm_queue(api_key, secret, sk))

    elif cmd == "queue-count":
        print_json(queue_stats())

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
            art_url = largest_image(track.get("image", []))
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
        youtube_art = len(sys.argv) > 7 and sys.argv[7] == "--youtube-art"
        print_json(get_track_info(api_key, artist, title, username, album, youtube_art))

    elif cmd == "lb-validate-token":
        if len(sys.argv) < 3:
            print_json({"error": -1, "message": "Usage: lb-validate-token <token> [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        base_url = sys.argv[3] if len(sys.argv) > 3 else ""
        print_json(lb_validate_token(token, base_url=base_url))

    elif cmd == "lb-now-playing":
        if len(sys.argv) < 5:
            print_json({"error": -1, "message": "Usage: lb-now-playing <token> <artist> <title> [album] [duration_ms] [player] [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        artist = sys.argv[3]
        title = sys.argv[4]
        album = sys.argv[5] if len(sys.argv) > 5 else ""
        duration_ms = sys.argv[6] if len(sys.argv) > 6 else 0
        player = sys.argv[7] if len(sys.argv) > 7 else ""
        base_url = sys.argv[8] if len(sys.argv) > 8 else ""
        print_json(lb_now_playing(token, artist, title, album, duration_ms, player, base_url=base_url))

    elif cmd == "lb-scrobble":
        if len(sys.argv) < 6:
            print_json({"error": -1, "message": "Usage: lb-scrobble <token> <artist> <title> <timestamp> [album] [duration_ms] [player] [recording_mbid] [release_mbid] [artist_mbids_csv] [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        artist = sys.argv[3]
        title = sys.argv[4]
        ts = sys.argv[5]
        album = sys.argv[6] if len(sys.argv) > 6 else ""
        duration_ms = sys.argv[7] if len(sys.argv) > 7 else 0
        player = sys.argv[8] if len(sys.argv) > 8 else ""
        recording_mbid = sys.argv[9] if len(sys.argv) > 9 else ""
        release_mbid = sys.argv[10] if len(sys.argv) > 10 else ""
        artist_mbids_raw = sys.argv[11] if len(sys.argv) > 11 else ""
        artist_mbids = [m.strip() for m in artist_mbids_raw.split(",") if m.strip()] if artist_mbids_raw else []
        base_url = sys.argv[12] if len(sys.argv) > 12 else ""
        print_json(lb_scrobble(
            token,
            artist,
            title,
            ts,
            album=album,
            duration_ms=duration_ms,
            player=player,
            recording_mbid=recording_mbid,
            release_mbid=release_mbid,
            artist_mbids=artist_mbids,
            base_url=base_url,
        ))

    elif cmd == "lb-flush-queue":
        if len(sys.argv) < 3:
            print_json({"error": -1, "message": "Usage: lb-flush-queue <token> [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        base_url = sys.argv[3] if len(sys.argv) > 3 else ""
        print_json(flush_lb_queue(token, base_url=base_url))

    elif cmd == "lb-get-info":
        if len(sys.argv) < 6:
            print_json({"error": -1, "message": "Usage: lb-get-info <token> <username> <artist> <title> [album] [recording_msid] [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        username = sys.argv[3]
        artist = sys.argv[4]
        title = sys.argv[5]
        album = sys.argv[6] if len(sys.argv) > 6 else ""
        recording_msid = sys.argv[7] if len(sys.argv) > 7 else ""
        base_url = sys.argv[8] if len(sys.argv) > 8 else ""
        print_json(lb_get_info(token, username, artist, title, album=album, recording_msid=recording_msid, base_url=base_url))

    elif cmd == "lb-love":
        if len(sys.argv) < 6:
            print_json({"error": -1, "message": "Usage: lb-love <token> <username> <artist> <title> [album] [recording_mbid] [recording_msid] [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        username = sys.argv[3]
        artist = sys.argv[4]
        title = sys.argv[5]
        album = sys.argv[6] if len(sys.argv) > 6 else ""
        recording_mbid = sys.argv[7] if len(sys.argv) > 7 else ""
        recording_msid = sys.argv[8] if len(sys.argv) > 8 else ""
        base_url = sys.argv[9] if len(sys.argv) > 9 else ""
        print_json(lb_love(
            token,
            username,
            artist,
            title,
            album=album,
            recording_mbid=recording_mbid,
            recording_msid=recording_msid,
            base_url=base_url,
        ))

    elif cmd == "lb-unlove":
        if len(sys.argv) < 6:
            print_json({"error": -1, "message": "Usage: lb-unlove <token> <username> <artist> <title> [album] [recording_mbid] [recording_msid] [base_url]"})
            sys.exit(1)
        token = sys.argv[2]
        username = sys.argv[3]
        artist = sys.argv[4]
        title = sys.argv[5]
        album = sys.argv[6] if len(sys.argv) > 6 else ""
        recording_mbid = sys.argv[7] if len(sys.argv) > 7 else ""
        recording_msid = sys.argv[8] if len(sys.argv) > 8 else ""
        base_url = sys.argv[9] if len(sys.argv) > 9 else ""
        print_json(lb_unlove(
            token,
            username,
            artist,
            title,
            album=album,
            recording_mbid=recording_mbid,
            recording_msid=recording_msid,
            base_url=base_url,
        ))

    elif cmd == "lb-recent-now-playing":
        if len(sys.argv) < 3:
            print_json({"error": -1, "message": "Usage: lb-recent-now-playing <username> [token] [base_url]"})
            sys.exit(1)
        username = sys.argv[2]
        token = sys.argv[3] if len(sys.argv) > 3 else ""
        base_url = sys.argv[4] if len(sys.argv) > 4 else ""
        print_json(lb_recent_now_playing(username, token=token, base_url=base_url))

    else:
        print_json({"error": -1, "message": f"Unknown command: {cmd}"})
        sys.exit(1)


if __name__ == "__main__":
    expand_stdin_request()
    main()
