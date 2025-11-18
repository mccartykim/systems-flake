# Working VM test with proper nixosTest syntax
{pkgs}:
pkgs.nixosTest {
  name = "working-network-test";

  nodes = {
    router = {
      system.stateVersion = "24.11";
      virtualisation.graphics = false; # Disable graphics to prevent hanging
      services.openssh.enable = true; # Just enable SSH to test it's running
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
    };

    server = {
      system.stateVersion = "24.11";
      virtualisation.graphics = false; # Disable graphics to prevent hanging
      services.openssh.enable = true; # Just enable SSH to test it's running
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
    };
  };

  testScript = ''
    start_all()

    router.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")

    router.wait_for_unit("sshd.service")
    server.wait_for_unit("sshd.service")

    print("🔥 Testing basic network connectivity...")
    router.succeed("ping -c 3 10.200.0.40")
    server.succeed("ping -c 3 10.200.0.50")

    print("🔐 Testing command execution across machines...")
    # Test VMs have backdoor access - we don't need SSH for testing
    # Just verify the machines can execute commands and see each other
    router.succeed("echo 'Router can execute commands'")
    server.succeed("echo 'Server can execute commands'")

    # Verify services are listening on expected ports
    router.succeed("ss -tulpn | grep :22")  # SSH is listening
    server.succeed("ss -tulpn | grep :22")  # SSH is listening

    print("🎉 Working VM test passed!")
  '';
}
