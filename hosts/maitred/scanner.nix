# Scanner configuration for maitred
# Fujitsu fi-6130Z with ADF duplex scanning + scan button automation
{
  config,
  lib,
  pkgs,
  ...
}: let
  scanDir = "/var/lib/scans";

  # Duplex scan script: ADF duplex → timestamped PDF
  scanScript = pkgs.writeShellScript "duplex-scan" ''
    set -euo pipefail

    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    TMPDIR=$(mktemp -d /tmp/scan-XXXXXX)
    OUTFILE="${scanDir}/scan-''${TIMESTAMP}.pdf"

    echo "Starting duplex scan at ''${TIMESTAMP}..."

    # Duplex ADF scan: 300dpi color, hardware deskew+crop, skip blank pages
    ${pkgs.sane-backends}/bin/scanimage \
      --device-name='fujitsu:fi-6130Zdj:605052' \
      --source "ADF Duplex" \
      --mode Color \
      --resolution 300 \
      --hwdeskewcrop=yes \
      --swskip 5 \
      --buffermode On \
      --format=pnm \
      --batch="''${TMPDIR}/page-%04d.pnm" \
      --batch-print \
      2>&1 || true

    # Check if any pages were scanned
    PAGE_COUNT=$(find "''${TMPDIR}" -name '*.pnm' | wc -l)
    if [ "$PAGE_COUNT" -eq 0 ]; then
      echo "No pages scanned (ADF empty?)"
      rm -rf "''${TMPDIR}"
      exit 0
    fi

    echo "Scanned ''${PAGE_COUNT} pages, converting to PDF..."

    # Convert all pages to a single PDF
    ${pkgs.imagemagick}/bin/convert \
      $(ls -1 "''${TMPDIR}"/page-*.pnm | sort) \
      -quality 85 \
      "''${OUTFILE}"

    rm -rf "''${TMPDIR}"

    echo "Saved: ''${OUTFILE} (''${PAGE_COUNT} pages)"
  '';

  # Button watcher: polls scan button, triggers scan script
  buttonWatcher = pkgs.writeShellScript "scan-button-watcher" ''
    set -euo pipefail

    DEVICE='fujitsu:fi-6130Zdj:605052'
    SCANNING=0

    echo "Watching scan button on ''${DEVICE}..."

    while true; do
      # Poll the scan button sensor
      BUTTON=$(${pkgs.sane-backends}/bin/scanimage \
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
      # Run as root for USB device access (SANE needs it)
      User = "root";
      Group = "scanner";
    };
  };

  # Share scans directory via Samba (read-only, same ACL as printers)
  services.samba.settings.scans = {
    "comment" = "Scanned Documents";
    "path" = scanDir;
    "public" = "yes";
    "browseable" = "yes";
    "guest ok" = "yes";
    "writable" = "no";
    "create mode" = "0644";
  };
}
