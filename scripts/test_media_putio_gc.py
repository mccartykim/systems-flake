#!/usr/bin/env python3
"""Unit + integration-style tests for media_putio_gc.py.

Run: python3 scripts/test_media_putio_gc.py
No third-party deps: stdlib unittest, a local stub Jellyfin HTTP server, and a
fake rclone executable. Nothing touches put.io or the real Jellyfin.
"""

import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import media_putio_gc as gc  # noqa: E402

DAY = 86400.0
NOW = 1_700_000_000.0  # fixed epoch for arithmetic tests


def _utime(path, age_days):
    ts = NOW - age_days * DAY
    os.utime(path, (ts, ts))


class TestPathHelpers(unittest.TestCase):
    def test_is_video(self):
        for p in ("a.mkv", "B.MP4", "x/y.ts", "show.s01e01.m4v"):
            self.assertTrue(gc.is_video(p), p)
        for p in ("a.srt", "a.partial", "a.mkv.partial", "a", "a.jpg", "x.nfo"):
            self.assertFalse(gc.is_video(p), p)

    def test_putio_relpath(self):
        root = "/mnt/media-drive/putio"
        self.assertEqual(gc.putio_relpath(root + "/a/b.mkv", root), "a/b.mkv")
        self.assertEqual(gc.putio_relpath(root + "/a/b.mkv", root + "/"), "a/b.mkv")
        self.assertIsNone(gc.putio_relpath("/elsewhere/a.mkv", root))
        self.assertIsNone(gc.putio_relpath(root, root))
        self.assertIsNone(gc.putio_relpath(root + "x/a.mkv", root))

    def test_is_excluded_component_aware(self):
        ex = ["Items shared with you/Parsimony"]
        self.assertTrue(gc.is_excluded("Items shared with you/Parsimony/a.mkv", ex))
        self.assertTrue(gc.is_excluded("items shared with you/parsimony", ex))
        self.assertTrue(gc.is_excluded("Items shared with you/Parsimony", ex))
        # Must not over-match sibling names or a different share.
        self.assertFalse(gc.is_excluded("Items shared with you/Parsimony2/a.mkv", ex))
        self.assertFalse(gc.is_excluded("chill.institute/Parsimony/a.mkv", ex))
        self.assertFalse(gc.is_excluded("", ex))

    def test_parse_dt(self):
        v = gc.parse_dt("2024-01-02T03:04:05.1234567Z")
        self.assertEqual(v.isoformat(), "2024-01-02T03:04:05.123456+00:00")
        self.assertEqual(
            gc.parse_dt("2024-01-02T05:04:05+02:00").isoformat(),
            "2024-01-02T03:04:05+00:00",
        )
        self.assertEqual(
            gc.parse_dt("2024-01-02T03:04:05-0130").isoformat(),
            "2024-01-02T04:34:05+00:00",
        )
        self.assertEqual(
            gc.parse_dt("2024-01-02 03:04:05").isoformat(),
            "2024-01-02T03:04:05+00:00",
        )
        for bad in (None, "", "yesterday", "2024-13-01T00:00:00Z", 7):
            self.assertIsNone(gc.parse_dt(bad), bad)


