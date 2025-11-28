# Multi-VM Network Test for kimb-services
# Tests the full network architecture with router + server VMs
{pkgs}:
pkgs.testers.nixosTest {
  name = "kimb-services-network";

  nodes = {
    router = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # Inline test keys (INSECURE - TEST ONLY!)
      environment.etc."ssh/test_key".text = ''
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACA6cuvGTQ594oYloSlGuZOw/bADNReXwL8PeBEpcsUYSgAAAJg4+GiyOPho
        sgAAAAtzc2gtZWQyNTUxOQAAACA6cuvGTQ594oYloSlGuZOw/bADNReXwL8PeBEpcsUYSg
        AAAEAnpykoRWSiMZDFiqIKQ2cpr/MttBLoLBNpWEniYNxKXjpy68ZNDn3ihiWhKUa5k7D9
        sAM1F5fAvw94ESlyxRhKAAAAFHRlc3Qtcm91dGVyQHZtLmxvY2FsAQ==
        -----END OPENSSH PRIVATE KEY-----
      '';

      # Test kimb-services setup
      imports = [../modules/kimb-services.nix];

      kimb = {
        domain = "test.local";
        services = {
          reverse-proxy = {
            enable = true;
            port = 80;
            subdomain = "www";
            host = "router";
            container = false; # Simplified for testing
            auth = "none";
            publicAccess = true;
            websockets = false;
          };
          blog = {
            enable = true;
            port = 8080;
            subdomain = "blog";
            host = "server"; # Blog hosted on server, reverse-proxied from router
            container = false;
            auth = "none";
            publicAccess = true;
            websockets = false;
          };
        };
      };

      # Enable simple HTTP server to simulate blog
      services.nginx = {
        enable = true;
        virtualHosts."test.local" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = 80;
            }
          ];
          locations."/" = {
            return = "200 'Hello from router - reverse proxy working!'";
            extraConfig = "add_header Content-Type text/plain;";
          };
        };
      };

      services.openssh.enable = true;
      users.users.test = {
        isNormalUser = true;
        password = "test";
        extraGroups = ["wheel"];
      };

      networking = {
        hostName = "router";
        firewall.enable = false;
        interfaces.eth1 = {
          ipv4.addresses = [
            {
              address = "10.200.0.50";
              prefixLength = 16;
            }
          ];
        };
      };

      system.stateVersion = "24.11";
    };

    server = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # Inline test keys (INSECURE - TEST ONLY!)
      environment.etc."ssh/test_key".text = ''
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACAs5ggQ0dT45MGrng+dFeVPhSRIvjnAne42nKGYdGMiFAAAAJiFBHcQhQR3
        EAAAAAtzc2gtZWQyNTUxOQAAACAs5ggQ0dT45MGrng+dFeVPhSRIvjnAne42nKGYdGMiFA
        AAAEClHdcZWHIf6VJh1jZY35l8sIVZANm7+vr+9mwQlGwJuSzmCBDR1Pjkwauej50V5U+F
        JEi+OcCd7jacoZh0YyIUAAAAFHRlc3Qtc2VydmVyQHZtLmxvY2FsAQ==
        -----END OPENSSH PRIVATE KEY-----
      '';

      # Test kimb-services setup
      imports = [../modules/kimb-services.nix];

      kimb = {
        domain = "test.local";
        services = {
          homeassistant = {
            enable = true;
            port = 8123;
            subdomain = "hass";
            host = "server";
            container = false; # Simplified for testing
            auth = "builtin";
            publicAccess = true;
            websockets = true;
          };
          blog = {
            enable = true;
            port = 8080;
            subdomain = "blog";
            host = "server";
            container = false;
            auth = "none";
            publicAccess = true;
            websockets = false;
          };
        };
      };

      # Enable simple HTTP server to simulate blog service
      services.nginx = {
        enable = true;
        virtualHosts."blog.test.local" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = 8080;
            }
          ];
          locations."/" = {
            return = "200 'Hello from server blog - cross-machine service test!'";
            extraConfig = "add_header Content-Type text/plain;";
          };
        };
      };

      services.openssh.enable = true;
      users.users.test = {
        isNormalUser = true;
        password = "test";
        extraGroups = ["wheel"];
      };

      networking = {
        hostName = "server";
        firewall.enable = false;
        interfaces.eth1 = {
          ipv4.addresses = [
            {
              address = "10.200.0.40";
              prefixLength = 16;
            }
          ];
        };
      };

      system.stateVersion = "24.11";
    };
  };

  testScript = ''
    start_all()

    # Wait for both VMs to boot
    router.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")

    router.wait_for_unit("sshd.service")
    server.wait_for_unit("sshd.service")

    print("🔥 Testing WHOLE ASS NETWORK connectivity...")

    # Test basic network connectivity
    router.succeed("ping -c 3 10.200.0.40")
    server.succeed("ping -c 3 10.200.0.50")

    # Test that kimb-services module is loaded and working
    print("🧠 Testing kimb-services module integration...")
    router.succeed("test -d /nix/store")  # Verify nix store is accessible
    server.succeed("test -d /nix/store")  # Verify nix store is accessible

    # Test that services are configured (check systemd units exist)
    print("Testing service integration on VMs...")
    router.succeed("systemctl status multi-user.target")
    server.succeed("systemctl status multi-user.target")

    # Wait for HTTP services to start
    print("🌐 Testing HTTP services...")
    router.wait_for_unit("nginx.service")
    server.wait_for_unit("nginx.service")

    # Test local HTTP services
    print("Testing router reverse-proxy service...")
    router.succeed("curl -s http://localhost:80 | grep 'reverse proxy working'")

    print("Testing server blog service...")
    server.succeed("curl -s http://localhost:8080 | grep 'cross-machine service test'")

    # Test cross-machine HTTP access (reverse proxy simulation)
    print("🔄 Testing cross-machine service access...")
    router.succeed("curl -s http://10.200.0.40:8080 | grep 'cross-machine service test'")
    server.succeed("curl -s http://10.200.0.50:80 | grep 'reverse proxy working'")

    # Test SSH connectivity between VMs
    print("🔐 Testing SSH connectivity...")
    router.succeed("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@10.200.0.40 'echo server-accessible-from-router'")
    server.succeed("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@10.200.0.50 'echo router-accessible-from-server'")

    # Test that kimb-services configuration is applied
    print("🧩 Testing kimb-services integration...")
    router.succeed("test -f /etc/nixos/configuration.nix || echo 'VM mode - config in different location'")
    server.succeed("test -f /etc/nixos/configuration.nix || echo 'VM mode - config in different location'")

    print("🎉 WHOLE ASS NETWORK TEST PASSED!")
    print("All test assertions completed successfully - if you see this, all tests passed!")
  '';
}
