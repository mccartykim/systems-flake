#!/usr/bin/env python3
"""Encrypt the HomeBox API-key pepper into secrets/homebox-api-pepper.age.

## Why this exists

The pepper must reach HomeBox as an environment variable, but it must not live in the Nix store —
unit `Environment=` lines are world-readable there. The pinned nixpkgs' homebox module only offers
`settings`, which becomes exactly that. The 0.26.2-era module added a `secrets` option, but this
repo is pinned to the 0.25.0-era one.

So the pepper goes through agenix instead, and HomeBox gets it via systemd `EnvironmentFile=`, which
systemd reads at start and resolves the `@path@` indirection in (a plain `Environment=` would NOT
expand it, which is a silent failure: the variable would literally be the string "@...@").

## Why not re-encrypt

The pepper already exists and is in use: it is hashed into the HomeBox API key that `bin_finder_ai`
authenticates with. `secrets.nix` says re-encrypting is safe because the plaintext is unchanged and
only the recipients differ — which is true here (add historian), so this does not invalidate
anything. Generating a NEW pepper would, and that is the one thing not to do.

## Recipients

historian's host key (the consumer) plus the bootstrap key, matching how every other secret in this
repo is addressed, so agenix rekeying keeps working.

Usage:
    tools/encrypt-pepper.py            # writes secrets/homebox-api-pepper.age
    tools/encrypt-pepper.py --check    # report what would happen, change nothing
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

#: The live pepper. Read from the agenix-decrypted copy FIRST: `secrets/homebox-api-pepper.age` is a
#: function of that value, so reading anything else risks re-encrypting a stale or absent pepper.
#:
#: The fallbacks exist because a NEW host has no agenix copy yet. Note the agenix file holds an
#: `HBOX_AUTH_API_KEY_PEPPER=<value>` env line rather than the bare value (systemd ignores an
#: EnvironmentFile line with no `=`), so that source needs its prefix stripped — see read_pepper().
#:
#: A pepper that is merely SHORT does not fail here; it fails inside HomeBox as a panic, and if it
#: overwrote a good one it would invalidate every issued API key. Hence the length floor below.
SOURCES = [
    pathlib.Path("/run/agenix/homebox-api-pepper"),
    pathlib.Path("/mnt/media-drive/bin-finder/homebox-api-pepper-secret"),
    pathlib.Path("/var/lib/homebox/api-pepper-secret"),
]

#: historian's SSH host key — the only consumer. From hosts/nebula-registry.nix.
#:
#: These two literals are transcribed from that file. During development a hand-typed copy of this
#: key was MALFORMED (one wrong base64 character) and age's error is "malformed SSH recipient",
#: which does not say "you mistyped it". If this ever changes, copy it programmatically:
#:
#:     python3 -c "import re,pathlib; t=pathlib.Path('hosts/nebula-registry.nix').read_text(); \
#:       print(re.search(r'historian = \{(.*?)\n    \};', t, re.S).group(1))"
RECIPIENT_HOST = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+"

#: The bootstrap key used for agenix re-encryption, same file as `bootstrap` in secrets.nix.
RECIPIENT_BOOTSTRAP = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U"

#: agenix's own minimum. HomeBox panics below 32 bytes, so this is also a correctness floor.
MIN_BYTES = 32

DEST = pathlib.Path(__file__).resolve().parent.parent / "secrets" / "homebox-api-pepper.age"


def read_pepper() -> tuple[pathlib.Path, bytes] | tuple[None, None]:
    """Find the plaintext pepper and return `(path, bytes)`.

    Strips the `HBOX_AUTH_API_KEY_PEPPER=` prefix when reading the agenix-decrypted copy, because
    that file is an EnvironmentFile and holds a `KEY=value` line. Writing the prefixed form straight
    back in would produce `HBOX_AUTH_API_KEY_PEPPER=HBOX_AUTH_API_KEY_PEPPER=...`, which is non-empty
    and therefore would not fail loudly — HomeBox would simply reject every API key.
    """
    for candidate in SOURCES:
        if not candidate.is_file():
            continue
        try:
            raw = candidate.read_bytes()
        except OSError:
            continue
        prefix = b"HBOX_AUTH_API_KEY_PEPPER="
        if raw.startswith(prefix):
            raw = raw[len(prefix):]
        return candidate, raw.strip()
    return None, None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--age", default="age", help="path to the age binary")
    args = ap.parse_args()

    src, raw = read_pepper()
    if src is None or raw is None:
        print("no pepper found in any of:", file=sys.stderr)
        for candidate in SOURCES:
            print(f"  {candidate}", file=sys.stderr)
        print(
            "On a fresh host the pepper does not exist yet. It is written by the nixpkgs homebox\n"
            "module's setup service, or migrated by hand. Generate one ONLY if keys have never been\n"
            "issued — a new pepper invalidates every existing HomeBox API key.",
            file=sys.stderr,
        )
        return 2

    # systemd EnvironmentFile requires KEY=VALUE. A bare value on its own line is SILENTLY IGNORED,
    # which makes HomeBox panic with the file present and readable — the failure looks like a missing
    # or truncated secret rather than a wrong file format. So the env line is built here.
    value = b"HBOX_AUTH_API_KEY_PEPPER=" + raw + b"\n"
    # Length only — never the value. A short pepper would panic HomeBox at start, so check it here
    # rather than discovering it after a deploy.
    if len(raw) < MIN_BYTES:
        print(
            f"pepper at {src} is {len(raw)} bytes, under the {MIN_BYTES}-byte minimum; "
            "HomeBox would refuse to start",
            file=sys.stderr,
        )
        return 2
    print(f"source     {src}")
    print(f"bytes      {len(raw)} secret + {len(value) - len(raw)} bytes of KEY= prefix")
    print(f"dest       {DEST}")

    if args.check:
        print("--check: nothing written")
        return 0

    recipients = [RECIPIENT_HOST, RECIPIENT_BOOTSTRAP]
    cmd = [args.age, "--encrypt"]
    for r in recipients:
        cmd += ["--recipient", r]
    cmd += ["--output", str(DEST)]

    if not DEST.parent.is_dir():
        print(f"missing directory {DEST.parent}", file=sys.stderr)
        return 2

    try:
        result = subprocess.run(cmd, input=value, capture_output=True, check=False)
    except FileNotFoundError:
        print(f"age binary not found ({args.age}); `nix develop` provides it", file=sys.stderr)
        return 2

    if result.returncode != 0:
        print(f"age failed ({result.returncode}): {result.stderr.decode()[:400]}", file=sys.stderr)
        return 1

    st = DEST.stat()
    print(f"wrote      {DEST}  ({st.st_size} bytes, {oct(st.st_mode & 0o777)})")
    print(f"recipients {len(recipients)}: historian host key + bootstrap")
    print()
    print("NOTE: the plaintext is unchanged, so no existing HomeBox API key is invalidated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
