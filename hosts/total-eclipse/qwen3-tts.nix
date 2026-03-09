# Qwen3-TTS server - zero-shot voice cloning via OpenAI-compatible API
#
# Uses the qwen-tts pip package (installed via uv) with a FastAPI wrapper.
# Model: Qwen/Qwen3-TTS-12Hz-1.7B-Base (~4.5GB download, 6-8GB VRAM)
# Endpoint: POST http://total-eclipse.nebula:8091/v1/audio/speech
{
  config,
  lib,
  pkgs,
  ...
}: let
  serverScript = ./qwen3-tts-server.py;

  setupScript = pkgs.writeShellScript "qwen3-tts-setup" ''
    set -e
    cd /var/lib/qwen3-tts
    if [ ! -d .venv ]; then
      echo "Creating virtualenv..."
      ${pkgs.uv}/bin/uv venv --python ${pkgs.python312}/bin/python3
      echo "Installing dependencies (this may take a few minutes)..."
      ${pkgs.uv}/bin/uv pip install qwen-tts fastapi "uvicorn[standard]" soundfile
      echo "Dependencies installed."
    fi
  '';

  startScript = pkgs.writeShellScript "qwen3-tts-start" ''
    cd /var/lib/qwen3-tts
    exec .venv/bin/python ${serverScript} --host 0.0.0.0 --port 8091
  '';
in {
  users.users.qwen3-tts = {
    isSystemUser = true;
    group = "qwen3-tts";
    home = "/var/lib/qwen3-tts";
  };
  users.groups.qwen3-tts = {};

  systemd.services.qwen3-tts = {
    description = "Qwen3 TTS OpenAI-compatible Server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    environment = {
      # libstdc++ for PyTorch, libcuda.so from NVIDIA driver
      LD_LIBRARY_PATH = "${lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
      ]}:/run/opengl-driver/lib";
      HF_HOME = "/var/lib/qwen3-tts/huggingface";
      PYTHONUNBUFFERED = "1";
      VOICES_DIR = "/var/lib/voice-references";
      HOME = "/var/lib/qwen3-tts";
    };

    serviceConfig = {
      Type = "simple";
      User = "qwen3-tts";
      Group = "qwen3-tts";
      ExecStartPre = setupScript;
      ExecStart = startScript;
      Restart = "on-failure";
      RestartSec = 30;
      # First start downloads ~4.5GB model from HuggingFace
      TimeoutStartSec = "10min";
      WorkingDirectory = "/var/lib/qwen3-tts";
      StateDirectory = "qwen3-tts";

      # Hardening
      NoNewPrivileges = true;
      ProtectHome = true;
      PrivateTmp = true;
    };

    path = [pkgs.uv pkgs.git];
  };
}
