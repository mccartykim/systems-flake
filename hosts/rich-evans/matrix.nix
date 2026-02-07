# Matrix homeserver (Tuwunel) + Discord bridge (mautrix-discord)
{
  config,
  lib,
  pkgs,
  ...
}: {
  # mautrix-discord depends on olm which is deprecated but still functional
  # The security concerns are about theoretical side-channel attacks, not remote exploits
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"
  ];

  services.matrix-tuwunel = {
    enable = true;
    settings.global = {
      server_name = "kimb.dev"; # Matrix ID domain (NOT matrix.kimb.dev)
      port = [6167];
      address = ["0.0.0.0"]; # Accessible via Nebula
      allow_registration = false;
      allow_federation = true;
    };
  };

  services.mautrix-discord = {
    enable = true;
    settings = {
      homeserver = {
        address = "http://127.0.0.1:6167";
        domain = "kimb.dev";
      };
      appservice = {
        hostname = "127.0.0.1";
        port = 29334;
        database = {
          type = "sqlite3";
          uri = "file:/var/lib/mautrix-discord/mautrix-discord.db?_txlock=immediate";
        };
      };
      bridge.permissions = {
        "@kimb:kimb.dev" = "admin";
      };
    };
  };

  # Ensure mautrix-discord starts after tuwunel
  systemd.services.mautrix-discord = {
    after = ["tuwunel.service"];
    requires = ["tuwunel.service"];
  };

  # Resource limits - rich-evans is a Celeron-based PC, be conservative
  systemd.services.tuwunel.serviceConfig = {
    MemoryMax = "1G";
    CPUQuota = "50%";
  };

  # Firewall - port 6167 opened via Nebula rules in configuration.nix
  networking.firewall.allowedTCPPorts = [6167];
}
