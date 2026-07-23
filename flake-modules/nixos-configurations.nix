# NixOS system configurations
{
  inputs,
  config,
  self,
  ...
}: let
  inherit (inputs) nixpkgs nixos-hardware nixos-facter-modules copyparty nil-flake media-classifier org-life-coach lifecoach-organism vacuum-organism org-crm organism void-master-organism factotum-organism confessor-organism explorator-organism chirurgeon-organism navigator-organism;
  inherit (config.flake.lib) mkDesktop mkServer mkHomeManager commonModules;
in {
  flake.nixosConfigurations = {
    # Dell E6400 ATG writerdeck — console-only network appliance
    creme = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
      modules =
        commonModules
        ++ [(self + "/hosts/creme/configuration.nix")];
    };

    # Surface 3 Go tablet
    cheesecake = mkDesktop {
      hostname = "cheesecake";
      hardwareModules = [
        nixos-facter-modules.nixosModules.facter
        {config.facter.reportPath = self + "/hosts/cheesecake/facter.json";}
      ];
    };

    # Steam Deck (Jovian NixOS)
    donut = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
      modules =
        commonModules
        ++ mkHomeManager {
          homeConfig = self + "/home/donut.nix";
        }
        ++ [
          # jovian module applies its own overlay internally — no need to add it again
          inputs.jovian-nixos.nixosModules.jovian
          (self + "/hosts/donut/configuration.nix")
        ];
    };

    # Desktops using mkDesktop helper
    historian = mkDesktop {
      hostname = "historian";
      extraModules = [media-classifier.nixosModules.default];
    };
    total-eclipse = mkDesktop {
      hostname = "total-eclipse";
      # Navigator Orlena — the cross-host read-only strategic planner (#49).
      # Self-contained module (provides its own package, mirroring the other
      # officers) + the config-only host file. No extraSpecialArgs needed.
      extraModules = [
        navigator-organism.nixosModules.default
        (self + "/hosts/total-eclipse/navigator-organism.nix")
      ];
    };

    marshmallow = mkDesktop {
      hostname = "marshmallow";
      hardwareModules = [
        nixos-hardware.nixosModules.lenovo-thinkpad-t490
        inputs.srvos.nixosModules.mixins-terminfo
        inputs.srvos.nixosModules.mixins-systemd-boot
      ];
    };

    bartleby = mkDesktop {
      hostname = "bartleby";
      hardwareModules = [
        nixos-hardware.nixosModules.lenovo-thinkpad
        inputs.srvos.nixosModules.mixins-systemd-boot
      ];
      extraModules = [
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
      # bridgeCrewSrc (40k_bridge source, flake=false) is consumed by the
      # imported org-bridge module (takes it as a module arg). `organism` is
      # consumed by the voidmaster-vox-bridge host file for organicBin.
      # `inputs` (already passed by mkServer) reaches the org-bridge host
      # file for org-agent's emacs + elisp.
      extraSpecialArgs = {
        inherit organism;
        bridgeCrewSrc = inputs."bridge-crew-src";
      };
      extraModules = [
        copyparty.nixosModules.default
        org-life-coach.nixosModules.default
        lifecoach-organism.nixosModules.default
        vacuum-organism.nixosModules.default
        # Phase-1 bridge crew: the Void-Master officer agent (self-contained
        # module from the voidmaster_organism flake) + the org-bridge broker
        # + vox-bridge Matrix transport (imported from the 40k_bridge source
        # tree). See 40k_bridge/deploy/SYSTEMS_FLAKE_PATCH.md.
        void-master-organism.nixosModules.default
        # High Factotum officer agent (Severin, read-only bookkeeper).
        # Self-contained module from the factotum_organism flake — it
        # resolves its own package from pkgs.system, so it needs NO
        # extraSpecialArgs (unlike org-bridge/vox-bridge which take
        # bridgeCrewSrc/organism). Consequently NO colmena meta.specialArgs
        # change is required (the prior colmena break was a missing
        # specialArgs; this module adds none).
        factotum-organism.nixosModules.default
        # Ship's Confessor officer agent (Aurelian, read-only fleet
        # chronicler). Self-contained module from the confessor_organism
        # flake — resolves its own package from pkgs.system, so it needs
        # NO extraSpecialArgs and NO colmena meta.specialArgs change
        # (same shape as the Factotum).
        confessor-organism.nixosModules.default
        # Magos Explorator officer agent (Velan, read-only machine-spirit
        # diagnostician). Self-contained module from the explorator_organism
        # flake — resolves its own package from pkgs.system, so it needs NO
        # extraSpecialArgs and NO colmena meta.specialArgs change (same shape
        # as the Confessor / Factotum).
        explorator-organism.nixosModules.default
        # Chirurgeon Vahan (ship's Medicae, household axis) — the 9th bridge
        # officer (#62). Self-contained module from the chirurgeon_organism
        # flake — resolves its own package from pkgs.system, so it needs NO
        # extraSpecialArgs and NO colmena meta.specialArgs change (same shape
        # as the Confessor / Factotum / Explorator).
        chirurgeon-organism.nixosModules.default
        (import "${inputs."bridge-crew-src"}/deploy/org-bridge.nix")
        (import "${inputs."bridge-crew-src"}/deploy/vox-bridge.nix")
        # Phase-2 vox-organism: the Astropath comms-bridge daemon (replaces the
        # Phase-1 voidmaster-vox-bridge above). Takes bridgeCrewSrc as a module
        # arg (threaded via specialArgs) to read the daemon script + seed
        # sample straight from the 40k_bridge source tree. See
        # 40k_bridge/deploy/vox-organism.nix.
        (import "${inputs."bridge-crew-src"}/deploy/vox-organism.nix")
        (self + "/hosts/rich-evans/life-coach.nix")
        (self + "/hosts/rich-evans/org-life-coach.nix")
        (self + "/hosts/rich-evans/lifecoach-organism.nix")
        (self + "/hosts/rich-evans/vacuum-organism.nix")
        (self + "/hosts/rich-evans/voidmaster-organism.nix")
        (self + "/hosts/rich-evans/voidmaster-vox-bridge.nix")
        (self + "/hosts/rich-evans/vox-organism.nix")
        (self + "/hosts/rich-evans/factotum-organism.nix")
        (self + "/hosts/rich-evans/confessor-organism.nix")
        (self + "/hosts/rich-evans/explorator-organism.nix")
        (self + "/hosts/rich-evans/chirurgeon-organism.nix")
        (self + "/hosts/rich-evans/org-bridge.nix")
        org-crm.nixosModules.default
        (self + "/hosts/rich-evans/org-crm.nix")
        (self + "/hosts/rich-evans/email-digest.nix")
        (self + "/hosts/rich-evans/borges.nix")
        # Buildbot master — DISABLED 2026-06-22 (gave up on buildbot-nix
        # fighting private-repo flake inputs; may revisit a different CI
        # scheme later). Re-enable by uncommenting; the module file
        # (hosts/rich-evans/buildbot-master.nix) is left intact.
        # (self + "/hosts/rich-evans/buildbot-master.nix")
      ];
    };

    # Router (custom - no srvos server, has specific networking needs)
    maitred = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
      modules =
        commonModules
        ++ [
          {
            kimb = {
              domain = "kimb.dev";
              admin = {
                name = "kimb";
                email = "mccartykim@zoho.com";
                displayName = "Kimberly";
              };
              networks = {
                containerBridge = "192.168.100.1";
                reverseProxyIP = "192.168.100.2";
                trustedNetworks = ["192.168.0.0/16" "10.100.0.0/16"];
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
          (self + "/hosts/maitred/configuration.nix")
        ];
    };
  };
}
