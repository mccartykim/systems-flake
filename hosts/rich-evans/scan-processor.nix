# Scan processor for rich-evans
# Watches for incoming TIFFs from maitred, runs OCR, produces timestamped PDFs
{
  config,
  lib,
  pkgs,
  ...
}: let
  incomingDir = "/var/lib/scans/incoming";
  outputDir = "/var/lib/scans/documents";

  # Process a batch of TIFFs into a single OCR'd PDF
  processScript = pkgs.writeShellScript "process-scans" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.img2pdf
      pkgs.ocrmypdf
    ]}:$PATH"

    INCOMING="${incomingDir}"
    OUTPUT="${outputDir}"

    mkdir -p "$OUTPUT"

    # Process each batch (identified by .batch marker files)
    for batchfile in "$INCOMING"/*.batch; do
      [ -f "$batchfile" ] || continue

      TIMESTAMP=$(basename "$batchfile" .batch)
      TMPDIR=$(mktemp -d /tmp/scan-process-XXXXXX)
      trap 'rm -rf "$TMPDIR"' EXIT

      echo "Processing batch ''${TIMESTAMP}..."

      # Collect TIFF pages for this batch
      PAGES=$(ls -1 "$INCOMING/''${TIMESTAMP}"_page-*.tiff 2>/dev/null | sort)
      PAGE_COUNT=$(echo "$PAGES" | grep -c . || true)

      if [ "$PAGE_COUNT" -eq 0 ]; then
        echo "No pages found for batch ''${TIMESTAMP}, removing marker"
        rm -f "$batchfile"
        continue
      fi

      # Convert TIFFs to intermediate PDF
      img2pdf $PAGES -o "$TMPDIR/raw.pdf"

      # OCR + optimize
      ocrmypdf \
        --rotate-pages \
        --deskew \
        --clean \
        --optimize 2 \
        --output-type pdf \
        "$TMPDIR/raw.pdf" \
        "$TMPDIR/ocr.pdf"

      # Generate 4-char hash from PDF content
      HASH=$(sha256sum "$TMPDIR/ocr.pdf" | head -c 4)
      OUTFILE="$OUTPUT/scan-''${TIMESTAMP}-''${HASH}.pdf"

      mv "$TMPDIR/ocr.pdf" "$OUTFILE"
      chmod 644 "$OUTFILE"

      # Clean up incoming files for this batch
      rm -f $PAGES "$batchfile"

      echo "Saved: ''${OUTFILE} (''${PAGE_COUNT} pages, id: ''${HASH})"

      trap - EXIT
      rm -rf "$TMPDIR"
    done
  '';
in {
  # Create directories (kimb-owned so maitred can rsync as kimb)
  systemd.tmpfiles.rules = [
    "d /var/lib/scans 0775 kimb kimb -"
    "d ${incomingDir} 0775 kimb kimb -"
    "d ${outputDir} 0775 kimb kimb -"
  ];

  # Path watcher: trigger processing when new .batch files arrive
  systemd.paths.scan-processor = {
    description = "Watch for new scan batches";
    wantedBy = ["multi-user.target"];
    pathConfig = {
      DirectoryNotEmpty = incomingDir;
      MakeDirectory = true;
    };
  };

  # Processing service (triggered by path watcher)
  systemd.services.scan-processor = {
    description = "Process scanned documents (OCR + PDF)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = processScript;
      # Nice it down so it doesn't compete with other services
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
}
