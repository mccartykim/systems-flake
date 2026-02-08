# Restic backup module for Backblaze B2
# Full-system backup suitable for bare-metal restore via restic restore + nixos-install
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
      default = [
        "/home/kimb"
        "/etc"
        "/var/lib"
        "/root"
      ];
      description = "Paths to back up";
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [
        # === /home/kimb excludes ===
        # Caches
        "/home/kimb/.cache"
        "/home/kimb/.local/share/Trash"

        # Gaming (large, re-downloadable)
        "/home/kimb/.local/share/Steam"
        "/home/kimb/.steam"
        "/home/kimb/.local/share/lutris"

        # Build artifacts & dev cruft
        "/home/kimb/**/node_modules"
        "/home/kimb/**/target"
        "/home/kimb/**/.direnv"
        "/home/kimb/**/result"

        # Nix store symlinks (not actual data)
        "/home/kimb/**/.nix-profile"
        "/home/kimb/**/.nix-defexpr"

        # === /var/lib excludes ===
        # Container/VM storage (huge, opaque, manage separately)
        "/var/lib/docker"
        "/var/lib/containers"
        "/var/lib/libvirt/images"
        "/var/lib/lxc"

        # Systemd runtime state (regenerated on boot)
        "/var/lib/systemd/coredump"

        # NixOS state that's rebuilt from config
        "/var/lib/nixos"

        # === System-wide cache/temp ===
        "/var/cache"
        "/var/tmp"
      ];
      description = "Paths to exclude from backup";
    };

    extraExclude = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional paths to exclude (appended to default excludes)";
    };

    backupCleanupCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command to run after backup completes";
    };

    timerConfig = mkOption {
      type = types.attrs;
      default = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "2h";
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

    services.restic.backups.home =
      {
        initialize = true;
        repository = "b2:kim-bucket:/restic";
        passwordFile = config.age.secrets.restic-password.path;
        environmentFile = config.age.secrets.restic-b2-env.path;
        paths = cfg.paths;
        exclude = cfg.exclude ++ cfg.extraExclude;
        timerConfig = cfg.timerConfig;
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
          "--keep-yearly 2"
        ];
      }
      // lib.optionalAttrs (cfg.backupCleanupCommand != null) {
        backupCleanupCommand = cfg.backupCleanupCommand;
      };
  };
}
