#!/usr/bin/env python3
import sys
import os
import json
import hashlib
import urllib.request
import urllib.parse

API_URL = "https://ws.audioscrobbler.com/2.0/"
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
        
        req.add_header('User-Agent', 'DMS-Scrobbler/1.0')
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            res_data = response.read().decode('utf-8')
            return json.loads(res_data)
    except urllib.error.HTTPError as e:
        try:
            err_data = e.read().decode('utf-8')
            return {"error": e.code, "message": err_data}
        except:
            return {"error": e.code, "message": str(e)}
    except Exception as e:
        return {"error": -1, "message": str(e)}

def print_json(data):
    print(json.dumps(data))

def queue_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    directory = os.path.join(base, "dms-scrobbler")
    os.makedirs(directory, exist_ok=True)
    return os.path.join(directory, "queue.json")

def load_queue():
    try:
        with open(queue_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except (FileNotFoundError, ValueError, OSError):
        return []

def save_queue(queue):
    try:
        with open(queue_path(), "w", encoding="utf-8") as f:
            json.dump(queue, f)
    except OSError:
        pass

def enqueue(entry):
    queue = load_queue()
    queue.append(entry)
    # Cap to avoid unbounded growth if the network stays down for a very long time.
    if len(queue) > 1000:
        queue = queue[-1000:]
    save_queue(queue)
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
            size = enqueue(entry)
            print_json({"queued": True, "queue_size": size})
        else:
            print_json(res)

    elif cmd == "flush-queue":
        if len(sys.argv) < 5:
            print_json({"error": -1, "message": "Usage: flush-queue <api_key> <secret> <session_key>"})
            sys.exit(1)
        api_key = sys.argv[2]
        secret = sys.argv[3]
        sk = sys.argv[4]

        queue = load_queue()
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
                # Still failing: keep this batch and everything after it for the next attempt.
                remaining.extend(queue[index:])
                break
            flushed += len(batch)
            index += 50

        save_queue(remaining)
        print_json({"flushed": flushed, "remaining": len(remaining)})

    elif cmd == "queue-count":
        print_json({"count": len(load_queue())})

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
        print_json(res)
        
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
        print_json(res)
        
    elif cmd == "get-info":
        if len(sys.argv) < 6:
            print_json({"error": -1, "message": "Usage: get-info <api_key> <artist> <title> <username>"})
            sys.exit(1)
        api_key = sys.argv[2]
        artist = sys.argv[3]
        title = sys.argv[4]
        username = sys.argv[5]
        
        params = {
            "api_key": api_key,
            "artist": artist,
            "track": title,
            "username": username,
        }
        res = call_api("track.getInfo", params)
        info = {"loved": False}
        if "track" in res:
            if "userloved" in res["track"]:
                info["loved"] = res["track"]["userloved"] == "1"
            if "album" in res["track"]:
                album_data = res["track"]["album"]
                if "title" in album_data:
                    info["album"] = album_data["title"]
                if "image" in album_data:
                    images = album_data["image"]
                    art_url = ""
                    for img in images:
                        if img.get("size") == "extralarge":
                            art_url = img.get("#text")
                        elif img.get("size") == "large" and not art_url:
                            art_url = img.get("#text")
                    if art_url:
                        info["album_art"] = art_url
        print_json(info)
            
    else:
        print_json({"error": -1, "message": f"Unknown command: {cmd}"})
        sys.exit(1)

if __name__ == "__main__":
    main()
