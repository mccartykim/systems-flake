# Personalization layer for the generic restic-b2-backup flake module.
# Sets kimb-specific defaults (repo, paths, secrets), exposes the
# `kimb.restic.enable` opt-in option that hosts use to turn on backups.
#
# Also prepends `restic unlock` as the first ExecStartPre so stale locks
# (left by a crashed backup on another host sharing the same B2 repo)
# are cleared before the repo-init check runs.  Without this, the
# pre-start `restic cat config || restic init` fails on a locked repo,
# which prevents the backup from ever running — including the
# `restic unlock` in ExecStart that would clear the lock.
#
# When observability is enabled, a staleness probe timer exports
# `restic_backup_staleness_seconds` via the node_exporter textfile
# collector so Prometheus can alert on backups that haven't completed
# within the expected window.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.kimb.restic;

  # The backup name from the restic-b2-backup module (defaults to "home").
  # This determines the systemd service name: restic-backups-${backupName}.
  backupName = config.services.resticB2.backupName;
  serviceName = "restic-backups-${backupName}";
  textfileDir = "/var/lib/prometheus-node-exporter-textfiles";
in {
  imports = [inputs.restic-b2-backup.nixosModules.default];

  options.kimb.restic = {
    enable = mkEnableOption "kimb's restic backups to shared B2 repo";

    extraExclude = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Per-host paths to exclude (appended to the kimb-default excludes).";
    };

    stalenessProbe = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable a staleness probe that checks how long since the last
        successful restic backup and exports
        restic_backup_staleness_seconds via the Prometheus
        node_exporter textfile collector.  Requires
        kimb.observability to be enabled on the host.
      '';
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

    # Clear stale locks before the repo-init check runs.
    # Without this, a leftover lock from a crashed/aborted backup on another
    # host (e.g., donut leaving a lock after a network interruption) causes
    # ExecStartPre's `restic cat config || restic init` to fail, which prevents
    # the backup from ever running — including the `restic unlock` in ExecStart
    # that would clear the lock.
    #
    # The `-` prefix makes the unlock non-fatal so that a first-time `restic
    # init` on a brand-new repo isn't blocked by the unlock failing on a
    # non-existent repo.
    systemd.services.${serviceName}.serviceConfig.ExecStartPre =
      mkBefore ["-${pkgs.restic}/bin/restic unlock"];

    # Staleness probe: checks how long since the last restic backup
    # completed and exports restic_backup_staleness_seconds via the
    # node_exporter textfile collector so Prometheus can alert on backups
    # that haven't run within the expected window (e.g., >24 h).
    # This catches stale-lock deadlocks proactively rather than relying
    # solely on UnitFailed alerts.
    #
    # Only activated when both kimb.restic.stalenessProbe (default true)
    # and kimb.observability.enable are set — the latter ensures
    # node_exporter is running with the textfile collector.
    systemd.services.restic-staleness-probe = mkIf (cfg.stalenessProbe && config.kimb.observability.enable) {
      description = "Export restic backup staleness metric";
      serviceConfig.Type = "oneshot";
      script = ''
        OUT=${textfileDir}/restic_staleness.prom.tmp
        FINAL=${textfileDir}/restic_staleness.prom
        NOW=$(${pkgs.coreutils}/bin/date +%s)
        staleness=999999

        # Check when the backup service last completed.
        # ExecMainExitTimestamp is empty until the service has run at least once.
        last_exit=$(${pkgs.systemd}/bin/systemctl show ${serviceName} --property=ExecMainExitTimestamp --value 2>/dev/null || echo "")
        if [ -n "$last_exit" ] && [ "$last_exit" != "n/a" ] && [ "$last_exit" != "" ]; then
          last_epoch=$(${pkgs.coreutils}/bin/date -d "$last_exit" +%s 2>/dev/null || echo 0)
          if [ "$last_epoch" -gt 0 ]; then
            staleness=$(( NOW - last_epoch ))
            # Clamp to non-negative (clock skew)
            [ "$staleness" -lt 0 ] && staleness=0
          fi
        fi

        cat > "$OUT" << EOF
        # HELP restic_backup_staleness_seconds Seconds since the last restic backup completed (999999 = never)
        # TYPE restic_backup_staleness_seconds gauge
        restic_backup_staleness_seconds $staleness
        EOF
        mv "$OUT" "$FINAL"
      '';
    };

    systemd.timers.restic-staleness-probe = mkIf (cfg.stalenessProbe && config.kimb.observability.enable) {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
    };

    # Ensure the textfile directory exists for the staleness probe.
    # (Duplicate of the rule in kimb.observability — harmless if both
    # are active, and required when observability is enabled but its
    # tmpfiles rule hasn't run yet.)
    systemd.tmpfiles.rules = mkIf (cfg.stalenessProbe && config.kimb.observability.enable) [
      "d ${textfileDir} 0777 nobody nogroup -"
    ];
  };
}
