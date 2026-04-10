{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.modules.ai-tools = {
    enable = mkEnableOption "AI development tools";
  };

  config = mkIf config.modules.ai-tools.enable {
    home.packages = with pkgs; [
      claude-code
    ];
  };
}
