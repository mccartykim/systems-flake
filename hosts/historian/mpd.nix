  # MPD httpd — the Choirmaster's music stream, ported from
# hosts/rich-evans/choirmaster-organism.nix at a3j.5 (the organism itself
# stays on rich-evans until the a3j.7 organisms domU; only the mpd service
# moves now, per the a3j.5 phase list).
#
# a3j.6 completion: the library moved from /mnt/media-drive/music_compressed
# (the seagate copy — kept current only by rich-evans's now-removed
# NFS-looped syncthing folder) to ~/compressed_music, this host's
# syncthing-managed copy of the SAME folder (fgp3e-2t6j7, sendreceive,
# verified in-sync at the flip). Content identical; the seagate copy goes
# stale (inert blob on the drive, tracked for cleanup at a3j.13).
# The compressed library is the one the Choirmaster casts.
#
# inotify auto_update does NOT work over NFS (events fire on the NFS server,
# never reach the client), so rich-evans's `settings.auto_update = "yes"` is
# replaced here by a polling `mpc update` timer — newly syncthing-synced
# tracks land in the DB within 15 min instead of instantly. Acceptable: the
# compressed folder's sender (total-eclipse) is wake-on-demand anyway.
#
# Reachability after the move:
#   - 8666 httpd stream: fetched by the bedroom Nest hub over the LAN (cast
#     sessions pull the URL directly — it must be a LAN address, hence
#     0.0.0.0 + a LAN firewall hole, mirroring rich-evans's posture).
#   - 6600 control: the Choirmaster organism (still on rich-evans, in the
#     vox-organism daemon) runs mpc against MPD_HOST, which the a3j.5 cutover
#     sets to historian's LAN IP 192.168.69.167 in
#     hosts/rich-evans/vox-organism.nix. Same env var feeds cast-stream's
#     stream URL, so one flip repoints both control and cast.
{
  lib,
  pkgs,
  ...
}: {
  # Read-only bind of the syncthing-managed ~/compressed_music for the
  # `mpd` user (cannot traverse the 0700 /home/kimb; jellyfin's music bind
  # in configuration.nix is the same pattern). NOTE: the bind must live
  # OUTSIDE /var/lib/mpd — the nixpkgs mpd module adds StateDirectory=mpd/
  # music when musicDirectory is exactly /var/lib/mpd/music, and systemd's
  # state-dir namespace setup then collides with the ro bind (EROFS at the
  # STATE_DIRECTORY step — the 03:02 activation failure). /srv/mpd-music
  # dodges the exact-match and keeps the ro guarantee.
  fileSystems."/srv/mpd-music" = {
    device = "/home/kimb/compressed_music";
    fsType = "none";
    options = ["bind" "ro"];
  };

  services.mpd = {
    enable = true;
    # Bind-mounted copy of ~/compressed_music (see fileSystems above) —
    # MPD runs as user `mpd` and /home/kimb is 0700 kimb:users, so it cannot
    # traverse the home path directly (same reason jellyfin's music bind
    # exists). The bind skips traversal; the folder itself is o+rx.
    # Order after the mount — RequiresMountsFor in [Unit] (unitConfig), the
    # section systemd actually honors for it (the email-digest lesson).
    musicDirectory = "/srv/mpd-music";
    # We open the firewall ourselves below (8666/6600) instead of letting the
    # module open it — its default (false) is kept explicit to silence the
    # non-loopback-bind warning.
    openFirewall = false;
    settings = {
      # Control port on all interfaces (Choirmaster mpc from rich-evans).
      # The httpd output has its own bind below.
      bind_to_address = "0.0.0.0";
      # RFC42 audio_output — renders an `audio_output { ... }` block. httpd
      # output only: historian has no speakers/desk audio for this service;
      # the Nest pulls the stream over the LAN, same as on rich-evans.
      auto_update = "no"; # inotify is dead over NFS (see header)
      audio_output = [
        {
          type = "httpd";
          name = "historian choirmaster stream";
          port = "8666";
          bind_to_address = "0.0.0.0";
          encoder = "lame";
          bitrate = "192";
          format = "44100:16:2";
        }
      ];
    };
  };

  # DB freshness over NFS: poll instead of inotify. 367 files — the update
  # scan itself takes seconds.
  systemd.services.mpd-update = {
    description = "Rescan MPD library (NFS inotify workaround)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.mpc}/bin/mpc update";
    };
  };
  systemd.timers.mpd-update = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/15";
      RandomizedDelaySec = "2m";
      Persistent = true;
    };
  };

  # LAN exposure: 8666 for the Nest's cast pull, 6600 for the Choirmaster's
  # mpc control (both from the LAN — the Nest is not a nebula node; the
  # firewall trust model matches rich-evans's, which also had 8666 open to
  # the LAN).
  # Order MPD after the music bind mount at activation (RequiresMountsFor
  # belongs in [Unit] — unitConfig — the section systemd honors; the
  # email-digest lesson about [Service]-section copies silently ignored).
  systemd.services.mpd.unitConfig.RequiresMountsFor = ["/srv/mpd-music"];

  networking.firewall.allowedTCPPorts = [8666 6600];
}