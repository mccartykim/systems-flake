# Oracle Cloud VM - Nebula lighthouse configuration
# Managed via system-manager (not NixOS)
# Runs 3 nebula networks: mainnet (10.100), buildnet (10.101), containernet (10.102)
{pkgs, ...}: let
  # Encrypted secrets from the repo (in Nix store, safe - they're encrypted)
  encryptedSecrets = {
    # Mainnet (existing nebula mesh)
    mainnet = {
      ca = ../../secrets/nebula-ca.age;
      cert = ../../secrets/nebula-oracle-cert.age;
      key = ../../secrets/nebula-oracle-key.age;
    };
    # Buildnet (hot CA for Claude Code sandboxes)
    buildnet = {
      ca = ../../secrets/buildnet-ca-cert.age;
      cert = ../../secrets/buildnet-oracle-cert.age;
      key = ../../secrets/buildnet-oracle-key.age;
    };
    # Containernet (hot CA for container mesh)
    containernet = {
      ca = ../../secrets/containernet-ca-cert.age;
      cert = ../../secrets/containernet-oracle-cert.age;
      key = ../../secrets/containernet-oracle-key.age;
    };
  };
in {
  config = {
    # System-manager requires setting the platform
    nixpkgs.hostPlatform = "x86_64-linux";

    environment.systemPackages = [pkgs.nebula pkgs.age pkgs.iptables];

    # ===== ENCRYPTED SECRETS IN /etc =====
    # Mainnet
    environment.etc."nebula/mainnet/encrypted/ca.age".source = encryptedSecrets.mainnet.ca;
    environment.etc."nebula/mainnet/encrypted/cert.age".source = encryptedSecrets.mainnet.cert;
    environment.etc."nebula/mainnet/encrypted/key.age".source = encryptedSecrets.mainnet.key;
    # Buildnet
    environment.etc."nebula/buildnet/encrypted/ca.age".source = encryptedSecrets.buildnet.ca;
    environment.etc."nebula/buildnet/encrypted/cert.age".source = encryptedSecrets.buildnet.cert;
    environment.etc."nebula/buildnet/encrypted/key.age".source = encryptedSecrets.buildnet.key;
    # Containernet
    environment.etc."nebula/containernet/encrypted/ca.age".source = encryptedSecrets.containernet.ca;
    environment.etc."nebula/containernet/encrypted/cert.age".source = encryptedSecrets.containernet.cert;
    environment.etc."nebula/containernet/encrypted/key.age".source = encryptedSecrets.containernet.key;

    # ===== MAINNET CONFIG (10.100.0.0/16, port 4242) =====
    environment.etc."nebula/mainnet/config.yml".text = ''
      pki:
        ca: /run/nebula-secrets/mainnet/ca.crt
        cert: /run/nebula-secrets/mainnet/oracle.crt
        key: /run/nebula-secrets/mainnet/oracle.key

      static_host_map:
        "10.100.0.50": ["kimb.dev:4242"]

      lighthouse:
        am_lighthouse: true
        serve_dns: false

      listen:
        host: 0.0.0.0
        port: 4242

      tun:
        dev: nebula0

      punchy:
        punch: true
        respond: true

      relay:
        am_relay: true
        use_relays: true

      firewall:
        outbound:
          - port: any
            proto: any
            host: any
        inbound:
          - port: any
            proto: icmp
            host: any
          - port: 22
            proto: tcp
            host: any
    '';

    # ===== BUILDNET CONFIG (10.101.0.0/16, port 4243) =====
    environment.etc."nebula/buildnet/config.yml".text = ''
      pki:
        ca: /run/nebula-secrets/buildnet/ca.crt
        cert: /run/nebula-secrets/buildnet/oracle.crt
        key: /run/nebula-secrets/buildnet/oracle.key

      static_host_map:
        "10.101.0.1": ["kimb.dev:4243"]

      lighthouse:
        am_lighthouse: true
        serve_dns: false
        # Peer with maitred for dual-lighthouse redundancy
        hosts:
          - "10.101.0.1"

      listen:
        host: 0.0.0.0
        port: 4243

      tun:
        dev: nebula-build

      punchy:
        punch: true
        respond: true

      relay:
        am_relay: true
        use_relays: true

      firewall:
        outbound:
          - port: any
            proto: any
            host: any
        inbound:
          - port: any
            proto: icmp
            host: any
    '';

    # ===== CONTAINERNET CONFIG (10.102.0.0/16, port 4244) =====
    environment.etc."nebula/containernet/config.yml".text = ''
      pki:
        ca: /run/nebula-secrets/containernet/ca.crt
        cert: /run/nebula-secrets/containernet/oracle.crt
        key: /run/nebula-secrets/containernet/oracle.key

      static_host_map:
        "10.102.0.1": ["kimb.dev:4244"]

      lighthouse:
        am_lighthouse: true
        serve_dns: false
        # Peer with maitred for dual-lighthouse redundancy
        hosts:
          - "10.102.0.1"

      listen:
        host: 0.0.0.0
        port: 4244

      tun:
        dev: nebula-container

      punchy:
        punch: true
        respond: true

      relay:
        am_relay: true
        use_relays: true

      firewall:
        outbound:
          - port: any
            proto: any
            host: any
        inbound:
          - port: any
            proto: icmp
            host: any
    '';

    # ===== DECRYPT SECRETS SERVICE =====
    systemd.services.nebula-secrets = {
      description = "Decrypt Nebula secrets for all networks";
      wantedBy = ["multi-user.target"];
      before = ["nebula-mainnet.service" "nebula-buildnet.service" "nebula-containernet.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "decrypt-nebula-secrets" ''
          set -euo pipefail

          # Mainnet
          mkdir -p /run/nebula-secrets/mainnet
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/ca.crt \
            /etc/nebula/mainnet/encrypted/ca.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/oracle.crt \
            /etc/nebula/mainnet/encrypted/cert.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/oracle.key \
            /etc/nebula/mainnet/encrypted/key.age

          # Buildnet
          mkdir -p /run/nebula-secrets/buildnet
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/buildnet/ca.crt \
            /etc/nebula/buildnet/encrypted/ca.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/buildnet/oracle.crt \
            /etc/nebula/buildnet/encrypted/cert.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/buildnet/oracle.key \
            /etc/nebula/buildnet/encrypted/key.age

          # Containernet
          mkdir -p /run/nebula-secrets/containernet
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/containernet/ca.crt \
            /etc/nebula/containernet/encrypted/ca.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/containernet/oracle.crt \
            /etc/nebula/containernet/encrypted/cert.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/containernet/oracle.key \
            /etc/nebula/containernet/encrypted/key.age

          chmod -R 600 /run/nebula-secrets/*/
          chmod 700 /run/nebula-secrets /run/nebula-secrets/*
        '';
      };
    };

    # ===== FIREWALL SETUP =====
    # Oracle Cloud Ubuntu has restrictive default iptables rules
    # This service ensures nebula ports are open before nebula starts
    systemd.services.nebula-firewall = {
      description = "Open firewall ports for Nebula networks";
      wantedBy = ["multi-user.target"];
      before = ["nebula-mainnet.service" "nebula-buildnet.service" "nebula-containernet.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "open-nebula-ports" ''
          # Idempotently add nebula port rules
          # Uses -C to check if rule exists, -I to insert at position 5 (after SSH rule)
          for port in 4242 4243 4244; do
            ${pkgs.iptables}/bin/iptables -C INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || \
              ${pkgs.iptables}/bin/iptables -I INPUT 5 -p udp --dport $port -j ACCEPT
          done
        '';
      };
    };

    # ===== NEBULA SERVICES =====
    systemd.services.nebula-mainnet = {
      description = "Nebula mainnet (10.100.0.0/16)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service" "nebula-firewall.service"];
      requires = ["nebula-secrets.service" "nebula-firewall.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/mainnet/config.yml";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    systemd.services.nebula-buildnet = {
      description = "Nebula buildnet (10.101.0.0/16)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service" "nebula-firewall.service"];
      requires = ["nebula-secrets.service" "nebula-firewall.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/buildnet/config.yml";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    systemd.services.nebula-containernet = {
      description = "Nebula containernet (10.102.0.0/16)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service" "nebula-firewall.service"];
      requires = ["nebula-secrets.service" "nebula-firewall.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/containernet/config.yml";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
