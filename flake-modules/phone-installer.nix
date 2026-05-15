# Phone / AVF / portable-host bootstrap installer.
#
# Builds a single shell script that takes a fresh Debian environment to a
# system-manager-managed host with nebula, dev tooling, and (optionally)
# an XFCE desktop + zed editor. Designed for Android AVF VMs that randomly
# wipe state (see sf-6cf), so the recovery path is `curl | bash` quick.
#
# Substrate is Debian + system-manager, NOT nixos-avf (user couldn't get
# the latter stable). Build-on-device with binary cache substitution from
# mccartykim.cachix.org — Tensor G4 handles the closures fine and cross-
# compiling electron/zed for one phone is not worth the yak shave.
{
  lib,
  self,
  ...
}: let
  defaultBinaryCaches = [
    {
      url = "https://mccartykim.cachix.org";
      key = "mccartykim.cachix.org-1:WzHencScmSzp4YOayeZBCqqNoM98LXFpf9wqUZf0e4s=";
    }
  ];

  defaultAptPackages = [
    "curl"
    "git"
    "ca-certificates"
    "xz-utils"
    "sudo"
  ];

  xfceAptPackages = [
    "xfce4"
    "xfce4-goodies"
    "lightdm"
  ];

  mkPhoneInstaller = pkgs: {
    hostName,
    pubkey ? null,
    repoUrl ? "https://github.com/mccartykim/systems-flake.git",
    extraAptPackages ? [],
    enableXfce ? true,
    enableZedInstaller ? true,
    binaryCaches ? defaultBinaryCaches,
  }: let
    aptPackages =
      defaultAptPackages
      ++ (lib.optionals enableXfce xfceAptPackages)
      ++ extraAptPackages;

    aptList = lib.concatStringsSep " " aptPackages;

    substituterUrls = lib.concatStringsSep " " (map (c: c.url) binaryCaches);
    substituterKeys = lib.concatStringsSep " " (map (c: c.key) binaryCaches);
  in
    pkgs.writeShellApplication {
      name = "${hostName}-installer";
      # Keep runtimeInputs empty: the script runs on a fresh Debian host
      # before nix is installed, so it must rely on system PATH (apt-get,
      # curl, bash) rather than nix-store paths.
      runtimeInputs = [];
      # The Determinate-installer pipe-to-sh and zed.dev installer pipe-to-sh
      # are both intentional — this is a `curl | bash` bootstrap. Tell
      # shellcheck to stop complaining about them.
      checkPhase = ''
        ${pkgs.shellcheck}/bin/shellcheck -e SC2312 -e SC2015 "$out/bin/${hostName}-installer"
      '';
      text = ''
        # ${hostName} bootstrap installer (parameterized via mkPhoneInstaller).
        # Idempotent: safe to re-run after an AVF wipe.
        set -euo pipefail

        HOST_NAME=${lib.escapeShellArg hostName}
        REPO_URL=${lib.escapeShellArg repoUrl}
        REPO_DIR="''${HOME}/systems-flake"
        ENABLE_ZED=${
          if enableZedInstaller
          then "1"
          else "0"
        }

        log() { printf '\n=== %s ===\n' "$*"; }

        # Stage 1: apt prerequisites + (optional) XFCE desktop.
        log "Stage 1: apt packages"
        sudo apt-get update
        # shellcheck disable=SC2086
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${aptList}

        # Stage 2: Determinate Nix installer (multi-user) if nix is absent.
        log "Stage 2: Nix"
        if ! command -v nix >/dev/null 2>&1; then
          curl --proto '=https' --tlsv1.2 -sSf -L \
            https://install.determinate.systems/nix \
            | sh -s -- install --determinate --no-confirm
          # Source the nix profile in the current shell so later stages see it.
          # shellcheck disable=SC1091
          . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        else
          echo "nix already installed at $(command -v nix)"
        fi

        # Stage 3: trust binary caches + enable flakes.
        # Determinate Nix manages /etc/nix/nix.conf itself; write our extras
        # to nix.custom.conf and reference it via extra-trusted-substituters.
        log "Stage 3: nix.conf"
        sudo mkdir -p /etc/nix
        sudo tee /etc/nix/nix.custom.conf >/dev/null <<EOF
        experimental-features = nix-command flakes
        extra-substituters = ${substituterUrls}
        extra-trusted-substituters = ${substituterUrls}
        extra-trusted-public-keys = ${substituterKeys}
        EOF
        # Make sure the main config includes our extras. Determinate already
        # writes extra-trusted-users; we just need to ensure include works.
        if ! sudo grep -q '^!include nix.custom.conf' /etc/nix/nix.conf 2>/dev/null; then
          echo '!include nix.custom.conf' | sudo tee -a /etc/nix/nix.conf >/dev/null
        fi
        sudo systemctl restart nix-daemon || true

        # Stage 4: clone (or fast-forward) the systems-flake repo.
        log "Stage 4: systems-flake repo"
        if [ -d "$REPO_DIR/.git" ]; then
          git -C "$REPO_DIR" fetch --all --prune
          git -C "$REPO_DIR" pull --ff-only
        else
          git clone "$REPO_URL" "$REPO_DIR"
        fi

        # Stage 5: apply the system-manager config for this host.
        log "Stage 5: system-manager switch"
        cd "$REPO_DIR"
        NIX_BIN="$(command -v nix)"
        sudo "$NIX_BIN" run --extra-experimental-features 'nix-command flakes' \
          github:numtide/system-manager -- switch --flake ".#$HOST_NAME"

        # Stage 6: zed (official installer; nixpkgs aarch64 story is shaky).
        if [ "$ENABLE_ZED" = "1" ] && ! command -v zed >/dev/null 2>&1; then
          log "Stage 6: zed"
          curl --proto '=https' --tlsv1.2 -sSf https://zed.dev/install.sh | sh
        fi

        # Stage 7: next steps.
        log "Done — next steps"
        cat <<'NEXTSTEPS'
        The system-manager config is now applied. Remaining manual steps:

          1. SSH host key (used to decrypt agenix secrets):
               sudo ssh-keygen -A
               cat /etc/ssh/ssh_host_ed25519_key.pub
             Send that pubkey to the mayor so they can:
               - update hosts/nebula-registry.nix
               - rerun `nix run .#generate-nebula-certs`
               - rerun `agenix-rekey` so this host can decrypt its secrets
             Until then, nebula-secrets.service will fail to decrypt and
             nebula won't come up.

          2. (XFCE only) reboot or `sudo systemctl start lightdm` to get
             a graphical session.

          3. Verify nebula:  nebula-cert print -path /run/nebula-secrets/*/*.crt
                              ip -4 addr show nebula0
        NEXTSTEPS
      '';
    };

  # Per-system wiring: build mochi-installer on both x86_64 (so CI can eval/
  # build it) and aarch64 (the actual target). `nix build` for the wrong
  # platform will need a cross-arch builder or a binary cache hit; that's
  # fine — the script's content is identical, only its bash wrapper differs.
  installerHosts = {
    mochi = {
      hostName = "mochi";
    };
  };
in {
  # mkPhoneInstaller is kept inside this module's let-binding rather than
  # exported via flake.lib: flake-parts won't merge two `flake.lib = …`
  # definitions without an explicit option declaration, and helpers.nix
  # already owns flake.lib. Reuse for new portable hosts (cronut etc.) is
  # by adding entries to the installerHosts attrset below.

  perSystem = {
    pkgs,
    system,
    ...
  }:
    lib.optionalAttrs
    (system == "aarch64-linux" || system == "x86_64-linux")
    {
      packages =
        lib.mapAttrs'
        (
          name: args:
            lib.nameValuePair "${name}-installer" (mkPhoneInstaller pkgs args)
        )
        installerHosts;
    };
}
