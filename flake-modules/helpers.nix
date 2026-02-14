# Helper functions and common module lists for NixOS configurations
{
  inputs,
  self,
  ...
}: let
  inherit (inputs) nixpkgs home-manager srvos nix-index-database firefox-nightly;

  # Overlay to fix Python packages with build/test issues
  pythonFixesOverlay = final: prev: {
    python3Packages = prev.python3Packages.override {
      overrides = pyFinal: pyPrev: {
        # extract_msg requires beautifulsoup4<4.14 but nixpkgs has 4.14.x
        # The package works fine with newer versions, just has strict bounds
        extract-msg = pyPrev.extract-msg.overridePythonAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
            pyFinal.pythonRelaxDepsHook
          ];
          pythonRelaxDeps = ["beautifulsoup4"];
        });

        # duckdb-engine tests fail because DuckDB doesn't implement all
        # PostgreSQL system catalogs (pg_collation, etc). The package itself
        # works fine; only the test suite has compatibility issues.
        duckdb-engine = pyPrev.duckdb-engine.overridePythonAttrs (old: {
          doCheck = false;
        });
      };
    };
  };

  # Overlay to use Firefox Nightly and override pkgs.firefox to point to nightly
  firefoxNightlyOverlay = final: prev: let
    nightlyPkgs = firefox-nightly.packages.${prev.system};
  in {
    firefox = nightlyPkgs.firefox-nightly-bin;
  };
in {
  # Export helpers via flake.lib for use by other modules
  flake.lib = rec {
    # Common modules applied to all NixOS configurations
    commonModules = [
      nix-index-database.nixosModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
      (self + "/modules/distributed-builds.nix")
      {kimb.distributedBuilds.enable = true;}
      (self + "/modules/agenix.nix")
      # Fix Python packages with strict version bounds + Firefox Nightly
      {nixpkgs.overlays = [pythonFixesOverlay firefoxNightlyOverlay];}
    ];

    # Desktop-specific modules (srvos desktop + common mixins)
    desktopModules = [
      srvos.nixosModules.desktop
      srvos.nixosModules.mixins-nix-experimental
      srvos.nixosModules.mixins-trusted-nix-caches
    ];

    # Server-specific modules
    serverModules = [
      srvos.nixosModules.server
      srvos.nixosModules.mixins-nix-experimental
      srvos.nixosModules.mixins-trusted-nix-caches
      srvos.nixosModules.mixins-systemd-boot
    ];

    # Darwin common modules
    darwinCommon = [
      home-manager.darwinModules.home-manager
      nix-index-database.darwinModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
    ];

    # Home-manager configuration helper
    mkHomeManager = {
      user ? "kimb",
      homeConfig,
      useGlobalPkgs ? true,
    }: [
      home-manager.nixosModules.home-manager
      {
        home-manager = {
          backupFileExtension = "backup";
          inherit useGlobalPkgs;
          useUserPackages = true;
          users.${user} = homeConfig;
        };
      }
    ];

    # Helper to create a desktop NixOS configuration
    mkDesktop = {
      hostname,
      system ? "x86_64-linux",
      extraModules ? [],
      extraSpecialArgs ? {},
      hardwareModules ? [],
      homeConfig ? (self + "/home/${hostname}.nix"),
      useGlobalPkgs ? true,
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs =
          {
            inherit inputs;
            outputs = self;
          }
          // extraSpecialArgs;
        modules =
          desktopModules
          ++ commonModules
          ++ hardwareModules
          ++ [(self + "/hosts/${hostname}/configuration.nix")]
          ++ mkHomeManager {inherit homeConfig useGlobalPkgs;}
          ++ extraModules;
      };

    # Helper to create a server NixOS configuration
    mkServer = {
      hostname,
      system ? "x86_64-linux",
      extraModules ? [],
      extraSpecialArgs ? {},
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs =
          {
            inherit inputs;
            outputs = self;
          }
          // extraSpecialArgs;
        modules =
          serverModules
          ++ commonModules
          ++ [(self + "/hosts/${hostname}/configuration.nix")]
          ++ extraModules;
      };
  };
}
