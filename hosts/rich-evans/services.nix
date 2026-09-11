# Rich-Evans services configuration using kimb-services options system
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
in {
  # Copyparty file sharing service (host service)
  services.copyparty = lib.mkIf cfg.services.copyparty.enable {
    enable = true;

    settings = {
      # Listen on all interfaces for LAN and Nebula access
      i = "0.0.0.0";
      # Keep default port 3923

      # Header-based SSO authentication with Authelia
      # Map Remote-User header from Authelia to Copyparty users
      idp-h-usr = "Remote-User";
      idp-h-grp = "Remote-Groups";

      # Trust maitred proxy for X-Forwarded-For and SSO headers
      xff-src = "10.100.0.0/16,192.168.100.0/24";

      # CORS configuration for reverse proxy uploads
      acao = "https://files.${cfg.domain}"; # Allow cross-origin from reverse proxy domain
      acam = "GET,POST,PUT,DELETE,HEAD,OPTIONS"; # Allow necessary HTTP methods
    };

    # Configure volumes with SSO user permissions
    volumes = {
      "/" = {
        path = "/mnt/seagate/copyparty";
        access = {
          # Give kimb full admin permissions via SSO header
          rwadmG = [cfg.admin.name];
          # Allow all authenticated users to read
          r = "*";
        };
      };
    };
  };

  # Home Assistant + mosquitto — REMOVED at a3j.6 phase 6a: moved to historian
  # as a unit (hosts/historian/home-assistant.nix; the registry entry lives
  # in the historian bucket now). The consumers still on this host (organism
  # daemons until a3j.7) point their haUrl at http://10.100.0.10:8123; the
  # vacuum's valetudo broker setting repoints to 192.168.69.167:1883.

  # Firewall configuration for enabled services
  networking.firewall = {
    allowedTCPPorts = lib.flatten [
      # Copyparty main port
      (lib.optional cfg.services.copyparty.enable cfg.services.copyparty.port)

      # Copyparty additional ports
      (lib.optionals cfg.services.copyparty.enable [3921 3945 3969 3990])



      # CUPS printing
      [631]

    ];

    allowedUDPPorts = lib.optionals cfg.services.copyparty.enable [
      3969 # TFTP
    ];

    allowedTCPPortRanges = lib.optionals cfg.services.copyparty.enable [
      {
        from = 12000;
        to = 12099;
      } # Dynamic ports for copyparty
    ];
  };

  # Create necessary directories
  systemd.tmpfiles.rules = lib.flatten [
    # Copyparty storage
    (lib.optional cfg.services.copyparty.enable "d /mnt/storage 0755 root root -")
    (lib.optional cfg.services.copyparty.enable "d /mnt/storage/public 0755 root root -")
  ];
}
