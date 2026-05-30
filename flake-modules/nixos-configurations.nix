# NixOS system configurations
{
  inputs,
  config,
  self,
  ...
}: let
  inherit (inputs) nixpkgs nixos-hardware nixos-facter-modules nixos-avf copyparty nil-flake claude_yapper kokoro media-classifier org-life-coach lifecoach-organism vacuum-organism org-crm;
  inherit (config.flake.lib) mkDesktop mkServer mkHomeManager commonModules;
in {
  flake.nixosConfigurations = {
    # Dell E6400 ARG laptop
    creme = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
      modules = [
       (self + "/hosts/creme/configuration.nix")
      ];
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
          useGlobalPkgs = true;
        }
        ++ [
          inputs.jovian-nixos.nixosModules.jovian
          {nixpkgs.overlays = [inputs.jovian-nixos.overlays.default];}
          (self + "/hosts/donut/configuration.nix")
        ];
    };

    # Desktops using mkDesktop helper
    historian = mkDesktop {
      hostname = "historian";
      extraSpecialArgs = {inherit media-classifier;};
      extraModules = [media-classifier.nixosModules.default];
    };
    total-eclipse = mkDesktop {hostname = "total-eclipse";};

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
      useGlobalPkgs = true;
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
      extraSpecialArgs = {
        inherit copyparty claude_yapper kokoro;
        org_life_coach = org-life-coach;
      };
      extraModules = [
        copyparty.nixosModules.default
        claude_yapper.nixosModules.default
        org-life-coach.nixosModules.default
        lifecoach-organism.nixosModules.default
        vacuum-organism.nixosModules.default
        (self + "/hosts/rich-evans/life-coach.nix")
        (self + "/hosts/rich-evans/org-life-coach.nix")
        (self + "/hosts/rich-evans/lifecoach-organism.nix")
        (self + "/hosts/rich-evans/vacuum-organism.nix")
        org-crm.nixosModules.default
        (self + "/hosts/rich-evans/org-crm.nix")
        (self + "/hosts/rich-evans/email-digest.nix")
        (self + "/hosts/rich-evans/buildbot-master.nix")
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
          (self + "/hosts/maitred/configuration.nix")
        ];
    };
  };
}
