# choirmaster-organism: host enablement for the Choirmaster Cassiel, the
# 13th bridge officer — on-demand music (MPD httpd + Chromecast). Find +
# start only (the Lord-Captain stops manually); NO heartbeat. The
# vox-organism daemon runs `organic <this-seed> "<msg>"` AS vox-organism
# (uid 998, a member of choirmaster-organism via the roster's
# daemonExtraGroups); choirmaster-infer dispatches play / cast-stream /
# mpd-status as bare names (the package wraps each with its runtime deps
# + CHOIRMASTER_LIB_PARENT, so the daemon needs only choirmaster-pkg on
# PATH — wired in vox-organism.nix).
#
# The module (choirmaster_organism/nixos/module.nix) is self-contained —
# it resolves its own package from pkgs.system, so this file is CONFIG-
# ONLY + needs NO extraSpecialArgs (same shape as the other self-contained
# officer host files). The officer is on-request: NO heartbeat + NO
# ollamaHost/ollamaModel here (the LLM env is inherited on the reactive
# path from the daemon, which inherits voidmaster-heartbeat's OLLAMA_*).
# CHOIRMASTER_STATE is mirrored into the daemon env (vox-organism.nix) for
# clean logging; MPD_HOST/MPD_HTTP_PORT/TTS_DEVICE all have working
# defaults in the package wrap (auto-LAN-IP + 8666 + "Kim's nest hub").
#
# MPD httpd: the Choirmaster casts the MPD httpd stream at the Nest hub.
# MPD runs on rich-evans (new — only creme had it before), reading
# /mnt/seagate/music_compressed + exposing an httpd audio output on
# 0.0.0.0:8666 (the port cast-stream builds the stream URL from, default
# MPD_HTTP_PORT). Control port 6600 stays loopback — mpc runs locally on
# the daemon. The Choirmaster can also play direct URLs via `mpc add
# <url>` (internet radio etc.) independent of the local library.
#
# Both music folders are PLAIN sendreceive on rich-evans's Seagate as of
# 2026-07-26 (a RUNTIME syncthing flip — no NixOS rebuild). Compressed
# (fgp3e-2t6j7, 367 .opus, 1.6G) + Music Originals (69p3x-vpttj, 365
# .flac/.mp3, 17G) sync plain from historian (sole source for originals) +
# total-eclipse (compressed). The encryption lived on the SENDER side
# (<encryptionPassword> on rich-evans's device entry in each sender's
# folder); flipping receiveencrypted→sendreceive in-place wedged the
# index DB (rescan 500'd) until the folder's index-v2 SQLite db was
# deleted + syncthing restarted. creme/marshmallow/cheesecake were
# offline at flip time + Pixel/kmccarty-YM2K aren't SSHable — those still
# encrypt to rich-evans (harmless; the plain senders populate the
# library). MPD reads the dir via the "other" read bit (syncthing writes
# 0644/0755); no group juggling needed.
#
# Routing to #choirmaster (room + route + daemon extraGroups + org-bridge
# scope stanza + bridge-log heading) ships from 40k_bridge; roster-DERIVED.
#
# Rollback: `services.choirmaster-organism.enable = false` + set
# `services.mpd.enable = false` + revert the routing row / scope stanza
# in 40k_bridge + rebuild. The Choirmaster never mutates anything but its
# own state; disable leaves no side effects (the Nest hub keeps doing
# whatever it was doing — find+start never auto-stops anything).
{...}: {
  services.choirmaster-organism.enable = true;

  # MPD httpd — the stream the Choirmaster casts. Control port 6600 stays
  # loopback (mpc runs locally on the daemon); the httpd output binds
  # 0.0.0.0:8666 so the Nest hub can fetch it over the LAN. musicDirectory
  # is the EXISTING /mnt/seagate/music_compressed (currently encrypted-
  # receive; becomes a real library after the runtime syncthing flip).
  # audio_output is the declarative RFC42 form (services.mpd.settings, a
  # list of attrsets — each renders an `audio_output { ... }` block); the
  # old `extraConfig` string was removed in current nixpkgs.
  services.mpd = {
    enable = true;
    musicDirectory = "/mnt/seagate/music_compressed";
    settings.audio_output = [
      {
        type = "httpd";
        name = "rich-evans choirmaster stream";
        port = "8666";
        bind_to_address = "0.0.0.0";
        encoder = "lame";
        bitrate = "192";
        format = "44100:16:2";
      }
    ];
  };
}