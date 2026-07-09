# Shared DNS resolver config — opt-in per host via kimb.maitredNameservers.enable.
# Puts the maitred router (via Nebula) first, with 1.1.1.1 as fallback.
{
  lib,
  config,
  ...
}: let
  registry = import ../hosts/nebula-registry.nix;
in {
  options.kimb.maitredNameservers.enable = lib.mkEnableOption "maitred-first DNS resolvers";

  config = lib.mkIf config.kimb.maitredNameservers.enable {
    networking.nameservers = [
      registry.nodes.maitred.ip # maitred router via Nebula
      "1.1.1.1" # Fallback
    ];
  };
}