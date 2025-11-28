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
        packages =
          lib.optionalAttrs (system == "x86_64-linux") {
            rich-evans-installer = nixos-generators.nixosGenerate {
              system = "x86_64-linux";
              modules = [
                ./installer/installer.nix
              ];
              format = "install-iso";
            };
          }
          // lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
            # ESPHome firmware builds
            esp32-cam-01-firmware = pkgs.stdenv.mkDerivation {
              name = "esp32-cam-01-firmware";
              src = ./esphome-configs;

              nativeBuildInputs = [pkgs.esphome];

              buildPhase = ''
                # Copy config and secrets
                mkdir -p build
                cp esp32-cam-01.yaml build/

                # Check if secrets exist, otherwise create dummy
                if [ -f secrets.yaml ]; then
                  cp secrets.yaml build/
                else
                  echo "Warning: secrets.yaml not found, using dummy values"
                  cat > build/secrets.yaml <<EOF
                wifi_ssid: "dummy"
                wifi_password: "dummy"
                api_encryption_key: "dummy=="
                ota_password: "dummy"
                ap_password: "dummy"
                EOF
                fi

                cd build
                esphome compile esp32-cam-01.yaml
              '';

              installPhase = ''
                mkdir -p $out
                cp -r esp32-cam-01 $out/
              '';
            };
          };

        # Formatter
        formatter = pkgs.alejandra;

        # Dev shells
        devShells = lib.optionalAttrs (system == "x86_64-linux") {
          default = pkgs.mkShell {
            packages = [
              pkgs.tealdeer
              pkgs.colmena
              pkgs.esphome # ESP32/ESP8266 firmware builder
              pkgs.esptool # ESP32/ESP8266 flasher
            ];
          };
        };

        # Apps for common tasks
        apps = lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
          flash-esp32-cam-01 = {
            type = "app";
            program = toString (pkgs.writeShellScript "flash-esp32-cam-01" ''
              set -e
              PORT=''${1:-/dev/ttyUSB0}

              echo "Building ESP32-CAM-01 firmware..."
              nix build .#esp32-cam-01-firmware

              FIRMWARE="result/esp32-cam-01/.pioenvs/esp32-cam-01/firmware.bin"

              if [ ! -f "$FIRMWARE" ]; then
                echo "Error: Firmware not found at $FIRMWARE"
                exit 1
              fi

              echo "Flashing to $PORT..."
              ${pkgs.esptool}/bin/esptool.py \
                --port "$PORT" \
                --baud 460800 \
                write_flash \
                0x10000 "$FIRMWARE"

              echo "Flash complete! Reset the ESP32-CAM to boot."
            '');
          };
        };

        # Flake checks - runs via `nix flake check`
        checks = lib.optionalAttrs (system == "x86_64-linux") {
          # VM tests
          minimal-test = import ./tests/minimal-test.nix {inherit pkgs;};
          network-test = import ./tests/network-test.nix {inherit pkgs;};
          working-vm-test = import ./tests/working-vm-test.nix {inherit pkgs;};

          # Configuration evaluation tests (fast - no VM)
          eval-historian = self.nixosConfigurations.historian.config.system.build.toplevel;
          eval-marshmallow = self.nixosConfigurations.marshmallow.config.system.build.toplevel;
          eval-bartleby = self.nixosConfigurations.bartleby.config.system.build.toplevel;
          eval-total-eclipse = self.nixosConfigurations.total-eclipse.config.system.build.toplevel;
          eval-maitred = self.nixosConfigurations.maitred.config.system.build.toplevel;
          eval-rich-evans = self.nixosConfigurations.rich-evans.config.system.build.toplevel;
        };
      };

      flake = let
        inherit (self) outputs;
        inherit (nixpkgs) lib;

        # Common modules applied to all NixOS configurations
        commonModules = [
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
          ./modules/distributed-builds.nix
          {kimb.distributedBuilds.enable = true;}
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

        # Home-manager configuration helper
        mkHomeManager = {
          user ? "kimb",
          homeConfig,
          useGlobalPkgs ? false,
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
          hardwareModules ? [],
          homeConfig ? ./home/${hostname}.nix,
          useGlobalPkgs ? false,
        }:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {inherit inputs outputs;};
            modules =
              desktopModules
              ++ commonModules
              ++ hardwareModules
              ++ [./hosts/${hostname}/configuration.nix]
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
            specialArgs = {inherit inputs outputs;} // extraSpecialArgs;
            modules =
              serverModules
              ++ commonModules
              ++ [./hosts/${hostname}/configuration.nix]
              ++ extraModules;
          };
      in {
        # Darwin configurations
        darwinConfigurations = let
          darwinCommon = [
            home-manager.darwinModules.home-manager
            nix-index-database.darwinModules.nix-index
            {programs.nix-index-database.comma.enable = true;}
          ];
        in {
          "kmccarty-YM2K" = nix-darwin.lib.darwinSystem {
            modules = darwinCommon ++ [
              ./darwin/kmccarty-YM2K/configuration.nix
              ./home/work-laptop.nix
            ];
          };
          "cronut" = nix-darwin.lib.darwinSystem {
            modules = darwinCommon ++ [
              ./darwin/cronut/configuration.nix
              ./home/cronut.nix
            ];
          };
        };

        # NixOS configuration entrypoint
        # Available through 'nixos-rebuild --flake .#your-hostname'
        nixosConfigurations = {
          # Installer ISO
          rich-evans-installer = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./installer/installer.nix
            ];
          };

          # Android Virtual Device
          bonbon = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules =
              commonModules
              ++ mkHomeManager {
                user = "droid";
                homeConfig = ./home/bonbon.nix;
                useGlobalPkgs = true;
              }
              ++ [
                ./avd/bonbon/configuration.nix
                nixos-avf.nixosModules.avf
              ];
          };

          # Surface 3 Go tablet
          cheesecake = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules =
              commonModules
              ++ mkHomeManager {
                homeConfig = ./home/cheesecake.nix;
                useGlobalPkgs = true;
              }
              ++ [
                nixos-facter-modules.nixosModules.facter
                {config.facter.reportPath = ./hosts/cheesecake/facter.json;}
                ./hosts/cheesecake/configuration.nix
              ];
          };

          # Desktops using mkDesktop helper
          historian = mkDesktop {hostname = "historian";};
          total-eclipse = mkDesktop {hostname = "total-eclipse";};

          marshmallow = mkDesktop {
            hostname = "marshmallow";
            hardwareModules = [
              nixos-hardware.nixosModules.lenovo-thinkpad-t490
              srvos.nixosModules.mixins-terminfo
              srvos.nixosModules.mixins-systemd-boot
            ];
          };

          bartleby = mkDesktop {
            hostname = "bartleby";
            useGlobalPkgs = true;
            hardwareModules = [
              nixos-hardware.nixosModules.lenovo-thinkpad
              srvos.nixosModules.mixins-systemd-boot
            ];
            extraModules = [
              ./modules/kimb-services.nix
              {
                nixpkgs.overlays = [nil-flake.overlays.nil];
                kimb.services.fractal-art = {
                  enable = false;
                  port = 8000;
                  subdomain = "art";
                  host = "bartleby";
                  auth = "none";
                  publicAccess = false;
                  websockets = false;
                };
              }
            ];
          };

          # Servers using mkServer helper
          rich-evans = mkServer {
            hostname = "rich-evans";
            extraSpecialArgs = {inherit copyparty;};
            extraModules = [
              copyparty.nixosModules.default
              ./modules/kimb-services.nix
              {
                kimb.services = {
                  copyparty = {
                    enable = true;
                    port = 3923;
                    subdomain = "files";
                    host = "rich-evans";
                    auth = "authelia";
                    publicAccess = true;
                    websockets = false;
                  };
                  homepage = {
                    enable = true;
                    port = 8082;
                    subdomain = "home-rich";
                    host = "rich-evans";
                    auth = "none";
                    publicAccess = false;
                    websockets = false;
                  };
                  homeassistant = {
                    enable = true;
                    port = 8123;
                    subdomain = "hass";
                    host = "rich-evans";
                    auth = "builtin";
                    publicAccess = true;
                    websockets = true;
                  };
                };
              }
            ];
          };

          # Router (custom - no srvos server, has specific networking needs)
          maitred = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {inherit inputs outputs;};
            modules =
              commonModules
              ++ [
                ./modules/kimb-services.nix
                {
                  kimb = {
                    domain = "kimb.dev";
                    admin = {
                      name = "kimb";
                      email = "mccartykim@zoho.com";
                      displayName = "Kimberly";
                    };
                    services = {
                      authelia = {
                        enable = true;
                        port = 9091;
                        subdomain = "auth";
                        host = "maitred";
                        auth = "none";
                        publicAccess = true;
                        websockets = false;
                      };
                      grafana = {
                        enable = true;
                        port = 3000;
                        subdomain = "grafana";
                        host = "maitred";
                        auth = "authelia";
                        publicAccess = true;
                        websockets = false;
                      };
                      prometheus = {
                        enable = true;
                        port = 9090;
                        subdomain = "prometheus";
                        host = "maitred";
                        auth = "authelia";
                        publicAccess = true;
                        websockets = false;
                      };
                      homepage = {
                        enable = true;
                        port = 8082;
                        subdomain = "home";
                        host = "maitred";
                        auth = "authelia";
                        publicAccess = true;
                        websockets = false;
                      };
                      homeassistant = {
                        enable = true;
                        port = 8123;
                        subdomain = "hass";
                        host = "rich-evans";
                        auth = "builtin";
                        publicAccess = true;
                        websockets = true;
                      };
                      blog = {
                        enable = true;
                        port = 8080;
                        subdomain = "blog";
                        host = "maitred";
                        containerIP = "192.168.100.3";
                        auth = "none";
                        publicAccess = true;
                        websockets = false;
                      };
                      reverse-proxy = {
                        enable = true;
                        port = 80;
                        subdomain = "www";
                        host = "maitred";
                        containerIP = "192.168.100.2";
                        auth = "none";
                        publicAccess = true;
                        websockets = false;
                      };
                    };
                    networks = {
                      containerBridge = "192.168.100.1";
                      reverseProxyIP = "192.168.100.2";
                      trustedNetworks = ["192.168.0.0/16" "10.100.0.0/16" "100.64.0.0/10"];
                    };
                    dns = {
                      provider = "cloudflare";
                      ttl = 1;
                      updatePeriod = 300;
                      servers = {
                        primary = "192.168.69.1";
                        fallback = ["8.8.8.8" "8.8.4.4"];
                      };
                    };
                  };
                }
                ./hosts/maitred/configuration.nix
              ];
          };

        };

        # Colmena deployment configuration
        colmena = let
          registry = import ./hosts/nebula-registry.nix;
          # Helper to create colmena node from registry entry
          makeColmenaNode = name: node: {
            deployment = {
              # Use hostname.nebula for DNS resolution, fallback comment shows IP
              # ${name}.nebula resolves via maitred DNS, or use node.ip (${node.ip}) directly
              targetHost = "${name}.nebula";
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

        # Tests are now in checks output (run via `nix flake check`)
        # Individual tests can be built with: nix build .#checks.x86_64-linux.minimal-test
      };
    };
}
