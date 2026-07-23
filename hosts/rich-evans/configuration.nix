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

  # Mount external storage
  fileSystems."/mnt/seagate" = {
    device = "/dev/disk/by-uuid/980870c5-7397-45dd-9f01-972f9b51d0f6";
    fsType = "ext4";
    options = ["defaults" "nofail"];
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

    # Mesh networking
    yggdrasil = {
      enable = false;
      persistentKeys = true;
      openMulticastPort = true;
      group = "wheel";
      settings = {
        Peers = [
          "tcp://longseason.1200bps.xyz:13121"
          "tls://longseason.1200bps.xyz:13122"
          "quic://198.23.229.154:9003"
        ];
        LinkLocalTCPPort = 65535;
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