class TestDecide(unittest.TestCase):
    def _decide(self, **kw):
        args = dict(rel="chill.institute/x/a.mkv", mtime=NOW - 31 * DAY,
                    link="/srv/media/TV Shows/Show/a.mkv",
                    userdata=[], favorite_paths=set(), now=NOW,
                    max_age_days=30, excludes=gc.DEFAULT_EXCLUDES)
        args.update(kw)
        return gc.decide(**args)

    def test_old_unwatched_is_eligible(self):
        self.assertEqual(self._decide(), (True, "unwatched"))

    def test_boundary_exactly_max_age_is_eligible(self):
        self.assertTrue(self._decide(mtime=NOW - 30 * DAY)[0])

    def test_too_new_protected(self):
        eligible, reason = self._decide(mtime=NOW - 29.9 * DAY)
        self.assertFalse(eligible)
        self.assertEqual(reason, "too-new")

    def test_missing_mtime_protected(self):
        self.assertEqual(self._decide(mtime=None), (False, "no-mtime"))

    def test_excluded_share_protected_even_if_old_and_unwatched(self):
        eligible, reason = self._decide(
            rel="Items shared with you/Parsimony/x/a.mkv"
        )
        self.assertFalse(eligible)
        self.assertEqual(reason, "excluded-share")

    def test_favorite_by_any_user_protected(self):
        link = "/srv/media/TV Shows/Show/a.mkv"
        self.assertEqual(
            self._decide(link=link, favorite_paths={link}),
            (False, "favorite"),
        )

    def test_favorited_series_protects_all_episodes(self):
        # Jellyfin stores the favorite on the Series, not the Episode.
        self.assertFalse(self._decide(
            link="/srv/media/TV Shows/Futurama (1999)/Season 1/e1.mkv",
            favorite_paths={"/srv/media/TV Shows/Futurama (1999)"},
        )[0])

    def test_favorited_season_protects_its_episodes(self):
        self.assertFalse(self._decide(
            link="/srv/media/TV Shows/Show/Season 1/e1.mkv",
            favorite_paths={"/srv/media/TV Shows/Show/Season 1"},
        )[0])

    def test_favorite_similar_prefix_does_not_protect(self):
        # "Show" must not protect "Show 2" or "Showcase".
        self.assertTrue(self._decide(
            link="/srv/media/TV Shows/Show 2/e1.mkv",
            favorite_paths={"/srv/media/TV Shows/Show"},
        )[0])
        self.assertTrue(self._decide(
            link="/srv/media/TV Shows/Showcase/e1.mkv",
            favorite_paths={"/srv/media/TV Shows/Show"},
        )[0])

    def test_viewed_within_window_protected(self):
        ud = [{"Played": True,
               "LastPlayedDate": "2023-12-01T00:00:00.0000000Z"}]
        eligible, reason = self._decide(
            userdata=ud, now=1_701_000_000.0  # 2023-11-26
        )
        # 2023-12-01 is after the (now - 30d) cutoff.
        self.assertFalse(eligible)
        self.assertEqual(reason, "viewed-recently")

    def test_viewed_before_window_still_eligible(self):
        # Seen long ago: "whether or not it's been seen before that period".
        ud = [{"Played": True,
               "LastPlayedDate": "2023-01-01T00:00:00Z"}]
        self.assertEqual(self._decide(userdata=ud), (True, "unwatched"))

    def test_in_progress_protected(self):
        ud = [{"Played": False, "PlaybackPositionTicks": 12_000_000}]
        self.assertEqual(self._decide(userdata=ud), (False, "in-progress"))

    def test_played_without_date_protected(self):
        ud = [{"Played": True}]
        self.assertEqual(self._decide(userdata=ud), (False, "played-undated"))
        ud2 = [{"Played": False, "PlayCount": 3}]
        self.assertEqual(self._decide(userdata=ud2), (False, "played-undated"))

    def test_finished_with_old_date_is_eligible(self):
        ud = [{"Played": True, "PlayCount": 1, "PlaybackPositionTicks": 0,
               "LastPlayedDate": "2023-01-01T00:00:00Z"}]
        self.assertTrue(self._decide(userdata=ud)[0])

    def test_multiple_users_union_protects(self):
        # Any user's recent view is enough; the other user's empty data is
        # irrelevant.
        ud = [{"Played": False},
              {"Played": True, "LastPlayedDate": "2023-11-30T00:00:00Z"}]
        self.assertFalse(
            self._decide(userdata=ud, now=1_701_000_000.0)[0]
        )


