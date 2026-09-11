# Paperless-ngx document management — the a3j.9.2 move from total-eclipse.
#
# Processes scanned documents pushed by maitred (Fujitsu fi-6130Z): auto-OCR,
# rotation correction, blank-page handling, full-text search.
#
# State lives at /var/lib/paperless (sqlite DB + media/ + index/ + the
# generated secret key) and was rsync'd verbatim at the cutover. Paperless
# stores RELATIVE paths under MEDIA_ROOT, so there is no path translation —
# the mountpoint is /var/lib/paperless on both hosts.
#
# Over-Nebula access: the web UI is covered by openToPersonalDevices (same as
# on total-eclipse), so no extra inbound rule is needed. maitred's scan rsync
# uses SSH (:22, open to any over Nebula) as kimb with ITS HOST KEY — hence the
# authorized_keys entry below.
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
      # nix-topology extractor expects this; set to the URL for topology diagram info
      domain = "historian.nebula";

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
      PAPERLESS_URL = "http://historian.nebula:28981";
      PAPERLESS_ALLOWED_HOSTS = "historian.nebula,localhost,127.0.0.1";
      PAPERLESS_CORS_ALLOWED_HOSTS = "http://historian.nebula:28981";
    };
  };

  # Create consumption directory for maitred's scanner rsync
  systemd.tmpfiles.rules = [
    "d /var/lib/paperless/consume 0775 paperless paperless -"
  ];

  # Allow kimb to write to the consumption dir (for the rsync from maitred)
  users.users.kimb.extraGroups = ["paperless"];

  # Allow maitred to rsync scans as kimb (it authenticates with its host key).
  # Additive: base.nix already provides kimb's own keys.
  users.users.kimb.openssh.authorizedKeys.keys = let
    registry = import ../nebula-registry.nix;
  in [
    registry.nodes.maitred.publicKey
  ];
}
