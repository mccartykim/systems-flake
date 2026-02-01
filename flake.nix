{
  description = "Kimb's system flakes";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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

    claude_yapper.url = "git+ssh://git@github.com/mccartykim/claude-alarmclock-agent.git";
    claude_yapper.inputs.nixpkgs.follows = "nixpkgs";

    # Kokoro TTS - local flake for now (has working build)
    kokoro.url = "git+ssh://git@github.com/mccartykim/kokoro-flake.git";
    kokoro.inputs.nixpkgs.follows = "nixpkgs";

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    # Jovian NixOS for Steam Deck
    jovian-nixos.url = "github:Jovian-Experiments/Jovian-NixOS";
    jovian-nixos.inputs.nixpkgs.follows = "nixpkgs";
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
    jovian-nixos,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./flake-modules # Modularized flake configuration
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
        packages = lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
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
              pkgs.beads # AI-native issue tracking
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

          # Generate nebula certificates from YubiKey-encrypted CA
          # This is Option A: standalone script approach
          generate-nebula-certs = let
            registry = import ./hosts/nebula-registry.nix;
            # Hosts with both IP and publicKey can have certs generated
            # (includes oracle now that its key is in the registry)
            nebulaHosts =
              lib.filterAttrs
              (name: cfg: cfg ? ip && cfg.ip != null && cfg ? publicKey && cfg.publicKey != null)
              registry.nodes;
            bootstrapKey = registry.bootstrap;

            # Build host info as shell-parseable data
            hostData =
              lib.mapAttrsToList (name: cfg: {
                inherit name;
                ip = cfg.ip;
                groups = cfg.groups or [];
                publicKey = cfg.publicKey;
              })
              nebulaHosts;
          in {
            type = "app";
            program = toString (pkgs.writeShellScript "generate-nebula-certs" ''
              set -e

              # Parse arguments
              DRY_RUN=false
              for arg in "$@"; do
                case "$arg" in
                  --dry-run|-n)
                    DRY_RUN=true
                    ;;
                  --help|-h)
                    echo "Usage: nix run .#generate-nebula-certs [--dry-run]"
                    echo ""
                    echo "Options:"
                    echo "  --dry-run, -n  Show what would be done without making changes"
                    echo "  --help, -h     Show this help"
                    exit 0
                    ;;
                esac
              done

              cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || pwd)"

              echo "=== Nebula Certificate Generator ==="
              if $DRY_RUN; then
                echo "    [DRY RUN - no changes will be made]"
              fi
              echo ""
              echo "This script:"
              echo "  1. Decrypts the YubiKey-encrypted CA"
              echo "  2. Generates certificates for each host"
              echo "  3. Re-encrypts them with regular agenix (to host SSH keys)"
              echo ""

              # Show hosts that will be processed
              echo "Hosts from registry (with IP + publicKey):"
              ${lib.concatMapStringsSep "\n" (host: ''
                  echo "  - ${host.name}: ${host.ip}/16, groups=[${lib.concatStringsSep "," host.groups}]"
                '')
                hostData}
              echo ""

              echo "Files that will be created/updated:"
              ${lib.concatMapStringsSep "\n" (host: ''
                  echo "  - secrets/nebula-${host.name}-cert.age (encrypted to ${host.name} + bootstrap)"
                  echo "  - secrets/nebula-${host.name}-key.age (encrypted to ${host.name} + bootstrap)"
                '')
                hostData}
              echo "  - secrets/nebula-ca.age (CA cert only, encrypted to all hosts)"
              echo ""

              if $DRY_RUN; then
                echo "=== Dry run complete ==="
                echo "Run without --dry-run to actually generate certificates."
                exit 0
              fi

              echo "Requirements: YubiKey with age identity must be plugged in"
              echo ""

              # Check for required tools
              command -v ${pkgs.age}/bin/age >/dev/null || { echo "Error: age not found"; exit 1; }
              command -v ${pkgs.nebula}/bin/nebula-cert >/dev/null || { echo "Error: nebula-cert not found"; exit 1; }

              # Create temp directory for working files
              TMPDIR=$(mktemp -d)
              trap "rm -rf $TMPDIR" EXIT

              # Decrypt CA from YubiKey-encrypted file
              echo "Decrypting CA (touch YubiKey if prompted)..."
              CA_FILE="secrets/nebula-ca-master.age"
              if [ ! -f "$CA_FILE" ]; then
                echo "Error: $CA_FILE not found"
                echo "Make sure you've encrypted the CA with YubiKeys first"
                exit 1
              fi

              # age-plugin-yubikey must be in PATH for age to find it
              export PATH="${pkgs.age-plugin-yubikey}/bin:$PATH"

              # Decrypt using YubiKey identity files (plugin needs explicit identity)
              ${pkgs.age}/bin/age -d \
                -i "${builtins.toString ./secrets/identities/yubikey-1.pub}" \
                -i "${builtins.toString ./secrets/identities/yubikey-2.pub}" \
                "$CA_FILE" > "$TMPDIR/ca-combined.pem" || {
                echo "Error: Failed to decrypt CA. Is your YubiKey plugged in?"
                echo "Make sure age-plugin-yubikey is available (enter nix develop first)"
                exit 1
              }

              # Split CA into key and cert
              ${pkgs.gnused}/bin/sed -n '1,/END NEBULA ED25519 PRIVATE KEY/p' "$TMPDIR/ca-combined.pem" > "$TMPDIR/ca.key"
              ${pkgs.gnused}/bin/sed -n '/BEGIN NEBULA CERTIFICATE/,/END NEBULA CERTIFICATE/p' "$TMPDIR/ca-combined.pem" > "$TMPDIR/ca.crt"

              echo "CA decrypted successfully!"
              echo ""

              # Bootstrap key for re-encryption
              BOOTSTRAP_KEY="${bootstrapKey}"

              # Generate certs for each host
              ${lib.concatMapStringsSep "\n" (host: ''
                  echo "Generating certificate for ${host.name}..."
                  HOST_NAME="${host.name}"
                  HOST_IP="${host.ip}"
                  HOST_GROUPS="${lib.concatStringsSep "," host.groups}"
                  HOST_PUBKEY="${host.publicKey}"

                  # Generate cert and key
                  ${pkgs.nebula}/bin/nebula-cert sign \
                    -ca-crt "$TMPDIR/ca.crt" \
                    -ca-key "$TMPDIR/ca.key" \
                    -name "$HOST_NAME" \
                    -ip "$HOST_IP/16" \
                    -groups "$HOST_GROUPS" \
                    -out-crt "$TMPDIR/$HOST_NAME.crt" \
                    -out-key "$TMPDIR/$HOST_NAME.key"

                  # Re-encrypt cert with agenix (to host key + bootstrap)
                  ${pkgs.age}/bin/age -r "$HOST_PUBKEY" -r "$BOOTSTRAP_KEY" \
                    -o "secrets/nebula-$HOST_NAME-cert.age" \
                    "$TMPDIR/$HOST_NAME.crt"

                  # Re-encrypt key with agenix (to host key + bootstrap)
                  ${pkgs.age}/bin/age -r "$HOST_PUBKEY" -r "$BOOTSTRAP_KEY" \
                    -o "secrets/nebula-$HOST_NAME-key.age" \
                    "$TMPDIR/$HOST_NAME.key"

                  echo "  ✓ secrets/nebula-$HOST_NAME-cert.age"
                  echo "  ✓ secrets/nebula-$HOST_NAME-key.age"
                  echo ""
                '')
                hostData}

              # Update the shared CA cert (public part only, for all hosts)
              echo "Updating shared CA certificate..."
              ${pkgs.age}/bin/age \
                ${lib.concatMapStringsSep " " (host: "-r \"${host.publicKey}\"") hostData} \
                -r "$BOOTSTRAP_KEY" \
                -o "secrets/nebula-ca.age" \
                "$TMPDIR/ca.crt"
              echo "  ✓ secrets/nebula-ca.age"
              echo ""

              echo "=== Done! ==="
              echo ""
              echo "Generated certificates are encrypted with regular agenix."
              echo "They can be decrypted by each host's SSH key."
              echo ""
              echo "Next steps:"
              echo "  1. Review the changes: jj diff"
              echo "  2. Commit: jj describe -m 'chore: regenerate nebula certificates'"
              echo "  3. Deploy: nix develop -c colmena apply"
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
