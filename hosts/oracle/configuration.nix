# Oracle Cloud VM - Nebula lighthouse configuration
# Managed via system-manager (not NixOS)
{pkgs, ...}: let
  # Encrypted secrets from the repo (in Nix store, safe - they're encrypted)
  encryptedSecrets = {
    ca = ../../secrets/nebula-ca.age;
    cert = ../../secrets/nebula-oracle-cert.age;
    key = ../../secrets/nebula-oracle-key.age;
  };
in {
  config = {
    # System-manager requires setting the platform
    nixpkgs.hostPlatform = "x86_64-linux";

    environment.systemPackages = [pkgs.nebula pkgs.age];

    # Place encrypted secrets in /etc/nebula/encrypted/ (from Nix store)
    environment.etc."nebula/encrypted/ca.age".source = encryptedSecrets.ca;
    environment.etc."nebula/encrypted/cert.age".source = encryptedSecrets.cert;
    environment.etc."nebula/encrypted/key.age".source = encryptedSecrets.key;

    # Nebula config (references decrypted secrets at runtime paths)
    environment.etc."nebula/config.yml".text = ''
      pki:
        ca: /run/nebula-secrets/ca.crt
        cert: /run/nebula-secrets/oracle.crt
        key: /run/nebula-secrets/oracle.key

      static_host_map:
        "10.100.0.1": ["35.222.40.201:4242"]
        "10.100.0.50": ["kimb.dev:4242"]

      lighthouse:
        am_lighthouse: true
        serve_dns: false

      listen:
        host: 0.0.0.0
        port: 4242

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

    # Oneshot service to decrypt secrets before nebula starts
    systemd.services.nebula-secrets = {
      description = "Decrypt Nebula secrets";
      wantedBy = ["multi-user.target"];
      before = ["nebula.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "decrypt-nebula-secrets" ''
          set -euo pipefail
          mkdir -p /run/nebula-secrets
          chmod 700 /run/nebula-secrets

          ${pkgs.age}/bin/age -d \
            -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/ca.crt \
            /etc/nebula/encrypted/ca.age

          ${pkgs.age}/bin/age -d \
            -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/oracle.crt \
            /etc/nebula/encrypted/cert.age

          ${pkgs.age}/bin/age -d \
            -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/oracle.key \
            /etc/nebula/encrypted/key.age

          chmod 600 /run/nebula-secrets/*
        '';
      };
    };

    systemd.services.nebula = {
      description = "Nebula mesh VPN";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service"];
      requires = ["nebula-secrets.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/config.yml";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
