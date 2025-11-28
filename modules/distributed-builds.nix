# Distributed Nix builds using historian as remote builder
# Clients offload builds to historian when reachable over nebula
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kimb.distributedBuilds;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix;
  sshKeys = import ../hosts/ssh-keys.nix;
  historianIP = registry.nodes.historian.ip;
  historianKey = registry.nodes.historian.publicKey;

  # Host keys from desktops/laptops that can use distributed builds
  clientHostKeys = sshKeys.desktopList ++ sshKeys.laptopList;
in {
  options.kimb.distributedBuilds = {
    enable = mkEnableOption "distributed Nix builds via historian";

    isBuilder = mkOption {
      type = types.bool;
      default = hostname == "historian";
      description = "Whether this host accepts remote builds";
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
    # Builder configuration (historian)
    (mkIf cfg.isBuilder {
      nix.settings.trusted-users = ["root" "@wheel"];

      # Accept SSH from client host keys for remote builds
      users.users.root.openssh.authorizedKeys.keys = clientHostKeys;
    })

    # Client configuration (all other hosts)
    (mkIf (!cfg.isBuilder) {
      nix.buildMachines = [{
        hostName = historianIP;
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
