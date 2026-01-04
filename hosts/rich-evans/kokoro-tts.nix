# Kokoro TTS Service
# OpenAI-compatible TTS server using Kokoro model
#
# The service exposes an HTTP API at localhost:3000
# POST /v1/audio/speech with JSON body: {"model": "kokoro", "input": "text", "voice": "bf_emma"}
{
  config,
  lib,
  pkgs,
  kokoro,
  ...
}: let
  # Model files fetched from GitHub releases
  kokoroModel = pkgs.fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx";
    hash = "sha256-fV347PfUsYeAFaMmhgU/0O6+K8N3I0YIdkzA7zY2psU=";
  };
  kokoroVoices = pkgs.fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin";
    hash = "sha256-vKYQuDCOjZnzLm/kGX5+wBZ5Jk7+0MrJFA/pwp8fv30=";
  };

  # Kokoro TTS binary from the flake
  kokoPackage = kokoro.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Wrapper script that sets up model paths
  # Note: --model, --data, --style are global options and must come before the subcommand
  kokoWrapper = pkgs.writeShellScriptBin "koko-server" ''
    export LD_LIBRARY_PATH="${pkgs.onnxruntime}/lib:${pkgs.espeak-ng}/lib:${pkgs.libopus}/lib:${pkgs.sonic}/lib:$LD_LIBRARY_PATH"
    exec ${kokoPackage}/bin/koko \
      --model ${kokoroModel} \
      --data ${kokoroVoices} \
      --style bf_emma \
      openai \
      --port 3000 \
      --ip 127.0.0.1 \
      "$@"
  '';
in {
  # Create kokoro-tts user
  users.users.kokoro-tts = {
    isSystemUser = true;
    group = "kokoro-tts";
    home = "/var/lib/kokoro-tts";
    createHome = true;
  };
  users.groups.kokoro-tts = {};

  # Kokoro TTS systemd service
  systemd.services.kokoro-tts = {
    description = "Kokoro TTS OpenAI-compatible Server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      Type = "simple";
      User = "kokoro-tts";
      Group = "kokoro-tts";
      ExecStart = "${kokoWrapper}/bin/koko-server";
      Restart = "always";
      RestartSec = 5;

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };

    # Runtime dependencies
    path = [pkgs.espeak-ng];
  };

  # Open firewall for localhost only (not needed for localhost but documenting)
  # networking.firewall.allowedTCPPorts = [ 3000 ];
}
