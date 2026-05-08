{
  config,
  lib,
  ...
}: let
  registry = import ./hosts/nebula-registry.nix;
in {
  # --- Networks ---
  networks = {
    lan = {
      name = "Home LAN";
      cidrv4 = "192.168.69.0/24";
      icon = "icons.internet";
    };
    nebula = {
      name = "Nebula Overlay";
      cidrv4 = "10.100.0.0/16";
      style = {
        primaryColor = "#6366f1";
        secondaryColor = "#e0e7ff";
        pattern = "dashed";
      };
    };
    containers = {
      name = "Container Bridge";
      cidrv4 = "192.168.100.0/24";
    };
  };

  # --- Internet ---
  nodes.internet = {
    name = "Internet";
    deviceType = "internet";
    interfaces = {
      wan = {
        network = null;
      };
    };
  };

  # --- Router ---
  nodes.maitred = {
    name = "maitred";
    deviceType = "router";
    hardware.info = "Datto 1000 — Edge router, reverse proxy, DNS";
    interfaces = {
      wan = {
        addresses = ["DHCP"];
        physicalConnections = [{node = "internet"; interface = "wan";}];
      };
      lan = {
        addresses = ["192.168.69.1/24"];
        network = "lan";
      };
      nebula = {
        addresses = ["10.100.0.50/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  # --- Desktops ---
  nodes.historian = {
    name = "historian";
    deviceType = "nixos";
    hardware.info = "GmkTec NucBox EVO-X1 — Daily driver desktop, Jellyfin, Ollama";
    interfaces = {
      lan = {
        addresses = ["DHCP"];
        network = "lan";
        physicalConnections = [{node = "maitred"; interface = "lan";}];
      };
      nebula = {
        addresses = ["10.100.0.10/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  nodes.total-eclipse = {
    name = "total-eclipse";
    deviceType = "nixos";
    hardware.info = "Costco gaming PC — Nvidia RTX 4060";
    interfaces = {
      lan = {
        addresses = ["DHCP"];
        network = "lan";
        physicalConnections = [{node = "maitred"; interface = "lan";}];
      };
      nebula = {
        addresses = ["10.100.0.6/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  # --- Servers ---
  nodes.rich-evans = {
    name = "rich-evans";
    deviceType = "nixos";
    hardware.info = "HP ProDesk 600 G2 DM — General server, cameras, Buildbot";
    interfaces = {
      lan = {
        addresses = ["DHCP"];
        network = "lan";
        physicalConnections = [{node = "maitred"; interface = "lan";}];
      };
      nebula = {
        addresses = ["10.100.0.40/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  # --- Laptops / portables ---
  nodes.marshmallow = {
    name = "marshmallow";
    deviceType = "nixos";
    hardware.info = "ThinkPad T490 — Daily driver laptop";
    interfaces = {
      wifi = {
        addresses = ["DHCP"];
        network = "lan";
        type = "wifi";
      };
      nebula = {
        addresses = ["10.100.0.4/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  nodes.bartleby = {
    name = "bartleby";
    deviceType = "nixos";
    hardware.info = "ThinkPad X131e — Beloved college laptop";
    interfaces = {
      wifi = {
        addresses = ["DHCP"];
        network = "lan";
        type = "wifi";
      };
      nebula = {
        addresses = ["10.100.0.3/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  nodes.cheesecake = {
    name = "cheesecake";
    deviceType = "nixos";
    hardware.info = "Microsoft Surface Go 3 — Portable tablet";
    interfaces = {
      wifi = {
        addresses = ["DHCP"];
        network = "lan";
        type = "wifi";
      };
      nebula = {
        addresses = ["10.100.0.5/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  nodes.donut = {
    name = "donut";
    deviceType = "nixos";
    hardware.info = "Valve Steam Deck — Portable gaming (Jovian NixOS)";
    interfaces = {
      wifi = {
        addresses = ["DHCP"];
        network = "lan";
        type = "wifi";
      };
      nebula = {
        addresses = ["10.100.0.7/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  # --- External / non-NixOS devices on Nebula ---
  nodes.oracle = {
    name = "oracle";
    deviceIcon = "icons.cloud";
    hardware.info = "Oracle Cloud VM — Nebula lighthouse + relay";
    interfaces = {
      wan = {
        addresses = ["150.136.155.204"];
        physicalConnections = [{node = "internet"; interface = "wan";}];
      };
      nebula = {
        addresses = ["10.100.0.2/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  nodes.tachikoma = {
    name = "tachikoma";
    deviceIcon = "icons.robot";
    hardware.info = "Dreame vacuum (Valetudo) — Robot vacuum with camera";
    interfaces = {
      lan = {
        addresses = ["192.168.69.177"];
        network = "lan";
        physicalConnections = [{node = "maitred"; interface = "lan";}];
      };
      nebula = {
        addresses = ["10.100.0.60/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };

  nodes.mochi = {
    name = "mochi";
    deviceIcon = "icons.smartphone";
    hardware.info = "Google Pixel 9 Pro — AVF/Debian (system-manager)";
    interfaces = {
      nebula = {
        addresses = ["10.100.0.8/16"];
        network = "nebula";
        type = "tunnel";
        virtual = true;
      };
    };
  };
}
