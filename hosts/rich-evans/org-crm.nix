# org-crm: Personal CRM agent
#
# Manages contacts, tasks, email digest, and scanned documents.
# Uses Ollama for LLM calls (replaces Claude CLI).
# Once verified working, remove email-digest.nix (this absorbs its functionality).
#
# Dedicated Discord bot app (Secretary) for DMs and slash commands.
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

  age.secrets = {
    # Mail secrets (same .age files as email-digest, but owned by org-crm user)
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
