#!/usr/bin/env python3
"""put.io media garbage collector.

Deletes a video from put.io when ALL of these hold:

  * it is older than --max-age-days (each file's clock starts at its own
    mtime, which rclone preserves from put.io via --no-update-modtime)
  * no Jellyfin user has it favorited
  * no Jellyfin user played it within --max-age-days (a view before that
    window does not save it)
  * it is not in progress (PlaybackPositionTicks > 0, not finished)

Scope is the media-classifier symlink farm under /srv/media/{Movies,TV Shows,
Anime}: only files the classifier linked into Jellyfin are candidates. Files
under an excluded put.io prefix (the roommate's shared folder) are never
touched, no matter how old or unwatched they are.

The Jellyfin API is used instead of its SQLite DB because the service runs as
kimb:media, which can read /run/agenix/jellyfin-api-key but not Jellyfin's
data directory.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

DEFAULT_MEDIA_ROOTS = [
    "/srv/media/Movies",
    "/srv/media/TV Shows",
    "/srv/media/Anime",
]
DEFAULT_PUTIO_ROOT = "/mnt/media-drive/putio"
DEFAULT_EXCLUDES = ["Items shared with you/Parsimony"]
DEFAULT_JELLYFIN_URL = "http://localhost:8096"

VIDEO_EXTS = (
    "mkv", "mp4", "avi", "m4v", "mov", "wmv", "flv", "webm", "ts",
    "m2ts", "mpg", "mpeg", "vob", "ogv", "3gp", "rm", "rmvb",
)
_VIDEO_RE = re.compile(r"\.(?:" + "|".join(VIDEO_EXTS) + r")$", re.IGNORECASE)
_DT_RE = re.compile(
    r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})"
    r"(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$"
)


def is_video(path: str) -> bool:
    """True for a path with a video extension (rclone .partial files excluded)."""
    return bool(_VIDEO_RE.search(path))


def putio_relpath(target: str, putio_root: str) -> str | None:
    """Path relative to the put.io mirror root, or None if outside it."""
    root = putio_root.rstrip("/") + "/"
    if not target.startswith(root):
        return None
    rel = target[len(root):]
    return rel or None


def is_excluded(rel: str, excludes: list[str]) -> bool:
    """True if rel is the excluded dir itself or lives under it.

    Component-aware on purpose: 'Parsimony2/foo' must not match 'Parsimony'.
    """
    low = rel.lower()
    for raw in excludes:
        ex = raw.strip("/").lower()
        if not ex:
            continue
        if low == ex or low.startswith(ex + "/"):
            return True
    return False


def parse_dt(value: str | None) -> datetime | None:
    """Parse a Jellyfin ISO-8601 timestamp (7-digit fractions, Z offsets).

    Returns an aware UTC datetime, or None for missing/garbage values.
    """
    if not isinstance(value, str):
        return None
    m = _DT_RE.match(value.strip())
    if not m:
        return None
    year, month, day, hour, minute, second, frac, tz = m.groups()
    micro = int((frac or "0")[:6].ljust(6, "0"))
    if tz in (None, "Z"):
        offset = timedelta(0)
    else:
        sign = 1 if tz[0] == "+" else -1
        digits = tz[1:].replace(":", "")
        offset = sign * timedelta(hours=int(digits[:2]), minutes=int(digits[2:4]))
    try:
        return datetime(
            int(year), int(month), int(day), int(hour), int(minute),
            int(second), micro, tzinfo=timezone(offset),
        ).astimezone(timezone.utc)
    except ValueError:
        return None


def has_favorited_ancestor(link: str, favorite_paths: set[str]) -> bool:
    """True if link or any parent directory is favorited.

    Jellyfin favorites live on the Series/Season item, not on each Episode, so
    a favorited show must protect every file beneath its path.
    """
    path = link
    while True:
        if path in favorite_paths:
            return True
        parent = os.path.dirname(path)
        if parent == path:
            return False
        path = parent


def decide(
    rel: str,
    mtime: float | None,
    link: str,
    userdata: list[dict] | None,
    favorite_paths: set[str] | None,
    now: float,
    max_age_days: float,
    excludes: list[str] | None = None,
) -> tuple[bool, str]:
    """Should this file be deleted? Returns (eligible, reason)."""
    if is_excluded(rel, excludes or []):
        return False, "excluded-share"
    if mtime is None:
        return False, "no-mtime"
    age_days = (now - mtime) / 86400.0
    if age_days < max_age_days:
        return False, "too-new"

    cutoff = now - max_age_days * 86400.0
    entries = userdata or []
    if has_favorited_ancestor(link, favorite_paths or set()):
        return False, "favorite"

    played_undated = False
    for u in entries:
        last = parse_dt(u.get("LastPlayedDate"))
        if last is not None and last.timestamp() >= cutoff:
            return False, "viewed-recently"
        played = bool(u.get("Played")) or int(u.get("PlayCount") or 0) > 0
        if played and last is None:
            played_undated = True
    if played_undated:
        # Seen at some unknown time: can't prove it is outside the window.
        return False, "played-undated"
    for u in entries:
        if int(u.get("PlaybackPositionTicks") or 0) > 0 and not u.get("Played"):
            return False, "in-progress"
    return True, "unwatched"


def iter_media_links(roots: list[str]):
    """Yield symlinks under the media roots that look like video files."""
    seen: set[str] = set()
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            for name in filenames:
                link = os.path.join(dirpath, name)
                if link in seen or not is_video(link) or not os.path.islink(link):
                    continue
                seen.add(link)
                yield link


def plan(
    roots: list[str],
    putio_root: str,
    userdata: dict[str, list[dict]],
    max_age_days: float,
    excludes: list[str],
    now: float | None = None,
) -> tuple[list[dict], dict[str, int]]:
    """Build the deletion list. Returns (actions, reason counts)."""
    now = time.time() if now is None else now
    favorite_paths = {
        path for path, entries in userdata.items()
        if any(bool(u.get("IsFavorite")) for u in entries)
    }
    actions: list[dict] = []
    reasons: dict[str, int] = {}
    for link in iter_media_links(roots):
        target = os.path.realpath(link)
        rel = putio_relpath(target, putio_root)
        if rel is None:
            continue
        try:
            mtime = os.stat(target).st_mtime
        except OSError:
            continue  # dead link; media-symlink-cleanup owns it
        eligible, reason = decide(
            rel, mtime, link, userdata.get(link), favorite_paths,
            now, max_age_days, excludes
        )
        reasons[reason] = reasons.get(reason, 0) + 1
        if eligible:
            actions.append({
                "link": link,
                "rel": rel,
                "age_days": (now - mtime) / 86400.0,
            })
    return actions, reasons


def _api_get_json(url: str, api_key: str, timeout: float = 60.0):
    req = urllib.request.Request(
        url, headers={"Authorization": f'MediaBrowser Token="{api_key}"'}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def jellyfin_userdata(
    base_url: str = DEFAULT_JELLYFIN_URL,
    api_key: str = "",
    page_size: int = 1000,
    timeout: float = 60.0,
) -> dict[str, list[dict]]:
    """Map Jellyfin item Path -> UserData of every user, unioned."""
    base = base_url.rstrip("/")
    users = _api_get_json(f"{base}/Users", api_key, timeout)
    data: dict[str, list[dict]] = {}
    for user in users:
        start = 0
        while True:
            query = urllib.parse.urlencode({
                # Series/Season included so a favorited show protects its
                # episodes (Jellyfin stores the favorite on the parent item).
                "recursive": "true",
                "includeItemTypes": "Movie,Episode,Series,Season",
                "fields": "Path,UserData",
                "enableImages": "false",
                "limit": page_size,
                "startIndex": start,
            })
            page = _api_get_json(
                f"{base}/Users/{user['Id']}/Items?{query}", api_key, timeout
            )
            items = page.get("Items") or []
            for item in items:
                path = item.get("Path")
                if path:
                    data.setdefault(path, []).append(item.get("UserData") or {})
            start += len(items)
            total = int(page.get("TotalRecordCount") or 0)
            if not items or start >= total:
                break
    return data


def delete_putio_file(
    rclone: str,
    config: str,
    rel: str,
    runner=subprocess.run,
) -> bool:
    """Delete one file from put.io. Returns False on failure."""
    argv = [rclone, "deletefile", "--config", config, "putio:" + rel]
    try:
        res = runner(argv, capture_output=True, text=True, check=False)
    except OSError as exc:
        print(f"ERROR: could not run {rclone}: {exc}", file=sys.stderr)
        return False
    if res.returncode != 0:
        detail = (res.stderr or res.stdout or "").strip()
        print(f"ERROR deleting putio:{rel}: {detail}", file=sys.stderr)
        return False
    return True


def main(argv: list[str] | None = None) -> int:
    # journald otherwise buffers every per-file line until the process exits,
    # which hides progress on a ~1h run.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--media-root", action="append", dest="media_roots",
                    help="media root to scan; repeatable")
    ap.add_argument("--putio-root", default=DEFAULT_PUTIO_ROOT)
    ap.add_argument("--max-age-days", type=float, default=30.0)
    ap.add_argument("--exclude", action="append", dest="excludes",
                    help="put.io path prefix to never touch; repeatable")
    ap.add_argument("--jellyfin-url", default=DEFAULT_JELLYFIN_URL)
    ap.add_argument("--jellyfin-key-file", required=True)
    ap.add_argument("--rclone", default="rclone")
    ap.add_argument("--rclone-config", required=True)
    ap.add_argument("--dry-run", action="store_true",
                    help="log decisions without calling rclone")
    args = ap.parse_args(argv)

    roots = args.media_roots or DEFAULT_MEDIA_ROOTS
    excludes = args.excludes if args.excludes is not None else DEFAULT_EXCLUDES

    with open(args.jellyfin_key_file, encoding="utf-8") as fh:
        api_key = fh.read().strip()

    userdata = jellyfin_userdata(args.jellyfin_url, api_key)
    actions, reasons = plan(
        roots, args.putio_root, userdata, args.max_age_days, excludes
    )

    mode = "DRY-RUN" if args.dry_run else "LIVE"
    print(f"media-putio-gc [{mode}]: {len(userdata)} Jellyfin paths, "
          f"{len(actions)} eligible of {sum(reasons.values())} candidates")
    summary = ", ".join(f"{k}={v}" for k, v in sorted(reasons.items()))
    print(f"  decisions: {summary}")

    failures = 0
    for action in actions:
        if args.dry_run:
            # Never call rclone in dry-run: one API round-trip per file would
            # hammer put.io for no benefit. The decisions ARE the dry run.
            print(
                f"  WOULD DELETE putio:{action['rel']} "
                f"(age {action['age_days']:.1f}d)"
            )
            continue
        print(f"  DELETE putio:{action['rel']} (age {action['age_days']:.1f}d)")
        if not delete_putio_file(args.rclone, args.rclone_config, action["rel"]):
            failures += 1

    if failures:
        print(f"  {failures} deletion(s) failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
