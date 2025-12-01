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

    # agenix-rekey for YubiKey master identity + declarative cert generation
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";

    # System-manager for non-NixOS hosts (e.g., Oracle VM lighthouse)
    system-manager.url = "github:numtide/system-manager";
    system-manager.inputs.nixpkgs.follows = "nixpkgs";

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
    agenix-rekey,
    nixos-facter-modules,
    system-manager,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        agenix-rekey.flakeModules.default
        ./flake-modules  # Modularized flake configuration
      ];

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
              pkgs.age # age encryption tool
              pkgs.age-plugin-yubikey # YubiKey support for age encryption
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

      # All flake outputs (nixosConfigurations, darwinConfigurations, colmena, systemConfigs)
      # are now defined in ./flake-modules/
    };
}
