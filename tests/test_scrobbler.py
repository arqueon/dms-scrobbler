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
        class Response:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return b"{}"

        with mock.patch.object(SCROBBLER.urllib.request, "urlopen", return_value=Response()):
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
        self.assertEqual(json.loads(result.stdout), {"count": 0})


if __name__ == "__main__":
    unittest.main()
