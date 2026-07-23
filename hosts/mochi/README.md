# mochi — Pixel 9 Pro AVF terminal

Debian Linux VM inside Android's AVF (Android Virtualization Framework) on
the Pixel 9 Pro. AVF is an Android beta and randomly wipes its disk image,
so the bootstrap path is designed for fast, idempotent recovery.

## Substrate choice

**Debian + system-manager**, not nixos-avf. nixos-avf was tried and never
got stable; AVF's tendency to wipe images makes "one-command rebuild" more
valuable than a fully declarative root. The system-manager layer manages
nebula, secrets, and the nix-built dev tooling; XFCE/lightdm and zed come
from native installers because their cross-compile stories on aarch64 are
not worth the closure size.

## Running the installer

On a freshly wiped mochi (Debian shell inside the AVF terminal app):

```bash
nix run --extra-experimental-features 'nix-command flakes' \
  github:mccartykim/systems-flake#mochi-installer
```

…or, if `nix` isn't even present yet, fetch the script from a peer host
that already has the closure built and pipe it:

```bash
curl -fsSL <url-to-prebuilt-script> | bash
```

The script is idempotent and re-runnable. It does, in order:

1. `apt-get install` XFCE/lightdm + curl/git/ca-certificates/xz-utils/sudo
2. Determinate Nix installer (multi-user) if `nix` is absent
3. Writes `/etc/nix/nix.custom.conf` with the `mccartykim.cachix.org`
   substituter + flakes feature flag, and `!include`s it from `/etc/nix/nix.conf`
4. Clones (or fast-forwards) the systems-flake repo to `~/systems-flake`
5. `nix run github:numtide/system-manager -- switch --flake .#mochi`
6. `curl https://zed.dev/install.sh | sh` if zed isn't present
7. Prints the manual post-install steps (below)

## Post-install: nebula comes up without a key rotation

The quick-restore script (`scripts/mochi-restore-bake.sh`) pre-installs
mochi's **STABLE** SSH host key from `flake_keys`. That key is the age
identity `nebula-secrets.service` uses to `age -d -i
/etc/ssh/ssh_host_ed25519_key` the Nebula cert/key/ca from the public `.age`
blobs that system-manager deploys to `/etc/nebula/mainnet/encrypted/`. So
after `system-manager switch --flake .#mochi` + `systemctl restart
nebula-secrets`, nebula comes up with NO `ssh-keygen -A` /
`generate-nebula-certs` / `agenix-rekey` ceremony — the host's identity
survives AVF wipes, and only the SSH host key (the one secret) is baked
into the Bitwarden note.

Prerequisite (already done in this offshoot): `secrets/nebula-ca.age` must
be encrypted to mochi's ssh pubkey (the cert/key `.age` already are).
`ca.age` is re-encrypted to the full registry `hostKeys` + bootstrap
superset — `ca.crt` is the CA's *public* cert, so re-encrypting it from
`flake_keys` plaintext needs no secret.

The rotation dance below is only needed if you bootstrap WITHOUT the
restore script (e.g. a bare `nix run ...#mochi-installer`), which
regenerates `/etc/ssh/ssh_host_ed25519_key` and leaves the registry's
`mochi.publicKey` stale:

1. On mochi: `sudo ssh-keygen -A` (only if the key is missing), then
   `cat /etc/ssh/ssh_host_ed25519_key.pub`.
2. In `systems-flake`: update `hosts/nebula-registry.nix` → `mochi.publicKey`.
3. Re-encrypt `secrets/nebula-{ca,mochi-cert,mochi-key}.age` to the new key
   (plain `age -r <mochi-pubkey>`; `ca.age` to ALL `hostKeys` + bootstrap,
   not just mochi — it is shared fleet-wide via `modules/nebula-node.nix`).
4. Commit, push; on mochi: `git -C ~/systems-flake pull && sudo nix run
   github:numtide/system-manager -- switch --flake .#mochi`.
5. Verify: `systemctl status nebula-mainnet` and `ip -4 addr show nebula0`.

## Reaching mochi after first switch

Once `system-manager switch --flake .#mochi` lands the hardening drop-in
(`/etc/ssh/sshd_config.d/10-mochi-hardening.conf`), sshd is bound to
`10.100.0.8` only — no LAN, no localhost, no password auth, no root.
Mochi is reachable exclusively over the nebula mesh:

```bash
ssh kimb@mochi.nebula
```

`ssh.service` is wired `Requires=/After=nebula-mainnet.service` via a
drop-in, so it won't try to bind before nebula0 exists.

## Local AI tooling

The system layer ships `claude-code` (Anthropic), the `claude-zai` wrapper
(Anthropic-compatible z.ai endpoint), and `ollama` (CPU-only inference;
AVF doesn't expose the GPU). `claude-zai` reads its API token from
`/run/agenix/zai-api-key` at exec time; mochi isn't an agenix recipient
today, so populate that file manually (`mkdir -p /run/agenix && install
-m 0400 /path/to/key /run/agenix/zai-api-key`) or override `keyFile` if
you actually want to use the wrapper. `ollama serve` runs on demand.

## Why XFCE + zed go outside system-manager

- **XFCE / lightdm via apt**: system-manager doesn't manage display
  managers / X session glue well, and apt's xfce4 metapackage handles
  PAM, polkit, and seat assignment correctly out of the box.
- **zed via zed.dev**: nixpkgs' zed-editor on aarch64-linux is large and
  has had build flakes; the official aarch64 prebuilt is the path of
  least surprise for a one-off device.

If/when nixos-avf becomes stable, both of these can move into the nix
layer — but for now, recover-fast wins.

## Adding more portable hosts

The installer is a function in `flake-modules/phone-installer.nix`:

```nix
mkPhoneInstaller pkgs {
  hostName = "cronut";
  enableXfce = false;          # headless, no desktop
  enableZedInstaller = false;
  extraAptPackages = ["wireguard-tools"];
}
```

Add the new host to the `installerHosts` attrset at the bottom of
`phone-installer.nix` and to `flake-modules/system-manager.nix`, then
`nix build .#cronut-installer` and ship.
