# Scanner configuration for maitred
# Fujitsu fi-6130Z with ADF duplex scanning + scan button automation
# Scans stage locally as TIFF, rsync to rich-evans for OCR + permanent storage
{
  config,
  lib,
  pkgs,
  ...
}: let
  scanDir = "/var/lib/scans";
  remoteScanDir = "/var/lib/scans/incoming";
  remoteHost = "rich-evans.nebula";

  # Duplex scan script: ADF duplex → timestamped multi-page TIFF
  scanScript = pkgs.writeShellScript "duplex-scan" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [
      pkgs.coreutils
      pkgs.findutils
      pkgs.sane-backends
    ]}:$PATH"

    TIMESTAMP=$(date +%Y%m%dT%H%M%S)
    TMPDIR=$(mktemp -d /tmp/scan-XXXXXX)
    trap 'rm -rf "$TMPDIR"' EXIT

    echo "Starting duplex scan at ''${TIMESTAMP}..."

    # Duplex ADF scan: 300dpi color, hardware deskew+crop, skip blank pages
    scanimage \
      --device-name='fujitsu:fi-6130Zdj:605052' \
      --source "ADF Duplex" \
      --mode Color \
      --resolution 300 \
      --hwdeskewcrop=yes \
      --swskip 5 \
      --buffermode On \
      --format=tiff \
      --batch="''${TMPDIR}/page-%04d.tiff" \
      --batch-print \
      2>&1 || true

    # Check if any pages were scanned
    PAGE_COUNT=$(find "''${TMPDIR}" -name '*.tiff' | wc -l)
    if [ "$PAGE_COUNT" -eq 0 ]; then
      echo "No pages scanned (ADF empty?)"
      exit 0
    fi

    echo "Scanned ''${PAGE_COUNT} pages, staging for sync..."

    # Move TIFF files to scan dir with timestamp prefix
    for f in "''${TMPDIR}"/page-*.tiff; do
      BASE=$(basename "$f")
      mv "$f" "${scanDir}/''${TIMESTAMP}_''${BASE}"
    done

    # Write a marker file so rich-evans knows this batch is complete
    echo "''${PAGE_COUNT}" > "${scanDir}/''${TIMESTAMP}.batch"

    echo "Staged ''${PAGE_COUNT} pages for sync (batch ''${TIMESTAMP})"
  '';

  # Button watcher: polls scan button, triggers scan script
  buttonWatcher = pkgs.writeShellScript "scan-button-watcher" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [pkgs.coreutils pkgs.sane-backends pkgs.gnugrep]}:$PATH"

    DEVICE='fujitsu:fi-6130Zdj:605052'
    SCANNING=0

    echo "Watching scan button on ''${DEVICE}..."

    while true; do
      # Poll the scan button sensor via scanimage option query
      BUTTON=$(scanimage \
        --device-name="''${DEVICE}" \
        --dont-scan \
        --all-options 2>/dev/null \
        | grep -A0 '^\s*--scan' \
        | grep -oP '\[(yes|no)\]' \
        | tr -d '[]' || echo "no")

      if [ "$BUTTON" = "yes" ] && [ "$SCANNING" -eq 0 ]; then
        SCANNING=1
        echo "Scan button pressed! Starting scan..."
        ${scanScript} || echo "Scan failed"
        SCANNING=0
        # Wait a bit after scan completes before polling again
        sleep 3
      fi

      sleep 1
    done
  '';

  # Rsync script: push scans to rich-evans, remove synced files
  syncScript = pkgs.writeShellScript "sync-scans" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [pkgs.coreutils pkgs.rsync pkgs.openssh]}:$PATH"

    # Only run if there are files to sync
    if ! ls ${scanDir}/*.batch &>/dev/null; then
      exit 0
    fi

    echo "Syncing scans to ${remoteHost}:${remoteScanDir}..."

    # Ensure remote directory exists
    ssh ${remoteHost} "mkdir -p ${remoteScanDir}"

    # Rsync with --remove-source-files to clean up after successful transfer
    rsync -av \
      --remove-source-files \
      ${scanDir}/ \
      ${remoteHost}:${remoteScanDir}/

    echo "Sync complete."
  '';
in {
  # Enable SANE scanner support
  hardware.sane = {
    enable = true;
    extraBackends = []; # fujitsu backend is built into sane-backends
  };

  # Add scanner group to user
  users.users.kimb.extraGroups = ["scanner" "lp"];

  # Create scan output directory
  systemd.tmpfiles.rules = [
    "d ${scanDir} 0775 root scanner -"
  ];

  # Scan button watcher service
  systemd.services.scan-button-watcher = {
    description = "Fujitsu fi-6130Z scan button watcher";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = buttonWatcher;
      Restart = "always";
      RestartSec = "5";
      User = "root";
      Group = "scanner";
    };
  };

  # Rsync scans to rich-evans every 2 minutes
  systemd.services.sync-scans = {
    description = "Sync scanned documents to rich-evans";
    after = ["network.target" "nebula@mesh.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = syncScript;
      User = "root";
    };
  };

  systemd.timers.sync-scans = {
    description = "Sync scans to rich-evans every 2 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/2";
      Persistent = true;
    };
  };

  # Share scans directory via Samba (read-only, same ACL as printers)
  services.samba.settings.scans = {
    "comment" = "Scanned Documents (staging)";
    "path" = scanDir;
    "public" = "yes";
    "browseable" = "yes";
    "guest ok" = "yes";
    "writable" = "no";
    "create mode" = "0644";
  };
}
