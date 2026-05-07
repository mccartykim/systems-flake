{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.ai-tools;
  claude-zai = pkgs.callPackage ../../pkgs/claude-zai.nix {keyFile = cfg.zaiKeyFile;};
in {
  options.modules.ai-tools = {
    enable = mkEnableOption "AI development tools";

    claudeZai = mkEnableOption "claude-zai wrapper (claude-code via api.z.ai)";

    zaiKeyFile = mkOption {
      type = types.str;
      default = "/run/agenix/zai-api-key";
      description = "Path the claude-zai wrapper reads ANTHROPIC_AUTH_TOKEN from at exec-time.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs;
      [
        claude-code
      ]
      ++ lib.optional cfg.claudeZai claude-zai;
  };
}
