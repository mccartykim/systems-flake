# Service Registry Module - Makes registry data available to all modules
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  # Import the registry data
  registryData = import ./service-registry-data.nix;
in {
  options.serviceRegistry = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the service registry";
    };

    data = mkOption {
      type = types.attrs;
      default = registryData;
      description = "The service registry data";
    };
  };

  config = mkIf config.serviceRegistry.enable {
    # Make registry available to all modules via specialArgs
    _module.args.registry = registryData;

    # Also make it available via config for modules that prefer that
    nixpkgs.overlays = [
      (self: super: {
        serviceRegistry = registryData;
      })
    ];

    # Export commonly needed values directly
    networking.domain = mkDefault registryData.domains.primary;

    # Set admin user if not already set
    users.users.${registryData.users.admin.name} = mkDefault {
      isNormalUser = true;
      description = registryData.users.admin.displayName;
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = registryData.users.admin.sshKeys;
    };
  };
}
