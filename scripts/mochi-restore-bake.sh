#!/usr/bin/env bash
# Bake a self-contained mochi AVF quick-restore script. ONLY the STABLE
# SSH host key is baked (from flake_keys); the Nebula cert/key/ca are NOT
# baked — they are decrypted ON-DEVICE by nebula-secrets.service using
# `age -d -i /etc/ssh/ssh_host_ed25519_key` against the PUBLIC .age blobs
# that system-manager deploys to /etc/nebula/mainnet/encrypted/ (the .age
# files ship in the cloned systems-flake repo). Only the SSH host key —
# which IS the age identity — goes in the Bitwarden note.
#
# Prerequisite: secrets/nebula-ca.age must be encrypted to mochi's ssh
# pubkey (the cert/key .age already are). The re-encrypt is committed in
# this same offshoot (ca.age → full registry hostKeys + bootstrap superset;
# ca.crt is the CA's PUBLIC cert, so re-encrypting from flake_keys plaintext
# needs no secret).
#
# Reads:  <flake_keys>/ssh/mochi_host_ed25519_key{,.pub}
# Appends the mochi-installer body (apt -> nix -> cachix -> clone ->
#   system-manager switch --flake .#mochi), then a final stage that
#   (re)starts nebula-secrets.service (on-device decrypt) and verifies nebula0.
# Writes: ~/android_revival_script/script.sh — paste into a Bitwarden secure
#   note, never commit.
#
# Run on a host that has flake_keys (syncthing) + nix:
#   nix shell nixpkgs#bash --command scripts/mochi-restore-bake.sh
set -euo pipefail

FK="${FLAKE_KEYS:-/home/kimb/shared_projects/flake_keys}"
OUT="${OUT:-$HOME/android_revival_script/script.sh}"
SF="${SYSTEMS_FLAKE:-/home/kimb/shared_projects/systems-flake}"
INSTALLER="${INSTALLER:-$(nix path-info "$SF#mochi-installer" 2>/dev/null)/bin/mochi-installer}"

for f in \
  "$FK/ssh/mochi_host_ed25519_key" "$FK/ssh/mochi_host_ed25519_key.pub"; do
  [ -f "$f" ] || { echo "missing key file: $f" >&2; exit 1; }
done
[ -f "$INSTALLER" ] || { echo "missing installer: $INSTALLER (build .#mochi-installer)" >&2; exit 1; }

SSHK_B64=$(base64 -w0 "$FK/ssh/mochi_host_ed25519_key")
SSHP_B64=$(base64 -w0 "$FK/ssh/mochi_host_ed25519_key.pub")

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'HDR'
#!/usr/bin/env bash
# mochi AVF quick-restore — only the STABLE SSH host key is baked; the
# Nebula cert/key/ca are decrypted on-device by nebula-secrets.service
# (age -d -i /etc/ssh/ssh_host_ed25519_key) from the .age blobs deployed
# by system-manager. GENERATED; never commit. Paste into a Bitwarden
# secure note; run on a fresh mochi AVF Debian shell.
set -euo pipefail
HDR
cat >> "$OUT" <<STAGE0A
# Stage 0a: pre-install mochi's STABLE SSH host key (survives AVF wipes).
# This key is the age identity nebula-secrets.service uses to decrypt the
# Nebula cert/key/ca from the public .age blobs. openssh-server (installed
# by the installer below) runs ssh-keygen -A on postinst, which only
# generates MISSING host keys — ours is already here, so it is preserved.
sudo install -d -m 755 /etc/ssh
printf '%s' "${SSHK_B64}" | base64 -d | sudo tee /etc/ssh/ssh_host_ed25519_key     >/dev/null
printf '%s' "${SSHP_B64}" | base64 -d | sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null
sudo chmod 600 /etc/ssh/ssh_host_ed25519_key
sudo chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
STAGE0A
# Append the mochi-installer body (drop its nix-store shebang; the body is
# portable bash using only system-PATH tools).
tail -n +2 "$INSTALLER" >> "$OUT"
cat >> "$OUT" <<'FINAL'
# Stage final: (re)start nebula-secrets.service — it does the on-device
# age -d -i /etc/ssh/ssh_host_ed25519_key decrypt of the cert/key/ca from
# /etc/nebula/mainnet/encrypted/*.age (deployed by system-manager) into
# /run/nebula-secrets/mainnet, then nebula-mainnet comes up against them.
sudo systemctl restart nebula-secrets.service 2>/dev/null || true
sudo systemctl restart nebula-mainnet.service 2>/dev/null || true
sleep 2
if ip -4 addr show nebula0 >/dev/null 2>&1; then
  echo "mochi is on the mesh: $(ip -4 -o addr show nebula0 | awk '{print $4}')"
else
  echo "nebula0 not up yet — check: sudo systemctl status nebula-mainnet nebula-secrets"
  echo "nebula-secrets log (decrypt errors = .age recipient mismatch): sudo journalctl -u nebula-secrets -b --no-pager"
fi
echo "SSH host key pre-installed; ssh kimb@mochi.nebula (host key stable across wipes)."
FINAL
chmod 600 "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT") bytes) — paste into a Bitwarden secure note."
echo "On a fresh mochi AVF shell: bash $OUT"