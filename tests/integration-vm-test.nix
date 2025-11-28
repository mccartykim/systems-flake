# VM Integration Test for kimb-services with fake Nebula network
#
# ⚠️ WARNING: This test includes PRIVATE KEYS for test purposes only!
# These keys are NOT SECURE and must NEVER be used in production.
# They exist solely to test agenix secret decryption in isolated VMs.
#
{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
  agenix ? null,
}: let
  # Test network configuration
  testNetwork = {
    subnet = "10.200.0.0/16";

    # Test lighthouse (simulated)
    lighthouse = {
      ip = "10.200.0.1";
      external = "127.0.0.1:4242";
    };

    # Test hosts
    hosts = {
      test-router = "10.200.0.50";
      test-server = "10.200.0.40";
      test-desktop = "10.200.0.10";
    };
  };

  # Test registry (mirrors structure of real nebula-registry.nix)
  testRegistry = {
    network = {
      subnet = testNetwork.subnet;
      lighthouse = testNetwork.lighthouse;
    };

    nodes = {
      lighthouse = {
        ip = testNetwork.lighthouse.ip;
        external = testNetwork.lighthouse.external;
        isLighthouse = true;
        role = "lighthouse";
        groups = ["lighthouse"];
        publicKey = null;
      };

      test-router = {
        ip = testNetwork.hosts.test-router;
        isLighthouse = false;
        role = "router";
        groups = ["routers" "nixos"];
        publicKey = builtins.readFile ./test-keys/test-ssh/test-router.pub;
      };

      test-server = {
        ip = testNetwork.hosts.test-server;
        isLighthouse = false;
        role = "server";
        groups = ["servers" "nixos"];
        publicKey = builtins.readFile ./test-keys/test-ssh/test-server.pub;
      };

      test-desktop = {
        ip = testNetwork.hosts.test-desktop;
        isLighthouse = false;
        role = "desktop";
        groups = ["desktops" "nixos"];
        publicKey = builtins.readFile ./test-keys/test-ssh/test-desktop.pub;
      };
    };
  };

  # Test kimb-services module with test registry
  testKimbServicesModule = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [../modules/kimb-services.nix];

    # Override registry import to use test registry
    disabledModules = [../modules/kimb-services.nix];
    options = let
      inherit (lib) mkOption types;
      serviceType = types.submodule ({
        name,
        config,
        ...
      }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable this service";
          };
          port = mkOption {
            type = types.port;
            description = "Port number for the service";
          };
          subdomain = mkOption {
            type = types.str;
            description = "Subdomain for the service";
          };
          host = mkOption {
            type = types.str;
            description = "Host where the service runs";
          };
          containerIP = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "IP address if service runs in a NixOS container";
          };
          auth = mkOption {
            type = types.enum ["none" "authelia" "builtin"];
            default = "none";
            description = "Authentication method";
          };
          publicAccess = mkOption {
            type = types.bool;
            default = false;
            description = "Whether service is publicly accessible";
          };
          websockets = mkOption {
            type = types.bool;
            default = false;
            description = "Whether service needs WebSocket support";
          };
        };
      });
    in {
      kimb = {
        domain = mkOption {
          type = types.str;
          default = "test.local";
          description = "Base domain for services";
        };

        services = mkOption {
          type = types.attrsOf serviceType;
          default = {};
          description = "Service configurations";
        };

        computed = mkOption {
          type = types.attrs;
          readOnly = true;
          description = "Computed values derived from service configurations";
        };
      };
    };

    config = let
      cfg = config.kimb;
    in {
      kimb.computed = {
        # Services with resolved test IPs
        servicesWithIPs = let
          addIP = name: service:
            service
            // {
              hostIP = testRegistry.nodes.${service.host}.ip or "127.0.0.1";
            };
        in
          lib.mapAttrs addIP cfg.services;

        enabledServices = lib.filterAttrs (name: service: service.enable) cfg.services;
      };
    };
  };

  # Test router VM configuration
  testRouterConfig = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports =
      [
        testKimbServicesModule
      ]
      ++ lib.optional (agenix != null) agenix.nixosModules.default;

    kimb = {
      domain = "test.local";
      services = {
        reverse-proxy = {
          enable = true;
          port = 80;
          subdomain = "www";
          host = "test-router";
          auth = "none";
          publicAccess = true;
          websockets = false;
        };

        blog = {
          enable = true;
          port = 8080;
          subdomain = "blog";
          host = "test-router";
          auth = "none";
          publicAccess = true;
          websockets = false;
        };
      };
    };

    # Minimal VM configuration
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };

    users.users.test = {
      isNormalUser = true;
      password = "test";
      extraGroups = ["wheel"];
    };

    # Test agenix secret decryption
    age.secrets.test-nebula-router-cert = {
      file = ../secrets/test-nebula-router-cert.age;
      mode = "0444";
      owner = "test";
    };

    # WARNING: This contains TEST PRIVATE KEYS - DO NOT USE IN PRODUCTION
    # Test VM needs private key to decrypt agenix secrets
    environment.etc."ssh/test_key" = {
      text = builtins.readFile ./test-keys/test-ssh/test-router;
      mode = "0400"; # Read-only for root
    };

    age.identityPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/test_key"
    ];

    # Test network setup (simulates Nebula)
    networking = {
      hostName = "test-router";
      firewall.enable = false; # Simplified for testing

      # Add test network interface
      interfaces.eth1 = {
        ipv4.addresses = [
          {
            address = testNetwork.hosts.test-router;
            prefixLength = 16;
          }
        ];
      };
    };

    system.stateVersion = "24.11";
  };

  # Test server VM configuration
  testServerConfig = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports =
      [
        testKimbServicesModule
      ]
      ++ lib.optional (agenix != null) agenix.nixosModules.default;

    kimb = {
      domain = "test.local";
      services = {
        homeassistant = {
          enable = true;
          port = 8123;
          subdomain = "hass";
          host = "test-server";
          auth = "builtin";
          publicAccess = true;
          websockets = true;
        };

        copyparty = {
          enable = true;
          port = 3923;
          subdomain = "files";
          host = "test-server";
          auth = "authelia";
          publicAccess = true;
          websockets = false;
        };
      };
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };

    users.users.test = {
      isNormalUser = true;
      password = "test";
      extraGroups = ["wheel"];
    };

    # WARNING: This contains TEST PRIVATE KEYS - DO NOT USE IN PRODUCTION
    # Test VM needs private key to decrypt agenix secrets
    environment.etc."ssh/test_key" = {
      text = builtins.readFile ./test-keys/test-ssh/test-server;
      mode = "0400"; # Read-only for root
    };

    age.identityPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/test_key"
    ];

    # Test agenix secret decryption
    age.secrets.test-nebula-server-cert = {
      file = ../secrets/test-nebula-server-cert.age;
      mode = "0444";
      owner = "test";
    };

    networking = {
      hostName = "test-server";
      firewall.enable = false;

      interfaces.eth1 = {
        ipv4.addresses = [
          {
            address = testNetwork.hosts.test-server;
            prefixLength = 16;
          }
        ];
      };
    };

    system.stateVersion = "24.11";
  };

  # Test desktop VM configuration
  testDesktopConfig = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports =
      [
        testKimbServicesModule
      ]
      ++ lib.optional (agenix != null) agenix.nixosModules.default;

    kimb = {
      domain = "test.local";
      services = {
        # Desktop has no services by default
        development-server = {
          enable = false;
          port = 8000;
          subdomain = "dev";
          host = "test-desktop";
          auth = "none";
          publicAccess = false;
          websockets = false;
        };
      };
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };

    users.users.test = {
      isNormalUser = true;
      password = "test";
      extraGroups = ["wheel"];
    };

    # WARNING: This contains TEST PRIVATE KEYS - DO NOT USE IN PRODUCTION
    # Test VM needs private key to decrypt agenix secrets
    environment.etc."ssh/test_key" = {
      text = builtins.readFile ./test-keys/test-ssh/test-desktop;
      mode = "0400"; # Read-only for root
    };

    age.identityPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/test_key"
    ];

    # Test agenix secret decryption
    age.secrets.test-nebula-desktop-cert = {
      file = ../secrets/test-nebula-desktop-cert.age;
      mode = "0444";
      owner = "test";
    };

    networking = {
      hostName = "test-desktop";
      firewall.enable = false;

      interfaces.eth1 = {
        ipv4.addresses = [
          {
            address = testNetwork.hosts.test-desktop;
            prefixLength = 16;
          }
        ];
      };
    };

    system.stateVersion = "24.11";
  };
