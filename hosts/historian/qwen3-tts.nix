# Qwen3-TTS voice-cloning server — the a3j.9.1 move from total-eclipse.
#
# CPU/GGML build: the `qwen3-tts-cuda` flake input is now CPU-only (torch from
# the PyTorch CPU index + qwentts-cpp-python's ggml backend), so this runs on
# historian's Zen5 cores with no GPU and no CUDA. Socket-activated like the
# total-eclipse original: the socket stays up and the first connection spawns
# the service, which exits after QWEN3_TTS_IDLE_TIMEOUT seconds of idle to
# free the loaded model's RAM.
#
# Endpoint: POST http://historian.nebula:8091/v1/audio/speech
# Consumers (4 organisms on rich-evans): vox TTS_SERVER, lifecoach-organism +
# chirurgeon-organism ttsServer, vacuum-organism qwenTtsServer.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  serverExecutable = inputs.qwen3-tts-cuda.packages.${pkgs.system}.default;
in {
  # Voice references are migrated STATE (rsync'd from total-eclipse at the
  # a3j.9.1 cutover — 11 voices). The dir is created here so a fresh host /
  # first boot has it.
  systemd.tmpfiles.rules = [
    "d /var/lib/voice-references 0755 qwen3-tts qwen3-tts -"
  ];

  users.users.qwen3-tts = {
    isSystemUser = true;
    group = "qwen3-tts";
    home = "/var/lib/qwen3-tts";
  };
  users.groups.qwen3-tts = {};

  systemd.sockets.qwen3-tts = {
    description = "Qwen3 TTS socket (activation)";
    wantedBy = ["sockets.target"];
    socketConfig = {
      ListenStream = "0.0.0.0:8091";
      Accept = false;
    };
  };

  systemd.services.qwen3-tts = {
    description = "Qwen3 TTS OpenAI-compatible Server (CPU/GGML)";
    after = ["network.target" "qwen3-tts.socket"];
    requires = ["qwen3-tts.socket"];

    path = [pkgs.sox];

    environment = {
      HF_HOME = "/var/lib/qwen3-tts/huggingface";
      QWEN3_TTS_MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-Base";
      QWEN3_TTS_BACKEND = "ggml";
      QWEN3_TTS_QUANT = "BF16";
      PYTHONUNBUFFERED = "1";
      VOICES_DIR = "/var/lib/voice-references";
      HOME = "/var/lib/qwen3-tts";
      QWEN3_TTS_IDLE_TIMEOUT = "45";
      # soundfile loads libsndfile via ctypes at runtime, so it must be on the
      # loader path. No CUDA libs: the ggml backend is pure CPU.
      LD_LIBRARY_PATH = lib.makeLibraryPath [(lib.getLib pkgs.libsndfile)];
    };

    serviceConfig = {
      Type = "simple";
      User = "qwen3-tts";
      Group = "qwen3-tts";
      ExecStart = "${serverExecutable}";
      # Clean idle exit is exit 0; socket activation handles respawn.
      Restart = "no";
      # First start downloads the model from HuggingFace (~3-4GB for 1.7B).
      TimeoutStartSec = "20min";
      WorkingDirectory = "/var/lib/qwen3-tts";
      StateDirectory = "qwen3-tts";

      NoNewPrivileges = true;
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # Nebula: the 4 consumer organisms live on rich-evans (a *server*, not a
  # personal device), so opening 8091 from it needs an explicit inbound rule.
  kimb.nebula.extraInboundRules = [
    {
      port = 8091;
      proto = "tcp";
      group = "servers";
    }
  ];
}
