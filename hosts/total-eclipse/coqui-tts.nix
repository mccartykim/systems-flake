{ config, lib, pkgs, ... }:
let
  # Python script for XTTS generation with inline uv dependencies
  xttsScript = pkgs.writeTextFile {
    name = "xtts-generate.py";
    text = ''
      # /// script
      # requires-python = ">=3.10"
      # dependencies = [
      #   "coqui-tts>=0.26",
      #   "transformers>=4.35,<4.45",
      # ]
      # ///
      import sys
      import os
      from TTS.api import TTS

      if len(sys.argv) < 4:
          print("Usage: xtts-generate.py <text> <speaker_wav> <output_path>", file=sys.stderr)
          sys.exit(1)

      text = sys.argv[1]
      speaker_wav = sys.argv[2]
      output_path = sys.argv[3]

      try:
          # Initialize TTS with XTTS model
          tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=True)

          # Generate audio with voice cloning
          tts.tts_to_file(text=text, speaker_wav=speaker_wav, language="en", file_path=output_path)

          print(f"Audio generated: {output_path}", file=sys.stderr)
          sys.exit(0)
      except Exception as e:
          print(f"XTTS generation failed: {e}", file=sys.stderr)
          sys.exit(1)
    '';
  };

  # Executable wrapper that uses nix-shell + uv
  xttsExecutable = pkgs.writeShellScriptBin "xtts-generate" ''
    export TTS_HOME="''${TTS_HOME:-.cache/TTS}"

    # Create a temp script to avoid argument quoting issues with nix-shell
    TEMP_SCRIPT="$(mktemp --suffix=.py)"
    cat > "$TEMP_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "coqui-tts>=0.26",
#   "torchcodec",
# ]
# ///
import sys
import os
from TTS.api import TTS

if len(sys.argv) < 4:
    print("Usage: xtts-generate.py <text> <speaker_wav> <output_path>", file=sys.stderr)
    sys.exit(1)

text = sys.argv[1]
speaker_wav = sys.argv[2]
output_path = sys.argv[3]

try:
    import torch
    use_gpu = torch.cuda.is_available()
    print(f"Using GPU: {use_gpu}", file=sys.stderr)
    tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=use_gpu)
    tts.tts_to_file(text=text, speaker_wav=speaker_wav, language="en", file_path=output_path)
    print(f"Audio generated: {output_path}", file=sys.stderr)
    sys.exit(0)
except Exception as e:
    print(f"XTTS generation failed: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
SCRIPT_EOF
    chmod +x "$TEMP_SCRIPT"

    # Run uv with build tools via nix-shell (pass args inside --run string)
    # Set LD_LIBRARY_PATH for libstdc++.so.6 needed by PyTorch
    # Set COQUI_TOS_AGREED to auto-accept license for non-interactive use
    ARGS=$(printf '%q ' "$@")
    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.ffmpeg-full.lib}/lib:$LD_LIBRARY_PATH"
    export COQUI_TOS_AGREED=1
    # Pre-create TOS agreement file for the XTTS model
    mkdir -p "$HOME/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2"
    touch "$HOME/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2/.agreement.txt"
    NIXPKGS_ALLOW_UNFREE=1 nix-shell --impure -p uv cargo rustc gcc pkg-config cudaPackages.cudatoolkit ffmpeg-full --run "uv run --python 3.13 $TEMP_SCRIPT $ARGS"
    EXIT_CODE=$?

    rm -f "$TEMP_SCRIPT"
    exit $EXIT_CODE
  '';
in
{
  # Add tools to system
  environment.systemPackages = [ pkgs.tts xttsExecutable ];


  # Copy voice reference to /var/lib/voice-references/
  # (assumes soup-short.wav is available at /home/kimb/shared_projects/claude_yapper/assets/voice-references/)
  system.activationScripts.voice-references = lib.stringAfter ["users"] ''
    mkdir -p /var/lib/voice-references

    # Check if source file exists and copy it
    SOURCE_FILE="/home/kimb/shared_projects/claude_yapper/assets/voice-references/soup-short.wav"
    DEST_FILE="/var/lib/voice-references/soup.wav"

    if [ -f "$SOURCE_FILE" ]; then
      cp "$SOURCE_FILE" "$DEST_FILE"
      chmod 644 "$DEST_FILE"
      echo "Copied voice reference to $DEST_FILE"
    else
      echo "Warning: Voice reference not found at $SOURCE_FILE"
      echo "To use voice cloning, ensure soup-short.wav is present at the expected location"
    fi
  '';
}
