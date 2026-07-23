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

    environment = {
      systemPackages = with pkgs; [
        nebula
        age
        # Dev tools (system-manager-managed nix layer; XFCE + zed come
        # in via apt + zed.dev installer respectively — see hosts/mochi/README.md).
        helix
        btop
        htop
        ripgrep
        fd
        jq
        git
        gh
        bat
        eza
        zoxide
        starship
        tmux
        kitty
        wezterm
        # Claude Code + z.ai-backed wrapper. claude-zai expects an ANTHROPIC
        # auth token at /run/agenix/zai-api-key; mochi is not part of the
        # agenix recipient set today, so the wrapper will refuse to launch
        # until the user populates that file out-of-band (see README).
        claude-code
        (pkgs.callPackage ../../pkgs/claude-zai.nix {})
        # CPU-only LLM inference (AVF doesn't expose GPU)
        ollama
      ];

      etc = {
        # sshd hardening: bind to nebula address only, key-only auth, no root.
        # Mochi is reachable via the nebula mesh as `kimb@mochi.nebula`.
        "ssh/sshd_config.d/10-mochi-hardening.conf".text = ''
          ListenAddress 10.100.0.8
          AddressFamily inet
          PasswordAuthentication no
          PermitRootLogin no
          PubkeyAuthentication yes
          KbdInteractiveAuthentication no
        '';

        # ssh.service must wait for nebula0 to come up, otherwise the
        # ListenAddress=10.100.0.8 bind will fail at boot.
        "systemd/system/ssh.service.d/10-after-nebula.conf".text = ''
          [Unit]
          After=nebula-mainnet.service
          Requires=nebula-mainnet.service
        '';

        # Encrypted secrets in /etc
        "nebula/mainnet/encrypted/ca.age".source = encryptedSecrets.mainnet.ca;
        "nebula/mainnet/encrypted/cert.age".source = encryptedSecrets.mainnet.cert;
        "nebula/mainnet/encrypted/key.age".source = encryptedSecrets.mainnet.key;

        # Nebula mainnet config (10.100.0.0/16)
        "nebula/mainnet/config.yml".text = ''
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
      };
    };

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
          # If the restore bundle pre-staged the Nebula cert/key (see
          # .#mochi-restore-generator / hosts/mochi/README.md), skip the
          # on-device SSH-host-key decrypt entirely — that path is what
          # makes a fresh AVF wipe rejoin the mesh without the rotation
          # dance. Only fall back to age-decrypt-from-host-key when the
          # secrets are absent (the steady-state agenix rotation path).
          if [ -s /run/nebula-secrets/mainnet/mochi.key ] \
             && [ -s /run/nebula-secrets/mainnet/mochi.crt ] \
             && [ -s /run/nebula-secrets/mainnet/ca.crt ]; then
            chmod -R 600 /run/nebula-secrets/mainnet/
            chmod 700 /run/nebula-secrets /run/nebula-secrets/mainnet
            echo "nebula secrets pre-staged; skipping on-device decrypt"
            exit 0
          fi
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
