# NixOS system configurations
{
  inputs,
  config,
  self,
  ...
}: let
  inherit (inputs) nixpkgs nixos-hardware nixos-facter-modules copyparty nil-flake media-classifier org-life-coach org-crm lifecoach-organism vacuum-organism;
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
      extraModules = [
        media-classifier.nixosModules.default
        # Copyparty — moved from rich-evans at a3j.6 phase 6b (with the
        # seagate local since a3j.4)
        copyparty.nixosModules.default
        # org-crm — moved from rich-evans at a3j.6 cutover 9 (2026-09-11);
        # host file hosts/historian/org-crm.nix. (The org-bridge broker that
        # stayed on rich-evans was removed 2026-09-23 with the bridge crew.)
        org-crm.nixosModules.default
      ];
    };
    total-eclipse = mkDesktop {
      hostname = "total-eclipse";
      # Navigator Orlena (a bridge-crew officer) was hosted here, moved to
      # historian at a3j.9.3, and then removed 2026-09-23 along with the whole
      # bridge crew. No extraModules.
      extraModules = [];
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
      extraModules = [
        # copyparty.nixosModules.default — MOVED to historian at a3j.6 6b
        org-life-coach.nixosModules.default
        # Lifecoach + vacuum sidekick — now DIRECT flake inputs (their former
        # `bridge-crew` aggregator was removed along with the 11 character
        # bridge officers). Both are self-contained: nixosModules.default
        # resolves its own package from pkgs.system, so no extraSpecialArgs.
        lifecoach-organism.nixosModules.default
        vacuum-organism.nixosModules.default
        (self + "/hosts/rich-evans/life-coach.nix")
        (self + "/hosts/rich-evans/org-life-coach.nix")
        (self + "/hosts/rich-evans/lifecoach-organism.nix")
        (self + "/hosts/rich-evans/vacuum-organism.nix")
        # org-crm — MOVED to historian at a3j.6 cutover 9 (module in
        # historian's extraModules; host file hosts/historian/org-crm.nix).
        # The file hosts/rich-evans/org-crm.nix stays for reference, like
        # borges.nix.
        # email-digest — MOVED to historian at a3j.6 6b (imported via its
        # configuration.nix; rich-evans keeps a user/group stub).
        # Borges host module — REMOVED at a3j.5: the service moved to historian
        # (hosts/historian/borges.nix; the module file stays here for
        # reference, like buildbot-master.nix). The import must go with the
        # registry entry move — the module reads config.kimb.services.borges,
        # which now lives in the historian bucket only.
        # (self + "/hosts/rich-evans/borges.nix")
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
