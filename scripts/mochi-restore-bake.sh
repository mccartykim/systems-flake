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
# The fido2-hmac plugin must be on PATH for age to invoke it (decrypting the
# YubiKey-sealed keys). Token + touch required at those decryptions.
FIDO_PLUGIN="$(command -v age-plugin-fido2-hmac || true)"
if [ -z "$FIDO_PLUGIN" ]; then
  FIDO_DIR="$(nix build nixpkgs#age-plugin-fido2-hmac --no-link --print-out-paths 2>/dev/null)"
  [ -n "$FIDO_DIR" ] && export PATH="$FIDO_DIR/bin:$PATH"
fi
YK_IDENTITY="${YK_IDENTITY:-$FK/ssh/mochi_host_yubikey_identity.txt}"

# --- gather the host key (prefer the YubiKey-sealed copy) ------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
if [ -f "$FK/ssh/mochi_host_ed25519_key.age" ]; then
  echo "flake_keys has a YubiKey-sealed host key — decrypting (touch the token)"
  "$AGE_BIN" -d -i "${HOST_KEY_AGE_IDENTITY:-$YK_IDENTITY}" -o "$tmp/host_key" \
    "$FK/ssh/mochi_host_ed25519_key.age"
elif [ -f "$FK/ssh/mochi_host_ed25519_key" ]; then
  echo "NOTE: falling back to PLAINTEXT host key — prefer the YubiKey-sealed .age" >&2
  cp "$FK/ssh/mochi_host_ed25519_key" "$tmp/host_key"
else
  echo "missing mochi host key in $FK/ssh/" >&2; exit 1
fi
cp "$FK/ssh/mochi_host_ed25519_key.pub" "$tmp/host_key.pub"
chmod 600 "$tmp/host_key"

# --- gather the git identity (prefer the YubiKey-sealed copy) --------------
GITKEY_STASH=0
if [ -f "$FK/ssh/mochi_git_ed25519_key.age" ]; then
  echo "decrypting YubiKey-sealed git identity (touch the token)"
  "$AGE_BIN" -d -i "${HOST_KEY_AGE_IDENTITY:-$YK_IDENTITY}" -o "$tmp/git_key" \
    "$FK/ssh/mochi_git_ed25519_key.age"
  GITKEY_STASH=1
elif [ -f "$FK/ssh/mochi_git_ed25519_key" ]; then
  echo "NOTE: falling back to PLAINTEXT git identity — prefer the YubiKey-sealed .age" >&2
  cp "$FK/ssh/mochi_git_ed25519_key" "$tmp/git_key"
  GITKEY_STASH=1
fi
# --- seal both keys to TWO independent recipients (either opens alone) -----
# age refuses to mix passphrase recipients with others in one file, so each
# key gets two sibling envelopes:
#   <key>.pass.age   — age -p (scrypt)   → the restore passphrase
#   <key>.fido2.age  — age -r <fido2 recipient> (offline seal; token+touch to open)
# The restore script tries the fido2 blob first, falls back to the passphrase.
FIDO_R="$("$AGE_BIN" 2>/dev/null; age-plugin-fido2-hmac -y "$YK_IDENTITY" 2>/dev/null | grep -oP "age1\\S+" | head -1)"
[ -n "$FIDO_R" ] || { echo "could not derive fido2 recipient from $YK_IDENTITY" >&2; exit 1; }

"$AGE_BIN" -p -o "$tmp/host_key.pass.age" "$tmp/host_key"
"$AGE_BIN" -r "$FIDO_R" -o "$tmp/host_key.fido2.age" "$tmp/host_key"
HOSTKEY_AGE_B64="$(base64 -w0 "$tmp/host_key.pass.age")"
HOSTKEY_FIDO_B64="$(base64 -w0 "$tmp/host_key.fido2.age")"
HOSTKEY_PUB_B64="$(base64 -w0 "$tmp/host_key.pub")"

if [ "$GITKEY_STASH" = 1 ] && [ -f "$tmp/git_key" ]; then
  "$AGE_BIN" -p -o "$tmp/git_key.pass.age" "$tmp/git_key"
  "$AGE_BIN" -r "$FIDO_R" -o "$tmp/git_key.fido2.age" "$tmp/git_key"
  GITKEY_AGE_B64="$(base64 -w0 "$tmp/git_key.pass.age")"
  GITKEY_FIDO_B64="$(base64 -w0 "$tmp/git_key.fido2.age")"
  GITKEY_PUB_B64="$(base64 -w0 "$FK/ssh/mochi_git_ed25519_key.pub")"
fi

