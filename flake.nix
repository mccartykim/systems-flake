{
  description = "Kimb's system flakes";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Nixpkgs pinned to ollama 0.30.5 for gemma4:12b support (0.30.4 crashes on 12b).
    # Remove this input once nixpkgs-unstable has ollama >= 0.30.5.
    nixpkgs-ollama.url = "github:NixOS/nixpkgs/bba51cb2479b7a23134f69b932811df999b892e1";

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

    # buildbot-nix for CI (master on rich-evans, worker on historian)
    buildbot-nix.url = "github:nix-community/buildbot-nix";
    buildbot-nix.inputs.nixpkgs.follows = "nixpkgs";

    # System-manager for non-NixOS hosts (e.g., Oracle VM lighthouse)
    system-manager.url = "github:numtide/system-manager";
    system-manager.inputs.nixpkgs.follows = "nixpkgs";

    # All private mccartykim/* inputs use git+https:// so the buildbot
    # worker's PAT (in /var/lib/buildbot-worker/.netrc) can authenticate
    # the fetch. ssh:// would need an SSH key on the worker, which we
    # don't have wired up; the github: short-form would use the
    # archive/<rev>.tar.gz URL, which fine-grained PATs cannot read.
    # git+https:// is the scheme that works with our existing auth.
    mist-blog.url = "git+ssh://git@github.com/mccartykim/mist-blog.git";
    mist-blog.inputs.nixpkgs.follows = "nixpkgs";

    # Private blog content tree (not a flake — just markdown sources).
    # Consumed by services.mist-blog via BLOG_CONTENT_DIR.
    kimb-blog-content.url = "git+ssh://git@github.com/mccartykim/kimb-blog-content.git";
    kimb-blog-content.flake = false;

    claude_yapper.url = "git+ssh://git@github.com/mccartykim/claude-alarmclock-agent.git";
    claude_yapper.inputs.nixpkgs.follows = "nixpkgs";

    # Kokoro TTS - local flake for now (has working build)
    kokoro.url = "git+ssh://git@github.com/mccartykim/kokoro-flake.git";
    kokoro.inputs.nixpkgs.follows = "nixpkgs";

    # Media classifier for Jellyfin library organization
    media-classifier.url = "git+ssh://git@github.com/mccartykim/media-classifier.git";
    media-classifier.inputs.nixpkgs.follows = "nixpkgs";

    # org-agent + org-life-coach (replaces claude_yapper life-coach)
    org-agent.url = "git+ssh://git@github.com/mccartykim/org-agent.git";
    org-agent.inputs.nixpkgs.follows = "nixpkgs";
    org-life-coach = {
      url = "git+ssh://git@github.com/mccartykim/org-life-coach.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        org-agent.follows = "org-agent";
      };
    };
    lifecoach-organism.url = "git+ssh://git@github.com/mccartykim/lifecoach_organism.git";
    lifecoach-organism.inputs.nixpkgs.follows = "nixpkgs";
    vacuum-organism.url = "git+ssh://git@github.com/mccartykim/vacuum_organism.git";
    vacuum-organism.inputs.nixpkgs.follows = "nixpkgs";
    org-crm = {
      url = "git+ssh://git@github.com/mccartykim/org_crm.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        org-agent.follows = "org-agent";
      };
    };

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    # Eden nightly (Switch emulator from upstream master)
    eden-nightly-flake.url = "github:mccartykim/eden-nightly-flake";
    eden-nightly-flake.inputs.nixpkgs.follows = "nixpkgs";

    # Jovian NixOS for Steam Deck
    jovian-nixos.url = "github:Jovian-Experiments/Jovian-NixOS";
    jovian-nixos.inputs.nixpkgs.follows = "nixpkgs";

    # Qwen3-TTS CUDA inference server (faster-qwen3-tts via uv2nix).
    qwen3-tts-cuda.url = "git+ssh://git@github.com/mccartykim/qwen3-tts-cuda-flake.git";
    qwen3-tts-cuda.inputs.nixpkgs.follows = "nixpkgs";

    # Generic restic-to-B2 backup module. systems-flake personalizes it
    # in modules/restic-backup.nix with kimb-specific paths + repo + secrets.
    restic-b2-backup.url = "git+ssh://git@github.com/mccartykim/restic-b2-backup-flake.git";

    # Generic Cloudflare dynamic DNS (inadyn) module. systems-flake
    # personalizes it in hosts/maitred/dns-update.nix with the kimb.dev
    # zone + agenix-managed API token.
    cloudflare-ddns.url = "git+ssh://git@github.com/mccartykim/cloudflare-ddns-flake.git";

    # Firefox Nightly
    firefox-nightly.url = "github:nix-community/flake-firefox-nightly";
    firefox-nightly.inputs.nixpkgs.follows = "nixpkgs";

    # Infrastructure/network diagram generator from NixOS configs
    nix-topology.url = "github:oddlama/nix-topology";
    nix-topology.inputs.nixpkgs.follows = "nixpkgs";

    # Doom Emacs as a Nix derivation — built once on historian/marshmallow,
    # creme substitutes from binary cache. Eliminates per-host doom sync.
    # Cachix substituter (doom-emacs-unstraightened.cachix.org) is wired in
    # creme's config; user doomdir lives at hosts/creme/doom.d/.
    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "nixpkgs";

    # Stylix: derives a base16 colorscheme from a wallpaper image and
    # applies it across the desktop (gtk, qt, terminals, vim, etc.).
    # Wallpaper itself is built locally from the PDX-carpet SVG via
    # pkgs/pdx-wallpaper.
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.inputs.home-manager.follows = "home-manager";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-ollama,
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
    eden-nightly-flake,
    nix-topology,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./flake-modules # Modularized flake configuration
        nix-topology.flakeModule
      ];

      systems = ["x86_64-linux" "aarch64-linux"];

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
        topology.modules = [
          ./topology.nix
        ];

        # Per-system packages
        packages = lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
          # ESPHome firmware builds (exposed at top level for convenience)
          esp32-cam-01-firmware = pkgs.callPackage ./pkgs/esp32-firmware.nix {};

          # Warewoolf: minimalist Electron novel-writing app.
          # Uses nixpkgs's default `electron` (latest stable) — upstream's
          # `electron ^18` constraint in package.json is long EOL and we
          # skip the bundled download via ELECTRON_SKIP_BINARY_DOWNLOAD.
          warewoolf = pkgs.callPackage ./pkgs/warewoolf {};

          # Custom-patched libreboot for Dell Latitude E6400 with nic3-14159's
          # mec5035-acpi commits (battery + AC + brightness Fn keys). See
          # pkgs/libreboot-e6400-mec5035/default.nix for the full story.
          libreboot-e6400-mec5035 = pkgs.callPackage ./pkgs/libreboot-e6400-mec5035 {};
        };

        # Formatter
        formatter = pkgs.alejandra;

        # Dev shells
        devShells = let
          # Repo-specific CLI tools only available inside the systems-flake devShell
          shellApps = [
            # flu: nix flake update + auto-describe
            # Usage: flu nixpkgs → updates nixpkgs input, commits "chore: flake bump nixpkgs"
            #        flu          → updates all inputs, commits "chore: flake lock update"
            (pkgs.writeShellApplication {
              name = "flu";
              runtimeInputs = [pkgs.nix];
              text = ''
                if [ $# -ge 1 ]; then
                  nix flake update "$1" && jj desc -m "chore: flake bump $1"
                else
                  nix flake update && jj desc -m "chore: flake lock update"
                fi
              '';
            })

            # deploy: colmena deploy shorthand
            # Usage: deploy historian         → colmena apply --on historian
            #        deploy historian,maitred → colmena apply --on historian,maitred
            (pkgs.writeShellApplication {
              name = "deploy";
              runtimeInputs = [pkgs.colmena];
              text = ''
                colmena apply --on "$@"
              '';
            })

            # nb: nix build piped through nom
            # Usage: nb .#nixosConfigurations.historian → nix build .#nixosConfigurations.historian 2>&1 | nom
            (pkgs.writeShellApplication {
              name = "nb";
              runtimeInputs = [pkgs.nix pkgs.nix-output-monitor];
              text = ''
                nix build "$@" 2>&1 | nom
              '';
            })

            # nswitch: nh os switch shorthand
            # Usage: nswitch historian → nh os switch .#nixosConfigurations.historian
            #        nswitch historian --target-host historian.nebula
            (pkgs.writeShellApplication {
              name = "nswitch";
              runtimeInputs = [pkgs.nh];
              text = ''
                host="$1"; shift
                nh os switch ".#nixosConfigurations.$host" "$@"
              '';
            })

            # nbuild: nh os build shorthand
            # Usage: nbuild historian → nh os build .#nixosConfigurations.historian
            (pkgs.writeShellApplication {
              name = "nbuild";
              runtimeInputs = [pkgs.nh];
              text = ''
                host="$1"; shift
                nh os build ".#nixosConfigurations.$host" "$@"
              '';
            })
          ];
        in lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
          default = pkgs.mkShell {
            packages =
              [
                pkgs.tealdeer
                pkgs.colmena
                pkgs.esphome # ESP32/ESP8266 firmware builder
                pkgs.esptool # ESP32/ESP8266 flasher
                pkgs.age # age encryption tool
                pkgs.age-plugin-yubikey # YubiKey support for age encryption
                pkgs.beads # AI-native issue tracking
                pkgs.nix-output-monitor # nom - for nb command
              ]
              ++ shellApps;
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
                inherit (cfg) ip;
                groups = cfg.groups or [];
                inherit (cfg) publicKey;
              })
              nebulaHosts;
          in {
            type = "app";
            program = toString (
              import ./scripts/generate-nebula-certs.nix {
                inherit pkgs lib hostData bootstrapKey;
              }
            );
          };
        };

        # Flake checks - runs via `nix flake check`
        checks = lib.optionalAttrs (system == "x86_64-linux") {
          # VM tests
          minimal-test = import ./tests/minimal-test.nix {inherit pkgs;};
          network-test = import ./tests/network-test.nix {inherit pkgs;};
          working-vm-test = import ./tests/working-vm-test.nix {inherit pkgs;};

          # Configuration evaluation tests (fast - no VM)
          # buildbot-nix builds every .#checks attr on each commit, so adding a
          # host's toplevel here means CI will catch breakage for that host.

          # Fish functions eval check: verifies the fish-functions module produces
          # the expected function definitions. Runs in seconds, no VM needed.
          eval-fish-functions =
            let
              # Test the module in isolation with includeJjPrompt = true
              testConfig = {
                imports = [./home/modules/fish-functions.nix];
                modules.fish-functions = {
                  enable = true;
                  includeJjPrompt = true;
                };
                programs.fish.enable = true;
                home.username = "test";
                home.homeDirectory = "/home/test";
                home.stateVersion = "24.11";
                programs.home-manager.enable = true;
              };
              hmLib = inputs.home-manager.lib;
              eval = hmLib.homeManagerConfiguration {
                pkgs = pkgs;
                modules = [testConfig];
              };
              functions = eval.config.programs.fish.functions;
              # Verify each function body contains the expected substring
              expectedSubstrings = {
                jd = "jj desc -m";
                nr = "nix run nixpkgs";
                ns = "nix shell nixpkgs";
                nru = "NIXPKGS_ALLOW_UNFREE";
                nsu = "NIXPKGS_ALLOW_UNFREE";
                cb = "fish_clipboard_copy";
                fish_jj_prompt = "jj log";
                fish_vcs_prompt = "fish_jj_prompt";
              };
              # Build a list of (name, expected, actual) for any mismatches
              mismatches = lib.filter
                (m: m != null)
                (lib.mapAttrsToList (name: expected:
                  if lib.hasInfix expected (functions.${name} or "")
                  then null
                  else {inherit name expected; actual = functions.${name} or "(missing)";})
                expectedSubstrings);
            in
              pkgs.runCommand "eval-fish-functions" {} ''
                ${lib.concatMapStrings (m: ''
                  echo "FAIL: ${m.name} expected '${m.expected}' in '${m.actual}'"
                '') mismatches}
                ${if mismatches == []
                  then "echo 'All ${toString (builtins.length (builtins.attrNames expectedSubstrings))} fish functions verified' > $out"
                  else "echo 'FAIL: ${toString (builtins.length mismatches)} function(s) mismatched' >&2; exit 1"
                }
              '';

          # Fish syntax validation: runs fish --no-execute on the generated
          # config to catch syntax errors that string checks would miss.
          eval-fish-syntax =
            let
              testConfig = {
                imports = [./home/modules/fish-functions.nix];
                modules.fish-functions = {
                  enable = true;
                  includeJjPrompt = true;
                };
                programs.fish.enable = true;
                home.username = "test";
                home.homeDirectory = "/home/test";
                home.stateVersion = "24.11";
                programs.home-manager.enable = true;
              };
              hmLib = inputs.home-manager.lib;
              eval = hmLib.homeManagerConfiguration {
                pkgs = pkgs;
                modules = [testConfig];
              };
              # Collect all generated fish function files
              fishFiles = eval.config.home.file;
              # Get the generated fish config directory
              fishFuncDir = "${eval.config.xdg.configFile."fish/functions".source or eval.config.programs.fish.functions}";
            in
              pkgs.runCommand "eval-fish-syntax" {
                nativeBuildInputs = [pkgs.fish];
              } ''
                # Validate each function definition by sourcing it with fish --no-execute
                errors=0
                ${lib.concatStrings (lib.mapAttrsToList (name: body: ''
                  # Write function to a temp file and validate syntax
                  cat > function_test.fish << 'FISHEOF'
                  function ${name}
                    ${body}
                  end
                  FISHEOF
                  if ! fish --no-execute function_test.fish 2>&1; then
                    echo "FAIL: fish syntax error in function '${name}'"
                    errors=$((errors + 1))
                  else
                    echo "OK: ${name}"
                  fi
                  rm function_test.fish
                '') eval.config.programs.fish.functions)}

                if [ $errors -gt 0 ]; then
                  echo "FAIL: $errors function(s) had syntax errors"
                  exit 1
                fi
                echo "All fish functions passed syntax validation" > $out
              '';

          eval-historian = self.nixosConfigurations.historian.config.system.build.toplevel;
          eval-marshmallow = self.nixosConfigurations.marshmallow.config.system.build.toplevel;
          eval-bartleby = self.nixosConfigurations.bartleby.config.system.build.toplevel;
          eval-total-eclipse = self.nixosConfigurations.total-eclipse.config.system.build.toplevel;
          eval-maitred = self.nixosConfigurations.maitred.config.system.build.toplevel;
          eval-rich-evans = self.nixosConfigurations.rich-evans.config.system.build.toplevel;
          eval-cheesecake = self.nixosConfigurations.cheesecake.config.system.build.toplevel;
          eval-donut = self.nixosConfigurations.donut.config.system.build.toplevel;
          eval-creme = self.nixosConfigurations.creme.config.system.build.toplevel;
        };
      };

      # All flake outputs (nixosConfigurations, darwinConfigurations, colmena, systemConfigs)
      # are now defined in ./flake-modules/
    };
}
