# Integration test for ephemeral nebula networks
# Tests cert service allocation and SSH command restriction for builder-only keys
{pkgs}:
pkgs.testers.nixosTest {
  name = "ephemeral-networks";

  nodes = {
    # Simulates maitred - lighthouse + cert service
    lighthouse = {
      config,
      lib,
      pkgs,
      ...
    }: {
      imports = [
        ../modules/kimb-services.nix
      ];

      # Minimal cert service test (without real nebula)
      systemd.services.test-cert-service = {
        description = "Test cert service";
        wantedBy = ["multi-user.target"];

        environment = {
          NETWORKS_CONFIG = builtins.toJSON {
            buildnet = {
              ca_cert = "/tmp/test-ca.crt";
              ca_key = "/tmp/test-ca.key";
              subnet = "10.101.0";
              pool_start = 100;
              pool_end = 110;
              default_duration = "1h";
              default_groups = ["builders"];
            };
          };
          PORT = "8444";
          STATE_DIR = "/tmp/cert-state";
          API_TOKEN = "test-token-12345";
        };

        serviceConfig = {
          Type = "simple";
          ExecStartPre = pkgs.writeShellScript "setup-test-ca" ''
            mkdir -p /tmp/cert-state
            # Generate test CA for the service
            ${pkgs.nebula}/bin/nebula-cert ca -name "test-ca" -duration 24h \
              -out-crt /tmp/test-ca.crt -out-key /tmp/test-ca.key
          '';
          ExecStart = "${pkgs.python3}/bin/python3 ${../packages/cert-service/cert-service.py}";
          Restart = "on-failure";
        };
      };

      networking = {
        hostName = "lighthouse";
        firewall.enable = false;
      };

      system.stateVersion = "24.11";
    };

    # Simulates historian - builder with command-restricted SSH
    builder = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # Test SSH command restriction for builder-only keys
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };

      # Add a command-restricted test key
      users.users.root.openssh.authorizedKeys.keys = [
        # Full access key (simulating trusted host)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJJTSJdpDh82486uPiMhhyhnci4tScp/SQdT7+ZfRqX test-trusted"

        # Command-restricted key (simulating Claude Code)
        ''command="${pkgs.coreutils}/bin/echo BUILD_ONLY_ACCESS",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILqHEaLZtdDwLKVxqG8c8hqw3r28xPJLPp/5B7m2sPqL test-builder-only''
      ];

      # Create test SSH keys
      environment.etc = {
        "test-keys/trusted".text = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACAiSU0iXaQ4fNuPOLj4jIYcoZ3IuLUnKf0kHU+/mX0akQAAAJjK1u7CytbuQg
          AAAAtzc2gtZWQyNTUxOQAAACAiSU0iXaQ4fNuPOLj4jIYcoZ3IuLUnKf0kHU+/mX0akQAA
          AEBOd8O9jZ9X3v3QKLB/YGO5oVQzWjHEE1rZ9w3b1s4TLiJJTSJdpDh82486uPiMhhyhnci
          4tScp/SQdT7+ZfRqRAAAAEnRlc3QtdHJ1c3RlZEBsb2NhbAE=
          -----END OPENSSH PRIVATE KEY-----
        '';
        "test-keys/builder-only".text = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACC6hxGi2bXQ8Cylcahv3PIasN69vMTySz6f+Ye5trD6iwAAAJi+1nDSvtZw0g
          AAAAtzc2gtZWQyNTUxOQAAACC6hxGi2bXQ8Cylcahv3PIasN69vMTySz6f+Ye5trD6iwAA
          AEDQ6r+iC4Lb4aT9Ek5kLRiXEDy8IyLgKS0eTqH5QNLk67qHEaLZtdDwLKVxqG8c8hqw3r
          28xPJLPp/5B7m2sPqLAAAAFnRlc3QtYnVpbGRlci1vbmx5QGxvY2FsAQ==
          -----END OPENSSH PRIVATE KEY-----
        '';
      };

      networking = {
        hostName = "builder";
        firewall.enable = false;
        interfaces.eth1.ipv4.addresses = [{
          address = "10.200.0.10";
          prefixLength = 16;
        }];
      };

      system.stateVersion = "24.11";
    };

    # Simulates Claude Code sandbox - ephemeral client
    client = {
      config,
      lib,
      pkgs,
      ...
    }: {
      environment.systemPackages = with pkgs; [
        curl
        jq
        openssh
      ];

      # Copy test keys from builder for SSH testing
      environment.etc = {
        "test-keys/trusted".text = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACAiSU0iXaQ4fNuPOLj4jIYcoZ3IuLUnKf0kHU+/mX0akQAAAJjK1u7CytbuQg
          AAAAtzc2gtZWQyNTUxOQAAACAiSU0iXaQ4fNuPOLj4jIYcoZ3IuLUnKf0kHU+/mX0akQAA
          AEBOd8O9jZ9X3v3QKLB/YGO5oVQzWjHEE1rZ9w3b1s4TLiJJTSJdpDh82486uPiMhhyhnci
          4tScp/SQdT7+ZfRqRAAAAEnRlc3QtdHJ1c3RlZEBsb2NhbAE=
          -----END OPENSSH PRIVATE KEY-----
        '';
        "test-keys/builder-only".text = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACC6hxGi2bXQ8Cylcahv3PIasN69vMTySz6f+Ye5trD6iwAAAJi+1nDSvtZw0g
          AAAAtzc2gtZWQyNTUxOQAAACC6hxGi2bXQ8Cylcahv3PIasN69vMTySz6f+Ye5trD6iwAA
          AEDQ6r+iC4Lb4aT9Ek5kLRiXEDy8IyLgKS0eTqH5QNLk67qHEaLZtdDwLKVxqG8c8hqw3r
          28xPJLPp/5B7m2sPqLAAAAFnRlc3QtYnVpbGRlci1vbmx5QGxvY2FsAQ==
          -----END OPENSSH PRIVATE KEY-----
        '';
      };

      networking = {
        hostName = "client";
        firewall.enable = false;
        interfaces.eth1.ipv4.addresses = [{
          address = "10.200.0.100";
          prefixLength = 16;
        }];
      };

      system.stateVersion = "24.11";
    };
  };

  testScript = ''
    start_all()

    # Wait for VMs to boot
    lighthouse.wait_for_unit("multi-user.target")
    builder.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    print("=== Phase 1: Test cert service ===")

    # Wait for cert service to start
    lighthouse.wait_for_unit("test-cert-service.service")
    lighthouse.wait_for_open_port(8444)

    # Test health endpoint (no auth required)
    lighthouse.succeed("curl -s http://localhost:8444/health | grep -q ok")
    print("Cert service health check passed")

    # Test cert allocation (requires auth)
    lighthouse.succeed('''
      curl -s -X POST \
        -H "Authorization: Bearer test-token-12345" \
        http://localhost:8444/buildnet/allocate \
        | jq -e '.ip' | grep -q "10.101.0"
    ''')
    print("Cert allocation test passed")

    # Test that allocation returns all required fields
    lighthouse.succeed('''
      response=$(curl -s -X POST \
        -H "Authorization: Bearer test-token-12345" \
        http://localhost:8444/buildnet/allocate)
      echo "$response" | jq -e '.ip'
      echo "$response" | jq -e '.name'
      echo "$response" | jq -e '.ca'
      echo "$response" | jq -e '.cert'
      echo "$response" | jq -e '.key'
    ''')
    print("Cert response fields validated")

    # Test status endpoint
    lighthouse.succeed('''
      curl -s \
        -H "Authorization: Bearer test-token-12345" \
        http://localhost:8444/status \
        | jq -e '.buildnet.allocated'
    ''')
    print("Cert service status check passed")

    # Test auth rejection
    lighthouse.fail("curl -s -X POST http://localhost:8444/buildnet/allocate | grep -q ip")
    print("Auth rejection test passed")

    print("=== Phase 2: Test SSH command restriction ===")

    # Wait for SSH on builder
    builder.wait_for_unit("sshd.service")
    builder.wait_for_open_port(22)

    # Setup SSH keys on client with proper permissions
    client.succeed("chmod 600 /etc/test-keys/trusted /etc/test-keys/builder-only")

    # Test that trusted key gets full shell access
    client.succeed('''
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i /etc/test-keys/trusted root@10.200.0.10 \
        "echo FULL_SHELL_ACCESS && hostname" | grep -q FULL_SHELL_ACCESS
    ''')
    print("Trusted key shell access test passed")

    # Test that builder-only key is command-restricted
    output = client.succeed('''
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i /etc/test-keys/builder-only root@10.200.0.10 \
        "echo SHOULD_NOT_SEE_THIS" 2>&1 || true
    ''')
    assert "BUILD_ONLY_ACCESS" in output, f"Expected BUILD_ONLY_ACCESS in output, got: {output}"
    print("Builder-only key command restriction test passed")

    # Verify the builder-only key cannot run arbitrary commands
    client.fail('''
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i /etc/test-keys/builder-only root@10.200.0.10 \
        "cat /etc/passwd" | grep -q root
    ''')
    print("Builder-only key arbitrary command rejection test passed")

    print("=== All ephemeral network tests passed! ===")
  '';
}
