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

    environment = {
      systemPackages = [pkgs.nebula pkgs.age pkgs.iptables pkgs.prometheus-blackbox-exporter];

      etc = {
        "blackbox/blackbox.yml".text = ''
          modules:
            http_2xx:
              prober: http
              timeout: 5s
              http:
                valid_status_codes:
                  - 200
                method: GET
        '';
        "nebula/encrypted/ca.age".source = encryptedSecrets.ca;
        "nebula/encrypted/cert.age".source = encryptedSecrets.cert;
        "nebula/encrypted/key.age".source = encryptedSecrets.key;

        "nebula/config.yml".text = ''
          pki:
            ca: /run/nebula-secrets/ca.crt
            cert: /run/nebula-secrets/oracle.crt
            key: /run/nebula-secrets/oracle.key

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
              # Blackbox exporter for external HTTP probes from maitred
              - port: 9115
                proto: tcp
                host: any
        '';
      };
    };

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
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/ca.crt \
            /etc/nebula/encrypted/ca.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/oracle.crt \
            /etc/nebula/encrypted/cert.age
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/oracle.key \
            /etc/nebula/encrypted/key.age
          chmod 600 /run/nebula-secrets/*
          chmod 700 /run/nebula-secrets
        '';
      };
    };

    # Oracle Cloud Ubuntu has restrictive default iptables rules; ensure 4242
    # and 9115 (blackbox exporter) are open before nebula starts.
    systemd.services.nebula-firewall = {
      description = "Open firewall ports for Nebula and Blackbox Exporter";
      wantedBy = ["multi-user.target"];
      before = ["nebula.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "open-firewall-ports" ''
          ${pkgs.iptables}/bin/iptables -C INPUT -p udp --dport 4242 -j ACCEPT 2>/dev/null || \
            ${pkgs.iptables}/bin/iptables -I INPUT 5 -p udp --dport 4242 -j ACCEPT
          ${pkgs.iptables}/bin/iptables -C INPUT -p tcp --dport 9115 -j ACCEPT 2>/dev/null || \
            ${pkgs.iptables}/bin/iptables -I INPUT 5 -p tcp --dport 9115 -j ACCEPT
        '';
      };
    };

    # Blackbox exporter for external HTTP probes from maitred
    systemd.services.blackbox-exporter = {
      description = "Prometheus Blackbox Exporter";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        ExecStart = "${pkgs.prometheus-blackbox-exporter}/bin/blackbox_exporter --config.file=/etc/blackbox/blackbox.yml --web.listen-address=:9115";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    systemd.services.nebula = {
      description = "Nebula mesh (10.100.0.0/16)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service" "nebula-firewall.service"];
      requires = ["nebula-secrets.service" "nebula-firewall.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/config.yml";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
