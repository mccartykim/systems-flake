# org-crm: Personal CRM agent
#
# Manages contacts, tasks, email digest, and scanned documents.
# Once verified working, remove email-digest.nix (this absorbs its functionality).
#
# Discord bot token: requires manual setup of a new Discord application
# ("Secretary") — see org_crm plan for details.
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
    provider = "claude";
    model = "haiku";

    # Mail passwords (own copies of the same secrets, owned by org-crm user)
    mailZohoPasswordFile = config.age.secrets.org-crm-mail-zoho.path;
    mailGmailPasswordFile = config.age.secrets.org-crm-mail-gmail.path;
    mailFastmailPasswordFile = config.age.secrets.org-crm-mail-fastmail.path;

    discordUserId = "366455267673636866";

    # Discord bot — uncomment after creating the bot application and encrypting token
    # discordBotTokenFile = config.age.secrets.discord-org-crm-token.path;
  };

  # Mail secrets (same .age files as email-digest, but owned by org-crm user)
  age.secrets.org-crm-mail-zoho = {
    file = ../../secrets/mail-zoho-password.age;
    owner = "org-crm";
    mode = "0400";
  };
  age.secrets.org-crm-mail-gmail = {
    file = ../../secrets/mail-gmail-password.age;
    owner = "org-crm";
    mode = "0400";
  };
  age.secrets.org-crm-mail-fastmail = {
    file = ../../secrets/mail-fastmail-password.age;
    owner = "org-crm";
    mode = "0400";
  };

  # Discord bot token — uncomment after encrypting with agenix
  # age.secrets.discord-org-crm-token = {
  #   file = ../../secrets/discord-org-crm-token.age;
  #   owner = "org-crm";
  #   mode = "0400";
  # };

}
