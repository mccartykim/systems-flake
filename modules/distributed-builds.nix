# Distributed Nix builds using historian as remote builder
# Clients offload builds to historian when reachable over nebula
# Supports both trusted (main mesh) and untrusted (buildnet) builders
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.distributedBuilds;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix;
  sshKeys = import ../hosts/ssh-keys.nix;

  # Main mesh config (existing)
  historianIP = registry.nodes.historian.ip;
  historianKey = registry.nodes.historian.publicKey;

  # Host keys from desktops/laptops that can use distributed builds
  clientHostKeys = sshKeys.desktopList ++ sshKeys.laptopList;

  # Buildnet config (new)
  buildnetIP = registry.nodes.historian.buildnetIp or null;
  buildnetLighthouses = registry.networks.buildnet.lighthouses or ["10.101.0.1"];
  buildnetPort = registry.networks.buildnet.port or 4243;

  # External endpoints for lighthouses (maitred + oracle)
  lighthouseEndpoints = {
    "10.101.0.1" = "kimb.dev:${toString buildnetPort}";      # maitred
    "10.101.0.2" = "150.136.155.204:${toString buildnetPort}"; # oracle
  };
in {
  options.kimb.distributedBuilds = {
    enable = mkEnableOption "distributed Nix builds via historian";

    isBuilder = mkOption {
      type = types.bool;
      default = hostname == "historian";
      description = "Whether this host accepts remote builds";
    };

    # NEW: Builder-only keys (command-restricted, no shell)
    builderOnlyKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        SSH keys that can only run nix-daemon (no shell access).
        Used for untrusted builders like Claude Code sandboxes.
      '';
      example = [
        "ssh-ed25519 AAAA... claude"
      ];
    };

    # NEW: Enable buildnet (second nebula network for builds)
    buildnet = {
      enable = mkEnableOption "buildnet nebula network for untrusted builders";

      lighthouses = mkOption {
        type = types.listOf types.str;
        default = buildnetLighthouses;
        description = "Buildnet lighthouse IPs";
      };
    };

    connectTimeout = mkOption {
      type = types.int;
      default = 10;
      description = "Seconds to wait for remote builder connection before falling back to local";
    };

    maxJobs = mkOption {
      type = types.int;
      default = 8;
      description = "Maximum parallel jobs on the remote builder";
    };

    speedFactor = mkOption {
      type = types.int;
      default = 2;
      description = "Preference weight for remote builder (higher = prefer remote)";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # === BUILDER CONFIG (historian) ===
    (mkIf cfg.isBuilder {
      nix.settings.trusted-users = ["root" "@wheel"];

      # Full-access keys (main mesh trusted hosts)
      users.users.root.openssh.authorizedKeys.keys = clientHostKeys;
    })

    # === BUILDER-ONLY KEYS (command-restricted, no shell) ===
    (mkIf (cfg.isBuilder && cfg.builderOnlyKeys != []) {
      users.users.root.openssh.authorizedKeys.keys = map (key:
        ''command="${pkgs.nix}/bin/nix-daemon --stdio",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ${key}''
      ) cfg.builderOnlyKeys;
    })

    # === BUILDER BUILDNET CONFIG (historian joins buildnet) ===
    (mkIf (cfg.isBuilder && cfg.buildnet.enable && buildnetIP != null) {
      # Buildnet nebula instance
      services.nebula.networks.buildnet = {
        enable = true;
        isLighthouse = false;
        ca = config.age.secrets.buildnet-ca.path;
        cert = config.age.secrets.buildnet-historian-cert.path;
        key = config.age.secrets.buildnet-historian-key.path;
        lighthouses = cfg.buildnet.lighthouses;
        staticHostMap = builtins.listToAttrs (map (lh: {
          name = lh;
          value = [lighthouseEndpoints.${lh}];
        }) cfg.buildnet.lighthouses);
        listen.port = buildnetPort;
        settings = {
          tun.dev = "nebula-build";
          firewall = {
            inbound = [
              {port = "any"; proto = "icmp"; host = "any";}
              # Only SSH from builders group
              {port = 22; proto = "tcp"; group = "builders";}
            ];
            outbound = [
              {port = "any"; proto = "any"; host = "any";}
            ];
          };
        };
      };

      # Buildnet secrets
      age.secrets = {
        buildnet-ca = {
          file = ../secrets/buildnet-ca-cert.age;
          path = "/etc/nebula-buildnet/ca.crt";
          owner = "nebula-buildnet";
          group = "nebula-buildnet";
          mode = "0644";
        };
        buildnet-historian-cert = {
          file = ../secrets/buildnet-historian-cert.age;
          path = "/etc/nebula-buildnet/historian.crt";
          owner = "nebula-buildnet";
          group = "nebula-buildnet";
          mode = "0644";
        };
        buildnet-historian-key = {
          file = ../secrets/buildnet-historian-key.age;
          path = "/etc/nebula-buildnet/historian.key";
          owner = "nebula-buildnet";
          group = "nebula-buildnet";
          mode = "0600";
        };
      };
    })

    # === CLIENT CONFIG (all other hosts - unchanged) ===
    (mkIf (!cfg.isBuilder) {
      nix.buildMachines = [{
        hostName = historianIP; # Main mesh IP
        system = "x86_64-linux";
        sshUser = "root";
        sshKey = "/etc/ssh/ssh_host_ed25519_key";
        inherit (cfg) maxJobs speedFactor;
        supportedFeatures = ["nixos-test" "big-parallel" "kvm"];
      }];

      nix.distributedBuilds = true;
      nix.settings.connect-timeout = cfg.connectTimeout;

      # Add historian's host key to known_hosts for root
      programs.ssh.knownHosts.historian = {
        hostNames = [historianIP "historian"];
        publicKey = historianKey;
      };
    })
  ]);
}
