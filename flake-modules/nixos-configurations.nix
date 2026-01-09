# NixOS system configurations
{
  inputs,
  config,
  self,
  ...
}: let
  inherit (inputs) nixpkgs nixos-hardware nixos-facter-modules nixos-avf copyparty nil-flake claude_yapper kokoro;
  inherit (config.flake.lib) mkDesktop mkServer mkHomeManager commonModules;
in {
  flake.nixosConfigurations = {
    # Surface 3 Go tablet
    cheesecake = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
      modules =
        commonModules
        ++ mkHomeManager {
          homeConfig = self + "/home/cheesecake.nix";
          useGlobalPkgs = true;
        }
        ++ [
          nixos-facter-modules.nixosModules.facter
          {config.facter.reportPath = self + "/hosts/cheesecake/facter.json";}
          (self + "/hosts/cheesecake/configuration.nix")
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
    historian = mkDesktop {hostname = "historian";};
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
        (self + "/modules/kimb-services.nix")
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
      extraSpecialArgs = {inherit copyparty claude_yapper kokoro;};
      extraModules = [
        copyparty.nixosModules.default
        claude_yapper.nixosModules.default
        (self + "/modules/kimb-services.nix")
        (self + "/hosts/rich-evans/life-coach.nix")
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
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
      modules =
        commonModules
        ++ [
          (self + "/modules/kimb-services.nix")
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
                cert-service = {
                  enable = true;
                  port = 8444;
                  subdomain = "certs";
                  host = "maitred";
                  auth = "builtin"; # Bearer token handled by service, not Authelia
                  publicAccess = true;
                  websockets = false;
                };
                homeassistant = {
                  enable = true;
                  port = 8123;
                  subdomain = "hass";
                  host = "rich-evans";
                  auth = "builtin"; # HA handles its own auth
                  publicAccess = true;
                  websockets = true; # Required for HA frontend
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
          (self + "/hosts/maitred/configuration.nix")
        ];
    };
  };
}
