#!/usr/bin/env python3
import sys
import json
import hashlib
import urllib.request
import urllib.parse

API_URL = "https://ws.audioscrobbler.com/2.0/"

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
        with urllib.request.urlopen(req) as response:
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
        print_json(res)
        
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
        if "track" in res and "userloved" in res["track"]:
            print_json({"loved": res["track"]["userloved"] == "1"})
        else:
            print_json({"loved": False, "raw": res})
            
    else:
        print_json({"error": -1, "message": f"Unknown command: {cmd}"})
        sys.exit(1)

if __name__ == "__main__":
    main()