class TestPlan(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.putio = os.path.join(self.root, "putio")
        self.media = os.path.join(self.root, "media")
        os.makedirs(os.path.join(self.putio, "chill.institute", "show"))
        os.makedirs(os.path.join(self.putio, "Items shared with you",
                                 "Parsimony", "hers"))
        os.makedirs(os.path.join(self.media, "TV Shows", "show"))
        self.cache = {}

    def tearDown(self):
        self.tmp.cleanup()

    def make(self, rel, age_days, link_rel=None, link=True):
        target = os.path.join(self.putio, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(b"x")
        _utime(target, age_days)
        if not link:
            return target
        link_rel = link_rel or rel
        link = os.path.join(self.media, link_rel)
        os.makedirs(os.path.dirname(link), exist_ok=True)
        os.symlink(target, link)
        return link

    def run_plan(self, userdata=None):
        return gc.plan(
            [self.media], self.putio, userdata or {}, 30,
            gc.DEFAULT_EXCLUDES, now=NOW,
        )

    def test_old_chill_file_planned(self):
        link = self.make("chill.institute/show/a.mkv", 45)
        actions, reasons = self.run_plan()
        self.assertEqual([a["rel"] for a in actions],
                         ["chill.institute/show/a.mkv"])
        self.assertEqual(actions[0]["link"], link)
        self.assertAlmostEqual(actions[0]["age_days"], 45, places=3)
        self.assertEqual(reasons["unwatched"], 1)

    def test_parsimony_is_never_planned(self):
        self.make("Items shared with you/Parsimony/hers/a.mkv", 400)
        actions, reasons = self.run_plan()
        self.assertEqual(actions, [])
        self.assertEqual(reasons["excluded-share"], 1)

    def test_favorite_is_not_planned(self):
        link = self.make("chill.institute/show/a.mkv", 45)
        actions, _ = self.run_plan({link: [{"IsFavorite": True}]})
        self.assertEqual(actions, [])

    def test_favorited_series_dir_is_not_planned(self):
        self.make("chill.institute/show/a.mkv", 45, "TV Shows/show/a.mkv")
        series = os.path.join(self.media, "TV Shows", "show")
        actions, reasons = self.run_plan({series: [{"IsFavorite": True}]})
        self.assertEqual(actions, [])
        self.assertEqual(reasons["favorite"], 1)

    def test_non_video_regular_file_and_dead_link_ignored(self):
        self.make("chill.institute/show/notes.txt", 400)
        reg = self.make("chill.institute/show/b.mkv", 400, link=False)
        _utime(reg, 400)
        dead = os.path.join(self.media, "TV Shows", "show", "dead.mkv")
        os.symlink(os.path.join(self.putio, "gone.mkv"), dead)
        outside = os.path.join(self.media, "TV Shows", "show", "out.mkv")
        os.symlink("/etc/hostname", outside)
        actions, _ = self.run_plan()
        self.assertEqual(actions, [])

    def test_new_file_not_planned(self):
        self.make("chill.institute/show/a.mkv", 5)
        self.assertEqual(self.run_plan()[0], [])

    def test_duplicate_roots_do_not_double_count(self):
        self.make("chill.institute/show/a.mkv", 45)
        actions, _ = gc.plan(
            [self.media, self.media], self.putio, {}, 30,
            gc.DEFAULT_EXCLUDES, now=NOW,
        )
        self.assertEqual(len(actions), 1)

    def test_missing_root_is_ignored(self):
        actions, reasons = gc.plan(
            [os.path.join(self.root, "nope")], self.putio, {}, 30, [],
            now=NOW,
        )
        self.assertEqual((actions, reasons), ([], {}))


class _StubHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    users = []
    items = {}
    seen_requests = []

    def log_message(self, *args):
        pass

    def _send(self, payload, code=200):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        _StubHandler.seen_requests.append(self.path)
        if self.headers.get("Authorization", "").startswith("MediaBrowser Token="):
            pass
        else:
            return self._send({"error": "no auth"}, 401)
        if parsed.path == "/Users":
            return self._send(_StubHandler.users)
        if parsed.path.startswith("/Users/") and parsed.path.endswith("/Items"):
            uid = parsed.path.split("/")[2]
            q = parse_qs(parsed.query)
            items = _StubHandler.items.get(uid, [])
            start = int(q.get("startIndex", ["0"])[0])
            limit = int(q.get("limit", ["1000"])[0])
            return self._send({
                "Items": items[start:start + limit],
                "TotalRecordCount": len(items),
            })
        return self._send({"error": "not found"}, 404)


class StubJellyfin:
    def __init__(self, users, items):
        _StubHandler.users = users
        _StubHandler.items = items
        _StubHandler.seen_requests = []
        self.httpd = HTTPServer(("127.0.0.1", 0), _StubHandler)
        self.thread = threading.Thread(
            target=self.httpd.serve_forever, daemon=True
        )

    def __enter__(self):
        self.thread.start()
        host, port = self.httpd.server_address
        return f"http://{host}:{port}"

    def __exit__(self, *exc):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)


class TestJellyfinClient(unittest.TestCase):
    def test_union_across_users_and_pagination(self):
        items = {
            "u1": [
                {"Path": "/srv/media/a.mkv", "UserData": {"IsFavorite": True}},
                {"Path": "/srv/media/b.mkv", "UserData": {"Played": True}},
            ],
            "u2": [
                {"Path": "/srv/media/a.mkv", "UserData": {"Played": True}},
                {"Path": "/srv/media/c.mkv", "UserData": {"IsFavorite": True}},
            ],
        }
        users = [{"Id": "u1", "Name": "one"}, {"Id": "u2", "Name": "two"}]
        with StubJellyfin(users, items) as url:
            data = gc.jellyfin_userdata(url, "SECRET", page_size=1)
        self.assertEqual(set(data), {"/srv/media/a.mkv", "/srv/media/b.mkv",
                                     "/srv/media/c.mkv"})
        self.assertEqual(len(data["/srv/media/a.mkv"]), 2)
        self.assertTrue(any(u.get("IsFavorite")
                            for u in data["/srv/media/a.mkv"]))
        # 2 users x 2 pages each + 1 /Users call.
        self.assertEqual(len(_StubHandler.seen_requests), 5)

    def test_missing_path_is_skipped(self):
        users = [{"Id": "u1", "Name": "one"}]
        items = {"u1": [{"UserData": {"IsFavorite": True}}]}
        with StubJellyfin(users, items) as url:
            data = gc.jellyfin_userdata(url, "SECRET")
        self.assertEqual(data, {})


class TestDelete(unittest.TestCase):
    def test_delete_argv(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append(argv)
            return type("R", (), {"returncode": 0, "stdout": "", "stderr": ""})()

        ok = gc.delete_putio_file(
            "/usr/bin/rclone", "/cfg", "a b/c.mkv", runner=runner
        )
        self.assertTrue(ok)
        self.assertEqual(calls[0],
                         ["/usr/bin/rclone", "deletefile", "--config", "/cfg",
                          "putio:a b/c.mkv"])

    def test_failure_reported(self):
        def runner(argv, **kwargs):
            return type("R", (), {"returncode": 1, "stdout": "",
                                  "stderr": "boom"})()

        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertFalse(gc.delete_putio_file(
                "rclone", "cfg", "x.mkv", runner=runner))
        self.assertIn("boom", err.getvalue())

    def test_missing_binary_reported(self):
        def runner(argv, **kwargs):
            raise OSError("not found")

        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertFalse(gc.delete_putio_file(
                "rclone", "cfg", "x.mkv", runner=runner))
        self.assertIn("could not run", err.getvalue())


class TestMainEndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.putio = os.path.join(self.root, "putio")
        self.media = os.path.join(self.root, "media")
        self.log = os.path.join(self.root, "rclone.log")
        self.rclone = os.path.join(self.root, "fake-rclone")
        with open(self.rclone, "w", encoding="utf-8") as fh:
            fh.write(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{self.log}"\n')
        os.chmod(self.rclone, os.stat(self.rclone).st_mode | stat.S_IXUSR)

        self.keyfile = os.path.join(self.root, "key")
        with open(self.keyfile, "w", encoding="utf-8") as fh:
            fh.write("SECRET\n")

        self.link = self._make(
            "chill.institute/show/old.mkv", 45,
            os.path.join(self.media, "TV Shows", "show", "old.mkv"),
        )
        self.hers = self._make(
            "Items shared with you/Parsimony/hers/old.mkv", 45,
            os.path.join(self.media, "TV Shows", "hers", "old.mkv"),
        )

        users = [{"Id": "u1", "Name": "kimb"}]
        items = {"u1": [
            {"Path": self.link, "UserData": {"Played": False}},
            {"Path": self.hers, "UserData": {"Played": False}},
        ]}
        self.stub = StubJellyfin(users, items)
        self.url = self.stub.__enter__()

    def tearDown(self):
        self.stub.__exit__(None, None, None)
        self.tmp.cleanup()

    def _make(self, rel, age_days, link):
        target = os.path.join(self.putio, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(b"x")
        _utime(target, age_days)
        os.makedirs(os.path.dirname(link), exist_ok=True)
        os.symlink(target, link)
        return link

    def _argv(self, *extra):
        return [
            "--media-root", self.media,
            "--putio-root", self.putio,
            "--jellyfin-url", self.url,
            "--jellyfin-key-file", self.keyfile,
            "--rclone", self.rclone,
            "--rclone-config", "/unused",
            *extra,
        ]

    def _log(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as fh:
            return fh.read().splitlines()

    def test_dry_run_deletes_nothing_and_skips_parsimony(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = gc.main(self._argv("--dry-run"))
        self.assertEqual(rc, 0)
        text = out.getvalue()
        self.assertIn("media-putio-gc [DRY-RUN]", text)
        self.assertIn("WOULD DELETE putio:chill.institute/show/old.mkv", text)
        self.assertNotIn("Parsimony", text)
        # Dry-run must not touch put.io at all (no rclone calls).
        self.assertEqual(self._log(), [])

    def test_live_deletes_only_eligible(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = gc.main(self._argv())
        self.assertEqual(rc, 0)
        self.assertIn("media-putio-gc [LIVE]", out.getvalue())
        log = self._log()
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].endswith("putio:chill.institute/show/old.mkv"))

    def test_failure_exit_code(self):
        with open(self.rclone, "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\nexit 3\n")
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            rc = gc.main(self._argv())
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
