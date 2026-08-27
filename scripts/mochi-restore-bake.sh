#!/usr/bin/env bash
# Bake a self-contained mochi AVF quick-restore script. Secrets are baked
# ONLY as age blobs encrypted to a restore passphrase chosen at bake time —
# the resulting Bitwarden note carries NO usable private key material. The
# passphrase goes in a SEPARATE Bitwarden entry (two-factor by construction:
# the note alone is inert, the passphrase alone is inert).
#
# Encrypted into the note:
#   - mochi's STABLE SSH host key (also the age identity nebula-secrets.service
#     uses on-device to decrypt the nebula cert/key/ca from the public .age
#     blobs system-manager deploys to /etc/nebula/mainnet/encrypted/)
#   - mochi's git identity (flake_keys/ssh/mochi_git_ed25519_key, if present)
#     — installed for root AND kimb so nix can fetch the ssh://git@github.com
#     flake inputs (organisms, blog, etc.) during the system-manager switch.
# The host key .pub and git key .pub are public and baked as plaintext.
#
# Reads:  <flake_keys>/ssh/mochi_host_ed25519_key{,.pub}
#         <flake_keys>/ssh/mochi_host_ed25519_key.age  (preferred if present;
#          decrypt with HOST_KEY_AGE_IDENTITY, e.g. an age-plugin-yubikey
#          identity file — the YubiKey upgrade path for flake_keys)
#         <flake_keys>/ssh/mochi_git_ed25519_key{,.pub} (optional)
# Writes: ~/android_revival_script/script.sh — paste into a Bitwarden note,
#         never commit. Passphrase → separate Bitwarden entry.
#
# Run on a host that has flake_keys (syncthing) + nix + age:
#   bash scripts/mochi-restore-bake.sh
# Re-bake any time (e.g. after rotating the host key) with a fresh passphrase.
set -euo pipefail

FK="${FLAKE_KEYS:-/home/kimb/shared_projects/flake_keys}"
OUT="${OUT:-$HOME/android_revival_script/script.sh}"
SF="${SYSTEMS_FLAKE:-/home/kimb/projects/systems-flake}"
INSTALLER="${INSTALLER:-$(nix path-info "$SF#mochi-installer" 2>/dev/null)/bin/mochi-installer}"

AGE_BIN="$(command -v age || true)"
[ -n "$AGE_BIN" ] || AGE_BIN="$(nix build nixpkgs#age --no-link --print-out-paths 2>/dev/null)/bin/age"
[ -x "$AGE_BIN" ] || { echo "age not available" >&2; exit 1; }

# --- gather the host key (prefer age-encrypted copy in flake_keys) ----------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
if [ -f "$FK/ssh/mochi_host_ed25519_key.age" ]; then
  echo "flake_keys has an age-encrypted host key — decrypting"
  if [ -n "${HOST_KEY_AGE_IDENTITY:-}" ]; then
    "$AGE_BIN" -d -i "$HOST_KEY_AGE_IDENTITY" -o "$tmp/host_key" "$FK/ssh/mochi_host_ed25519_key.age"
  else
    "$AGE_BIN" -d -o "$tmp/host_key" "$FK/ssh/mochi_host_ed25519_key.age"   # passphrase prompt
  fi
elif [ -f "$FK/ssh/mochi_host_ed25519_key" ]; then
  echo "NOTE: flake_keys host key is PLAINTEXT — consider the YubiKey/age upgrade" >&2
  cp "$FK/ssh/mochi_host_ed25519_key" "$tmp/host_key"
else
  echo "missing mochi host key in $FK/ssh/" >&2; exit 1
fi
cp "$FK/ssh/mochi_host_ed25519_key.pub" "$tmp/host_key.pub"
chmod 600 "$tmp/host_key"

# --- encrypt host key + (optional) git key to the restore passphrase -------
# age -p reads the passphrase from the tty (enter + confirm). Both blobs use
# the SAME passphrase; the restore script prompts for it exactly twice.
"$AGE_BIN" -p -o "$tmp/host_key.age" "$tmp/host_key"
HOSTKEY_AGE_B64="$(base64 -w0 "$tmp/host_key.age")"
HOSTKEY_PUB_B64="$(base64 -w0 "$tmp/host_key.pub")"

GITKEY_STASH=0
if [ -f "$FK/ssh/mochi_git_ed25519_key" ]; then
  "$AGE_BIN" -p -o "$tmp/git_key.age" "$FK/ssh/mochi_git_ed25519_key"
  GITKEY_AGE_B64="$(base64 -w0 "$tmp/git_key.age")"
  GITKEY_PUB_B64="$(base64 -w0 "$FK/ssh/mochi_git_ed25519_key.pub")"
  GITKEY_STASH=1
fi

