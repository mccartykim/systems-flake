# Paperless-ngx document management system
# Processes scanned documents from maitred (Fujitsu fi-6130Z)
# Auto-OCR, rotation correction, blank page handling, full-text search
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.paperless = {
    enable = true;
    port = 28981;
    address = "0.0.0.0"; # Accessible over Nebula
    consumptionDirIsPublic = true; # maitred rsyncs as kimb
    settings = {
      # OCR settings
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_OCR_ROTATE_PAGES = "true";
      PAPERLESS_OCR_ROTATE_PAGES_THRESHOLD = "2"; # Aggressive rotation (catches upside-down)
      PAPERLESS_OCR_DESKEW = "true";
      PAPERLESS_OCR_CLEAN = "clean-final"; # unpaper cleanup in final output
      PAPERLESS_OCR_MODE = "skip"; # Skip pages that already have text layer
      PAPERLESS_OCR_SKIP_ARCHIVE_FILE = "with_text";
      PAPERLESS_OCR_OUTPUT_TYPE = "pdfa";

      # Consumer settings
      PAPERLESS_CONSUMER_RECURSIVE = "true";
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = "true";

      # Filename handling
      PAPERLESS_FILENAME_FORMAT = "{{ created_year }}/{{ created_month }}/{{ title }}";

      # Performance - use available CPU threads
      PAPERLESS_TASK_WORKERS = "4";
      PAPERLESS_THREADS_PER_WORKER = "2";

      # Web UI accessible over Nebula
      PAPERLESS_URL = "http://total-eclipse.nebula:28981";
      PAPERLESS_ALLOWED_HOSTS = "total-eclipse.nebula,localhost,127.0.0.1";
      PAPERLESS_CORS_ALLOWED_HOSTS = "http://total-eclipse.nebula:28981";
    };
  };

  # Create consumption directory for maitred scanner rsync
  systemd.tmpfiles.rules = [
    "d /var/lib/paperless/consume 0775 paperless paperless -"
  ];

  # Allow kimb to write to consumption dir (for rsync from maitred)
  users.users.kimb.extraGroups = ["paperless"];

  # Open paperless port on nebula for web UI access
  kimb.nebula.extraInboundRules = [
    {
      port = 28981;
      proto = "tcp";
      groups = ["desktops" "laptops"];
    }
  ];

  # Allow maitred to rsync scans as kimb
  users.users.kimb.openssh.authorizedKeys.keys = let
    sshKeys = import ../ssh-keys.nix;
    registry = import ../nebula-registry.nix;
  in
    sshKeys.authorizedKeys
    ++ [registry.nodes.maitred.publicKey];
}
