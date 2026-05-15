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

## Post-install: rotate the SSH host key + agenix pubkey

The bootstrap regenerates `/etc/ssh/ssh_host_ed25519_key`, which means the
**publicKey field in `hosts/nebula-registry.nix` is now stale**. Until it
is updated, `nebula-secrets.service` cannot decrypt the host's age-encrypted
certs and nebula will not come up.

To rotate:

```bash
# On mochi:
sudo ssh-keygen -A       # only if /etc/ssh/ssh_host_ed25519_key.pub is missing
cat /etc/ssh/ssh_host_ed25519_key.pub
# Send that to the mayor.
```

Then in `systems-flake` on a workstation:

1. Update `hosts/nebula-registry.nix` → `mochi.publicKey` and drop the
   `TODO(sf-6cf)` comment.
2. Regenerate nebula certs:
   ```bash
   nix run .#generate-nebula-certs
   ```
3. Rerun agenix-rekey so the existing secrets are re-encrypted to the new
   host key:
   ```bash
   nix run .#agenix-rekey -- rekey
   ```
4. Commit the updated `secrets/nebula-mochi-{cert,key}.age` files.
5. On mochi: `git -C ~/systems-flake pull && sudo nix run github:numtide/system-manager -- switch --flake .#mochi`
6. Verify: `systemctl status nebula-mainnet` and `ip -4 addr show nebula0`.

The follow-up bead **sf-dnx** tracks the rotation lifecycle.

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
