# Helper functions and common module lists for NixOS configurations
{
  inputs,
  self,
  ...
}: let
  inherit (inputs) nixpkgs home-manager srvos nix-index-database firefox-nightly nix-topology lix-module claude-wrapper;

  # Overlay to fix Python packages with build/test issues
  pythonFixesOverlay = final: prev: {
    python3Packages = prev.python3Packages.override {
      overrides = pyFinal: pyPrev: {
        # extract_msg requires beautifulsoup4<4.14 but nixpkgs has 4.14.x
        # The package works fine with newer versions, just has strict bounds
        extract-msg = pyPrev.extract-msg.overridePythonAttrs (old: {
          nativeBuildInputs =
            (old.nativeBuildInputs or [])
            ++ [
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
    # Common modules applied to all NixOS configurations.
    # lix-module goes first so its overlay (nixVersions.stable → Lix + the
    # CppNix-keep list) is applied before anything else consults nix. This covers
    # every NixOS host, including creme/donut which use commonModules directly
    # rather than mkDesktop/mkServer. (Darwin uses darwinModules.lixFromNixpkgs
    # separately if ever wanted.)
    commonModules = [
      lix-module.nixosModules.lixFromNixpkgs
      nix-index-database.nixosModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
      (self + "/modules/distributed-builds.nix")
      {kimb.distributedBuilds.enable = true;}
      (self + "/modules/agenix.nix")
      (self + "/modules/sre-agent.nix")
      (self + "/modules/observability.nix")
      (self + "/modules/syncthing.nix")
      (self + "/modules/maitred-nameservers.nix")
      (self + "/modules/zai-api-key.nix")
      # kimb.* option declarations + per-host service auto-injection
      (self + "/modules/kimb-services.nix")
      (self + "/services/default.nix")
      # Fix Python packages with strict version bounds + Firefox Nightly +
      # the generic claude-code wrapper generator (pkgs.mkClaudeWrapper).
      {nixpkgs.overlays = [pythonFixesOverlay firefoxNightlyOverlay claude-wrapper.overlays.default];}
      # Infrastructure/network diagram generation
      nix-topology.nixosModules.default
      # Static nebula host entries so hostname.nebula resolves without maitred DNS
      (_: let
        registry = import (self + "/hosts/nebula-registry.nix");
        names = builtins.attrNames registry.nodes;
        # Nodes that carry an SSH host key in the registry (tachikoma doesn't).
        pinned = builtins.filter (n: (registry.nodes.${n}.publicKey or null) != null) names;
      in {
        networking.extraHosts =
          builtins.concatStringsSep "\n"
          (builtins.map (name: "${registry.nodes.${name}.ip} ${name}.nebula") names);
        # Pin every fleet host's SSH host key fleet-wide so `ssh …@<host>.nebula`
        # never TOFU-prompts and never breaks when a host rekeys. This caught
        # oracle 2026-07-25: total-eclipse had drifted off oracle's key and colmena
        # couldn't SSH to it → oracle's authorized_keys went stale → phone→oracle
        # failed auth. mochi is included here too — it's a nebula host but NOT
        # NixOS-managed (AVF Debian), so its key never enters via the normal NixOS
        # host-key path; the AVF restore script bakes this STABLE key. Registry
        # keys verified 2026-07-25 to match live `ssh-keyscan` for oracle +
        # historian + mochi.
        programs.ssh.knownHosts =
          builtins.listToAttrs (builtins.map (n: {
            name = n;
            value = {
              hostNames = ["${n}.nebula" registry.nodes.${n}.ip];
              publicKey = registry.nodes.${n}.publicKey;
            };
          }) pinned);
      })
    ];

    # Desktop-specific modules (srvos desktop + common mixins)
    # NB: mixins-nix-experimental deliberately omitted — it enables CppNix-only
    # experimental features (ca-derivations, impure-derivations, recursive-nix,
    # fetch-closure, blake3-hashes, configurable-impure-env) that Lix doesn't
    # implement, which hard-fails the nix.conf build-time validator under Lix.
    desktopModules = [
      srvos.nixosModules.desktop
      srvos.nixosModules.mixins-trusted-nix-caches
    ];

    # Server-specific modules (see desktopModules note re: nix-experimental)
    serverModules = [
      srvos.nixosModules.server
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