[ -f "$INSTALLER" ] || { echo "missing installer: $INSTALLER (build .#mochi-installer)" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'HDR'
#!/usr/bin/env bash
# mochi AVF quick-restore — keys travel ONLY as age envelopes sealed to two
# independent recipients (YubiKey fido2-hmac / restore passphrase); this
# script contains NO usable private key material. Either one opens them
# alone: the key-restore stage (Stage 3b, inside a nix shell) tries the
# YubiKey (USB-OTG, touch) first and falls back to the passphrase. The
# passphrase lives in a SEPARATE Bitwarden entry. GENERATED; never commit.
# Run on a fresh mochi AVF Debian shell (as droid or root; sudo needed).
set -euo pipefail
umask 077

# Stage 0: stash the sealed envelopes + the (inert) YubiKey identity handle.
# Actual decryption happens in Stage 3b, inside a nix shell (age + fido2
# plugin from the aarch64 binary cache).
install -d -m 700 /tmp/mochi-restore
printf '%s' "HOSTKEY_PUB_PLACEHOLDER"  | base64 -d > /tmp/mochi-restore/host-key.pub
printf '%s' "HOSTKEY_FIDO_PLACEHOLDER" | base64 -d > /tmp/mochi-restore/host-key.fido2.age
printf '%s' "HOSTKEY_PASS_PLACEHOLDER" | base64 -d > /tmp/mochi-restore/host-key.pass.age
cat > /tmp/mochi-restore/yk-identity.txt <<'YKID'
YK_IDENTITY_PLACEHOLDER
YKID
HDR

if [ "$GITKEY_STASH" = 1 ]; then
  cat >> "$OUT" <<GITSTASH
# Stage 0b: stash the git identity (decrypted in Stage 3b, installed in
# Stage final for root + kimb). Sealed to BOTH recipients; .pub is public.
printf '%s' "$GITKEY_PUB_B64" | base64 -d > /tmp/mochi-restore/git-key.pub
printf '%s' "$GITKEY_FIDO_B64" | base64 -d > /tmp/mochi-restore/git-key.fido2.age
printf '%s' "$GITKEY_AGE_B64" | base64 -d > /tmp/mochi-restore/git-key.pass.age
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
if [ -f /root/.mochi-git-key ]; then
  # Install the git identity for root (nix fetches of ssh://git@github.com
  # flake inputs run as root during `system-manager switch`) and for kimb.
  # Stage 3b already decrypted it (or a bare install generated it).
  sudo install -d -m 700 /root/.ssh /home/kimb/.ssh
  sudo install -m 600 /root/.mochi-git-key /root/.ssh/id_ed25519
  sudo install -m 644 /root/.mochi-git-key.pub /root/.ssh/id_ed25519.pub
  sudo install -m 600 /root/.mochi-git-key /home/kimb/.ssh/id_ed25519
  if [ -f /tmp/mochi-restore/git-key.pub ]; then
    sudo install -m 644 /tmp/mochi-restore/git-key.pub /home/kimb/.ssh/id_ed25519.pub
  else
    sudo install -m 644 /root/.mochi-git-key.pub /home/kimb/.ssh/id_ed25519.pub
  fi
  sudo chown -R kimb:kimb /home/kimb/.ssh
  printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/id_ed25519\n  IdentitiesOnly yes\n' \
    | sudo tee /root/.ssh/config >/dev/null
  printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/id_ed25519\n  IdentitiesOnly yes\n' \
    | sudo tee /home/kimb/.ssh/config >/dev/null
  sudo chown kimb:kimb /home/kimb/.ssh/config
  sudo rm -rf /tmp/mochi-restore /root/.mochi-git-key /root/.mochi-git-key.pub
  echo "git identity installed for root + kimb. GitHub registration (one-time):"
  echo "  $(cat /home/kimb/.ssh/id_ed25519.pub)"
fi
echo "SSH host key pre-installed; ssh kimb@mochi.nebula (host key stable across wipes)."
FINAL

# Splice the baked blobs into the placeholders (keeps plaintext out of every
# heredoc above; only ciphertext + public keys are embedded in the output).
HOSTKEY_AGE_B64="$HOSTKEY_AGE_B64" HOSTKEY_FIDO_B64="$HOSTKEY_FIDO_B64" \
HOSTKEY_PUB_B64="$HOSTKEY_PUB_B64" GITKEY_FIDO_B64="$GITKEY_FIDO_B64" \
YK_IDENTITY_TEXT="$(cat "$YK_IDENTITY")" python3 - "$OUT" <<'SPLICE'
import os, sys
path = sys.argv[1]
s = open(path).read()
for var, ph in [("HOSTKEY_AGE_B64","HOSTKEY_PASS_PLACEHOLDER"),
                ("HOSTKEY_FIDO_B64","HOSTKEY_FIDO_PLACEHOLDER"),
                ("HOSTKEY_PUB_B64","HOSTKEY_PUB_PLACEHOLDER"),
                ("GITKEY_FIDO_B64","GITKEY_FIDO_PLACEHOLDER"),
                ("YK_IDENTITY_TEXT","YK_IDENTITY_PLACEHOLDER")]:
    s = s.replace(ph, os.environ[var])
open(path, "w").write(s)
SPLICE
chmod 600 "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
echo "→ paste into a Bitwarden note; store the restore PASSPHRASE in a SEPARATE entry."
echo "On a fresh mochi AVF shell: bash $OUT"