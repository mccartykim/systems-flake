# Rich Evans - HP Mini PC home server
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  sshKeys = import ../ssh-keys.nix;
in {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/server.nix

    # Services configuration
    ./services.nix

    # Server-specific modules
    ./guacamole.nix

    # Camera/webcam server
    ./camera.nix

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Restic backups to Backblaze B2
    ../../modules/restic-backup.nix

    # Journal-remote receiver (sink for systemd-journal-upload from other hosts)
    ../../modules/journal-remote-sink.nix

    # Matrix homeserver (Tuwunel) + Discord bridge
    ./matrix.nix

    # Knitwork — lexicon host + firehose indexer (host service, proxied via maitred)
    ./knitwork.nix

    # Knitwork BFF — ATProto OAuth write relay (host service, /api/* on knit.kimb.dev)
    ./knitwork-bff.nix

    # DNS server - DISABLED: moved to maitred router
    # ./dns.nix

    # Static networking
    ./networking.nix

    # SRE agent — DISABLED: noisy, low value, pegs historian GPU at 100%
    # ./sre-agent.nix
  ];

  # Restic backup to shared B2 repo
  kimb.restic.enable = true;

  # Syncthing — shared config via kimb.syncthing module (guiAddress dropped:
  # was 0.0.0.0:8384; default localhost:8384 is fine, reach via Nebula/SSH tunnel)
  kimb.syncthing.enable = true;
  kimb.maitredNameservers.enable = true;
  kimb.zaiApiKey.enable = true;

  # Centralized observability — DISABLED: too noisy, low value for now
  # kimb.observability.enable = true;

  # Receive journal uploads — DISABLED along with observability
  # kimb.journalRemote.enable = true;

  # Nebula configuration with server-specific firewall rules
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
    extraInboundRules = [
      # Copyparty ports
      {
        port = 3923;
        proto = "tcp";
        host = "any";
      }
      {
        port = 3921;
        proto = "tcp";
        host = "any";
      }
      {
        port = 3945;
        proto = "tcp";
        host = "any";
      }
      {
        port = 3990;
        proto = "tcp";
        host = "any";
      }
      {
        port = "12000-12099";
        proto = "tcp";
        host = "any";
      }
      {
        port = 69;
        proto = "udp";
        host = "any";
      }
      {
        port = 3969;
        proto = "udp";
        host = "any";
      }
      # Guacamole
      {
        port = 4822;
        proto = "tcp";
        host = "any";
      }
      {
        port = 8080;
        proto = "tcp";
        host = "any";
      }
      # Syncthing
      {
        port = 8384;
        proto = "tcp";
        host = "any";
      }
      {
        port = 22000;
        proto = "tcp";
        host = "any";
      }
      {
        port = 22000;
        proto = "udp";
        host = "any";
      }
      # Home Assistant / ESPHome
      {
        port = 8123;
        proto = "tcp";
        host = "any";
      }
      {
        port = 6053;
        proto = "tcp";
        host = "any";
      }
      # Camera streaming - only from personal devices
      {
        port = 8554;
        proto = "tcp";
        groups = ["desktops" "laptops"];
      }
      # Life Coach Dashboard - web UI for monitoring agent sessions
      # (lifecoach-organism on 8586; old org-life-coach on 8585 is
      # mkForce-disabled but firewall hole left open as a no-op)
      {
        port = 8586;
        proto = "tcp";
        host = "any";
      }
      # Matrix/Tuwunel homeserver
      {
        port = 6167;
        proto = "tcp";
        host = "any";
      }
      # SRE agent webhook (Alertmanager → rich-evans)
      {
        port = 9095;
        proto = "tcp";
        host = "maitred";
      }
      # NFSv4 over Nebula — historian reads the seagate media library (read-only).
      # NFSv4 = port 2049 only (no mountd/lockd/statd); the host firewall already
      # trusts nebula1, so this Nebula rule is the sole gate.
      {
        port = 2049;
        proto = "tcp";
        host = "historian";
      }
    ];
  };

  # Host identification
  networking.hostName = "rich-evans";

  # Boot configuration
  boot.loader.systemd-boot = {
    enable = true;
    edk2-uefi-shell.enable = true;
    netbootxyz.enable = true;
  };

  # Mount external storage. commit=60 raises the ext4 journal commit interval
  # from the default 5s to 60s: mbsync writes a flood of small Maildir files
  # without fsync-per-message, and mu index writes to the xapian db — both are
  # write-heavy workloads that stall on jbd2's periodic 5s commit blocking
  # writers. A 60s commit amortizes those flushes (acceptable: at worst 60s of
  # recently-written mail/index is lost on a crash, and the mail source of
  # truth is the IMAP server, re-synced next cycle). Helps the backlog drain
  # + the first full mu index clear the 30-min timeout window.
  fileSystems."/mnt/seagate" = {
    device = "/dev/disk/by-uuid/980870c5-7397-45dd-9f01-972f9b51d0f6";
    fsType = "ext4";
    options = ["defaults" "nofail" "commit=60"];
  };

  # NFS export of the seagate to historian (10.100.0.10) over Nebula, so Jellyfin
  # (on historian) can read the put.io library. Read-only — rich-evans is the
  # single writer (rclone writes /mnt/seagate locally); historian only reads via
  # this mount. NFSv4.1 (TCP-only, one port — fits Nebula): fsid=0 makes this
  # export the v4 pseudo-root, so the client mounts 10.100.0.40:/ and sees the
  # seagate's contents (e.g. /mnt/rich-evans-seagate/putio == /mnt/seagate/putio).
  # The host firewall trusts nebula1 (trustedInterfaces), so only the Nebula
  # rule above gates it — no networking.firewall entry needed.
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/seagate 10.100.0.10(ro,no_subtree_check,sync,fsid=0)
    '';
  };

  # Shared put.io rclone config (same .age file / path / owner as historian's
  # declaration; rekeyed to rich-evans's host key in secrets/secrets.nix). Used by
  # rclone-putio-sync below.
  age.secrets.rclone-config = {
    file = ../../secrets/rclone-config.age;
    path = "/run/agenix/rclone-config";
    mode = "0400";
    owner = "kimb";
  };

  # Whole-account put.io mirror -> /mnt/seagate (ported from historian; replaces
  # the PNY 2-dir allow-list sync). DECISIONS (locked in the migration staging
  # notes): --delete-after --max-delete 1000 and NO --backup-dir — deletes only
  # free space (no overfill mechanism), and put.io is the source of truth so a
  # spurious delete (transient empty listing, the anime-RCA) self-heals on the
  # next re-sync rather than needing a backup dir. --max-delete 1000 (file COUNT)
  # aborts a spurious mass-delete before it wipes the library; legit large deletes
  # (a removed show = few big files) pass under the cap. --transfers 2 (not 16):
  # the seagate is SMR (sustained write ~49 MB/s; bursts into the CMR cache then
  # collapse), and 2 large sequential writes are SMR's best case — > put.io's
  # post-throttle ~25-37 MB/s, so the seagate keeps up with NO cache. 16 concurrent
  # writes would thrash the CMR cache and collapse below single-stream.
  # --cutoff-mode HARD + --max-duration 1h hard-stops at the cap (no CAUTIOUS drain)
  # so --size-only resumes partials on the next 3-min tick. `|| true` so the soft
  # max-duration / max-delete exit doesn't skip ExecStartPost. UMask=0022 keeps new
  # files 755/644 (world-readable) so Jellyfin on historian (jellyfin:jellyfin, NOT
  # in rich-evans's `users` group) can read them via the ro NFS export — the
  # rsync-seeded content was chmod'd a+rX at cutover.
  systemd.services.rclone-putio-sync = {
    description = "Sync all of put.io to /mnt/seagate";
    # Timer-driven oneshot: a deploy that changes this unit's store path would
    # otherwise restart it and block the switch until ExecStart finishes (up to
    # --max-duration 1h). restartIfChanged=false leaves the running instance alone;
    # the unit def updates on disk and the next 3-min tick runs the new version.
    restartIfChanged = false;
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "kimb";
      Group = "users";
      UMask = "0022";
      ExecStart = let
        sync = pkgs.writeShellScript "rclone-putio-sync" ''
          ${pkgs.rclone}/bin/rclone sync --config /run/agenix/rclone-config \
            putio: /mnt/seagate/putio/ \
            --verbose --stats 30s --size-only --no-update-modtime --no-update-dir-modtime \
            --delete-after --max-delete 1000 --fast-list --checkers 16 --transfers 2 \
            --max-transfer 50G --cutoff-mode HARD --max-duration 1h \
            || true
        '';
      in "${sync}";
      ExecStartPost = "+${pkgs.writeShellScript "post-sync" ''
        ${pkgs.findutils}/bin/find /mnt/seagate/putio -mindepth 2 -type d -empty -delete || true
      ''}";
    };
  };

  systemd.timers.rclone-putio-sync = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/3"; # every 3 min
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };

  nixpkgs.overlays = [inputs.copyparty.overlays.default];

  # Server-specific services
  services = {
    miniflux = {
      enable = false;
      adminCredentialsFile = "/etc/miniflux-credentials";
      config = {
        LISTEN_ADDR = "0.0.0.0:8080";
      };
    };

    # Print server configuration
    printing = {
      browsing = true;
      drivers = [pkgs.brgenml1cupswrapper];
      openFirewall = true;
      listenAddresses = ["0.0.0.0:631"];
    };

    ipp-usb.enable = true;

    # Audio for server (legacy PulseAudio)
    pipewire.enable = false;
    pulseaudio.enable = true;
  };

  # User configuration with SSH keys
  users.users.kimb = {
    openssh.authorizedKeys.keys = sshKeys.authorizedKeys;
    initialPassword = "changeme";
    extraGroups = ["dialout"]; # USB serial access for ESPHome flashing
  };

  # Programs configuration
  programs = {
    mosh.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  # Server-specific packages and environment
  environment = {
    systemPackages = with pkgs; [
      linux-firmware
      rclone
      nh
      zoxide
      esphome # ESP32 flashing and management
      claude-code
      (pkgs.callPackage ../../pkgs/claude-zai.nix {})
      # Diagnostics for the bridge crew: python3 + jq for ad-hoc Matrix / organism
      # JSON inspection over ssh (the vox-organism daemon ships its OWN pinned
      # python3 interpreter via pkgs.python3.withPackages, so this is not a
      # runtime dep of the daemon — just the operator's PATH).
      python3
      jq
      # mu — the Interrogator (#53) runs read-only `mu find`/`mu view` over the
      # index the email-digest service already maintains (it is NOT a package
      # runtimeDep of interrogator_organism — the index/Maildir only exist on
      # rich-evans + the hermetic test stubs mu). Placed here so it resolves on
      # the vox-organism daemon's reactive PATH (/run/current-system/sw/bin)
      # + a manual interrogator-invoke. See email-digest.nix for the index.
      mu
    ];

    # Override default shell setup for server
    shells = [pkgs.fish];
    variables.EDITOR = lib.mkForce "nvim";
    sessionVariables.FLAKE = "/home/kimb/systems-flake";
  };

  users.defaultUserShell = pkgs.fish;

  # Trusted users for nix operations
  nix.settings.trusted-users = ["kimb" "root"];

  # Firewall configuration
  #
  networking.firewall = {
    allowedTCPPorts = [
      9001 # Existing service
      3923 # Copyparty HTTP
      3921 # Copyparty FTP
      3945 # Copyparty SMB
      3990 # Copyparty additional
      4822 # Guacamole daemon
      8080 # Guacamole web interface
    ];
    allowedTCPPortRanges = [
      {
        from = 12000;
        to = 12099;
      } # Copyparty dynamic ports
    ];
    allowedUDPPorts = [
      65535 # Existing
      69 # TFTP
      1900 # UPnP
      3969 # Copyparty TFTP
      5353 # mDNS/Bonjour
      20
    ];
  };
  networking.firewall.trustedInterfaces = ["nebula1" "lo"];

  # Lifecoach freshness metric — DISABLED along with observability
  # systemd.services.lifecoach-freshness-probe = { ... };
  # systemd.timers.lifecoach-freshness-probe = { ... };

  system.stateVersion = "23.11";
}
