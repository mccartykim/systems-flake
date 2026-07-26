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
# music_compressed is currently a syncthing ENCRYPTED-receive folder on
# rich-evans (folder fgp3e-2t6j7, 7 plain senders fleet-wide). While
# encrypted, MPD scans only .syncthing-enc blocks → an empty library
# (honest inert MVP: the Choirmaster plays direct URLs / internet radio
# meanwhile). The user authorized flipping that folder to PLAIN receive
# across the 7 senders + rich-evans so MPD gets a real library; that flip
# is a RUNTIME syncthing operation (no NixOS rebuild) — tracked separately
# from this wiring. After it lands, MPD's next rescan reads the real
# .flac/.mp3 set. Music Originals (69p3x-vpttj) stays encrypted-receive as
# the lossless backup; only the derived compressed set goes plain. MPD
# reads the dir via the "other" read bit (syncthing writes 0644/0755); no
# group juggling needed.
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