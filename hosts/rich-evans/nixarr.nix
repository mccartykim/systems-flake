{pkgs, ...}: {
  services = {
    jellyfin = {
      enable = false;
      user = "media";
      group = "media";
    };

    jellyseerr = {
      enable = false;
      openFirewall = true;
    };

    transmission = {
      enable = false;
      home = "/mnt/seagate/torrent_zone/transmission";
      user = "media";
      group = "media";
      openFirewall = true;
      openRPCPort = true;
      settings = {
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist = ["127.0.0.1" "192.168.*.*" "100.*.*.*" "rich-evans" "kims-macbook-pro"];
        rpc-whitelist-enabled = true;
        rpc-host-whitelist = ["127.0.0.1" "192.168.*.*" "100.*.*.*" "rich-evans"];
        rpc-host-whitelist-enabled = true;
        bind-address-ipv4 = "205.142.240.210";
        port-forwarding-enabled = true;
        rpc-enabled = true;
        rpc-username = "kimb";
        rpc-password = "kimb";
      };
    };

    sonarr = {
      enable = false;
      user = "media";
      group = "media";
      openFirewall = true;
    };
    prowlarr = {
      enable = false;
      openFirewall = true;
    };
    radarr = {
      enable = false;
      user = "media";
      group = "media";
      openFirewall = true;
    };
  };

  users = {
    users = {
      media = {
        group = "media";
        isSystemUser = true;
      };
      "kimb".extraGroups = ["media"];
    };
    groups.media = {};
  };

  virtualisation.oci-containers = let
    startTailscale = pkgs.writeScriptBin "startTailscale" ''
      #!/bin/sh
      echo "hi"
      ${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking
      ${pkgs.tailscale}/bin/tailscale up --authkey=$$TAILSCALE_KEY
      ${pkgs.tailscale}/bin/tailscale status
    '';
    nix-transmission = pkgs.dockerTools.buildLayeredImage {
      name = "container-transmission";
      tag = "latest";
      contents = [
        pkgs.coreutils
        pkgs.tailscale
        startTailscale
      ];
      config = {
        Env = ["TAILSCALE_KEY="];
        Cmd = ["${startTailscale}/bin/startTailscale"];
      };
    };
  in {
    containers = {
      test = {
        image = "${nix-transmission}";
        environment = {
          PUID = "13021";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };
      sonarr = {
        autoStart = true;
        image = "lscr.io/linuxserver/sonarr:latest";
        ports = ["8989:8989"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/sonarr-config:/config"
          "/mnt/seagate/torrent_zone/data:/data"
        ];
        environment = {
          PUID = "13001";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };

      radarr = {
        autoStart = true;
        image = "linuxserver/radarr:latest";
        ports = ["7878:7878"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/radarr-config:/config"
          "/mnt/seagate/torrent_zone/data:/data"
        ];
        environment = {
          PUID = "13002";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };

      bazarr = {
        autoStart = true;
        image = "lscr.io/linuxserver/bazarr:latest";
        ports = ["6767:6767"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/bazarr-config:/config"
          "/mnt/seagate/torrent_zone/data/media:/media"
        ];
        environment = {
          PUID = "13012";
          PGID = "13000";
          TZ = "America/New_York";
        };
      };

      lidarr = {
        autoStart = true;
        image = "lscr.io/linuxserver/lidarr:latest";
        ports = ["8686:8686"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/lidarr-config:/config"
          "/mnt/seagate/torrent_zone/data:/data"
        ];
        environment = {
          PUID = "13003";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };

      readarr = {
        autoStart = true;
        image = "lscr.io/linuxserver/readarr:develop";
        ports = ["8787:8787"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/readarr-config:/config"
          "/mnt/seagate/torrent_zone/data:/data"
        ];
        environment = {
          PUID = "13004";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };

      prowlarr = {
        autoStart = false;
        image = "lscr.io/linuxserver/prowlarr:develop";
        ports = ["9696:9696"];
        volumes = ["/mnt/seagate/torrent_zone/config/prowlarr-config:/config"];
        environment = {
          PUID = "13006";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };

      qbittorrent = {
        autoStart = false;
        image = "lscr.io/linuxserver/qbittorrent:latest";
        ports = ["8080:8080" "6881:6881" "6881:6881/udp"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/qbittorrent-config:/config"
          "/mnt/seagate/torrent_zone/data/torrents:/data/torrents"
        ];
        environment = {
          PUID = "13007";
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
          WEBUI_PORT = "8080";
        };
        extraOptions = [
          # "--network=bridge interface=wg0"
        ];
      };

      jellyfin = {
        autoStart = true;
        image = "lscr.io/linuxserver/jellyfin:latest";
        ports = ["8096:8096"];
        volumes = [
          "/mnt/seagate/torrent_zone/config/jellyfin-config:/config"
          "/mnt/seagate/torrent_zone/data/media:/data"
        ];
        environment = {
          PUID = "1000"; # Assuming specific user handling is corrected.
          PGID = "13000";
          UMASK = "002";
          TZ = "America/New_York";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/seagate/torrent_zone/ 0770 - media - -"
  ];

  # services.mullvad-vpn.enable = true;
  networking = {
    iproute2.enable = true;
    wg-quick.interfaces = let
      # [Peer] section -> Endpoint
      server_ip = "205.142.240.210";
    in {
      wg0 = {
        autostart = false;
        # [Interface] section -> Address
        address = ["10.2.0.2/32"];

        # [Peer] section -> Endpoint:port
        listenPort = 51820;
        dns = ["10.2.0.1"];

        # Path to the private key file.
        privateKeyFile = "/etc/proton-vpn.key";

        peers = [
          {
            # [Peer] section -> PublicKey
            publicKey = "/HvEnSU5JaswyBC/YFs74eGLXqLdzsaFeVT8SD1KYAc=";
            # [Peer] section -> AllowedIPs
            allowedIPs = ["0.0.0.0/0"];
            # [Peer] section -> Endpoint:port
            endpoint = "${server_ip}:51820";
          }
        ];
      };
    };
  };
}
