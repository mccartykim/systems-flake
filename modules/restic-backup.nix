# Restic backup module for Backblaze B2
# Backs up /home/kimb with deduplication across all hosts
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.restic;
in {
  options.kimb.restic = {
    enable = mkEnableOption "restic backups to Backblaze B2";

    paths = mkOption {
      type = types.listOf types.str;
      default = ["/home/kimb"];
      description = "Paths to back up";
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [
        # Cache directories
        "/home/kimb/.cache"
        "/home/kimb/.local/share/Steam"
        "/home/kimb/.local/share/lutris"
        "/home/kimb/.local/share/Trash"
        # Build artifacts
        "/home/kimb/**/node_modules"
        "/home/kimb/**/target"
        "/home/kimb/**/.direnv"
        "/home/kimb/**/result"
        # Nix store symlinks
        "/home/kimb/**/.nix-profile"
        "/home/kimb/**/.nix-defexpr"
      ];
      description = "Paths to exclude from backup";
    };

    timerConfig = mkOption {
      type = types.attrs;
      default = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      description = "Systemd timer configuration";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      restic-password = {
        file = ../secrets/restic-password.age;
        mode = "0400";
      };
      restic-b2-env = {
        file = ../secrets/restic-b2-env.age;
        mode = "0400";
      };
    };

    services.restic.backups.home = {
      initialize = true;
      repository = "b2:kim-bucket:/restic/${config.networking.hostName}";
      passwordFile = config.age.secrets.restic-password.path;
      environmentFile = config.age.secrets.restic-b2-env.path;
      paths = cfg.paths;
      exclude = cfg.exclude;
      timerConfig = cfg.timerConfig;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
        "--keep-yearly 2"
      ];
    };
  };
}
