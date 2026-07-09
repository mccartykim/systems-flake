# Shared z.ai API key agenix secret — opt-in per host via kimb.zaiApiKey.enable.
# The secret is read at runtime by the claude-zai wrapper (home/modules/ai-tools.nix)
# from /run/agenix/zai-api-key; keeping the name preserves that path.
{
  lib,
  config,
  ...
}: {
  options.kimb.zaiApiKey.enable = lib.mkEnableOption "shared zai-api-key agenix secret";

  config = lib.mkIf config.kimb.zaiApiKey.enable {
    age.secrets.zai-api-key = {
      file = ../secrets/zai-api-key.age;
      owner = "kimb";
      mode = "0400";
    };
  };
}