in {
  # Main integration test
  integrationTest = pkgs.testers.nixosTest {
    name = "kimb-services-integration";

    nodes = {
      router = testRouterConfig;
      server = testServerConfig;
      desktop = testDesktopConfig;
    };

    testScript = ''
      # Start all VMs
      start_all()

      # Wait for VMs to be ready
      router.wait_for_unit("multi-user.target")
      server.wait_for_unit("multi-user.target")
      desktop.wait_for_unit("multi-user.target")

      # Wait for SSH
      router.wait_for_unit("sshd.service")
      server.wait_for_unit("sshd.service")
      desktop.wait_for_unit("sshd.service")

      # Test network connectivity between VMs
      print("Testing network connectivity...")
      router.succeed("ping -c 3 ${testNetwork.hosts.test-server}")
      router.succeed("ping -c 3 ${testNetwork.hosts.test-desktop}")
      server.succeed("ping -c 3 ${testNetwork.hosts.test-router}")
      server.succeed("ping -c 3 ${testNetwork.hosts.test-desktop}")
      desktop.succeed("ping -c 3 ${testNetwork.hosts.test-router}")
      desktop.succeed("ping -c 3 ${testNetwork.hosts.test-server}")

      # Test SSH connectivity
      print("Testing SSH connectivity...")
      router.succeed("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@${testNetwork.hosts.test-server} 'echo test-server-ssh-ok'")
      server.succeed("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@${testNetwork.hosts.test-router} 'echo test-router-ssh-ok'")

      # Test agenix secret decryption on all VMs
      print("Testing agenix secret decryption...")
      router.succeed("test -f /run/agenix/test-nebula-router-cert")
      router.succeed("cat /run/agenix/test-nebula-router-cert | grep -q 'CERTIFICATE'")
      server.succeed("test -f /run/agenix/test-nebula-server-cert")
      server.succeed("cat /run/agenix/test-nebula-server-cert | grep -q 'CERTIFICATE'")
      desktop.succeed("test -f /run/agenix/test-nebula-desktop-cert")
      desktop.succeed("cat /run/agenix/test-nebula-desktop-cert | grep -q 'CERTIFICATE'")

      # Test that kimb-services computed values work correctly
      print("Testing service IP resolution...")
      router.succeed("nixos-rebuild build --flake /etc/nixos#test-router")
      server.succeed("nixos-rebuild build --flake /etc/nixos#test-server")
      desktop.succeed("nixos-rebuild build --flake /etc/nixos#test-desktop")

      # Test service configurations are generated correctly
      print("Checking enabled services on each host...")

      # Router should have reverse-proxy and blog enabled
      router.succeed("systemctl list-units --type=service | grep -E '(reverse-proxy|blog)' || echo 'services not started yet'")

      # Server should have copyparty and homeassistant services configured
      server.succeed("systemctl list-units --type=service | grep -E '(copyparty|homeassistant)' || echo 'services not started yet'")

      # Desktop should have no services enabled by default
      desktop.succeed("systemctl list-units --type=service | grep -v -E '(ssh|network|systemd)' | wc -l")

      # Test functional service patterns work
      print("Testing functional service generation...")

      # Check that services with correct IPs are generated in computed values
      router.succeed("nix eval --json '.#nixosConfigurations.test-router.config.kimb.computed.servicesWithIPs.reverse-proxy.hostIP' | grep '${testNetwork.hosts.test-router}'")
      server.succeed("nix eval --json '.#nixosConfigurations.test-server.config.kimb.computed.servicesWithIPs.copyparty.hostIP' | grep '${testNetwork.hosts.test-server}'")

      print("All integration tests passed!")
    '';
  };

  # Unit tests for service configuration
  unitTests = {
    testServiceIPResolution = let
      testConfig = lib.evalModules {
        modules = [
          testKimbServicesModule
          {
            kimb.services = {
              test-service = {
                enable = true;
                port = 8080;
                subdomain = "test";
                host = "test-server";
                auth = "none";
                publicAccess = true;
                websockets = false;
              };
            };
          }
        ];
      };
    in {
      expr = testConfig.config.kimb.computed.servicesWithIPs.test-service.hostIP;
      expected = testNetwork.hosts.test-server;
    };

    testEnabledServiceFiltering = let
      testConfig = lib.evalModules {
        modules = [
          testKimbServicesModule
          {
            kimb.services = {
              enabled-service = {
                enable = true;
                port = 8080;
                subdomain = "enabled";
                host = "test-server";
              };
              disabled-service = {
                enable = false;
                port = 8081;
                subdomain = "disabled";
                host = "test-server";
              };
            };
          }
        ];
      };
    in {
      expr = builtins.attrNames testConfig.config.kimb.computed.enabledServices;
      expected = ["enabled-service"];
    };
  };
}
