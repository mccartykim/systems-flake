{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.ai-tools;
  claude-zai = pkgs.callPackage ../../pkgs/claude-zai.nix {keyFile = cfg.zaiKeyFile;};
  ollama-pi = pkgs.callPackage ../../pkgs/ollama-pi.nix {
    baseUrl = cfg.ollamaPiBaseUrl;
    models = cfg.ollamaPiModels;
  };
  # claude-code -> local ollama (anthropic-native), via the generic
  # mkClaudeWrapper generator (claude-wrapper overlay). The opus variant uses
  # the text-only glm-5.2 and the proxy reroutes its image requests to kimi; the
  # k3 variant uses the multimodal kimi-k3 as opus so the reroute is a no-op
  # (it is also billing-blocked until extra-usage balance is added at
  # ollama.com/settings).
  claude-ollama = pkgs.mkClaudeWrapper.override {
    name = "claude-ollama";
    endpoint = cfg.claudeOllamaEndpoint;
    opusModel = "glm-5.2:cloud";
    sonnetModel = "kimi-k2.7-code:cloud";
    haikuModel = "qwen3.5:397b-cloud";
    opusImageModel = "kimi-k2.7-code:cloud"; # glm-5.2 can't see images -> kimi
    dummyAuth = "ollama";
  };
  claude-ollama-k3 = pkgs.mkClaudeWrapper.override {
    name = "claude-ollama-k3";
    endpoint = cfg.claudeOllamaEndpoint;
    opusModel = "kimi-k3:cloud"; # multimodal -> imageModels all default to themselves
    sonnetModel = "kimi-k2.7-code:cloud";
    haikuModel = "qwen3.5:397b-cloud";
    dummyAuth = "ollama";
  };
in {
  options.modules.ai-tools = {
    enable = mkEnableOption "AI development tools";

    claudeZai = mkEnableOption "claude-zai wrapper (claude-code via api.z.ai)";

    zaiKeyFile = mkOption {
      type = types.str;
      default = "/run/agenix/zai-api-key";
      description = "Path the claude-zai wrapper reads ANTHROPIC_AUTH_TOKEN from at exec-time.";
    };

    ollamaPi = mkEnableOption "ollama-pi wrapper (pi-coding-agent via local Ollama)";

    ollamaPiBaseUrl = mkOption {
      type = types.str;
      default = "http://localhost:11434/v1";
      description = "Ollama OpenAI-compatible endpoint the ollama-pi wrapper targets.";
    };

    ollamaPiModels = mkOption {
      type = types.listOf types.str;
      default = ["kimi-k2.7-code:cloud" "glm-5.2:cloud" "glm-5.1:cloud"];
      description = ''
        Ollama model ids exposed in pi's /model picker. The first is the
        launch default. Only models the endpoint actually serves will work.
      '';
    };

    claudeOllama = mkEnableOption "claude-ollama wrapper (claude-code via local anthropic-native Ollama, opus=glm-5.2, images rerouted to kimi)";

    claudeOllamaK3 = mkEnableOption "claude-ollama-k3 wrapper (claude-code via Ollama, opus=kimi-k3 multimodal; needs extra-usage balance)";

    claudeOllamaEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:11434";
      description = "Anthropic-native Ollama base URL (no /v1) the claude-ollama wrappers target.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs;
      [
        claude-code
      ]
      ++ lib.optional cfg.claudeZai claude-zai
      ++ lib.optional cfg.ollamaPi ollama-pi
      ++ lib.optional cfg.claudeOllama claude-ollama
      ++ lib.optional cfg.claudeOllamaK3 claude-ollama-k3;
  };
}
