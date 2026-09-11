# org-crm: Personal CRM agent
#
# Manages contacts, tasks, email digest, and scanned documents.
# Uses Ollama for LLM calls (replaces Claude CLI).
# Dedicated Discord bot app (Secretary) for DMs and slash commands.
#
# MOVED from rich-evans at a3j.6 cutover 9 (2026-09-11). State 16G rode the
# two-pass rsync VERBATIM: /var/lib/org-crm paths are identical on both hosts,
# so the mu xapian index (baked with /var/lib/org-crm/Mail) and the mbsync
# SyncState needed NO translation (state.db audited: zero path columns).
# OLLAMA_HOST (historian.nebula:11434, module default) now resolves same-host.
# scanDir is vestigial (scans flow maitred -> total-eclipse paperless) — kept
# for config parity; /var/lib/scans does not exist here.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # NOTE: org-crm.nixosModules.default is imported at the flake level

  services.org-crm = {
    enable = true;
    user = "org-crm";
    stateDir = "/var/lib/org-crm";

    orgFile = "/var/lib/org-crm/data/tasks.org";
    notesDir = "/var/lib/org-crm/data/notes";
    scanDir = "/var/lib/scans/documents";

    interval = 300; # 5 minutes
    # Sonnet/opus-tier cloud model — org-crm is a multi-turn reasoning agent
    # (contacts/tasks/email-digest + tool dispatch). Passed as --model on
    # ExecStart, overriding the module's OLLAMA_MODEL env default.
    # think:false is set in the repo call site (org_crm.claude_runner).
    model = "kimi-k2.7-code:cloud";

    # Mail passwords (own copies of the same secrets, owned by org-crm user)
    mailZohoPasswordFile = config.age.secrets.org-crm-mail-zoho.path;
    mailGmailPasswordFile = config.age.secrets.org-crm-mail-gmail.path;
    mailFastmailPasswordFile = config.age.secrets.org-crm-mail-fastmail.path;

    discordUserId = "366455267673636866";

    discordBotTokenFile = config.age.secrets.discord-org-crm-token.path;
    enableDiscordBot = true;
    discordAllowedUsers = "366455267673636866"; # Kimb only
  };

  # kimi-k2.7-code:cloud supports 256k context. org-crm does multi-turn
  # reasoning + email-digest over 3 mailboxes — raise the context window
  # well above the repo default (32768) so large digests don't truncate.
  systemd.services.org-crm.environment.ORG_CRM_NUM_CTX = "262144";

  age.secrets = {
    # Mail secrets (same .age files as email-digest, but owned by org-crm user;
    # pre-keyed to fleetCore at a3j.10, no re-key needed for the move)
    org-crm-mail-zoho = {
      file = ../../secrets/mail-zoho-password.age;
      owner = "org-crm";
      mode = "0400";
    };
    org-crm-mail-gmail = {
      file = ../../secrets/mail-gmail-password.age;
      owner = "org-crm";
      mode = "0400";
    };
    org-crm-mail-fastmail = {
      file = ../../secrets/mail-fastmail-password.age;
      owner = "org-crm";
      mode = "0400";
    };

    # Dedicated Discord bot token (Secretary app)
    discord-org-crm-token = {
      file = ../../secrets/discord-org-crm-token.age;
      owner = "org-crm";
      mode = "0400";
    };
  };
}