# SRE Agent host configuration
# Phase 1: webhook + LLM triage + Discord bot + agenix secrets
{
  config,
  lib,
  ...
}: {
  kimb.sreAgent = {
    enable = true;
    discordTokenFile = config.age.secrets.discord-sre-token.path;
    githubTokenFile = config.age.secrets.gh-sre-token.path;
    ollamaCloudKeyFile = config.age.secrets.ollama-cloud-key.path;
    githubRepo = "mccartykim/homelab-incidents";
    alertChannelId = "900242088434757662";
    webhookPort = 9095;
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "gemma4:12b";
    enableDiscordBot = true;
    enableLlmTriage = true;
    enablePrWorker = true;
    githubSourceRepo = "mccartykim/systems-flake";
    prWorkerModel = "gemma4:12b";
    prWorkerGitAuthorName = "sre-agent";
    prWorkerGitAuthorEmail = "sre-agent@nebula";
    prometheusUrl = "http://10.100.0.50:9090";
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

  age.secrets.ollama-cloud-key = {
    file = ../../secrets/ollama-cloud-key.age;
    owner = "sre-agent";
    mode = "0400";
  };
}
