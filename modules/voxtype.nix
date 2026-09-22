# Voxtype push-to-talk speech-to-text — opt-in per host via kimb.voxtype.enable.
#
# Voxtype is a whisper.cpp-based dictation daemon: hold a key, speak, release,
# and the transcript is typed at the cursor. We run it as a systemd USER
# service for kimb on the graphical session, and drive recording with
# voxtype's OWN built-in evdev hotkey (push_to_talk mode) rather than a
# compositor binding or keyd, because:
#
#   * KDE Plasma exposes no key-release event, so a compositor binding could
#     only ever toggle — not hold-to-talk. i3 does support `bindsym --release`
#     but Plasma (total-eclipse, marshmallow) does not.
#   * keyd sends one command per key PRESS and has no release binding at all.
#   * voxtype's evdev listener reads /dev/input directly, kernel-level, and so
#     sees press AND release regardless of compositor. That is the only
#     mechanism that yields hold-to-talk uniformly across Plasma and i3 hosts.
#
# Consequence: the trigger key must NOT be claimed by keyd or by a compositor
# binding, or it never reaches voxtype. See modules/peripherals.nix, which
# deliberately does not bind the keys used here.
#
# NOTE on the version floor: voxtype < 1.0.1 leaked a stale evdev fd onto the
# transient uinput keyboard that dotool creates for text output, which spun a
# thread at 100% CPU and killed the hotkey listener after the first
# transcription (upstream issue #445 — reported with keyd + dotool + evdev
# listener, i.e. exactly this shape; fixed by the poll()/POLLHUP guard in
# is_injection_keyboard/fd_is_hung_up). Do not let this package drift below
# 1.0.1.
#
# Voxtype upstream ships an official home-manager module (in its own repo, not
# in nixpkgs); this module deliberately does not use it — the repo keeps
# session services in system-level modules (cf. hosts/historian/kdeconnect-sms.nix).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb.voxtype;

  # Whisper ggml models. Hash verified against the HuggingFace artifact (a
  # `nix build` of the fetchurl succeeds), so this substitutes cleanly instead
  # of downloading at runtime. Extend this attrset if another model is wanted.
  models = {
    "base.en" = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";
      hash = "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=";
    };
    "small.en" = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin";
      hash = "sha256-xhONbVjsyDIgl+D5h8MvG+i7ChhTKj+I9zTRu/nEHl0=";
    };
  };

  modelFile = pkgs.fetchurl {
    inherit (models.${cfg.model}) url hash;
  };

  tomlFormat = pkgs.formats.toml {};

  configFile = tomlFormat.generate "voxtype-config.toml" ({
      state_file = "auto";
      hotkey = {
        enabled = true;
        key = cfg.key;
        modifiers = cfg.modifiers;
        mode = "push_to_talk";
      };
      whisper = {
        # Absolute store path: voxtype resolves a bare name against
        # ~/.local/share/voxtype/models, which we do not want to depend on.
        model = toString modelFile;
        language = "en";
        translate = false;
        on_demand_loading = false;
        eager_processing = cfg.eagerProcessing;
        flash_attention = cfg.flashAttention;
      };
      output =
        {
          mode = cfg.outputMode;
          fallback_to_clipboard = true;
        }
        // lib.optionalAttrs (cfg.driverOrder != []) {
          driver_order = cfg.driverOrder;
        };
    }
    // cfg.settings);
