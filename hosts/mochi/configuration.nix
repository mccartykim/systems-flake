# Mochi - Pixel 9 Pro AVF terminal
# Managed via system-manager (Debian/AVF, not NixOS)
{pkgs, ...}: let
  encryptedSecrets = {
    mainnet = {
      ca = ../../secrets/nebula-ca.age;
      cert = ../../secrets/nebula-mochi-cert.age;
      key = ../../secrets/nebula-mochi-key.age;
    };
  };
in {
  config = {
    nixpkgs.hostPlatform = "aarch64-linux";
    nixpkgs.config.allowUnfree = true;

    environment.systemPackages = with pkgs; [
      nebula
      age
      # Dev tools
      helix
      btop
      htop
      ripgrep
      fd
      jq
      git
      # Claude Code
      claude-code
    ];

    # Encrypted secrets in /etc
    environment.etc."nebula/mainnet/encrypted/ca.age".source = encryptedSecrets.mainnet.ca;
    environment.etc."nebula/mainnet/encrypted/cert.age".source = encryptedSecrets.mainnet.cert;
    environment.etc."nebula/mainnet/encrypted/key.age".source = encryptedSecrets.mainnet.key;

    # Nebula mainnet config (10.100.0.0/16)
    environment.etc."nebula/mainnet/config.yml".text = ''
      pki:
        ca: /run/nebula-secrets/mainnet/ca.crt
        cert: /run/nebula-secrets/mainnet/mochi.crt
        key: /run/nebula-secrets/mainnet/mochi.key

      static_host_map:
        "10.100.0.50": ["kimb.dev:4242"]
        "10.100.0.2": ["150.136.155.204:4242"]

      lighthouse:
        am_lighthouse: false
        hosts:
          - "10.100.0.50"
          - "10.100.0.2"

      listen:
        host: 0.0.0.0
        port: 0

      tun:
        dev: nebula0
        mtu: 1300

      punchy:
        punch: true
        respond: true

      relay:
        relays:
          - "10.100.0.50"
          - "10.100.0.2"
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

    # Decrypt secrets service
    systemd.services.nebula-secrets = {
      description = "Decrypt Nebula secrets";
      wantedBy = ["multi-user.target"];
      before = ["nebula-mainnet.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "decrypt-nebula-secrets" ''
          set -euo pipefail
          mkdir -p /run/nebula-secrets/mainnet
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/ca.crt \
            /etc/nebula/mainnet/encrypted/ca.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/mochi.crt \
            /etc/nebula/mainnet/encrypted/cert.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/mochi.key \
            /etc/nebula/mainnet/encrypted/key.age
          chmod -R 600 /run/nebula-secrets/mainnet/
          chmod 700 /run/nebula-secrets /run/nebula-secrets/mainnet
        '';
      };
    };

    # Nebula service
    systemd.services.nebula-mainnet = {
      description = "Nebula mainnet (10.100.0.0/16)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service"];
      requires = ["nebula-secrets.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/mainnet/config.yml";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
