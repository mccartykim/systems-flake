# systemd-journal-remote receiver sink
# Companion to modules/observability.nix — receives journal uploads on
# TCP/19532 (plain HTTP) from senders that set kimb.observability.enable.
# Retention is bounded via journal-remote.conf MaxUse (2G total, or ~2G
# per sender with --split-mode=host).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.journalRemote;
  port = 19532;
in {
  options.kimb.journalRemote = {
    enable = mkEnableOption "systemd-journal-remote receiver sink (HTTP/19532)";
  };

  config = mkIf cfg.enable {
    users.users.systemd-journal-remote = {
      isSystemUser = true;
      group = "systemd-journal-remote";
    };
    users.groups.systemd-journal-remote = {};

    systemd.tmpfiles.rules = [
      "d /var/log/journal/remote 0755 systemd-journal-remote systemd-journal-remote -"
    ];

    # Retention limit via config file (works on all systemd versions;
    # the --max-use CLI flag was only added in systemd 261).
    environment.etc."systemd/journal-remote.conf".text = ''
      [Remote]
      MaxUse=2G
    '';

    systemd.sockets.systemd-journal-remote = {
      description = "Journal Remote Sink";
      listenStreams = [(toString port)];
      wantedBy = ["sockets.target"];
    };

    # Reachability: senders connect over Nebula. Hosts enabling this sink
    # are expected to have nebula1 in networking.firewall.trustedInterfaces,
    # so no explicit allowedTCPPorts entry is needed here. If that ever
    # changes, open port ${toString port} on the nebula interface.
    systemd.services.systemd-journal-remote = {
      description = "Journal Remote Sink";
      requires = ["systemd-journal-remote.socket"];
      after = ["systemd-journal-remote.socket"];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-remote --output=/var/log/journal/remote/ --split-mode=host";
        User = "systemd-journal-remote";
        Group = "systemd-journal-remote";
      };
    };
  };
}
