# Scanner configuration for maitred
# Fujitsu fi-6130Z with ADF duplex scanning + scan button automation
# Scans stage locally as TIFF, rsync to total-eclipse paperless-ngx for processing
{
  config,
  lib,
  pkgs,
  ...
}: let
  scanDir = "/var/lib/scans";
  remoteScanDir = "/var/lib/paperless/consume";
  remoteHost = "kimb@total-eclipse.nebula";

  commonPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.findutils
    pkgs.sane-backends
    pkgs.gnugrep
    pkgs.usb-reset
  ];

  # Find the fujitsu scanner device name dynamically
  findDevice = ''
    DEVICE=$(scanimage -L 2>/dev/null | grep -oP 'fujitsu:\S+' | head -1)
    if [ -z "$DEVICE" ]; then
      echo "Scanner not found, attempting USB reset..."
      usb-reset 04c5:11f3 2>/dev/null || true
      sleep 3
      DEVICE=$(scanimage -L 2>/dev/null | grep -oP 'fujitsu:\S+' | head -1)
    fi
    if [ -z "$DEVICE" ]; then
      echo "Scanner still not found after reset"
      return 1
    fi
    # Strip trailing quote if scanimage -L wraps in quotes
    DEVICE="''${DEVICE%\'}"
    echo "Using device: $DEVICE"
  '';

  # Duplex scan script: ADF duplex → timestamped multi-page TIFF
  scanScript = pkgs.writeShellScript "duplex-scan" ''
    set -euo pipefail
    export PATH="${commonPath}:$PATH"

    ${findDevice}

    TIMESTAMP=$(date +%Y%m%dT%H%M%S)
    TMPDIR=$(mktemp -d /tmp/scan-XXXXXX)
    trap 'rm -rf "$TMPDIR"' EXIT

    echo "Starting duplex scan at ''${TIMESTAMP}..."

    # Duplex ADF scan: 300dpi color, hardware deskew+crop, skip blank pages
    scanimage \
      --device-name="$DEVICE" \
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

    echo "Staged ''${PAGE_COUNT} pages for sync (batch ''${TIMESTAMP})"
  '';

  # Button watcher: polls scan button, triggers scan script
  buttonWatcher = pkgs.writeShellScript "scan-button-watcher" ''
    set -euo pipefail
    export PATH="${commonPath}:$PATH"

    SCANNING=0
    FAIL_COUNT=0

    echo "Starting scan button watcher..."

    while true; do
      # Discover device each iteration (handles sleep/reset)
      DEVICE=$(scanimage -L 2>/dev/null | grep -oP 'fujitsu:\S+' | head -1)
      DEVICE="''${DEVICE%\'}"

      if [ -z "$DEVICE" ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        if [ "$FAIL_COUNT" -ge 5 ]; then
          echo "Scanner not found after $FAIL_COUNT attempts, trying USB reset..."
          usb-reset 04c5:11f3 2>/dev/null || true
          FAIL_COUNT=0
          sleep 5
        else
          sleep 3
        fi
        continue
      fi
      FAIL_COUNT=0

      # Poll the scan button sensor
      BUTTON=$(scanimage \
        --device-name="$DEVICE" \
        --dont-scan \
        -A 2>/dev/null \
        | grep -P '^\s+--scan' \
        | grep -oP '\[(yes|no)\]' \
        | tr -d '[]' || echo "no")

      if [ "$BUTTON" = "yes" ] && [ "$SCANNING" -eq 0 ]; then
        SCANNING=1
        echo "Scan button pressed! Starting scan..."
        ${scanScript} || echo "Scan failed"
        SCANNING=0
        sleep 3
      fi

      sleep 1
    done
  '';

  # Rsync script: push scans to total-eclipse paperless, remove synced files
  syncScript = pkgs.writeShellScript "sync-scans" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [pkgs.coreutils pkgs.rsync pkgs.openssh pkgs.findutils]}:$PATH"

    # Only run if there are files to sync
    if [ -z "$(find ${scanDir} -name '*.tiff' 2>/dev/null)" ]; then
      exit 0
    fi

    SSH_OPTS="-i /etc/ssh/ssh_host_ed25519_key -o StrictHostKeyChecking=accept-new"

    echo "Syncing scans to ${remoteHost}:${remoteScanDir}..."

    # Ensure remote directory exists
    ssh $SSH_OPTS ${remoteHost} "mkdir -p ${remoteScanDir}"

    # Rsync with --remove-source-files to clean up after successful transfer
    rsync -av \
      -e "ssh $SSH_OPTS" \
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

  # usb-reset for scanner recovery
  environment.systemPackages = [pkgs.usb-reset];

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
