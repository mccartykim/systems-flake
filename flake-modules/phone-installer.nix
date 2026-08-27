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

        # Stage 1: apt prerequisites + weston (no desktop meta-packages: only
        # barebones weston behaves on the AVF Terminal display).
        log "Stage 1: apt packages"
        sudo apt-get update
        # shellcheck disable=SC2086
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${aptList}

        # Stage 1b: admin user + sshd nopw hardening. Runs BEFORE anything
        # can start sshd so the "ssh MUST be nopw" guarantee holds from the
        # first second: even if the default AVF account (droid@droid) fails
        # to get locked, password login is impossible and only `kimb` (with
        # the owner's pubkeys) may connect. Idempotent across wipes/re-runs.
        log "Stage 1b: admin user + sshd nopw"
        sudo mkdir -p /etc/ssh/sshd_config.d
        printf '%s\n' \
          'PasswordAuthentication no' \
          'KbdInteractiveAuthentication no' \
          'PermitRootLogin no' \
          'PubkeyAuthentication yes' \
          'AllowUsers kimb' \
          | sudo tee /etc/ssh/sshd_config.d/00-mochi-nopw.conf >/dev/null
        if ! id kimb >/dev/null 2>&1; then
          sudo useradd -m -s /bin/bash kimb
        fi
        # Passwordless sudo for kimb — mirrors the AVF default account so
        # restore/ops scripts behave identically under either user.
        printf '%s\n' 'kimb ALL=(ALL) NOPASSWD:ALL' \
          | sudo tee /etc/sudoers.d/90-kimb >/dev/null
        sudo chmod 440 /etc/sudoers.d/90-kimb
        # Lock the default account's password (pubkey/sudo still work; there
        # simply is no password to brute-force). Best-effort: some AVF
        # images may not have a `droid` user to lock.
        if id droid >/dev/null 2>&1; then
          sudo usermod -L droid 2>/dev/null || true
        fi
        # Inbound keys are PUBLIC. Order of preference: (1) keys stashed by
        # the quick-restore header (baked at bake time — zero network
        # dependency), (2) live fetch from github with retries. Never a hard
        # failure: sshd is key-only ("nopw" is absolute), so if neither
        # source lands, warn loudly — console access still works.
        sudo install -d -m 700 -o kimb -g kimb /home/kimb/.ssh
        if [ -s /tmp/mochi-restore/authorized_keys ]; then
          sudo install -m 600 -o kimb -g kimb /tmp/mochi-restore/authorized_keys \
            /home/kimb/.ssh/authorized_keys
          echo "authorized_keys: baked keys installed"
        elif curl -fsSL --retry 3 --retry-delay 2 --max-time 30 \
             https://github.com/mccartykim.keys \
             | sudo tee /home/kimb/.ssh/authorized_keys >/dev/null; then
          sudo chmod 600 /home/kimb/.ssh/authorized_keys
          echo "authorized_keys: fetched from github"
        else
          echo "!!! WARNING: no authorized_keys source available — ssh stays" >&2
          echo "!!! locked out (nopw) until keys are added manually via console:" >&2
          echo "!!!   curl -fsSL https://github.com/mccartykim.keys | sudo tee /home/kimb/.ssh/authorized_keys" >&2
        fi
        # Git identity for GitHub (ssh:// flake inputs are fetched as root
        # during the system-manager switch). The quick-restore script stashes
        # one at /root/.mochi-git-key — prefer it so GitHub registration is a
        # ONE-TIME step. Bare installs (no bake) generate a fresh key that
        # must be (re-)registered after every wipe.
        if [ ! -f /root/.mochi-git-key ] && [ ! -f /home/kimb/.ssh/id_ed25519 ]; then
          sudo ssh-keygen -t ed25519 -N "" -f /root/.mochi-git-key \
            -C "$HOST_NAME AVF git identity (generated, not registered)" -q
        fi
        # Apply the hardening to any already-running sshd (openssh-server's
        # postinst auto-starts it; restart picks up the drop-in).
        sudo systemctl restart ssh 2>/dev/null \
          || sudo systemctl restart sshd 2>/dev/null \
          || true

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

        # Stage 3b: restore the STABLE host key + git identity (quick-restore
        # flow only — bare installs skip). Runs INSIDE a nix shell so the
        # fido2 plugin needs no Debian packaging: with the YubiKey on
        # USB-OTG, decryption is just a touch; without it, the passphrase.
        # Either envelope opens the keys alone.
        if [ -f /tmp/mochi-restore/host-key.fido2.age ] || [ -f /tmp/mochi-restore/host-key.pass.age ]; then
          log "Stage 3b: restore keys (YubiKey or passphrase)"
          # Runs INSIDE a nix shell so the fido2 plugin needs no Debian
          # packaging: with the YubiKey on USB-OTG, decryption is a touch;
          # without it, the passphrase. Either envelope opens the keys alone.
          #!/usr/bin/env bash
          set -euo pipefail
          restore_either() {
            local fido="$1" pass="$2" out="$3" label="$4"
            if command -v age-plugin-fido2-hmac >/dev/null 2>&1 && [ -f /tmp/mochi-restore/yk-identity.txt ]; then
              echo ">>> $label: touch the YubiKey <<<"
              if age -d -i /tmp/mochi-restore/yk-identity.txt -o "$out" "$fido" 2>/dev/null; then
                echo "$label: decrypted via YubiKey"; return 0
              fi
              echo "$label: YubiKey path failed - falling back to passphrase"
            fi
            age -d -o "$out" "$pass"   # prompts for the restore passphrase
          }
          restore_either /tmp/mochi-restore/host-key.fido2.age /tmp/mochi-restore/host-key.pass.age /tmp/mochi-host-ed25519 "host key"
          install -m 600 /tmp/mochi-host-ed25519 /etc/ssh/ssh_host_ed25519_key
          install -m 644 /tmp/mochi-restore/host-key.pub /etc/ssh/ssh_host_ed25519_key.pub
          printf 'host key restored: '; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub || true
          if [ -f /tmp/mochi-restore/git-key.fido2.age ] || [ -f /tmp/mochi-restore/git-key.pass.age ]; then
            restore_either /tmp/mochi-restore/git-key.fido2.age /tmp/mochi-restore/git-key.pass.age /root/.mochi-git-key "git identity"
            chmod 600 /root/.mochi-git-key
          fi
        KRESTORE
          # Root: the fido2 token needs /dev/hidraw; nix shell brings age +
          # the plugin from the aarch64 binary cache.
          sudo nix shell nixpkgs#age nixpkgs#age-plugin-fido2-hmac -c bash /tmp/mochi-key-restore.sh
          rm -f /tmp/mochi-key-restore.sh /tmp/mochi-host-ed25519
        fi

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

          1. SSH host key — SKIP if you ran the quick-restore script (it
             pre-bakes the STABLE host key, which is also the age identity
             nebula-secrets.service decrypts with). Only for a BARE install
             (no pre-baked key):
               sudo ssh-keygen -A
               cat /etc/ssh/ssh_host_ed25519_key.pub
             then update hosts/nebula-registry.nix, re-encrypt the nebula
             .age secrets, redeploy, and rotate any baked copies.

          2. (weston) run `weston` inside the VM for the barebones
             compositor — the Terminal display + touchpad-via-screen combo
             that actually works (KDE/XFCE do not).

          3. If /root/.mochi-git-key was generated (not restored from the
             quick-restore script), register its pubkey on GitHub
             (Settings → SSH keys) so the ssh:// flake inputs fetch.

          4. Verify nebula:  nebula-cert print -path /run/nebula-secrets/*/*.crt
                              ip -4 addr show nebula0
        NEXTSTEPS
      '';
    };

  # Per-system wiring: build mochi-installer on both x86_64 (so CI can eval/
  # build it) and aarch64 (the actual target). `nix build` for the wrong
  # platform will need a cross-arch builder or a binary cache hit; that's
  # fine — the script's content is identical, only its bash wrapper differs.
  # mochi-restore-generator: run ONCE on a trusted host that has the bootstrap
  # age identity. It pre-decrypts the mochi Nebula cert/key/ca, base64s them,
  # and writes a self-contained restore script to $OUT (default
  # ~/android_revival_script/script.sh) that:
  #   Stage 0  — writes the pre-baked Nebula secrets to /run/nebula-secrets so
  #              nebula comes up with NO SSH-host-key rotation dance (the
  #              on-device nebula-secrets.service skips when keys are present);
  #   then      appends the mochi-installer body (apt → nix → cachix → clone →
  #              `system-manager switch --flake .#mochi`);
  #   Stage final — (re)starts nebula + verifies nebula0 is on the mesh.
  # The decrypted key flows file→base64→output-file ONLY: it is never printed
  # and never enters the nix store (the generator contains only the ENCRYPTED
  # .age blobs, which are already in the public repo). The output script is
  # meant to be pasted into a Bitwarden secure note and run on a fresh AVF
  # Debian shell. See hosts/mochi/README.md.
  mkRestoreGenerator = pkgs: {
    installer,
    caAge ? "${self.outPath}/secrets/nebula-ca.age",
    certAge ? "${self.outPath}/secrets/nebula-mochi-cert.age",
    keyAge ? "${self.outPath}/secrets/nebula-mochi-key.age",
  }: let
    installerBin = "${installer}/bin/mochi-installer";
  in
    pkgs.writeShellApplication {
      name = "mochi-restore-generator";
      runtimeInputs = with pkgs; [age coreutils];
      # SC2129: the heredoc append pattern (cat >> "$OUT" <<EOF) is intentional
      # here — we assemble the restore script in header/stage/final blocks.
      checkPhase = ''
        ${pkgs.shellcheck}/bin/shellcheck -e SC2129 "$out/bin/mochi-restore-generator"
      '';
      text = ''
        set -euo pipefail
        AGE_IDENTITY="''${AGE_IDENTITY:?need AGE_IDENTITY = path to the bootstrap age identity}"
        OUT="''${OUT:-$HOME/android_revival_script/script.sh}"

        command -v age >/dev/null 2>&1 || {
          echo "age not on PATH; run via: AGE_IDENTITY=... nix shell nixpkgs#age --command \"\$0\" \"\$@\"" >&2
          exit 1
        }

        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
        # Decrypt the ENCRYPTED .age blobs (already public in the repo) with the
        # bootstrap identity. Plaintext lives only in $tmp + the output file.
        # CA_AGE/CERT_AGE/KEY_AGE override the baked paths (testable with dummy
        # .age; also lets a rekeyed blob be pointed at without rebuilding).
        age -d -i "$AGE_IDENTITY" -o "$tmp/ca.crt"  "''${CA_AGE:-${caAge}}"
        age -d -i "$AGE_IDENTITY" -o "$tmp/mochi.crt" "''${CERT_AGE:-${certAge}}"
        age -d -i "$AGE_IDENTITY" -o "$tmp/mochi.key" "''${KEY_AGE:-${keyAge}}"
        CA_B64="$(base64 -w0 "$tmp/ca.crt")"
        CERT_B64="$(base64 -w0 "$tmp/mochi.crt")"
        KEY_B64="$(base64 -w0 "$tmp/mochi.key")"

        mkdir -p "$(dirname "$OUT")"
        cat > "$OUT" <<'HDR'
        #!/usr/bin/env bash
        # mochi AVF quick-restore — Nebula key pre-baked. GENERATED; never commit.
        # Paste into a Bitwarden secure note; run on a fresh mochi AVF Debian shell.
        set -euo pipefail
        HDR
        cat >> "$OUT" <<STAGE0
        # Stage 0: pre-staged Nebula secrets → nebula up with NO SSH-key rotation.
        sudo install -d -m 700 /run/nebula-secrets/mainnet
        printf '%s' "''${CA_B64}" | base64 -d | sudo tee /run/nebula-secrets/mainnet/ca.crt >/dev/null
        printf '%s' "''${CERT_B64}" | base64 -d | sudo tee /run/nebula-secrets/mainnet/mochi.crt >/dev/null
        printf '%s' "''${KEY_B64}" | base64 -d | sudo tee /run/nebula-secrets/mainnet/mochi.key >/dev/null
        sudo chmod 600 /run/nebula-secrets/mainnet/*
        STAGE0
        # Append the mochi-installer body (drop its nix-store shebang; the body is
        # portable bash using only system-PATH tools — apt-get/curl/git/sudo).
        tail -n +2 "${installerBin}" >> "$OUT"
        cat >> "$OUT" <<'FINAL'
        # Stage final: (re)start nebula against the pre-staged keys + verify.
        sudo systemctl restart nebula-secrets.service 2>/dev/null || true
        sudo systemctl restart nebula-mainnet.service 2>/dev/null || true
        sleep 2
        if ip -4 addr show nebula0 >/dev/null 2>&1; then
          echo "mochi is on the mesh: $(ip -4 -o addr show nebula0 | awk '{print $4}')"
        else
          echo "nebula0 not up yet — check: sudo systemctl status nebula-mainnet nebula-secrets"
        fi
        FINAL
        chmod 600 "$OUT"
        echo "wrote $OUT ($(wc -c < "$OUT") bytes) — paste into a Bitwarden secure note."
        echo "On a fresh mochi AVF shell: bash $OUT"
      '';
    };

  installerHosts = {
    mochi = {
      hostName = "mochi";
      # Headless + barebones weston: only weston has usable touchpad-via-
      # screen behavior on the AVF Terminal display; KDE/XFCE customization
      # never stuck, so no desktop meta-packages, no display manager.
      enableXfce = false;
      extraAptPackages = ["weston"];
      # The system-manager config hardens sshd (sshd_config.d + ssh.service
      # After=nebula-mainnet) but assumes ssh.service exists; a fresh AVF
      # Debian image doesn't ship openssh-server. Install it here so the
      # pre-baked stable host key (Stage 0a of the restore script) is picked
      # up by ssh-keygen -A's "only generate missing" logic, not clobbered.
      # openssh-server so the pre-baked stable host key (Stage 0a of the
      # restore script) is picked up by ssh-keygen -A's "only generate
      # missing" logic, not clobbered.
      # NO apt `age`: nebula-secrets.service decrypts the cert/key/ca
      # on-device via ${pkgs.age}/bin/age (nix age, present after switch)
      # using /etc/ssh/ssh_host_ed25519_key as the age identity. The restore
      # script (scripts/mochi-restore-bake.sh) bakes ONLY the SSH host key;
      # the .age blobs come from the cloned repo. See hosts/mochi/README.md.
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
        let
          installers =
            lib.mapAttrs'
            (
              name: args:
                lib.nameValuePair "${name}-installer" (mkPhoneInstaller pkgs args)
            )
            installerHosts;
        in
          # mochi-restore-generator depends on the mochi-installer (it appends
          # the installer's body to the generated restore script).
          installers
          // (lib.optionalAttrs (installers ? mochi-installer) {
            "mochi-restore-generator" = mkRestoreGenerator pkgs {
              installer = installers.mochi-installer;
            };
          });
    };
}