[ -f "$INSTALLER" ] || { echo "missing installer: $INSTALLER (build .#mochi-installer)" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'HDR'
#!/usr/bin/env bash
# mochi AVF quick-restore — keys travel ONLY as passphrase-encrypted age
# blobs; this script contains NO usable private key material. The restore
# passphrase lives in a SEPARATE Bitwarden entry. GENERATED; never commit.
# Run on a fresh mochi AVF Debian shell (as droid or root; sudo needed).
set -euo pipefail

# Stage 0-pre: age (Debian bookworm+/trixie) for the encrypted-key restore.
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq age curl ca-certificates sudo

# Stage 0a: restore mochi's STABLE SSH host key from the passphrase-encrypted
# blob. This key is the age identity nebula-secrets.service later uses to
# decrypt the nebula cert/key/ca — no rotation dance, no plaintext in notes.
sudo install -d -m 755 /etc/ssh
printf '%s' "HOSTKEY_PUB_PLACEHOLDER" | base64 -d | sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null
printf '%s' "HOSTKEY_AGE_PLACEHOLDER" | base64 -d > /tmp/mochi-host-key.age
age -d -o /tmp/mochi-host-ed25519 /tmp/mochi-host-key.age   # prompts for the restore passphrase
sudo install -m 600 /tmp/mochi-host-ed25519 /etc/ssh/ssh_host_ed25519_key
rm -f /tmp/mochi-host-ed25519 /tmp/mochi-host-key.age
printf 'host key restored: '; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub || true
HDR

if [ "$GITKEY_STASH" = 1 ]; then
  cat >> "$OUT" <<GITSTASH
# Stage 0b: stash the git identity (installed in Stage final for root + kimb).
# Encrypted with the SAME restore passphrase; the .pub is public material.
printf '%s' "$GITKEY_PUB_B64" | base64 -d > /root/.mochi-git-key.pub
printf '%s' "$GITKEY_AGE_B64" | base64 -d > /root/.mochi-git-key.age
chmod 600 /root/.mochi-git-key.age
GITSTASH
fi

# Append the mochi-installer body (drop its nix-store shebang; the body is
# portable bash using only system-PATH tools — apt-get/curl/git/sudo).
tail -n +2 "$INSTALLER" >> "$OUT"

cat >> "$OUT" <<'FINAL'
# Stage final: restart nebula against the restored host key + verify.
sudo systemctl restart nebula-secrets.service 2>/dev/null || true
sudo systemctl restart nebula-mainnet.service 2>/dev/null || true
sleep 2
if ip -4 addr show nebula0 >/dev/null 2>&1; then
  echo "mochi is on the mesh: $(ip -4 -o addr show nebula0 | awk '{print $4}')"
else
  echo "nebula0 not up yet — check: sudo systemctl status nebula-mainnet nebula-secrets"
  echo "decrypt errors = .age recipient mismatch: sudo journalctl -u nebula-secrets -b --no-pager"
fi
if [ -f /root/.mochi-git-key.age ]; then
  # Install the git identity for root (nix fetches of ssh://git@github.com
  # flake inputs run as root during `system-manager switch`) and for kimb.
  age -d -o /root/.mochi-git-key /root/.mochi-git-key.age   # restore passphrase (2nd prompt)
  sudo install -d -m 700 /root/.ssh /home/kimb/.ssh
  sudo install -m 600 /root/.mochi-git-key /root/.ssh/id_ed25519
  sudo install -m 644 /root/.mochi-git-key.pub /root/.ssh/id_ed25519.pub
  sudo install -m 600 /root/.mochi-git-key /home/kimb/.ssh/id_ed25519
  sudo install -m 644 /root/.mochi-git-key.pub /home/kimb/.ssh/id_ed25519.pub
  sudo chown -R kimb:kimb /home/kimb/.ssh
  printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/id_ed25519\n  IdentitiesOnly yes\n' \
    | sudo tee /root/.ssh/config >/dev/null
  printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/id_ed25519\n  IdentitiesOnly yes\n' \
    | sudo tee /home/kimb/.ssh/config >/dev/null
  sudo chown kimb:kimb /home/kimb/.ssh/config
  sudo rm -f /root/.mochi-git-key /root/.mochi-git-key.pub /root/.mochi-git-key.age
  echo "git identity installed for root + kimb. GitHub registration (one-time):"
  echo "  $(cat /home/kimb/.ssh/id_ed25519.pub)"
fi
echo "SSH host key pre-installed; ssh kimb@mochi.nebula (host key stable across wipes)."
FINAL

# Splice the baked blobs into the placeholders (keeps plaintext out of every
# heredoc above; only ciphertext + public keys are embedded in the output).
HOSTKEY_AGE_B64="$HOSTKEY_AGE_B64" HOSTKEY_PUB_B64="$HOSTKEY_PUB_B64" python3 - "$OUT" <<'SPLICE'
import os, sys
path = sys.argv[1]
s = open(path).read()
s = s.replace("HOSTKEY_AGE_PLACEHOLDER", os.environ["HOSTKEY_AGE_B64"])
s = s.replace("HOSTKEY_PUB_PLACEHOLDER", os.environ["HOSTKEY_PUB_B64"])
open(path, "w").write(s)
SPLICE
chmod 600 "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
echo "→ paste into a Bitwarden note; store the restore PASSPHRASE in a SEPARATE entry."
echo "On a fresh mochi AVF shell: bash $OUT"