in {
  options.kimb.voxtype = {
    enable = lib.mkEnableOption "Voxtype push-to-talk speech-to-text";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.voxtype;
      defaultText = lib.literalExpression "pkgs.voxtype";
      description = ''
        Voxtype build. Use `pkgs.voxtype-vulkan` on hosts with a usable GPU —
        `flashAttention` is a whisper.cpp GPU optimization and is inert without
        it.
      '';
      example = lib.literalExpression "pkgs.voxtype-vulkan";
    };

    key = lib.mkOption {
      type = lib.types.str;
      default = "SCROLLLOCK";
      description = ''
        Key to hold for push-to-talk. voxtype does NOT resolve kernel key names
        generally: it accepts a fixed whitelist of named keys (SCROLLLOCK,
        PAUSE, CAPSLOCK, NUMLOCK, INSERT, the modifiers, F1-F24, navigation,
        media keys, SPACE, ENTER, TAB, BACKSPACE, ESC, GRAVE) plus a numeric
        escape hatch for anything else.

        Anything outside that whitelist must be given as a kernel keycode with
        the `EVTEST_` prefix — e.g. the JIS かな key, KEY_KATAKANAHIRAGANA (93),
        is `EVTEST_93`. (`WEV_`/`X11_`/`XEV_` prefixes are also accepted but are
        XKB keycodes, offset by 8 from the kernel value, so a WEV_ code would
        be one less than its EVTEST_ value for code 93.) Discover a code with
        `evtest` or `keyd monitor`.

        An unrecognised value makes the daemon fail to start with
        "Unknown key", so prefer checking with `evtest` first.

        The key must not be bound by keyd or the compositor, or voxtype's
        evdev listener will never see it.
      '';
      example = "EVTEST_93";
    };

    modifiers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Modifier keys that must be held alongside `key`. Not alternative
        triggers — voxtype supports one `key` plus held modifiers only.
      '';
      example = ["LEFTCTRL" "LEFTALT"];
    };

    model = lib.mkOption {
      type = lib.types.enum (builtins.attrNames models);
      default = "base.en";
      description = "Whisper model to fetch and use. `.en` models are English-only and faster.";
    };

    eagerProcessing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Transcribe audio in chunks while recording continues, cutting
        perceived latency on slower machines. Experimental upstream — chunk
        boundaries can occasionally duplicate or drop a word.
      '';
    };

    flashAttention = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whisper.cpp flash attention: lower GPU memory, faster inference. Only
        meaningful with a GPU-backed build (`pkgs.voxtype-vulkan`) — the CPU
        build accepts the setting and does nothing with it.
      '';
    };

    outputMode = lib.mkOption {
      type = lib.types.enum ["type" "clipboard" "paste" "file"];
      default = "type";
      description = ''
        How a finished transcript is delivered: `type` simulates keystrokes at
        the caret, `clipboard` copies it, `paste` copies then sends the paste
        chord, `file` writes it to `output.file_path`.

        `type` needs an injector usable in the session plus `/dev/uinput`
        access — this module enables `hardware.uinput` and adds kimb to the
        `input`/`uinput` groups for that. On X11 the workable drivers are
        dotool and ydotool; wtype/eitype are Wayland-only.
      '';
    };

    driverOrder = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["wtype" "eitype" "dotool" "ydotool" "clipboard" "xclip"]);
      default = [];
      description = ''
        Restrict/order the output injector fallback chain. Empty leaves
        voxtype's default order. Setting this makes the list exhaustive —
        voxtype stops consulting `fallback_to_clipboard` when it is present.
      '';
      example = ["dotool" "clipboard"];
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {};
      description = ''
        Extra voxtype config, deep-merged over the generated defaults. Escape
        hatch for options this module does not surface — see
        <https://voxtype.io> for the full schema.
      '';
      example = lib.literalExpression ''
        {
          audio.device = "plughw:2,0";
          text.spoken_punctuation = true;
        }
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the daemon with the graphical session (`startTarget`). Hosts that
        never activate `graphical-session.target` (bare `startx`, e.g. creme)
        must set `startTarget = "default.target"` and `linger = true` instead.
      '';
    };

    startTarget = lib.mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      description = ''
        systemd target that pulls in the user service and that the unit is
        `PartOf`. Use `default.target` for hosts without a
        `graphical-session.target` (pair with `linger = true`).
      '';
    };

    linger = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep kimb's user manager running at boot with no login session, so the
        service can start under `default.target`. Required on hosts that never
        activate `graphical-session.target`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.users.users ? kimb && config.users.users.kimb.home != null;
        message = "kimb.voxtype requires users.users.kimb to be configured with a home directory.";
      }
    ];

    # Rendered config, installed system-wide and pinned explicitly with
    # `voxtype -c ...` on the unit. Using -c rather than letting the daemon
    # discover /etc/voxtype/config.toml keeps system truth authoritative: the
    # lookup chain is user config -> system config, so a stray
    # ~/.config/voxtype/config.toml would otherwise silently shadow this file.
    #
    # The model path inside that file is a plain /nix/store path, which is
    # GC-able. environment.etc alone does NOT keep it alive — /etc is built by
    # the activation script at switch time and is not a GC root — so the model
    # could be collected and the daemon would then fail on a missing model.
    # Referencing it from a systemPackage makes the profile hold the reference,
    # which pins the whole chain (voxtype -> model) as a GC root.
    environment.etc."voxtype/config.toml".source = configFile;

    # Installs the CLI as well as the daemon: `voxtype status`,
    # `voxtype record start/stop` (for external triggers such as an extra mouse
    # button) and `voxtype info devices` are all needed interactively. Also the
    # GC root for the model path referenced by the generated config.
    environment.systemPackages = [cfg.package];

    # /dev/uinput access for the text injectors (dotool creates a transient
    # virtual keyboard; ydotool writes to /dev/uinput). Without this the
    # daemon runs but no text ever reaches the cursor.
    hardware.uinput.enable = true;

    # The evdev hotkey listener reads /dev/input/* directly.
    users.users.kimb.extraGroups = ["input" "uinput"];
    users.users.kimb.linger = lib.mkIf cfg.linger true;

    systemd.user.services.voxtype = {
      description = "Voxtype push-to-talk voice-to-text daemon";
      documentation = ["https://voxtype.io"];
      partOf = [cfg.startTarget];
      after =
        lib.optionals (cfg.startTarget == "graphical-session.target") [
          "graphical-session.target"
          "pipewire.service"
          "pipewire-pulse.service"
        ]
        ++ lib.optionals (cfg.startTarget == "default.target") [
          # No graphical target to order against; just wait for audio.
          "pipewire.service"
          "pipewire-pulse.service"
        ];
      wantedBy = lib.optionals cfg.autoStart [cfg.startTarget];
      serviceConfig = {
        Type = "simple";
        # Clear a stale pidlock before starting. voxtype refuses to start if
        # $XDG_RUNTIME_DIR/voxtype/voxtype.lock names a live pid, and it does not
        # clean that file up after an unclean exit (SIGKILL, OOM, crash) — which
        # leaves the unit crash-looping forever on "another voxtype instance is
        # already running". The check is deliberately guarded on the pid being
        # dead: a genuinely running instance still blocks startup, so this can
        # only ever remove a stale lock.
        ExecStartPre = pkgs.writeShellScript "voxtype-clear-stale-lock" ''
          set -eu
          lock="''${XDG_RUNTIME_DIR:-/tmp}/voxtype/voxtype.lock"
          [ -e "$lock" ] || exit 0
          pid=$(cat "$lock" 2>/dev/null || true)
          # A *live* pid means a genuine instance: leave it alone. Anything else
          # — empty, garbage, or a dead pid — is a stale lock and gets removed.
          # (kill -0 on a non-numeric pid just fails, so garbage is treated as
          # stale, which is what we want.)
          if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "voxtype: live instance (pid $pid) holds $lock; leaving it alone" >&2
            exit 0
          fi
          echo "voxtype: removing stale lock $lock (pid ''${pid:-unknown} not live)" >&2
          rm -f "$lock"
        '';
        # Pin the config so the system file wins over any user config.
        ExecStart = "${cfg.package}/bin/voxtype -c /etc/voxtype/config.toml daemon";
        Restart = "on-failure";
        RestartSec = 5;
        # The runtime dir is where voxtype keeps its pidlock (voxtype.lock) and
        # state file, which `voxtype record start/stop/toggle` read.
        Environment = ["XDG_RUNTIME_DIR=%t"];
      };
    };
  };
}
