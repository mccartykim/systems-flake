# SRE Agent host configuration
# Phase 0: stub webhook receiver + agenix secrets
{config, ...}: {
  kimb.sreAgent = {
    enable = true;
    discordTokenFile = config.age.secrets.discord-sre-token.path;
    githubTokenFile = config.age.secrets.gh-sre-token.path;
    githubRepo = "mccartykim/homelab-incidents";
    alertChannelId = "900242088434757662";
    webhookPort = 9095;
  };

  age.secrets.discord-sre-token = {
    file = ../../secrets/discord-sre-token.age;
    owner = "sre-agent";
    mode = "0400";
  };

  age.secrets.gh-sre-token = {
    file = ../../secrets/gh-sre-token.age;
    owner = "sre-agent";
    mode = "0400";
  };
}
