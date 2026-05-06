# Personalization layer for the generic restic-b2-backup flake module.
# Sets kimb-specific defaults (repo, paths, secrets), exposes the
# `kimb.restic.enable` opt-in option that hosts use to turn on backups.
{
  config,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.kimb.restic;
in {
  imports = [inputs.restic-b2-backup.nixosModules.default];

  options.kimb.restic = {
    enable = mkEnableOption "kimb's restic backups to shared B2 repo";
    extraExclude = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Per-host paths to exclude (appended to the kimb-default excludes).";
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

    services.resticB2 = {
      enable = true;
      repository = "b2:kim-bucket:/restic";
      passwordFile = config.age.secrets.restic-password.path;
      environmentFile = config.age.secrets.restic-b2-env.path;
      inherit (cfg) extraExclude;

      paths = [
        "/home/kimb"
        "/etc"
        "/var/lib"
        "/root"
      ];

      # Override the generic exclude defaults with kimb-specific ones —
      # the generic module's defaults use globs like `**/.cache`, but
      # for kimb's paths we want explicit `/home/kimb/.cache` style.
      exclude = [
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
    };
  };
}
