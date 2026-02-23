# Nix Sandbox - Remote nix build service for Claude Code.
# Runs inside a NixOS container (supervisor) on the host.
# Per-build isolation via nested systemd-nspawn containers.
#
# Architecture:
#   [host] -> containers.nix-sandbox (supervisor, 192.168.101.2)
#               -> Python API (port 8090)
#               -> Per-build: systemd-nspawn --ephemeral
#                    -> Isolated PID/mount/network namespaces
#                    -> /nix/store (bind-ro, host store)
#                    -> /nix/var/nix/daemon-socket (bind, host daemon)
#                    -> /build workspace (bind-rw, per-job)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.nixSandbox;

  apiScript = ../packages/nix-sandbox/nix-sandbox-api.py;
  primerPath = ../packages/nix-sandbox/primer.md;

  # Minimal rootfs for inner nspawn containers (nspawn build mode)
  buildRoot = pkgs.runCommand "sandbox-build-root" {} ''
    mkdir -p $out/{bin,usr/bin,etc,tmp,proc,dev,sys,run,build,var/empty}
    mkdir -p $out/nix/store $out/nix/var/nix/daemon-socket

    # Shell
    ln -s ${pkgs.bash}/bin/bash $out/bin/sh
    ln -s ${pkgs.bash}/bin/bash $out/bin/bash
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env

    # Build tools
    for tool in ${pkgs.nix}/bin/nix ${pkgs.iproute2}/bin/ip \
                ${pkgs.git}/bin/git ${pkgs.gnutar}/bin/tar ${pkgs.gzip}/bin/gzip; do
      ln -s $tool $out/bin/$(basename $tool)
    done

    # Coreutils
    for tool in ${pkgs.coreutils}/bin/*; do
      name=$(basename $tool)
      [ ! -e $out/bin/$name ] && ln -s $tool $out/bin/$name
    done

    # Users and groups (nix daemon needs nixbld users)
    echo "root:x:0:0::/root:/bin/sh" > $out/etc/passwd
    echo "root:x:0:" > $out/etc/group
    echo "nixbld:x:30000:" >> $out/etc/group
    for i in $(seq 1 32); do
      echo "nixbld$i:x:$((30000+i)):30000::/var/empty:/usr/sbin/nologin" >> $out/etc/passwd
    done

    # Name resolution
    echo "hosts: files dns" > $out/etc/nsswitch.conf
    echo "nameserver 8.8.8.8" > $out/etc/resolv.conf
  '';
in {
  options.kimb.nixSandbox = {
    enable = mkEnableOption "nix-sandbox remote build service";

    port = mkOption {
      type = types.port;
      default = 8090;
      description = "Port for the nix-sandbox API service";
    };

    buildMode = mkOption {
      type = types.enum ["direct" "nspawn"];
      default = "nspawn";
      description = "Build isolation: 'direct' for subprocess, 'nspawn' for nested systemd-nspawn";
    };

    maxConcurrent = mkOption {
      type = types.int;
      default = 2;
      description = "Maximum number of simultaneous builds";
    };

    buildTimeout = mkOption {
      type = types.int;
      default = 1800;
      description = "Maximum build time in seconds (max 1800)";
    };

    wanInterface = mkOption {
      type = types.str;
      default = "eno1";
      description = "Host network interface for outbound NAT from containers";
    };

    buildMemoryLimit = mkOption {
      type = types.str;
      default = "4G";
      description = "Per-build memory limit (systemd MemoryMax format)";
    };

    buildCpuQuota = mkOption {
      type = types.str;
      default = "200%";
      description = "Per-build CPU quota (systemd CPUQuota format, 200% = 2 cores)";
    };
  };

  config = mkIf cfg.enable {
    # Agenix secret for API token (decrypted on host, bind-mounted into container)
    age.secrets.nix-sandbox-token = {
      file = ../secrets/nix-sandbox-token.age;
      mode = "0400";
      owner = "root";
    };

    # NAT for container traffic + port forwarding to supervisor
    networking.nat = {
      enable = true;
      externalInterface = cfg.wanInterface;
      internalInterfaces = ["ve-+"];
    };
    networking.nat.forwardPorts = [
      {
        sourcePort = cfg.port;
        destination = "192.168.101.2:${toString cfg.port}";
        proto = "tcp";
      }
    ];

    # Allow API port from Nebula mesh
    networking.firewall.interfaces."nebula1" = {
      allowedTCPPorts = [cfg.port];
    };

    # Supervisor container
    containers.nix-sandbox = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = "192.168.101.1";
      localAddress = "192.168.101.2";

      # CAP_SYS_ADMIN is granted by default; CAP_NET_ADMIN needed for nested nspawn veth
      additionalCapabilities = ["CAP_NET_ADMIN"];

      bindMounts = {
        # Agenix secret from host
        "/run/secrets/api-token" = {
          hostPath = config.age.secrets.nix-sandbox-token.path;
          isReadOnly = true;
        };
        # Host nix daemon socket — builds use the host's single nix daemon
        "/nix/var/nix/daemon-socket" = {
          hostPath = "/nix/var/nix/daemon-socket";
        };
      };

      config = {
        pkgs,
        lib,
        ...
      }: {
        system.stateVersion = "24.11";

        # Nix CLI needs experimental features for `nix build` / `nix flake check`
        nix.settings.experimental-features = ["nix-command" "flakes"];

        # Disable container's own nix daemon — use host's via bind-mounted socket
        systemd.sockets.nix-daemon.enable = lib.mkForce false;
        systemd.services.nix-daemon.enable = lib.mkForce false;

        # Allow API traffic into the container
        networking.firewall.allowedTCPPorts = [cfg.port];

        # IP forwarding for per-build NAT (nspawn veth networking)
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

        # API service
        systemd.services.nix-sandbox = {
          description = "Nix Sandbox API Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];

          environment = {
            BUILD_MODE = cfg.buildMode;
            PORT = toString cfg.port;
            PRIMER_PATH = toString primerPath;
            BUILD_ROOT = toString buildRoot;
            MAX_CONCURRENT = toString cfg.maxConcurrent;
            BUILD_TIMEOUT = toString cfg.buildTimeout;
            BUILD_MEMORY_LIMIT = cfg.buildMemoryLimit;
            BUILD_CPU_QUOTA = cfg.buildCpuQuota;
          };

          path = with pkgs; [nix git gnutar gzip iproute2 iptables systemd coreutils];

          serviceConfig = {
            Restart = "always";
            RestartSec = "5s";
          };

          script = ''
            export API_TOKEN=$(cat /run/secrets/api-token)
            exec ${pkgs.python3}/bin/python3 ${apiScript}
          '';
        };

        # GC timer to clean up sandbox build outputs from the host store.
        # Since the daemon socket is bind-mounted from the host, nix-collect-garbage
        # talks to the host daemon and operates on the host store. It only deletes
        # paths with no GC roots — sandbox builds use --no-link (no roots), while
        # the host's system profiles and other services are protected.
        systemd.services.nix-sandbox-gc = {
          description = "Garbage-collect sandbox build outputs";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 1d";
          };
        };
        systemd.timers.nix-sandbox-gc = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };
    };
  };
}
