# mochi — Pixel 9 Pro AVF terminal

Debian Linux VM inside Android's AVF (Android Virtualization Framework) on
the Pixel 9 Pro. AVF is an Android beta and randomly wipes its disk image,
so the bootstrap path is designed for fast, idempotent recovery.

## Substrate choice

**Debian + system-manager**, not nixos-avf. nixos-avf was tried and never
got stable; AVF's tendency to wipe images makes "one-command rebuild" more
valuable than a fully declarative root. The system-manager layer manages
nebula, secrets, sshd hardening, fleet /etc/hosts, and the nix-built dev
tooling; **barebones weston** comes from apt because it is the only
compositor with usable touchpad-via-screen behavior on the AVF Terminal
display (KDE and XFCE customization never stuck), and zed comes from its
official installer because the nixpkgs aarch64 closure is not worth the
trouble for a one-off device.

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

1. `apt-get install` weston + curl/git/ca-certificates/xz-utils/sudo
2. sshd nopw hardening + `kimb` admin user (pubkeys from github) + lock of
   the default `droid` account's password — so ssh is key-only from the
   first minute even before system-manager touches anything
2. Determinate Nix installer (multi-user) if `nix` is absent
3. Writes `/etc/nix/nix.custom.conf` with the `mccartykim.cachix.org`
   substituter + flakes feature flag, and `!include`s it from `/etc/nix/nix.conf`
4. Clones (or fast-forwards) the systems-flake repo to `~/systems-flake`
5. `nix run github:numtide/system-manager -- switch --flake .#mochi`
6. `curl https://zed.dev/install.sh | sh` if zed isn't present
7. Prints the manual post-install steps (below)

## Post-install: nebula comes up without a key rotation

The quick-restore script (`scripts/mochi-restore-bake.sh`) pre-installs
mochi's **STABLE** SSH host key from `flake_keys` — but encrypted: the key
travels ONLY as an age blob sealed to a restore passphrase chosen at bake
time, so the Bitwarden note carries **no usable private key material**.
The passphrase lives in a SEPARATE Bitwarden entry (the note alone is
inert; the passphrase alone is inert). At restore, the script prompts for
it twice (host key + git identity).

That key is the age identity `nebula-secrets.service` uses to `age -d -i
/etc/ssh/ssh_host_ed25519_key` the Nebula cert/key/ca from the public `.age`
blobs that system-manager deploys to `/etc/nebula/mainnet/encrypted/`. So
after `system-manager switch --flake .#mochi` + `systemctl restart
nebula-secrets`, nebula comes up with NO `ssh-keygen -A` /
`generate-nebula-certs` / `agenix-rekey` ceremony — the host's identity
survives AVF wipes, and only the SSH host key is baked (sealed).

The bake script ALSO seals mochi's **git identity**
(`flake_keys/ssh/mochi_git_ed25519_key`) into the note — installed for root
and kimb so nix can fetch the `ssh://git@github.com` flake inputs
(organisms, blog, knitwork, …) during the switch. Register that key on
GitHub ONCE (Settings → SSH keys); re-bakes reuse the same key, so no
re-registration after wipes. If you instead run a bare
`nix run ...#mochi-installer`, a fresh git key is generated and must be
registered after every wipe.

flake_keys upgrade path: store the host key as `mochi_host_ed25519_key.age`
(encrypted to your YubiKey via age-plugin-yubikey); the bake script prefers
it and decrypts with `HOST_KEY_AGE_IDENTITY` at bake time — then flake_keys
holds no plaintext host key either.

Prerequisite (already done): `secrets/nebula-ca.age` is encrypted to
mochi's ssh pubkey (cert/key `.age` too — re-sealed 2026-08 to the
post-rotation pair from flake_keys; the superseded pair is stashed as
`flake_keys/nebula/mochi-superseded-2026-08-02.*`). `ca.crt` is the CA's
*public* cert, so re-encrypting it from `flake_keys` plaintext needs no
secret.

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

The hardening drop-ins (`/etc/ssh/sshd_config.d/00-mochi-nopw.conf` from
the installer, `10-mochi-hardening.conf` from system-manager) mean sshd is
password-auth-disabled, root-login-disabled, and restricted to `AllowUsers
kimb` on ALL interfaces. sshd does NOT pin to the nebula IP: the wildcard
bind covers nebula0 whenever it appears AND the LAN, so the phone can be
smoke-tested from a laptop before the mesh is up (the AVF VM is NATed
behind Android, so LAN exposure is inherently limited).

```bash
ssh kimb@mochi.nebula        # over the mesh
ssh kimb@<vm-lan-address>    # during bootstrap smoke tests
```

The `nebula-hosts` oneshot re-splices the fleet's `hostname.nebula` entries
into /etc/hosts at every boot (marker-managed block), so mochi can reach
peers by name even though its nebula config uses no DNS.

## Local AI tooling

The system layer ships `claude-code` (Anthropic), the `claude-zai` wrapper
(Anthropic-compatible z.ai endpoint), and `ollama` (CPU-only inference;
AVF doesn't expose the GPU). `claude-zai` reads its API token from
`/run/agenix/zai-api-key` at exec time; mochi isn't an agenix recipient
today, so populate that file manually (`mkdir -p /run/agenix && install
-m 0400 /path/to/key /run/agenix/zai-api-key`) or override `keyFile` if
you actually want to use the wrapper. `ollama serve` runs on demand.

## Why weston + zed go outside system-manager

- **weston via apt**: barebones weston is the only compositor whose
  touchpad-via-screen behavior works on the AVF Terminal display; KDE/XFCE
  customization never stuck. system-manager doesn't manage session/seat
  glue well anyway, and Debian's weston package pulls the right stack.
- **zed via zed.dev**: nixpkgs' zed-editor on aarch64-linux is large and
  has had build flakes; the official aarch64 prebuilt is the path of
  least surprise for a one-off device.

If/when nixos-avf becomes stable, both of these can move into the nix
layer — but for now, recover-fast wins.

## File bridge (phone_projects)

Files move desktop↔phone via the syncthing folder `phone_projects`
(id `nzjer-77q4e`, shared with the Pixel 9 Pro's syncthing app) and reach
the VM through AVF's shared directories — the VM sees Android storage
directly, so NO syncthing service runs inside the VM. Copy out of the
shared dir into `$HOME` when durability matters: Android data survives
AVF wipes better than the VM image does.

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
