# Simplified VM Integration Test for kimb-services
# Uses inline test keys for easier Nix evaluation
{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib }:

let
  # Test network configuration
  testNetwork = {
    subnet = "10.200.0.0/16";
    hosts = {
      test-router = "10.200.0.50";
      test-server = "10.200.0.40"; 
    };
  };

  # Inline test keys (INSECURE - TEST ONLY!)
  testKeys = {
    router = {
      public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA6y68ZNDn3ihiWhKUa5k7D9sAM1F5fAvw94ESlyxRhK test-router@vm.local";
      private = ''
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACA6cuvGTQ594oYloSlGuZOw/bADNReXwL8PeBEpcsUYSgAAAJg4+GiyOPho
        sgAAAAtzc2gtZWQyNTUxOQAAACA6cuvGTQ594oYloSlGuZOw/bADNReXwL8PeBEpcsUYSg
        AAAEAnpykoRWSiMZDFiqIKQ2cpr/MttBLoLBNpWEniYNxKXjpy68ZNDn3ihiWhKUa5k7D9
        sAM1F5fAvw94ESlyxRhKAAAAFHRlc3Qtcm91dGVyQHZtLmxvY2FsAQ==
        -----END OPENSSH PRIVATE KEY-----
      '';
    };
    server = {
      public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnmCBDR1Pjkwauej50V5U+FJEi+OcCd7jacoZh0YyIU test-server@vm.local";
      private = ''
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACAs5ggQ0dT45MGrng+dFeVPhSRIvjnAne42nKGYdGMiFAAAAJiFBHcQhQR3
        EAAAAAtzc2gtZWQyNTUxOQAAACAs5ggQ0dT45MGrng+dFeVPhSRIvjnAne42nKGYdGMiFA
        AAAEClHdcZWHIf6VJh1jZY35l8sIVZANm7+vr+9mwQlGwJuSzmCBDR1Pjkwauej50V5U+F
        JEi+OcCd7jacoZh0YyIUAAAAFHRlc3Qtc2VydmVyQHZtLmxvY2FsAQ==
        -----END OPENSSH PRIVATE KEY-----
      '';
    };
  };

  # Test VM configuration
  testRouterConfig = { config, lib, pkgs, ... }: {
    # WARNING: Contains test-only insecure keys!
    environment.etc."ssh/test_key" = {
      text = testKeys.router.private;
      mode = "0400";
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };
    
    users.users.test = {
      isNormalUser = true;
      password = "test";
      extraGroups = [ "wheel" ];
    };
    
    networking = {
      hostName = "test-router";
      firewall.enable = false;
      interfaces.eth1 = {
        ipv4.addresses = [{
          address = testNetwork.hosts.test-router;
          prefixLength = 16;
        }];
      };
    };

    system.stateVersion = "24.11";
  };

  testServerConfig = { config, lib, pkgs, ... }: {
    # WARNING: Contains test-only insecure keys!
    environment.etc."ssh/test_key" = {
      text = testKeys.server.private;
      mode = "0400";
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };
    
    users.users.test = {
      isNormalUser = true;
      password = "test";
      extraGroups = [ "wheel" ];
    };
    
    networking = {
      hostName = "test-server";
      firewall.enable = false;
      interfaces.eth1 = {
        ipv4.addresses = [{
          address = testNetwork.hosts.test-server;
          prefixLength = 16;
        }];
      };
    };

    system.stateVersion = "24.11";
  };

in
# Simple integration test using modern testers.runNixOSTest
pkgs.testers.runNixOSTest {
  name = "kimb-services-simple";
  
  nodes = {
    router = testRouterConfig;
    server = testServerConfig;
  };

  testScript = ''
    start_all()
    
    router.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")
    
    router.wait_for_unit("sshd.service")
    server.wait_for_unit("sshd.service")
    
    print("Testing network connectivity...")
    router.succeed("ping -c 3 ${testNetwork.hosts.test-server}")
    server.succeed("ping -c 3 ${testNetwork.hosts.test-router}")
    
    print("Testing test key deployment...")
    router.succeed("test -f /etc/ssh/test_key")
    server.succeed("test -f /etc/ssh/test_key")
    
    print("Testing SSH connectivity...")
    router.succeed("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@${testNetwork.hosts.test-server} 'echo server-accessible'")
    server.succeed("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@${testNetwork.hosts.test-router} 'echo router-accessible'")
    
    print("🎉 Simple VM test passed!")
  '';
}