# Distributed Nix builds using historian and total-eclipse as remote builders
# Clients offload builds to builders when reachable over nebula
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.distributedBuilds;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix {secretsFlake = inputs.secretsFlake;};
  sshKeys = import ../hosts/ssh-keys.nix {secretsFlake = inputs.secretsFlake;};

  # Builder configs
  historianIP = registry.nodes.historian.ip;
  historianKey = registry.nodes.historian.publicKey;
  totalEclipseIP = registry.nodes.total-eclipse.ip;
  totalEclipseKey = registry.nodes.total-eclipse.publicKey;

  # Host keys from all NixOS hosts that can use distributed builds
  clientHostKeys = sshKeys.desktopList ++ sshKeys.laptopList ++ sshKeys.applianceList;
in {
  options.kimb.distributedBuilds = {
    enable = mkEnableOption "distributed Nix builds via historian";

    isBuilder = mkOption {
      type = types.bool;
      default = builtins.elem hostname ["historian" "total-eclipse"];
      description = "Whether this host accepts remote builds";
    };

    # Builder-only keys (command-restricted, no shell)
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
      users.users.root.openssh.authorizedKeys.keys =
        map (
          key: ''command="${pkgs.nix}/bin/nix-daemon --stdio",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ${key}''
        )
        cfg.builderOnlyKeys;
    })

    # === CLIENT CONFIG (all other hosts) ===
    (mkIf (!cfg.isBuilder) {
      nix.buildMachines = [
        {
          hostName = historianIP;
          system = "x86_64-linux";
          sshUser = "root";
          sshKey = "/etc/ssh/ssh_host_ed25519_key";
          inherit (cfg) maxJobs speedFactor;
          supportedFeatures = ["nixos-test" "big-parallel" "kvm"];
        }
        {
          hostName = totalEclipseIP;
          system = "x86_64-linux";
          sshUser = "root";
          sshKey = "/etc/ssh/ssh_host_ed25519_key";
          maxJobs = 4;
          speedFactor = 1;
          supportedFeatures = ["nixos-test" "kvm"];
        }
      ];

      nix.distributedBuilds = true;
      # nix.distributedBuilds no longer auto-populates this in current nixpkgs,
      # so point nix at the generated machines file explicitly.
      nix.settings.builders = ["@/etc/nix/machines"];
      nix.settings.connect-timeout = cfg.connectTimeout;

      # Add builder host keys to known_hosts for root
      programs.ssh.knownHosts.historian = {
        hostNames = [historianIP "historian"];
        publicKey = historianKey;
      };
      programs.ssh.knownHosts.total-eclipse = {
        hostNames = [totalEclipseIP "total-eclipse"];
        publicKey = totalEclipseKey;
      };
    })
  ]);
}
