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
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs;
      [
        claude-code
      ]
      ++ lib.optional cfg.claudeZai claude-zai
      ++ lib.optional cfg.ollamaPi ollama-pi;
  };
}
