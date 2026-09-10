# MPD httpd — the Choirmaster's music stream, ported from
# hosts/rich-evans/choirmaster-organism.nix at a3j.5 (the organism itself
# stays on rich-evans until the a3j.7 organisms domU; only the mpd service
# moves now, per the a3j.5 phase list).
#
# Music lives on the seagate, read via the /mnt/media-drive NFS automount
# (read-only) until a3j.4 physically moves the drive here — path-preserved,
# so this config is untouched by that move. The compressed library
# (music_compressed) is the one the Choirmaster casts.
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
  services.mpd = {
    enable = true;
    musicDirectory = "/mnt/media-drive/music_compressed";
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
  networking.firewall.allowedTCPPorts = [8666 6600];
}