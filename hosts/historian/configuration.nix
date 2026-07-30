# Historian - Desktop (AMD graphics, gaming, AI/ML workloads)
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    # ../profiles/desktop.nix
    # ../profiles/gaming.nix

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Restic backups to Backblaze B2
    ../../modules/restic-backup.nix

    # Knitwork webApp SPA container (builds wasmJs at start, nginx serves;
    # proxied to knit.kimb.dev via maitred's socat forwarder)
    ./knitwork-web.nix

    # Buildbot worker — DISABLED 2026-06-22 (gave up on buildbot-nix
    # fighting private-repo flake inputs; may revisit a different CI
    # scheme later). Re-enable by uncommenting this import; the module
    # file (hosts/historian/buildbot-worker.nix) is left intact.
    # ./buildbot-worker.nix

    # bridge-scribe — the #60 authoring servitor. A forced-command ssh target
    # (rich-evans vox-organism daemon -> historian) that clones a plain-git
    # scratch copy, commits on proposed/<slug>, and pushes with the repo's
    # GitHub deploy key. See hosts/historian/bridge-scribe.nix.
    ./bridge-scribe.nix

    # Forgejo — the Nebula-only git forge (#forge). Officers propose here;
    # the Lord-Captain reviews + merges instead of GitHub. See ./forgejo.nix.
    ./forgejo.nix
  ];

  # Enable the bridge-scribe authoring servitor (#60): the forced-command ssh
  # target rich-evans's vox-organism daemon reaches to materialize officer
  # author requests (clone -> commit on proposed/<slug> -> push). See
  # ./bridge-scribe.nix.
  services.bridge-scribe.enable = true;

  # Syncthing — shared config via kimb.syncthing module
  kimb.syncthing.enable = true;
  kimb.maitredNameservers.enable = true;
  kimb.zaiApiKey.enable = true;

  # Expose music library to Jellyfin (read-only bind mount)
  fileSystems."/var/lib/jellyfin/music" = {
    device = "/home/kimb/Music";
    fsType = "none";
    options = ["bind" "ro"];
  };

  # NFS mount of rich-evans's seagate, mounted at /mnt/media-drive — the SAME
  # path the retired PNY exFAT drive occupied. All 1774 existing /srv/media
  # symlinks target /mnt/media-drive/putio/..., so mounting the seagate here
  # makes them resolve to the NFS tree AUTOMATICALLY: no symlink repoint, and the
  # media-classifier `processed` state keys (str(filepath)) are unchanged → no
  # mass ollama reclassify of existing shows (only genuinely-new content —
  # ChromeCastellaneta, future shares — gets classified). Read-only, automounted
  # on access, soft+timeo so a rich-evans outage fails operations instead of
  # hanging Jellyfin. vers=4.1 = port 2049 only (no rpcbind/mountd); fsid=0 on the
  # export makes the seagate the v4 pseudo-root, hence "10.100.0.40:/".
  fileSystems."/mnt/media-drive" = {
    device = "10.100.0.40:/";
    fsType = "nfs";
    options = [
      "ro"
      "noatime"
      "vers=4.1"
      "proto=tcp"
      "x-systemd.automount"
      "x-systemd.idle-timeout=5min"
      "x-systemd.mount-timeout=30"
      "soft"
      "timeo=30"
      "retrans=2"
    ];
  };

  kimb = {
    # Restic backups
    restic.enable = true;
    restic.extraExclude = [
      "/home/kimb/.android"
      "/home/kimb/.gradle"
    ];

    # Centralized observability — DISABLED: too noisy, low value for now
    # observability.enable = true;

    # Nebula configuration (certs generated via `nix run .#generate-nebula-certs`)
    nebula = {
      enable = true;
      openToPersonalDevices = true;
      # Allow servers (like rich-evans) to access Ollama API
      extraInboundRules = [
        {
          port = 11434;
          proto = "tcp";
          group = "servers";
        }
        {
          port = 8096;
          proto = "tcp";
          host = "maitred";
        }
        # Journal-remote sink (maitred → historian for log aggregation)
        {
          port = 19532;
          proto = "tcp";
          host = "maitred";
        }
        # Knitwork webApp SPA: maitred's socat forwarder (knit-web-proxy)
        # reaches the knit-web nspawn container's nginx on :8088. Without
        # this, Nebula drops the router's traffic (maitred is a server, not a
        # personal device, so openToPersonalDevices doesn't cover it).
        {
          port = 8088;
          proto = "tcp";
          host = "maitred";
        }
        # Forgejo HTTP API (#forge): rich-evans is a *server*, not a personal
        # device, so openToPersonalDevices doesn't cover it — officers/daemon
        # there need an explicit rule to reach the forge on 10.100.0.10:3000.
        # Personal-device webui access is already covered by
        # openToPersonalDevices; SSH :2222 is scribe-localhost + personal
        # devices, so no rule for it.
        {
          port = 3000;
          proto = "tcp";
          group = "servers";
        }
      ];
    };

    # Distributed builds
    distributedBuilds = {
      # enable = true; # Already enabled via commonModules

      # Claude Code SSH key - can only run nix-daemon, no shell access
      builderOnlyKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcpY/DdbidptJJsrr3DgZyrwMYW79cpRwqwb5GbCGy7 claude"
      ];
    };
  };
  # Virtualization configuration
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };

    libvirtd.enable = true;
  };

  # Host identification and networking configuration
  networking = {
    hostName = "historian";

    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Network interface configuration
    interfaces.eno1.wakeOnLan = {
      enable = true;
      policy = ["magic" "unicast"];
    };

    # Extended firewall configuration for streaming
    firewall = {
      allowedTCPPorts = [
        47984
        47989
        47990
        48000
        48010
        22000
      ];
      allowedUDPPorts = [4242 22000]; # Nebula
      allowedUDPPortRanges = [
        {
          from = 47998;
          to = 48020;
        }
        {
          from = 8000;
          to = 8010;
        }
      ];
      trustedInterfaces = [
        "virbr0"
        "nebula1"
      ];
    };
  };

  # AMD graphics hardware configuration
  services.xserver.videoDrivers = ["amdgpu"];

  # AMD GPU hardware acceleration
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
  ];

  # AMD-specific configuration
  hardware.amdgpu.opencl.enable = true;

  # ROCm support for compute workloads
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  # Boot configuration
  boot = {
    # AMD-specific kernel modules
    kernelModules = ["amdgpu" "kvm-amd"];

    # - amdgpu.gttsize: 4GB VRAM + 56GB GTT ≈ 60GB for ROCm inference
    # - video=HDMI-A-1:...@60e: force AMDGPU to expose a fake 1080p connector
    #   even when no monitor is plugged in, so SDDM's autologin actually
    #   brings up a Plasma session (and therefore Sunshine) for headless
    #   Moonlight streaming. The trailing 'e' forces enabled regardless of
    #   hotplug state.
    kernelParams = [
      "amdgpu.gttsize=57344"
      "video=HDMI-A-1:1920x1080@60e"
    ];

    # Boot loader customizations
    loader.systemd-boot = {
      netbootxyz.enable = true;
      memtest86.enable = true;
    };

    plymouth = {
      enable = true;
      themePackages = [
        pkgs.adi1090x-plymouth-themes
      ];
      theme = "dna";
    };
  };

  # Environment configuration
  environment = {
    # Environment variables for AMD
    sessionVariables = {
      LIBVA_DRIVER_NAME = "radeonsi";
      VDPAU_DRIVER = "radeonsi";
    };

    # Additional packages specific to historian
    systemPackages = with pkgs; [
      # ROCm packages for compute
      rocmPackages.rocm-smi
      radeontop
      python3Packages.torchWithRocm
      # Historian specific packages
      legendary-gl
      # sunshine
      toolbox
      cachix
      lmstudio
      tealdeer
      rebar3
      erlang
      # Media
      vlc
      rclone
      # Email
      mu
      isync
    ];
  };

  # AMD-specific configuration
  nixpkgs.config.rocmSupport = true;

  # Jellyfin system user has home=/var/empty (read-only), so Mesa/Vulkan
  # shader cache writes fail and the Vulkan subtitle overlay pipeline deadlocks.
  systemd.services.jellyfin.environment.XDG_CACHE_HOME = "/var/cache/jellyfin";

  # Ollama health probe: exports model load status, inference latency, and
  # context truncation count to Prometheus via the node_exporter textfile collector.
  systemd.services.ollama-health-probe = {
    description = "Export ollama model status, latency, and truncation metrics";
    serviceConfig.Type = "oneshot";
    path = [pkgs.curl pkgs.jq pkgs.coreutils pkgs.systemd];
    script = ''
      OUT=/var/lib/prometheus-node-exporter-textfiles/ollama_health.prom.tmp
      FINAL=/var/lib/prometheus-node-exporter-textfiles/ollama_health.prom
      NOW=$(${pkgs.coreutils}/bin/date +%s)

      ollama_up=0
      model_loaded=0
      vram_bytes=0
      latency_seconds=0
      truncations=0

      # Check liveness and model status via /api/ps
      ps_json=$(${pkgs.curl}/bin/curl -sf --max-time 5 http://localhost:11434/api/ps 2>/dev/null) && ollama_up=1

      if [ "$ollama_up" -eq 1 ]; then
        # Check if the cloud model is loaded (warm in the ollama proxy)
        model_loaded=$(${pkgs.jq}/bin/jq -r '.models[] | select(.name=="kimi-k2.7-code:cloud") | 1' <<< "$ps_json" 2>/dev/null | head -1)
        model_loaded=''${model_loaded:-0}
        [ "$model_loaded" != "1" ] && model_loaded=0

        # VRAM usage of loaded models
        vram_bytes=$(${pkgs.jq}/bin/jq -r '[.models[].size_vram // 0] | add // 0' <<< "$ps_json" 2>/dev/null)
        vram_bytes=''${vram_bytes:-0}

        # Measure end-to-end latency through the cloud model path that
        # production agents now depend on. Non-fatal: if ollama is still
        # loading or the request times out, report latency as 0 (the probe
        # still exports ollama_up=1 and model_loaded status).
        start=$(${pkgs.coreutils}/bin/date +%s%N)
        if ${pkgs.curl}/bin/curl -sf --max-time 60 -X POST http://localhost:11434/api/chat \
          -H "Content-Type: application/json" \
          -d '{"model":"kimi-k2.7-code:cloud","options":{"num_predict":1},"think":false,"messages":[{"role":"user","content":"hi"}],"stream":false}' >/dev/null 2>&1; then
          end=$(${pkgs.coreutils}/bin/date +%s%N)
          latency_seconds=$(( (end - start) / 1000000 ))
          latency_ms=$(( latency_seconds / 1000 ))
          latency_seconds=$( ${pkgs.coreutils}/bin/printf '%d.%03d' $(( latency_ms / 1000 )) $(( latency_ms % 1000 )) )
        fi

        # Count context truncation warnings in the last 5 minutes
        truncations=$(${pkgs.systemd}/bin/journalctl -u ollama --since "5 min ago" --no-pager -q 2>/dev/null | grep -c "truncating input prompt" || true)
      fi

      {
        echo "# HELP ollama_up Whether ollama /api/ps responded (1=ok, 0=fail)"
        echo "# TYPE ollama_up gauge"
        echo "ollama_up $ollama_up"
        echo "# HELP ollama_model_loaded Whether kimi-k2.7-code:cloud is warm in the ollama proxy (1=loaded, 0=not loaded)"
        echo "# TYPE ollama_model_loaded gauge"
        echo "ollama_model_loaded $model_loaded"
        echo "# HELP ollama_model_vram_bytes Total VRAM used by loaded models in bytes"
        echo "# TYPE ollama_model_vram_bytes gauge"
        echo "ollama_model_vram_bytes $vram_bytes"
        echo "# HELP ollama_inference_latency_seconds Time for a minimal kimi-k2.7-code:cloud inference call"
        echo "# TYPE ollama_inference_latency_seconds gauge"
        echo "ollama_inference_latency_seconds $latency_seconds"
        echo "# HELP ollama_truncations_total Context truncation events in the last 5 minutes"
        echo "# TYPE ollama_truncations_total gauge"
        echo "ollama_truncations_total $truncations"
      } > "$OUT"
      mv "$OUT" "$FINAL"
    '';
  };

  systemd.timers.ollama-health-probe = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/2";
      Persistent = true;
    };
  };

  # TV user for living room - Steam Big Picture, Firefox, Flatpak
  users.users.tv = {
    isNormalUser = true;
    description = "Living Room TV";
    extraGroups = ["video" "audio" "input" "users" "media"];
    # No password - auto-login only
    hashedPassword = "";
    shell = pkgs.bash;
  };

  # Firefox auto-launch for TV user
  systemd.user.services.firefox-tv = {
    description = "Firefox for TV";
    wantedBy = ["graphical-session.target"];
    after = ["graphical-session-started.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.firefox}/bin/firefox --new-window about:blank";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    environment = {
      DISPLAY = ":0";
    };
  };

  # Services configuration
  services = {
    # Jellyfin media server with VA-API hardware transcoding
    jellyfin = {
      enable = true;
      openFirewall = true;
      hardwareAcceleration = {
        enable = true;
        type = "vaapi";
        device = "/dev/dri/renderD128";
      };
      transcoding = {
        enableHardwareEncoding = true;
        hardwareDecodingCodecs = {
          h264 = true;
          hevc = true;
          vp9 = true;
          av1 = true; # VCN 3.0 supports AV1 decode
        };
        enableToneMapping = false; # Vulkan overlay deadlocks on AMD RADV with HEVC 10-bit + ASS subtitle burn-in
      };
    };

    # Smart card daemon for YubiKey support
    pcscd.enable = true;

    # Thunderbolt device authorization (for dock enrollment)
    hardware.bolt.enable = true;

    # AI/ML services with ROCm acceleration
    ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
      rocmOverrideGfx = "11.5.0";
      openFirewall = true;
      host = "0.0.0.0";
      # Enable parallel inference — needed when Claude Code session shares the
      # ollama instance; otherwise benchmark/agent requests queue behind it.
      # Strix Point iGPU has enough unified memory for multiple concurrent slots.
      environmentVariables = {
        OLLAMA_IGPU_ENABLE = "1";  # Required for Strix Point iGPU (Radeon 890M)
        OLLAMA_NUM_PARALLEL = "4";
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
        OLLAMA_KEEP_ALIVE = "30m";
        # Must be OLLAMA_CONTEXT_LENGTH, NOT OLLAMA_NUM_CTX (silently ignored).
        # With 64GB RAM + 57GB GTT, 128K context uses ~8-12GB KV cache (q8_0),
        # well within budget. Lifecoach prompts are ~88K tokens; this prevents
        # truncation. Callers that need less pass num_ctx per-request.
        OLLAMA_CONTEXT_LENGTH = "131072";
      };
    };
    open-webui = {
      enable = false;
      host = "0.0.0.0";
      openFirewall = true;
      environment = {
        OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      };
    };

    # Enable Sunshine for game streaming
    sunshine.enable = true;

    # Additional services
    xrdp = {
      enable = true;
      openFirewall = true;
    };

    # Avahi for service discovery
    avahi.publish = {
      enable = true;
      userServices = true;
    };
  };

  # Media group for Jellyfin + drive access
  users.groups.media.gid = 1500;

  # Additional user groups
  users.users.kimb = {
    description = "Kimberly";
    extraGroups = [
      "docker"
      "dialout"
      "input"
      "libvirtd"
      "media"
    ];
  };

  # Jellyfin needs video/render for VA-API and media for library access
  users.users.jellyfin.extraGroups = ["video" "render" "media"];

  # Enable cross-compilation for ARM via QEMU emulation
  boot.binfmt.emulatedSystems = ["armv6l-linux" "aarch64-linux"];

  # Programs configuration
  programs = {
    nix-ld.enable = true;
    virt-manager.enable = true;
    appimage.enable = true;
  };

  # === Agenix secrets for media pipeline ===
  age.secrets.rclone-config = {
    file = ../../secrets/rclone-config.age;
    path = "/run/agenix/rclone-config";
    mode = "0400";
    owner = "kimb";
  };

  # Jellyfin API key for media-classifier library rescan trigger
  age.secrets.jellyfin-api-key = {
    file = ../../secrets/jellyfin-api-key.age;
    group = "media";
    mode = "0440";
  };

  # === Media pipeline systemd services ===

  # rclone-putio-sync MOVED to rich-evans (whole-account mirror to /mnt/seagate,
  # see hosts/rich-evans/configuration.nix). Historian no longer syncs put.io — it
  # reads the seagate via the NFS mount above. Reactivity now comes from the
  # media-classifier timer below (replacing this unit's ExecStartPost trigger).
  # At the cutover deploy, stop the transient rclone-criminal-intent.service
  # (the dedicated PNY pull) too — it's obsolete once the seagate sync is live.

  # Media classifier module (external flake). Scans the NFS-mounted seagate at
  # /mnt/media-drive/putio — the same path the old PNY occupied, so existing
  # /srv/media symlinks resolve to the seagate unchanged and the classifier's
  # `processed` state keys (str(filepath)) don't change → no mass ollama
  # reclassify of existing shows; only genuinely-new content (ChromeCastellaneta,
  # future shares) gets classified. Whole-tree sourceDir (was a 2-dir allow-list
  # that mirrored the PNY's capacity-driven cherry-pick).
  services.media-classifier = {
    enable = true;
    # Now the PRIMARY trigger (was a 6h backstop while rclone-putio-sync's
    # ExecStartPost drove classification). The sync moved to rich-evans, so the
    # classifier polls the NFS tree itself. 1-min cadence: most polls hit the NFS
    # dir cache and don't round-trip to rich-evans. New content lands on the
    # seagate every 3 min (rich-evans sync), so 1-min polling catches it within a
    # minute. The Jellyfin Refresh in ExecStartPost is throttled to 3 min (below)
    # so this faster cadence doesn't 3x the library-scan rate.
    timer.enable = true;
    timer.onCalendar = "*:0/1"; # was 6h
    sourceDirs = [
      "/mnt/media-drive/putio"
    ];
    # Pin shows the heuristics/AniList/LLM scorer mis-bins as TV. Checked before
    # scoring, so it survives rescans. (The old comment about a source-path change
    # forcing a full reclassify + reverting manual moves was wrong: create_symlink
    # is additive-only and the classifier keys state on the full filepath — and
    # the mount-swap keeps that filepath stable anyway.)
    categoryOverrides = {
      "ONE PIECE" = "anime";
      "Gachiakuta" = "anime";
    };
    ollamaHost = "http://total-eclipse.nebula:11434";
    ollamaModel = "qwen3:8b";
    user = "kimb";
    group = "media";
  };

  # The module hardcodes RandomizedDelaySec="30m" in the classifier timer
  # (module.nix line 160) — at 1-min cadence that's up to 30m skew, defeating the
  # point. Override to 5s. Also speed up the broken-symlink cleanup timer from the
  # module's "daily" default to 3 min, so dead symlinks (source-side deletes) don't
  # linger in Jellyfin's library between daily runs.
  systemd.timers.media-classifier.timerConfig.RandomizedDelaySec = lib.mkForce "5s";
  systemd.timers.media-symlink-cleanup.timerConfig.OnCalendar = lib.mkForce "*:0/3";

  # Override ExecStartPost: prune empty show/season dirs (was the rclone-putio-sync
  # ExecStartPost's job; the sync moved to rich-evans) + trigger a Jellyfin library
  # refresh. The refresh is THROTTLED to every 3 min via a stamp file — the
  # classifier ticks every 1 min, but a full Library/Refresh each tick would 3x the
  # old 3-min scan cadence and prod the DeleteItem scan-abort bug (see the
  # media-jellyfin-index-check service below). The module's jellyfinApiKey option
  # embeds the key in the Nix store, so we leave it empty and read it from the
  # agenix secret here instead. Runs as kimb:media (no `+`): kimb owns /srv/media
  # and the StateDirectory, and is in `media` so it can read the 0440 API-key secret.
  systemd.services.media-classifier.serviceConfig.ExecStartPost =
    let
      jellyfinApiKeyFile = config.age.secrets.jellyfin-api-key.path;
    in
    pkgs.writeShellScript "trigger-jellyfin-scan" ''
      # mindepth 2 protects the Anime/Movies/TV Shows roots.
      ${pkgs.findutils}/bin/find /srv/media -mindepth 2 -type d -empty -delete || true
      STAMP=/var/lib/media-classifier/jellyfin-scan.stamp
      NOW=$(${pkgs.coreutils}/bin/date +%s)
      LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
      if [ $((NOW - LAST)) -ge 180 ]; then
        API_KEY="$(cat ${jellyfinApiKeyFile})"
        ${pkgs.curl}/bin/curl -sf -X POST \
          "http://localhost:8096/Library/Refresh?api_key=$API_KEY" \
          || echo "Warning: Jellyfin scan trigger failed (non-fatal)"
        echo "$NOW" > "$STAMP"
      fi
    '';

  # === Jellyfin index drift detector ===
  # Alerts when a media file the classifier symlinked into /srv/media is missing
  # from Jellyfin's library — the symptom of Jellyfin's DeleteItem SQLite bug
  # (UNIQUE constraint failed on UserData) that aborts the whole-library scan
  # and silently blocks new items from appearing. Read-only: no DB writes, no
  # jellyfin restart. On mismatch it logs ERR and exits non-zero so the unit
  # shows as failed in `systemctl` / journalctl. The fix stays a manual runbook
  # (stop jellyfin; DELETE stale BaseItems rows whose Path is gone on disk +
  # orphaned UserData/AncestorIds; restart; trigger scan) — deliberately NOT
  # auto-heal, to avoid routine DB surgery / downtime.
  systemd.services.media-jellyfin-index-check = {
    description = "Detect media files missing from Jellyfin's library";
    serviceConfig = {
      Type = "oneshot";
      User = "jellyfin";
      Group = "media";
      ExecStart = pkgs.writeShellScript "media-jellyfin-index-check" ''
        set -uo pipefail
        DB="/var/lib/jellyfin/data/jellyfin.db"
        GRACE_MIN=15 # only flag live symlinks older than this — let scans run first

        is_video() {
          local low="''${1,,}"
          case "$low" in
            *.mkv|*.mp4|*.avi|*.m4v|*.mov|*.wmv|*.flv|*.webm|*.ts|*.m2ts|*.mpg|*.mpeg|*.vob|*.ogv|*.3gp|*.rm|*.rmvb) return 0 ;;
            *) return 1 ;;
          esac
        }

        # Paths Jellyfin has indexed under /srv/media (read-only; WAL-safe concurrent read)
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT
        ${pkgs.sqlite}/bin/sqlite3 "$DB" -readonly \
          "SELECT Path FROM BaseItems WHERE Path LIKE '/srv/media/%';" \
          | sort -u > "$tmp"

        missing=0
        # Direction A: live symlinks in /srv/media that Jellyfin has NOT indexed —
        # symptom of the scan-abort bug blocking NEW items from appearing.
        while IFS= read -r -d "" link; do
          is_video "$link" || continue
          # Skip dead symlinks here: media-symlink-cleanup prunes them, and
          # Direction B below catches the case that actually matters (Jellyfin
          # still referencing a now-gone path).
          target="$(${pkgs.coreutils}/bin/readlink -f -- "$link")"
          [ -r "$target" ] || continue
          if ! ${pkgs.gnugrep}/bin/grep -Fxq -- "$link" "$tmp"; then
            echo "MISSING FROM JELLYFIN: $link" >&2
            missing=1
          fi
        done < <(${pkgs.findutils}/bin/find \
          "/srv/media/TV Shows" "/srv/media/Anime" "/srv/media/Movies" \
          -type l -mmin "+$GRACE_MIN" -print0 2>/dev/null)

        stale=0
        # Direction B: Jellyfin BaseItems whose /srv/media path no longer exists
        # on disk. This was the dead-symlink blind spot — media-symlink-cleanup
        # deletes dead symlinks every ~3 min (inside the rclone sync
        # ExecStartPost), so walking /srv/media can't see source-side deletions:
        # the symlink is gone before this check runs. But Jellyfin's BaseItems row
        # persists (the DeleteItem SQLite bug aborts the scan that would prune
        # it), so a BaseItem whose path is missing on disk is the durable signal
        # that media the user expects has silently vanished (the
        # anime-disappearing symptom). Without this direction the check was
        # blind to exactly the failure mode that prompted it.
        while IFS= read -r jpath; do
          [ -n "$jpath" ] || continue
          is_video "$jpath" || continue
          if [ ! -e "$jpath" ]; then
            echo "JELLYFIN STALE ENTRY (file gone on disk): $jpath" >&2
            stale=1
          fi
        done < "$tmp"

        if [ "$missing" -eq 1 ] || [ "$stale" -eq 1 ]; then
          echo "Jellyfin index drift detected (missing=$missing stale=$stale) — likely the scan-abort (DeleteItem UNIQUE-constraint) bug. Runbook: stop jellyfin; DELETE stale BaseItems rows whose Path is gone on disk + orphaned UserData/AncestorIds; restart; trigger scan." >&2
          exit 1
        fi
        exit 0
      '';
    };
  };

  systemd.timers.media-jellyfin-index-check = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/10"; # Every 10 minutes
      RandomizedDelaySec = "2m";
      Persistent = true;
    };
  };

  system.stateVersion = "23.11";
}
