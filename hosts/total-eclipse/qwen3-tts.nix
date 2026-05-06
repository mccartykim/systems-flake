# Qwen3-TTS server - zero-shot voice cloning via OpenAI-compatible API.
#
# Server executable comes from the qwen3-tts-cuda flake input (uv2nix-built
# venv with CUDA autopatchelf). This module provides only the host-side
# wiring: voice references, user, socket-activated systemd unit.
#
# Model: configurable via QWEN3_TTS_MODEL env (0.6B or 1.7B Base)
# Endpoint: POST http://total-eclipse.nebula:8091/v1/audio/speech
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  serverExecutable = inputs.qwen3-tts-cuda.packages.${pkgs.system}.default;
  voiceRefDir = "/home/kimb/shared_projects/claude_yapper/assets/voice-references";
in {
  # Copy voice reference files to /var/lib/voice-references/ for the TTS server
  system.activationScripts.voice-references = lib.stringAfter ["users"] ''
    mkdir -p /var/lib/voice-references
    for voice in soup-short jet2 caine; do
      for ext in wav txt; do
        src="${voiceRefDir}/$voice.$ext"
        # soup-short.wav -> soup.wav (legacy naming)
        dest="/var/lib/voice-references/''${voice%-short}.$ext"
        if [ -f "$src" ]; then
          cp "$src" "$dest"
          chmod 644 "$dest"
        fi
      done
    done
  '';

  users.users.qwen3-tts = {
    isSystemUser = true;
    group = "qwen3-tts";
    home = "/var/lib/qwen3-tts";
  };
  users.groups.qwen3-tts = {};

  # Socket activation: systemd keeps port 8091 listening persistently. First
  # incoming connection spawns qwen3-tts.service, which handles requests then
  # exits after QWEN3_TTS_IDLE_TIMEOUT seconds of idle (see server code).
  # Process exit fully frees the ~4.5GB CUDA context so ollama can use the GPU.
  systemd.sockets.qwen3-tts = {
    description = "Qwen3 TTS socket (activation)";
    wantedBy = ["sockets.target"];
    socketConfig = {
      ListenStream = "0.0.0.0:8091";
      Accept = false;
    };
  };

  systemd.services.qwen3-tts = {
    description = "Qwen3 TTS OpenAI-compatible Server";
    after = ["network.target" "qwen3-tts.socket"];
    requires = ["qwen3-tts.socket"];

    path = [pkgs.sox];

    environment = {
      HF_HOME = "/var/lib/qwen3-tts/huggingface";
      QWEN3_TTS_MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-Base";
      PYTHONUNBUFFERED = "1";
      VOICES_DIR = "/var/lib/voice-references";
      HOME = "/var/lib/qwen3-tts";
      QWEN3_TTS_IDLE_TIMEOUT = "45";
      # libcuda.so.1 from NVIDIA driver, libsndfile for soundfile, libcudnn_graph for cuDNN
      LD_LIBRARY_PATH =
        lib.makeLibraryPath [
          (lib.getLib pkgs.libsndfile)
          (lib.getLib pkgs.cudaPackages.cudnn)
        ]
        + ":/run/opengl-driver/lib";
    };

    serviceConfig = {
      Type = "simple";
      User = "qwen3-tts";
      Group = "qwen3-tts";
      ExecStart = "${serverExecutable}";
      # Clean idle exit is exit 0; socket activation handles respawn.
      Restart = "no";
      # First start downloads ~4.5GB model from HuggingFace; warm cold-starts
      # take 8-20s for model load + CUDA graph capture.
      TimeoutStartSec = "10min";
      WorkingDirectory = "/var/lib/qwen3-tts";
      StateDirectory = "qwen3-tts";

      # Hardening
      NoNewPrivileges = true;
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
