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

    # email-digest STUB — user/group only (a3j.6 6b interim, see the file)
    ./email-digest-stub.nix

    # Matrix homeserver — REMOVED at a3j.6: Tuwunel + mautrix-discord moved
    # to historian (hosts/historian/matrix.nix; the vox-organism daemon here
    # polls 10.100.0.10:6167 over Nebula until a3j.7). The module file stays
    # for reference.
    # ./matrix.nix

    # Knitwork — REMOVED at a3j.5: the lexicon host + firehose indexer moved
    # to historian (hosts/historian/knitwork.nix; the registry entry lives in
    # the historian bucket). The module file stays for reference, like
    # buildbot-master.nix.
    # ./knitwork.nix

    # Knitwork BFF — REMOVED at a3j.5: the ATProto OAuth write relay moved to
    # historian (hosts/historian/knitwork-bff.nix).
    # ./knitwork-bff.nix

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
      # Matrix/Tuwunel homeserver — REMOVED at a3j.6 (moved to historian; the
      # vox-organism daemon polls it over Nebula at 10.100.0.10:6167).
      # SRE agent webhook (Alertmanager → rich-evans)
      {
        port = 9095;
        proto = "tcp";
        host = "maitred";
      }
      # a3j.4: NFSv4 rule REMOVED — the seagate lives on historian now.
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

  # a3j.6 completion: the /mnt/seagate NFS mount is REMOVED — org-crm
  # (the last 6b drive consumer) moved to historian at cutover 9,
  # rich-evans's syncthing seagate folders were removed (the mesh lives on
  # historian: ~/Music, ~/compressed_music, ~/org, ~/work-org,
  # ~/color_ebooks), and org-bridge (staying here per a3j.7.1) reads a
  # LOCAL ~/org dir (crew-context.org md5-verified identical) instead of
  # the drive via the old symlink. The ~/work-org symlink (pointing at
  # all-encrypted receiveencrypted blobs — never readable) was removed
  # too. No drive consumer remains on this host.

  # a3j.4: NFS export REMOVED — the seagate physically moved to historian
  # (which now reverse-exports it rw to this host for the 6b interim; see
  # the mount above). This host is no longer an NFS server.

  # Shared put.io rclone config (same .age file / path / owner as historian's
  # declaration; rekeyed to rich-evans's host key in secrets/secrets.nix). Used by
  # rclone-putio-sync below.
  age.secrets.rclone-config = {
    file = ../../secrets/rclone-config.age;
    path = "/run/agenix/rclone-config";
    mode = "0400";
    owner = "kimb";
  };

  # a3j.4: rclone-putio-sync REMOVED — the put.io writer runs on historian now
  # (local writes to the drive beat NFS writes; same unit body, see
  # hosts/historian/configuration.nix).

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
      4822 # Guacamole daemon
      8080 # Guacamole web interface
      # 8666 removed at a3j.5 — the MPD httpd stream moved to historian
      # (LAN IP 192.168.69.167:8666; the Nest fetches it there now). Note:
      # the old comment's "music.kimb.dev" Caddy proxy never existed in the
      # config — no vhost replacement is needed.
    ];
    allowedTCPPortRanges = [
    ];
    allowedUDPPorts = [
      65535 # Existing
      1900 # UPnP
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
