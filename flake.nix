{
  description = "Kimb's system flakes";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Add flake-parts
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Nil lsp thingy
    nil-flake.url = "github:oxalica/nil";

    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixos-avf.url = "github:nix-community/nixos-avf";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    copyparty.url = "github:9001/copyparty";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    mist-blog.url = "git+ssh://git@github.com/mccartykim/mist-blog";
    mist-blog.inputs.nixpkgs.follows = "nixpkgs";

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
  };

  outputs = {
    self,
    nixpkgs,
    flake-parts,
    copyparty,
    home-manager,
    nixos-hardware,
    nil-flake,
    nix-darwin,
    srvos,
    nix-index-database,
    nixos-avf,
    nixos-generators,
    disko,
    agenix,
    nixos-facter-modules,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        inherit (nixpkgs) lib;
      in {
        # Per-system packages
        packages = lib.optionalAttrs (system == "x86_64-linux") {
          # Legacy installer for rich-evans
          rich-evans-installer = nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            modules = [
              ./installer/installer.nix
            ];
            format = "install-iso";
          };

          # New interactive flake-aware installer
          flake-installer = nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./installer/installer-iso.nix
            ];
            format = "iso";
          };
        };

        # Formatter
        formatter = pkgs.alejandra;

        # Dev shells
        devShells = lib.optionalAttrs (system == "x86_64-linux") {
          default = pkgs.mkShell {
            packages = [pkgs.tealdeer pkgs.colmena];
          };
        };
      };

      flake = let
        inherit (self) outputs;
        inherit (nixpkgs) lib;
      in {
        # Darwin configurations
        darwinConfigurations = {
          "kmccarty-YM2K" = nix-darwin.lib.darwinSystem {
            modules = [
              home-manager.darwinModules.home-manager
              ./darwin/kmccarty-YM2K/configuration.nix
              ./home/work-laptop.nix
              nix-index-database.darwinModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
            ];
          };
          "cronut" = nix-darwin.lib.darwinSystem {
            modules = [
              home-manager.darwinModules.home-manager
              ./darwin/cronut/configuration.nix
              ./home/cronut.nix
              nix-index-database.darwinModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
            ];
          };
        };

        # NixOS configuration entrypoint
        # Available through 'nixos-rebuild --flake .#your-hostname'
        nixosConfigurations = {
          rich-evans-installer = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./installer/installer.nix
            ];
          };

          bonbon = inputs.nixpkgs.lib.nixosSystem {
            # system to build for
            system = "aarch64-linux";
            # modules to use
            modules = [
              ./avd/bonbon/configuration.nix # our previous config file
              home-manager.nixosModules.home-manager # make home manager available to configuration.nix
              {
                # use system-level nixpkgs rather than the HM private ones
                # "This saves an extra Nixpkgs evaluation, adds consistency, and removes the dependency on NIX_PATH, which is otherwise used for importing Nixpkgs."
                home-manager = {
                  useGlobalPkgs = true;
                  users.droid = ./home/bonbon.nix;
                  backupFileExtension = "backup";
                };
              }
              nixos-avf.nixosModules.avf
              nix-index-database.nixosModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
            ];
          };

          cheesecake = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              nixos-facter-modules.nixosModules.facter
              {config.facter.reportPath = ./hosts/cheesecake/facter.json;}
              ./hosts/cheesecake/configuration.nix
              home-manager.nixosModules.home-manager
              nix-index-database.nixosModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  users.kimb = import ./home/cheesecake.nix;
                };
              }
            ];
          };

          marshmallow = nixpkgs.lib.nixosSystem {
            specialArgs = {inherit inputs outputs;};
            # > our main nixos configuration file <
            modules = [
              srvos.nixosModules.desktop
              srvos.nixosModules.mixins-trusted-nix-caches
              srvos.nixosModules.mixins-terminfo
              srvos.nixosModules.mixins-systemd-boot
              srvos.nixosModules.mixins-nix-experimental
              srvos.nixosModules.mixins-trusted-nix-caches
              nixos-hardware.nixosModules.lenovo-thinkpad-t490
              ./hosts/marshmallow/configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager = {
                  backupFileExtension = "backup";
                  # useGlobalPkgs = true;
                  useUserPackages = true;
                  users.kimb = ./home/marshmallow.nix;
                };
              }
              nix-index-database.nixosModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
            ];
          };

          total-eclipse = nixpkgs.lib.nixosSystem {
            specialArgs = {inherit inputs outputs;};
            # > our main nixos configuration file <
            modules = [
              ./hosts/total-eclipse/configuration.nix
              nix-index-database.nixosModules.nix-index
              srvos.nixosModules.desktop
              srvos.nixosModules.mixins-nix-experimental
              srvos.nixosModules.mixins-trusted-nix-caches
              {programs.nix-index-database.comma.enable = true;}
              home-manager.nixosModules.home-manager
              {
                home-manager = {
                  backupFileExtension = "backup";
                  # useGlobalPkgs = true;
                  useUserPackages = true;
                  users.kimb = ./home/total-eclipse.nix;
                };
              }
            ];
          };

          historian = nixpkgs.lib.nixosSystem {
            specialArgs = {inherit inputs outputs;};
            # > our main nixos configuration file <
            modules = [
              ./hosts/historian/configuration.nix
              nix-index-database.nixosModules.nix-index
              srvos.nixosModules.desktop
              srvos.nixosModules.mixins-nix-experimental
              srvos.nixosModules.mixins-trusted-nix-caches
              {programs.nix-index-database.comma.enable = true;}
              home-manager.nixosModules.home-manager
              {
                home-manager = {
                  backupFileExtension = "backup";
                  # useGlobalPkgs = true;
                  useUserPackages = true;
                  users.kimb = ./home/historian.nix;
                };
              }
            ];
          };

          rich-evans = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {inherit inputs outputs copyparty;};
            modules = [
              copyparty.nixosModules.default
              srvos.nixosModules.server
              srvos.nixosModules.mixins-trusted-nix-caches
              srvos.nixosModules.mixins-systemd-boot
              srvos.nixosModules.mixins-nix-experimental
              ./modules/kimb-services.nix

              # Service configuration for rich-evans
              {
                kimb.services = {
                  # File sharing service
                  copyparty = {
                    enable = true;
                    port = 3923;
                    subdomain = "files"; # files.kimb.dev
                    host = "rich-evans";
                    container = false;
                    auth = "authelia"; # Requires two-factor auth
                    publicAccess = true;
                    websockets = false;
                  };

                  # Homepage on rich-evans
                  homepage = {
                    enable = true;
                    port = 8082;
                    subdomain = "home-rich"; # Different from maitred
                    host = "rich-evans";
                    container = false;
                    auth = "none"; # Local access only
                    publicAccess = false; # Not exposed publicly
                    websockets = false;
                  };

                  # Home Assistant (smart home)
                  homeassistant = {
                    enable = true;
                    port = 8123;
                    subdomain = "hass";
                    host = "rich-evans";
                    container = true; # OCI container
                    auth = "builtin"; # Has its own auth
                    publicAccess = true;
                    websockets = true; # Needs WebSocket support
                  };
                };
              }

              nix-index-database.nixosModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
              ./hosts/rich-evans/configuration.nix
            ];
          };

          maitred = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {inherit inputs outputs;};
            modules = [
              ./modules/kimb-services.nix

              # Service configuration using options system
              {
                kimb = {
                  domain = "kimb.dev";
                  admin = {
                    name = "kimb";
                    email = "mccartykim@zoho.com";
                    displayName = "Kimberly";
                  };

                  services = {
                    # Authentication service (container)
                    authelia = {
                      enable = true;
                      port = 9091;
                      subdomain = "auth";
                      host = "maitred";
                      container = false; # Uses host network
                      auth = "none"; # No auth required for auth service
                      publicAccess = true;
                      websockets = false;
                    };

                    # Monitoring stack (host services)
                    grafana = {
                      enable = true;
                      port = 3000;
                      subdomain = "grafana";
                      host = "maitred";
                      container = false;
                      auth = "authelia";
                      publicAccess = true;
                      websockets = false;
                    };

                    prometheus = {
                      enable = true;
                      port = 9090;
                      subdomain = "prometheus";
                      host = "maitred";
                      container = false;
                      auth = "authelia";
                      publicAccess = true;
                      websockets = false;
                    };

                    # Homepage dashboard (host service)
                    homepage = {
                      enable = true;
                      port = 8082;
                      subdomain = "home";
                      host = "maitred";
                      container = false;
                      auth = "authelia";
                      publicAccess = true;
                      websockets = false;
                    };

                    # Blog service (container)
                    blog = {
                      enable = true;
                      port = 8080;
                      subdomain = "blog"; # Creates blog.kimb.dev
                      host = "maitred";
                      container = true;
                      auth = "none"; # Public blog
                      publicAccess = true;
                      websockets = false;
                    };

                    # Reverse proxy (container) - always enabled on maitred
                    reverse-proxy = {
                      enable = true;
                      port = 80;
                      subdomain = "www"; # Not used - handles all domains
                      host = "maitred";
                      container = true;
                      auth = "none";
                      publicAccess = true;
                      websockets = false;
                    };
                  };

                  networks = {
                    containerBridge = "192.168.100.1";
                    reverseProxyIP = "192.168.100.2";
                    trustedNetworks = [
                      "192.168.0.0/16" # LAN (192.168.69.0/24)
                      "10.100.0.0/16" # Nebula mesh
                      "100.64.0.0/10" # Tailscale
                    ];
                  };

                  dns = {
                    provider = "cloudflare";
                    ttl = 1;
                    updatePeriod = 300;
                    servers = {
                      primary = "192.168.69.1"; # maitred
                      fallback = ["8.8.8.8" "8.8.4.4"];
                    };
                  };
                };
              }

              ./hosts/maitred/configuration.nix
              nix-index-database.nixosModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
            ];
          };

          bartleby = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {inherit inputs outputs;};
            modules = [
              srvos.nixosModules.desktop
              srvos.nixosModules.mixins-systemd-boot
              srvos.nixosModules.mixins-nix-experimental
              srvos.nixosModules.mixins-trusted-nix-caches
              nixos-hardware.nixosModules.lenovo-thinkpad
              ./modules/kimb-services.nix

              # Service configuration for bartleby (desktop - no services by default)
              {
                kimb.services = {
                  # Fractal art service (available but disabled)
                  fractal-art = {
                    enable = false; # Set to true to enable
                    port = 8000;
                    subdomain = "art";
                    host = "bartleby";
                    container = false;
                    auth = "none";
                    publicAccess = false;
                    websockets = false;
                  };
                };
              }

              {
                nixpkgs.overlays = [
                  nil-flake.overlays.nil
                ];
              }
              ./hosts/bartleby/configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager = {
                  backupFileExtension = "backup";
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  users.kimb = ./home/bartleby.nix;
                };
              }
              nix-index-database.nixosModules.nix-index
              {programs.nix-index-database.comma.enable = true;}
            ];
          };
        };

        # Colmena deployment configuration
        colmena = let
          registry = import ./hosts/nebula-registry.nix;
          # Helper to create colmena node from registry entry
          makeColmenaNode = name: node: {
            deployment = {
              targetHost = node.ip; # Use Nebula IPs for direct connection to all hosts
              targetUser = "kimb";
              buildOnTarget = false;
            };
            imports = self.nixosConfigurations.${name}._module.args.modules;
          };
        in
          {
            meta = {
              nixpkgs = import nixpkgs {
                system = "x86_64-linux";
                overlays = [];
              };
              specialArgs = {inherit inputs outputs copyparty;};
            };
          }
          // (builtins.mapAttrs makeColmenaNode
            (builtins.removeAttrs registry.nodes ["lighthouse"])); # Skip non-NixOS lighthouse

        # Test suite
        tests =
          {
            # Full integration test (requires working file paths)
            integrationTest = import ./tests/integration-vm-test.nix {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
              inherit (nixpkgs.legacyPackages.x86_64-linux) lib;
              inherit agenix;
            };

            # Simple VM test with inline keys
            simpleVMTest = import ./tests/simple-vm-test.nix {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
              inherit (nixpkgs.legacyPackages.x86_64-linux) lib;
            };

            # Minimal test for debugging
            minimalTest = import ./tests/minimal-test.nix {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
            };

            # Multi-VM network test with kimb-services
            networkTest = import ./tests/network-test.nix {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
            };

            # Working VM test for debugging
            workingVMTest = import ./tests/working-vm-test.nix {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
            };

            # Installer tests
            installerTests = import ./tests/installer-test.nix {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
              inherit (nixpkgs.legacyPackages.x86_64-linux) lib;
            };
          }
          // (import ./tests/installer-test.nix {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            inherit (nixpkgs.legacyPackages.x86_64-linux) lib;
          })
          // (import ./tests/integration-vm-test.nix {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            inherit (nixpkgs.legacyPackages.x86_64-linux) lib;
            inherit agenix;
          });
      };
    };
}
