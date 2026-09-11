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

    # Xen boot via GRUB-multiboot2 chainload (firmware-safe xen.efi path)
    ../../modules/xen-grub-boot.nix

    # domU networking (a3j.3): standalone NAT bridge xenbr0 (192.168.101.0/24)
    # for vif-* guests — networkd bridge + dnsmasq DHCP/DNS + nftables NAT.
    # Guests attach with vif = [ "bridge=xenbr0" ] in their xl.cfg.
    ../../modules/xen-domu-network.nix

    # Knitwork webApp SPA container (builds wasmJs at start, nginx serves;
    # proxied to knit.kimb.dev via maitred's socat forwarder)
    ./knitwork-web.nix

    # === a3j.5 low-risk service migrations (from rich-evans) ===
    # All registry-gated via kimb.services (services/default.nix): each file
    # is inert (mkIf) until its entry moves to the historian bucket at
    # cutover — except mpd, which has no registry entry and starts at the
    # pre-work deploy (fresh DB scan over the NFS-mounted seagate; no
    # consumers point at it until the MPD_HOST flip).

    # Borges — EPUB-first ebook server (library via /mnt/media-drive NFS)
    ./borges.nix

    # Knitwork — lexicon host + firehose indexer (host service; maitred's
    # socat forwarder repoints via the registry `host` flip)
    ./knitwork.nix

    # Knitwork BFF — ATProto OAuth write relay (/api/* on knit.kimb.dev)
    ./knitwork-bff.nix

    # MPD httpd stream — the Choirmaster's music (Nest fetches over LAN)
    ./mpd.nix

    # Homepage dashboard — the consolidated instance (LAN-only)
    ./homepage.nix

    # === a3j.6 phase 6a: Home Assistant + mosquitto (from rich-evans) —
    # the epic's named-risk service; state is purely local (/var/lib/hass),
    # .storage verified IP-clean, no USB hardware binding (see file header) ===
    ./home-assistant.nix

    # === a3j.6 phase 6a: Matrix homeserver (Tuwunel) + mautrix-discord (from
    # rich-evans) — embedded store, federation keys ride the state rsync
    # untouched ===
    ./matrix.nix

    # === a3j.6 phase 6b: copyparty (from rich-evans, with the seagate
    # local since a3j.4) ===
    ./copyparty.nix

    # === a3j.6 phase 6b: email-digest (from rich-evans) — mbsync + mu
    # index + hourly Discord digest; Maildir local since a3j.4, xapian
    # index on this host's NVMe (pre-built at cutover) ===
    ./email-digest.nix

    # === a3j.6 phase 6b cutover 9: org-crm (from rich-evans) — personal
    # CRM agent (tasks/notes/mail digest, Secretary Discord bot). State
    # /var/lib/org-crm rode the rsync verbatim — identical paths, mu index
    # + mbsync SyncState needed zero translation ===
    ./org-crm.nix

    # === a3j.8.1: monitoring stack (from maitred) — prometheus + grafana
    # + blackbox. State (TSDB + grafana sqlite/dashboards) moves via the
    # runbook two-pass rsync; see the file header for scrape deltas ===
    ./monitoring.nix

    # === a3j.9.1: Qwen3-TTS voice server (from total-eclipse) — CPU/GGML ===
    ./qwen3-tts.nix

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

  # === a3j.4: the seagate is PHYSICALLY LOCAL now (moved from rich-evans
  # 2026-09-11). Same mountpoint — /mnt/media-drive — so every consumer
  # (borges library, mpd music_compressed, jellyfin's 1774 /srv/media
  # symlinks, media-classifier state keys) keeps working with ZERO path
  # changes; only the device swapped from the ro NFS automount to the local
  # ext4. nofail keeps boot safe with the drive unplugged; noatime to spare
  # the SMR drive; commit=60 preserved from rich-evans for the
  # email-digest Maildir/mu small-file write storm when 6b lands (same
  # rationale as the original rich-evans mount). Interim NFS REVERSE-
  # EXPORT (below): rich-evans's remaining drive consumers (copyparty,
  # email-digest Maildir, org-crm bulk — the 6b cohort) keep working
  # unchanged at /mnt/seagate until their cutovers, then the export drops.
  fileSystems."/mnt/media-drive" = {
    device = "/dev/disk/by-uuid/980870c5-7397-45dd-9f01-972f9b51d0f6";
    fsType = "ext4";
    options = ["nofail" "noatime" "commit=60"];
  };

  # === a3j.6 completion: reverse-NFS export REMOVED (the seagate is local) ===
  # org-crm (the
  # last 6b drive consumer) moved at cutover 9, rich-evans's syncthing
  # seagate folders were removed (the mesh lives here: ~/Music,
  # ~/compressed_music, ~/org, ~/work-org, ~/color_ebooks), and org-bridge
  # (staying on rich-evans per a3j.7.1) now reads a LOCAL ~/org dir
  # (crew-context.org md5-verified identical) instead of the drive via
  # the symlink. The nebula 2049 rule is gone too.

  # === a3j.4: put.io mirror writer ported from rich-evans — the drive is
  # local here now, and rclone writing locally beats writing over NFS.
  # Same unit body as rich-evans's (restartIfChanged=false so a deploy never
  # blocks on a long sync; --transfers 2 SMR-tuned; UMask=0022 keeps new files
  # world-readable for Jellyfin), with the target flipped to the local mount.
  systemd.services.rclone-putio-sync = {
    description = "Sync all of put.io to /mnt/media-drive";
    restartIfChanged = false;
    after = ["network-online.target" "mnt-media\\x2ddrive.mount"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "kimb";
      Group = "users";
      UMask = "0022";
      ExecStart = let
        sync = pkgs.writeShellScript "rclone-putio-sync" ''
          ${pkgs.rclone}/bin/rclone sync --config /run/agenix/rclone-config \
            putio: /mnt/media-drive/putio/ \
            --verbose --stats 30s --size-only --no-update-modtime --no-update-dir-modtime \
            --delete-after --max-delete 1000 --fast-list --checkers 16 --transfers 2 \
            --max-transfer 50G --cutoff-mode HARD --max-duration 1h \
            || true
        '';
      in "${sync}";
      ExecStartPost = "+${pkgs.writeShellScript "post-sync" ''
        ${pkgs.findutils}/bin/find /mnt/media-drive/putio -mindepth 2 -type d -empty -delete || true
      ''}";
    };
  };

  systemd.timers.rclone-putio-sync = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/3";
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };

  # PNY PRO ELITE V2 (1TB USB 3.2 flash) — games / Steam library volume. This
  # drive was /mnt/media-drive's exFAT put.io copy pre-migration; put.io is now
  # mirrored on the rich-evans seagate (the live NFS source), so the PNY copy
  # was redundant and got reformatted. ext4 over exFAT: Proton needs POSIX perms
  # + symlinks + case-sensitivity, none of which exFAT provides — Proton breaks
  # on exFAT. ext4 is the robust pick for a *removable* USB drive (journals
  # through an unclean unmount, the main risk for a yanked cable; btrfs is
  # intolerant of unclean shutdown and CoW-fragments big game files, f2fs is
  # flash-optimized but the PNY's own FTL already wear-levels + it's less
  # mainstream/recoverable). nofail so an unplugged drive doesn't break boot;
  # noatime to spare flash write endurance on reads. Steam library wiring is a
  # separate, deferred step — for now this just mounts the volume.
  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-uuid/ad6c50d2-1c09-4b16-8dcb-4e7690ee61e8";
    fsType = "ext4";
    options = ["nofail" "noatime"];
  };

  # Copyparty overlay (module imports pkgs.copyparty via this overlay —
  # moved from rich-evans at a3j.6 6b)
  nixpkgs.overlays = [inputs.copyparty.overlays.default];

  kimb = {
    # Restic backups
    restic.enable = true;
    # a3j.4: the seagate's irreplaceables now restic-covered from HERE (they
    # were only covered incidentally while the drive lived on rich-evans;
    # now it's historian's responsibility the moment the drive plugged in).
    # Regenerable bulk (putio mirror, tv, games) stays OUT — same split the
    # runbook specified. The extraPaths option lands in modules/restic-
    # backup.nix with this change.
    restic.extraPaths = [
      "/mnt/media-drive/email-digest" # Maildir — mbsync's write target until 6b
      "/mnt/media-drive/org" # org-crm bulk until 6b
      "/mnt/media-drive/tooms_photos"
    ];
    restic.extraExclude = [
      "/home/kimb/.android"
      "/home/kimb/.gradle"
      # a3j.8.1: prometheus TSDB — regenerable, up to 10G retention cap of
      # segment churn per backup pass. grafana.db (dashboards/datasources)
      # is 1.5M and rides the normal /var/lib include.
      "/var/lib/prometheus2"
    ];

    # Centralized observability — re-enabled for the a3j.8.1 monitoring
    # cutover: node_exporter on :9100 (historian is now its own scrape
    # target + the textfile host for the restic staleness probe and the
    # ollama-health-probe metrics, which were previously writing into a
    # dir nobody scraped). journal-upload stays OFF (opt-in option,
    # default false — the sink on rich-evans is disabled fleet-wide).
    observability.enable = true;

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
        # there need an explicit rule to reach the forge on 10.100.0.10:3030.
        # Personal-device webui access is already covered by
        # openToPersonalDevices; SSH :2222 is scribe-localhost + personal
        # devices, so no rule for it.
        # a3j.8.1: port 3000 -> 3030 (grafana took the conventional 3000;
        # bridge-scribe's FORGE_URL flipped in the same push).
        {
          port = 3030;
          proto = "tcp";
          group = "servers";
        }
        # a3j.4 interim: NFSv4.1 (port 2049 only — no rpcbind/mountd) rw
        # reverse-export to rich-evans, whose remaining drive consumers
        # (copyparty, email-digest Maildir, org-crm bulk — the 6b cohort)
        # still live there. DROPPED at 6b completion (cutover 9) with the
        # export itself — rich-evans no longer mounts the drive.
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

  # === Xen hypervisor — RESUMED 2026-09-10 via GRUB-multiboot2 (a3j.2) ===
  # Trial #1 (direct xen.efi) died pre-kernel at the firmware handoff; the
  # GmkTec BIOS 1.04 (latest published for the base EVO-X1) is confirmed to
  # kill xen.efi specifically, while Xen 4.22 + Strix Point + AMD-Vi are
  # proven healthy via GRUB multiboot2 (hardware trial #2 + ROCm/ollama
  # green under dom0). modules/xen-grub-boot.nix provides the chainload
  # entries and scrubs the broken UKI entries the upstream builder writes.
  # setXenDefault stays false until a GRUB-path boot is confirmed at the
  # desk, so unattended reboots/power cycles still land on the plain entry.
  virtualisation.xen = {
    enable = true;
    boot.builderVerbosity = "quiet";
    # C xenstored, not the nixpkgs default oxenstored (ocamlPackages.oxenstored
    # = xapi-project v25.3.0, March 2025): it predates the XS_GET_QUOTA wire op
    # that libxl 4.22 issues during `xl list -l`, and it silently drops the op
    # instead of replying ENOSYS (xenstore.txt spec) — every -l caller wedges
    # forever, including xendomains stop (90s hang per reboot until it was
    # masked). The C daemon from the same xen-4.22.0 package implements the op.
    # Takes effect on next boot (xenstored is RefuseManualStop).
    # Root cause + evidence: systems-flake-a3j.12.
    store.path = "${config.virtualisation.xen.package}/bin/xenstored";
  };
  boot.xenGrubBoot = {
    enable = true;
    setXenDefault = true;
  };

  # domU networking (a3j.3) — NAT bridge for vif-* guests. Standalone bridge
  # (no physical enslavement): NM owns eno1/enp100s0 today, and at the a3j.8
  # router phase those roles swap — the NAT bridge must not care which port
  # carries the uplink. NAT is nftables (base profile); the iptables
  # networking.nat module would be inert here. Guests: DHCP .100–.200,
  # static .10–.99 free. Mesh reach into guests happens via
  # kimb.xenDomuNetwork.portForwards as services migrate (a3j.5/6/7).
  kimb.xenDomuNetwork.enable = true;

  # xendomains DISABLED until the first real domU lands (a3j.7). Its only job
  # is autostarting /etc/xen/auto/*.cfg — empty today — but its stop path
  # runs `xl list -l`, which currently stalls against oxenstored (see a3j.7
  # notes: plain `xl list` works, `xl list -l` wedges; only a reboot clears
  # the daemon state). The stall made every switch-time stop hang the full
  # 90s TimeoutStopSec and fail the switch. Re-enable in a3j.7 when
  # /etc/xen/auto is populated — and re-test stop behavior with live guests
  # before trusting it on a shutdown path.
  systemd.services.xendomains.enable = lib.mkForce false;

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

  # ROCm support for compute workloads; plus PNY 1TB USB staging (phase 0,
  # a3j.1): qcow2 domU images + nspawn roots. Steam library wiring remains
  # deferred; vacuum-backups lives here already. Not in the restic include
  # set (paths are home/etc/var-lib/root), so excluded from backup by
  # construction — domU state backs up from within each guest.
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    "d /mnt/games/xen 0755 kimb users -"
    "d /mnt/games/machines 0755 kimb users -"
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
        OLLAMA_IGPU_ENABLE = "1"; # Required for Strix Point iGPU (Radeon 890M)
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
    # Use the cloud ollama subscription via historian's proxy. Local qwen3:8b on
    # total-eclipse emits only thinking tokens and returns an empty response field
    # for /api/generate even with /no_think; kimi-k2.7-code:cloud works when the
    # classifier sends "think": false (media-classifier fix).
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";
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
  systemd.services.media-classifier.serviceConfig.ExecStartPost = let
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
