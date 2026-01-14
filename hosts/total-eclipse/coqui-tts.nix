{ config, lib, pkgs, ... }: {
  # Make tts CLI available system-wide
  environment.systemPackages = [ pkgs.tts ];

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
