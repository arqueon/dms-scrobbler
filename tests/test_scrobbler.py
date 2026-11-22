import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("dms_scrobbler", ROOT / "scrobbler.py")
SCROBBLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCROBBLER)


class FakeHTTPResponse:
    def __init__(self, body_dict, status=200, headers=None):
        self._body = json.dumps(body_dict).encode("utf-8")
        self.status = status
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self._body

    def getcode(self):
        return self.status


class ScrobblerTests(unittest.TestCase):
    def test_search_normalization_handles_ligatures_and_accents(self):
        self.assertEqual(
            SCROBBLER._normalize_search_text("L'œil de ma grand-mère"),
            "l oeil de ma grand mere",
        )

    def test_signature_ignores_transport_parameters(self):
        params = {
            "method": "track.love",
            "api_key": "key",
            "track": "Song",
            "format": "json",
            "callback": "ignored",
        }
        self.assertEqual(
            SCROBBLER.make_signature(params, "secret"),
            "ff60b67d2a728c01654ce8ba40453ba8",
        )

    def test_retryable_errors(self):
        for code in (-1, 8, 11, 16, 29, 500, 503):
            with self.subTest(code=code):
                self.assertTrue(SCROBBLER.is_retryable({"error": code}))
        for code in (2, 6, 9, 401, 404):
            with self.subTest(code=code):
                self.assertFalse(SCROBBLER.is_retryable({"error": code}))

    def test_lb_retryable_errors(self):
        for code in (-1, 429, 500, 502, 503):
            with self.subTest(code=code):
                self.assertTrue(SCROBBLER.is_lb_retryable({"error": code}))
        for code in (400, 401, 403, 404, 422):
            with self.subTest(code=code):
                self.assertFalse(SCROBBLER.is_lb_retryable({"error": code}))

    def test_largest_image_skips_lastfm_placeholder_star(self):
        placeholder = "https://lastfm.freetls.fastly.net/i/u/300x300/2a96cbd8b46e442fc41c2b86b821562f.png"
        real_art = "https://lastfm.freetls.fastly.net/i/u/300x300/abcdef1234567890.jpg"
        self.assertEqual(
            SCROBBLER.largest_image([{"size": "extralarge", "#text": placeholder}]),
            "",
        )
        self.assertEqual(
            SCROBBLER.largest_image([
                {"size": "extralarge", "#text": placeholder},
                {"size": "large", "#text": real_art},
            ]),
            real_art,
        )

    def test_recent_now_playing_picks_largest_non_placeholder_art(self):
        placeholder = "https://lastfm.freetls.fastly.net/i/u/300x300/2a96cbd8b46e442fc41c2b86b821562f.png"
        xl_art = "https://example.test/xl.jpg"
        small_art = "https://example.test/small.jpg"
        api_payload = {
            "recenttracks": {
                "track": [{
                    "@attr": {"nowplaying": "true"},
                    "artist": {"name": "Artist"},
                    "name": "Track",
                    "album": {"#text": "Album"},
                    "loved": "1",
                    "url": "https://www.last.fm/music/Artist/_/Track",
                    "image": [
                        {"size": "extralarge", "#text": xl_art},
                        {"size": "small", "#text": small_art},
                        {"size": "mega", "#text": placeholder},
                    ],
                }]
            }
        }
        buf = io.StringIO()
        with mock.patch.object(SCROBBLER, "call_api", return_value=api_payload), \
             mock.patch.object(sys, "argv", ["scrobbler.py", "recent-now-playing", "key", "user"]), \
             mock.patch("sys.stdout", buf):
            SCROBBLER.main()
        result = json.loads(buf.getvalue())
        self.assertTrue(result["now_playing"])
        self.assertEqual(result["album_art"], xl_art)
        self.assertTrue(result["loved"])

    def test_love_accepts_explicit_lastfm_confirmation(self):
        self.assertEqual(
            SCROBBLER.confirmed_write_result(
                {"lfm": {"status": "ok"}},
                "track.love",
            ),
            {"lfm": {"status": "ok"}},
        )
        failed = SCROBBLER.confirmed_write_result({}, "track.love")
        self.assertEqual(failed["error"], -1)
        self.assertIn("did not confirm", failed["message"])

    def test_love_accepts_empty_json_after_http_success(self):
        with mock.patch.object(
            SCROBBLER.urllib.request,
            "urlopen",
            return_value=FakeHTTPResponse({}, status=200),
        ):
            api_result = SCROBBLER.call_api(
                "track.love",
                {"api_key": "key"},
                secret="secret",
                is_post=True,
            )
        self.assertEqual(api_result, {"http_status": 200})
        self.assertEqual(
            SCROBBLER.confirmed_write_result(api_result, "track.love"),
            {"http_status": 200},
        )

    def test_love_rejects_explicit_failed_status_even_after_http_success(self):
        failed = SCROBBLER.confirmed_write_result(
            {"lfm": {"status": "failed"}, "http_status": 200},
            "track.love",
        )
        self.assertEqual(failed["error"], -1)
        self.assertIn("did not confirm", failed["message"])

    def test_http_error_keeps_lastfm_error_code(self):
        error = urllib.error.HTTPError(
            SCROBBLER.API_URL,
            400,
            "Bad Request",
            {},
            io.BytesIO(b'{"error": 6, "message": "Track not found"}'),
        )
        try:
            with mock.patch.object(SCROBBLER.urllib.request, "urlopen", side_effect=error):
                result = SCROBBLER.call_api("track.getInfo", {"api_key": "key"})
        finally:
            error.close()
        self.assertEqual(result["error"], 6)
        self.assertEqual(result["http_status"], 400)
        self.assertEqual(result["message"], "Track not found")

    def test_album_lookup_fills_missing_track_art(self):
        track_result = {
            "track": {
                "userloved": "1",
                "album": {
                    "title": "Album",
                    "image": [{"size": "large", "#text": ""}],
                },
            }
        }
        album_result = {
            "album": {
                "name": "Album",
                "image": [
                    {"size": "large", "#text": "https://example.test/large.jpg"},
                    {"size": "extralarge", "#text": "https://example.test/xl.jpg"},
                ],
            }
        }
        with mock.patch.object(SCROBBLER, "call_api", side_effect=[track_result, album_result]) as call:
            result = SCROBBLER.get_track_info("key", "Artist", "Track", "user", "Album")
        self.assertTrue(result["loved"])
        self.assertEqual(result["album"], "Album")
        self.assertEqual(result["album_art"], "https://example.test/xl.jpg")
        self.assertEqual(call.call_args_list[1].args[0], "album.getInfo")

    def test_youtube_art_search_requires_opt_in(self):
        track_result = {"track": {"userloved": "0", "album": {"title": ""}}}
        with mock.patch.object(SCROBBLER, "call_api", return_value=track_result), \
             mock.patch.object(SCROBBLER, "get_youtube_music_art", return_value="art-url") as search:
            without_opt_in = SCROBBLER.get_track_info("key", "Artist", "Track", "user")
            self.assertNotIn("album_art", without_opt_in)
            search.assert_not_called()
            with_opt_in = SCROBBLER.get_track_info("key", "Artist", "Track", "user", youtube_art=True)
            self.assertEqual(with_opt_in["album_art"], "art-url")
            search.assert_called_once_with("Artist", "Track", "")

    def test_youtube_music_search_extracts_matching_art(self):
        data = {
            "contents": {
                "musicResponsiveListItemRenderer": {
                    "flexColumns": [
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {"runs": [{"text": "The Ship (Edit)"}]}
                            }
                        },
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {
                                    "runs": [
                                        {"text": "Song"},
                                        {"text": " • "},
                                        {"text": "Incredible Polo"},
                                    ]
                                }
                            }
                        },
                    ],
                    "thumbnail": {
                        "musicThumbnailRenderer": {
                            "thumbnail": {
                                "thumbnails": [
                                    {
                                        "url": "https://yt3.googleusercontent.com/art=w120",
                                        "width": 120,
                                        "height": 120,
                                    },
                                    {
                                        "url": "https://yt3.googleusercontent.com/art=w544",
                                        "width": 544,
                                        "height": 544,
                                    },
                                ]
                            }
                        }
                    },
                }
            }
        }
        encoded = "".join(
            f"\\x{byte:02x}"
            for byte in json.dumps(data, separators=(",", ":")).encode("utf-8")
        )
        html = (
            "initialData.push({path: '\\/search', params: JSON.parse('\\x7b\\x7d'), "
            f"data: '{encoded}'}});"
        )
        self.assertEqual(
            SCROBBLER.extract_youtube_music_art(
                html,
                "Incredible Polo",
                "The Ship (Edit)",
            ),
            "https://yt3.googleusercontent.com/art=w544",
        )
        self.assertEqual(
            SCROBBLER.extract_youtube_music_art(
                html,
                "Different Artist",
                "The Ship (Edit)",
            ),
            "",
        )

    def test_youtube_music_search_accepts_official_video_not_cover(self):
        def renderer(title, publisher, art):
            return {
                "musicResponsiveListItemRenderer": {
                    "flexColumns": [
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {"runs": [{"text": title}]}
                            }
                        },
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {
                                    "runs": [
                                        {"text": "Video"},
                                        {"text": " • "},
                                        {"text": publisher},
                                    ]
                                }
                            }
                        },
                    ],
                    "thumbnail": {
                        "musicThumbnailRenderer": {
                            "thumbnail": {
                                "thumbnails": [
                                    {"url": art, "width": 480, "height": 360}
                                ]
                            }
                        }
                    },
                }
            }

        data = {
            "contents": [
                renderer(
                    "Incredible Polo – The Ship (Sub. Español)",
                    "MrEsoj",
                    "https://i.ytimg.com/vi/cover/hqdefault.jpg",
                ),
                renderer(
                    'Incredible Polo - "The Ship" (Official video)',
                    "INCREDIBLE POLO",
                    "https://i.ytimg.com/vi/official/hqdefault.jpg",
                ),
            ]
        }
        encoded = "".join(
            f"\\x{byte:02x}"
            for byte in json.dumps(data, separators=(",", ":")).encode("utf-8")
        )
        html = (
            "initialData.push({path: '\\/search', params: JSON.parse('\\x7b\\x7d'), "
            f"data: '{encoded}'}});"
        )
        self.assertEqual(
            SCROBBLER.extract_youtube_music_art(
                html,
                "Incredible Polo",
                "The Ship (Edit)",
            ),
            "https://i.ytimg.com/vi/official/hqdefault.jpg",
        )

    def test_youtube_music_search_uses_exact_album_when_track_is_absent(self):
        data = {
            "contents": {
                "musicResponsiveListItemRenderer": {
                    "flexColumns": [
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {"runs": [{"text": "Pourquoi j'ai mal"}]}
                            }
                        },
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {
                                    "runs": [
                                        {"text": "EP"},
                                        {"text": " • "},
                                        {"text": "Gina"},
                                    ]
                                }
                            }
                        },
                    ],
                    "thumbnail": {
                        "musicThumbnailRenderer": {
                            "thumbnail": {
                                "thumbnails": [
                                    {
                                        "url": "https://yt3.googleusercontent.com/ep=w544",
                                        "width": 544,
                                        "height": 544,
                                    }
                                ]
                            }
                        }
                    },
                }
            }
        }
        encoded = "".join(
            f"\\x{byte:02x}"
            for byte in json.dumps(data, separators=(",", ":")).encode("utf-8")
        )
        html = (
            "initialData.push({path: '\\/search', params: JSON.parse('\\x7b\\x7d'), "
            f"data: '{encoded}'}});"
        )
        self.assertEqual(
            SCROBBLER.extract_youtube_music_art(
                html,
                "Gina",
                "L'œil de ma grand-mère",
                "Pourquoi j'ai mal",
            ),
            "https://yt3.googleusercontent.com/ep=w544",
        )

    def test_youtube_music_search_prefers_square_album_for_collaboration(self):
        def renderer(title, media_type, publisher, art, width, height):
            return {
                "musicResponsiveListItemRenderer": {
                    "flexColumns": [
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {"runs": [{"text": title}]}
                            }
                        },
                        {
                            "musicResponsiveListItemFlexColumnRenderer": {
                                "text": {
                                    "runs": [
                                        {"text": media_type},
                                        {"text": " • "},
                                        {"text": publisher},
                                    ]
                                }
                            },
                        },
                    ],
                    "thumbnail": {
                        "musicThumbnailRenderer": {
                            "thumbnail": {
                                "thumbnails": [
                                    {
                                        "url": art,
                                        "width": width,
                                        "height": height,
                                    }
                                ]
                            }
                        }
                    },
                }
            }

        data = {
            "contents": [
                renderer(
                    "60fps",
                    "Video",
                    "Yan Wagner & Meryem Aboulouafa",
                    "https://i.ytimg.com/vi/video/hqdefault.jpg",
                    480,
                    360,
                ),
                renderer(
                    "Souffle",
                    "Album",
                    "Yan Wagner",
                    "https://yt3.googleusercontent.com/album=w544",
                    544,
                    544,
                ),
            ]
        }
        encoded = "".join(
            f"\\x{byte:02x}"
            for byte in json.dumps(data, separators=(",", ":")).encode("utf-8")
        )
        html = (
            "initialData.push({path: '\\/search', params: JSON.parse('\\x7b\\x7d'), "
            f"data: '{encoded}'}});"
        )
        self.assertEqual(
            SCROBBLER.extract_youtube_music_art(
                html,
                "Yan Wagner & Meryem Aboulouafa",
                "60fps",
                "Souffle",
            ),
            "https://yt3.googleusercontent.com/album=w544",
        )

    def test_queue_writes_are_locked_and_atomic(self):
        with tempfile.TemporaryDirectory() as cache_dir:
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": cache_dir}):
                enqueue_code = (
                    "import importlib.util,sys;"
                    "spec=importlib.util.spec_from_file_location('worker',sys.argv[1]);"
                    "module=importlib.util.module_from_spec(spec);"
                    "spec.loader.exec_module(module);"
                    "module.enqueue({'artist':'Artist '+sys.argv[2],"
                    "'track':'Track','timestamp':sys.argv[2]})"
                )
                env = os.environ.copy()
                processes = [
                    subprocess.Popen(
                        [sys.executable, "-c", enqueue_code, str(ROOT / "scrobbler.py"), str(index)],
                        env=env,
                    )
                    for index in range(16)
                ]
                for process in processes:
                    self.assertEqual(process.wait(timeout=10), 0)

                queue = SCROBBLER.load_queue()
                self.assertEqual(len(queue), 16)
                self.assertEqual(
                    {entry["artist"] for entry in queue},
                    {f"Artist {index}" for index in range(16)},
                )
                queue_file = Path(SCROBBLER.queue_path())
                json.loads(queue_file.read_text(encoding="utf-8"))
                self.assertEqual(stat.S_IMODE(queue_file.stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(queue_file.parent.stat().st_mode), 0o700)

    def test_queue_rejects_symlinked_file(self):
        with tempfile.TemporaryDirectory() as cache_dir:
            queue_dir = Path(cache_dir) / "dms-scrobbler"
            queue_dir.mkdir()
            target = Path(cache_dir) / "target.json"
            target.write_text("[]", encoding="utf-8")
            (queue_dir / "queue.json").symlink_to(target)
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": cache_dir}):
                with self.assertRaisesRegex(OSError, "Unsafe queue path"):
                    SCROBBLER.load_queue()

    def test_stdin_json_transport(self):
        with tempfile.TemporaryDirectory() as cache_dir:
            env = os.environ.copy()
            env["XDG_CACHE_HOME"] = cache_dir
            result = subprocess.run(
                [sys.executable, str(ROOT / "scrobbler.py"), "--stdin-json"],
                input='{"args":["queue-count"]}\n',
                text=True,
                capture_output=True,
                check=False,
                env=env,
                timeout=10,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"count": 0, "lastfm": 0, "listenbrainz": 0})

    # ── ListenBrainz Tests ──

    def test_normalize_lb_url(self):
        self.assertEqual(SCROBBLER.normalize_lb_url(""), "https://api.listenbrainz.org")
        self.assertEqual(SCROBBLER.normalize_lb_url("https://lb.example.org/"), "https://lb.example.org")
        with self.assertRaises(ValueError):
            SCROBBLER.normalize_lb_url("file:///etc/passwd")
        with self.assertRaises(ValueError):
            SCROBBLER.normalize_lb_url("javascript:alert(1)")

    def test_call_lb_api_normalizes_http_error_message(self):
        err = urllib.error.HTTPError(
            "https://api.listenbrainz.org/1/metadata/lookup/",
            401,
            "Unauthorized",
            {"X-RateLimit-Remaining": "29", "X-RateLimit-Reset-In": "3"},
            io.BytesIO(b'{"code":401,"error":"You need to provide an Authorization header."}'),
        )
        try:
            with mock.patch.object(SCROBBLER.urllib.request, "urlopen", side_effect=err):
                res = SCROBBLER.call_lb_api("GET", "/1/metadata/lookup/")
        finally:
            err.close()
        self.assertEqual(res["error"], 401)
        self.assertEqual(res["http_status"], 401)
        self.assertEqual(res["message"], "You need to provide an Authorization header.")
        self.assertEqual(res["ratelimit_remaining"], 29)

    def test_lb_validate_token(self):
        with mock.patch.object(
            SCROBBLER.urllib.request,
            "urlopen",
            return_value=FakeHTTPResponse({"code": 200, "valid": True, "user_name": "arqueon"}),
        ) as urlopen_mock:
            valid = SCROBBLER.lb_validate_token("tok-123")
        self.assertTrue(valid["valid"])
        self.assertEqual(valid["username"], "arqueon")
        req = urlopen_mock.call_args.args[0]
        self.assertEqual(req.get_header("Authorization"), "Token tok-123")

        with mock.patch.object(
            SCROBBLER.urllib.request,
            "urlopen",
            return_value=FakeHTTPResponse({"code": 200, "valid": False, "message": "Token invalid."}),
        ):
            invalid = SCROBBLER.lb_validate_token("bad-tok")
        self.assertFalse(invalid["valid"])
        self.assertEqual(invalid["error"], 401)

    def test_lb_now_playing_omits_listened_at_and_returns_msid(self):
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            captured["auth"] = req.get_header("Authorization")
            captured["body"] = json.loads(req.data.decode("utf-8"))
            return FakeHTTPResponse({"status": "ok", "recording_msid": "msid-abc"})

        with mock.patch.object(SCROBBLER.urllib.request, "urlopen", side_effect=fake_urlopen):
            res = SCROBBLER.lb_now_playing(
                "tok-1", "Radiohead", "Creep", album="Pablo Honey", duration_ms=238000, player="mpd"
            )
        self.assertEqual(res, {"status": "ok", "recording_msid": "msid-abc"})
        self.assertIn("return_msid=true", captured["url"])
        self.assertEqual(captured["auth"], "Token tok-1")
        self.assertEqual(captured["body"]["listen_type"], "playing_now")
        item = captured["body"]["payload"][0]
        self.assertNotIn("listened_at", item)
        self.assertEqual(item["track_metadata"]["release_name"], "Pablo Honey")
        self.assertEqual(item["track_metadata"]["additional_info"]["duration_ms"], 238000)
        self.assertEqual(item["track_metadata"]["additional_info"]["media_player"], "mpd")

    def test_lb_scrobble_queues_on_retryable_only(self):
        with tempfile.TemporaryDirectory() as cache_dir:
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": cache_dir}):
                with mock.patch.object(
                    SCROBBLER,
                    "call_lb_api",
                    return_value={"error": 429, "message": "Rate limit exceeded"},
                ):
                    queued = SCROBBLER.lb_scrobble(
                        "tok", "Artist", "Track", 1700000100, album="Album", duration_ms=180000, player="mpd"
                    )
                self.assertTrue(queued["queued"])
                self.assertEqual(queued["service"], "listenbrainz")
                self.assertEqual(SCROBBLER.queue_stats()["listenbrainz"], 1)

                with mock.patch.object(
                    SCROBBLER,
                    "call_lb_api",
                    return_value={"error": 401, "message": "Unauthorized"},
                ):
                    rejected = SCROBBLER.lb_scrobble("bad", "Artist", "Track2", 1700000200)
                self.assertEqual(rejected["error"], 401)
                self.assertEqual(SCROBBLER.queue_stats()["listenbrainz"], 1)

    def test_multi_service_offline_queue_isolation(self):
        with tempfile.TemporaryDirectory() as cache_dir:
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": cache_dir}):
                SCROBBLER.save_queue([
                    {"artist": "Lfm1", "track": "Song1", "timestamp": "100"},
                    {"service": "listenbrainz", "artist": "Lb2", "track": "Song2", "timestamp": 300},
                    {"service": "listenbrainz", "artist": "Lb1", "track": "Song1", "timestamp": 200},
                ])
                stats = SCROBBLER.queue_stats()
                self.assertEqual(stats, {"count": 3, "lastfm": 1, "listenbrainz": 2})

                with mock.patch.object(SCROBBLER, "call_api", return_value={"scrobbles": {"@attr": {"accepted": 1}}}) as lfm_mock:
                    lfm_res = SCROBBLER.flush_lastfm_queue("k", "s", "sk")
                self.assertEqual(lfm_res["flushed"], 1)
                self.assertEqual(lfm_res["remaining"], 0)
                self.assertEqual(lfm_res["total_remaining"], 2)
                self.assertEqual(len(lfm_mock.call_args_list), 1)
                self.assertEqual(SCROBBLER.queue_stats()["listenbrainz"], 2)

                lb_bodies = []

                def fake_lb(method, path, token=None, base_url=None, params=None, body=None):
                    lb_bodies.append(body)
                    return {"status": "ok"}

                with mock.patch.object(SCROBBLER, "call_lb_api", side_effect=fake_lb):
                    lb_res = SCROBBLER.flush_lb_queue("tok")
                self.assertEqual(lb_res["flushed"], 2)
                self.assertEqual(lb_res["remaining"], 0)
                self.assertEqual(lb_res["total_remaining"], 0)
                self.assertEqual(lb_bodies[0]["listen_type"], "import")
                # Sorted ascending by timestamp
                self.assertEqual(
                    [x["listened_at"] for x in lb_bodies[0]["payload"]],
                    [200, 300],
                )
                self.assertEqual(SCROBBLER.load_queue(), [])

    def test_lb_flush_stops_when_ratelimit_exhausted(self):
        with tempfile.TemporaryDirectory() as cache_dir:
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": cache_dir}):
                entries = [
                    {"service": "listenbrainz", "artist": f"A{i}", "track": f"T{i}", "timestamp": 1000 + i}
                    for i in range(105)
                ]
                SCROBBLER.save_queue(entries)
                with mock.patch.object(
                    SCROBBLER,
                    "call_lb_api",
                    return_value={"status": "ok", "ratelimit_remaining": 0},
                ) as lb_mock:
                    res = SCROBBLER.flush_lb_queue("tok")
                self.assertEqual(len(lb_mock.call_args_list), 1)
                self.assertEqual(res["flushed"], 100)
                self.assertEqual(res["remaining"], 5)
                self.assertEqual(len(SCROBBLER.load_queue()), 5)

    def test_lb_lookup_sends_auth_and_retries_without_album(self):
        calls = []

        def fake_lb(method, path, token=None, base_url=None, params=None, body=None):
            calls.append((token, params))
            if "release_name" in params:
                return {}
            return {
                "recording_mbid": "mbid-rec-1",
                "release_mbid": "mbid-rel-1",
                "artist_mbids": ["mbid-art-1"],
                "release_name": "Canonical Album",
            }

        with mock.patch.object(SCROBBLER, "call_lb_api", side_effect=fake_lb):
            res = SCROBBLER.lb_lookup_metadata("tok-99", "Artist", "Track", album="Deluxe Edition")
        self.assertEqual(res["recording_mbid"], "mbid-rec-1")
        self.assertEqual(calls[0][0], "tok-99")
        self.assertIn("release_name", calls[0][1])
        self.assertNotIn("release_name", calls[1][1])

    def test_lb_love_prefers_mbid_and_falls_back_to_playing_now_msid(self):
        # 1) Mapped recording -> uses recording_mbid
        with mock.patch.object(
            SCROBBLER,
            "lb_lookup_metadata",
            return_value={"recording_mbid": "mbid-1", "release_mbid": "rel-1"},
        ), mock.patch.object(
            SCROBBLER,
            "lb_find_msid_from_user_listens",
            return_value={},
        ), mock.patch.object(
            SCROBBLER,
            "call_lb_api",
            return_value={"status": "ok"},
        ) as fb_mock:
            res = SCROBBLER.lb_love("tok", "arqueon", "Artist", "Song")
        self.assertTrue(res["loved"])
        self.assertEqual(fb_mock.call_args.kwargs["body"], {"recording_mbid": "mbid-1", "score": 1})

        # 2) Unmapped recording -> calls playing_now?return_msid=true and loves via MSID
        with mock.patch.object(SCROBBLER, "lb_lookup_metadata", return_value={}), \
             mock.patch.object(SCROBBLER, "lb_find_msid_from_user_listens", return_value={}), \
             mock.patch.object(
                 SCROBBLER,
                 "lb_now_playing",
                 return_value={"status": "ok", "recording_msid": "msid-minted"},
             ) as np_mock, \
             mock.patch.object(SCROBBLER, "call_lb_api", return_value={"status": "ok"}) as fb_mock:
            res2 = SCROBBLER.lb_love("tok", "arqueon", "Obscure", "Demo")
        self.assertTrue(res2["loved"])
        self.assertEqual(res2["recording_msid"], "msid-minted")
        np_mock.assert_called_once()
        self.assertEqual(fb_mock.call_args.kwargs["body"], {"recording_msid": "msid-minted", "score": 1})

    def test_lb_unlove_clears_legacy_msid_and_mbid_feedback(self):
        feedback_posts = []

        def fake_lb(method, path, token=None, base_url=None, params=None, body=None):
            if path.endswith("/get-feedback-for-recordings"):
                return {
                    "feedback": [
                        {"recording_mbid": "mbid-1", "recording_msid": None, "score": 1},
                        {"recording_mbid": None, "recording_msid": "msid-legacy", "score": 1},
                    ]
                }
            if path == "/1/feedback/recording-feedback":
                feedback_posts.append(body)
                return {"status": "ok"}
            return {}

        with mock.patch.object(
            SCROBBLER,
            "lb_lookup_metadata",
            return_value={"recording_mbid": "mbid-1"},
        ), mock.patch.object(
            SCROBBLER,
            "lb_find_msid_from_user_listens",
            return_value={"recording_msid": "msid-legacy"},
        ), mock.patch.object(
            SCROBBLER,
            "call_lb_api",
            side_effect=fake_lb,
        ):
            res = SCROBBLER.lb_unlove("tok", "arqueon", "Artist", "Song")

        self.assertFalse(res["loved"])
        self.assertEqual(
            feedback_posts,
            [
                {"recording_mbid": "mbid-1", "score": 0},
                {"recording_msid": "msid-legacy", "score": 0},
            ],
        )

    def test_lb_recent_now_playing_resolves_love_status(self):
        def fake_lb(method, path, token=None, base_url=None, params=None, body=None):
            if path.endswith("/playing-now"):
                return {
                    "payload": {
                        "listens": [{
                            "recording_msid": "msid-live",
                            "track_metadata": {
                                "artist_name": "Fenne Lily",
                                "track_name": "Hypochondriac",
                                "release_name": "Hypochondriac",
                                "mbid_mapping": {
                                    "recording_mbid": "rec-mbid-1",
                                    "release_mbid": "rel-mbid-1",
                                },
                            },
                        }]
                    }
                }
            if path.endswith("/get-feedback-for-recordings"):
                return {"feedback": [{"recording_mbid": "rec-mbid-1", "score": 1}]}
            return {}

        with mock.patch.object(SCROBBLER, "call_lb_api", side_effect=fake_lb):
            res = SCROBBLER.lb_recent_now_playing("arqueon", token="tok")
        self.assertTrue(res["now_playing"])
        self.assertEqual(res["artist"], "Fenne Lily")
        self.assertEqual(res["track"], "Hypochondriac")
        self.assertTrue(res["loved"])
        self.assertEqual(res["url"], "https://musicbrainz.org/recording/rec-mbid-1")


if __name__ == "__main__":
    unittest.main()
