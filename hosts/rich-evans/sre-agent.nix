# SRE Agent host configuration
# Phase 1: webhook + LLM triage + redaction + Discord bot + agenix secrets
{config, lib, ...}: {
  kimb.sreAgent = {
    enable = true;
    discordTokenFile = config.age.secrets.discord-sre-token.path;
    githubTokenFile = config.age.secrets.gh-sre-token.path;
    ollamaCloudKeyFile = config.age.secrets.ollama-cloud-key.path;
    githubRepo = "mccartykim/homelab-incidents";
    alertChannelId = "900242088434757662";
    webhookPort = 9095;
    ollamaHost = "http://total-eclipse.nebula:11434";
    ollamaModel = "qwen3:8b";
    enableDiscordBot = true;
    enableLlmTriage = true;
    enablePrWorker = true;
    githubSourceRepo = "mccartykim/systems-flake";
    prWorkerModel = "gemma4:31b";
    prWorkerCloudHost = "http://historian.nebula:11434";
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
