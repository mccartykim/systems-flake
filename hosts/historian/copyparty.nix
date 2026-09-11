# Copyparty file share — the a3j.6 phase-6b migration from rich-evans
# (ported from the framework block in hosts/rich-evans/services.nix).
#
# The volume IS the seagate (/mnt/media-drive/copyparty) — zero data
# movement, the files ride the drive that landed at a3j.4; the path swap
# (was /mnt/seagate/copyparty on rich-evans, local-disk then) is the only
# change. State is trivial (~80K in /var/lib/copyparty, rsync'd).
#
# NOTE: the registry entry (subdomain "files", auth=authelia,
# publicAccess=true) is ASPIRATIONAL — files.kimb.dev has never had a
# maitred duplicate entry, so no vhost/socat exists; copyparty is reached
# directly by IP:3923 over LAN/Nebula, exactly as on rich-evans. Giving
# it a real vhost would be a new feature (a deliberate post-migration
# decision, not a cutover variable) — the SSO header config below is kept
# ready for it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
in {
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
      acao = "https://files.${cfg.domain}";
      acam = "GET,POST,PUT,DELETE,HEAD,OPTIONS";
    };

    # The volume: the seagate's copyparty tree, local since a3j.4.
    volumes = {
      "/" = {
        path = "/mnt/media-drive/copyparty";
        access = {
          # Give kimb full admin permissions via SSO header
          rwadmG = [cfg.admin.name];
          # Allow all authenticated users to read
          r = "*";
        };
      };
    };
  };

  # Direct-access exposure (LAN + Nebula), mirroring rich-evans's posture:
  # main HTTP + FTP/SMB sidecars + the dynamic port range + TFTP.
  networking.firewall = {
    allowedTCPPorts =
      lib.optional cfg.services.copyparty.enable cfg.services.copyparty.port
      ++ lib.optionals cfg.services.copyparty.enable [3921 3945 3990];
    allowedUDPPorts = lib.optionals cfg.services.copyparty.enable [3969];
    allowedTCPPortRanges = lib.optionals cfg.services.copyparty.enable [
      {
        from = 12000;
        to = 12099;
      }
    ];
  };

  kimb.nebula.extraInboundRules = lib.optionals cfg.services.copyparty.enable [
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
  ];
}