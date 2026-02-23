# Minimal NixOS VM configuration for nix-sandbox build environment.
# Built via nixos-generators as a qcow image.
# Boots with serial console, mounts virtiofs shares, runs build agent.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Minimal system
  system.stateVersion = "24.11";
  documentation.enable = false;

  # Boot: serial console, no display
  boot = {
    kernelParams = ["console=ttyS0,115200n8"];
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_net"
      "virtiofs"
      "9p"
      "9pnet_virtio"
    ];
  };

  # Additional filesystem mounts (root fs handled by nixos-generators qcow format)
  fileSystems = {
    # virtiofs mount for host /nix/store (read-only)
    "/nix/store" = {
      device = "nix-store";
      fsType = "virtiofs";
      options = ["ro"];
    };
    # virtiofs mount for build workspace
    "/build" = {
      device = "build-dir";
      fsType = "virtiofs";
    };
  };

  # Nix with flakes enabled
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      # Allow builds from any user
      trusted-users = ["root" "builder"];
      # Limit parallelism inside the VM (host controls total resources)
      max-jobs = 4;
      cores = 0; # Use all available cores per job
    };
  };

  # Minimal packages for building
  environment.systemPackages = with pkgs; [
    git
    curl
    gnutar
    gzip
    xz
  ];

  # Networking: configured dynamically from kernel cmdline by build agent
  networking = {
    hostName = "sandbox";
    useDHCP = false;
    firewall.enable = false;
  };

  # Builder user (non-root builds)
  users.users.builder = {
    isNormalUser = true;
    home = "/build/home";
    group = "builder";
  };
  users.groups.builder = {};

  # Build agent: reads /build/metadata.json, executes nix commands, reports results
  systemd.services.build-agent = {
    description = "Nix Sandbox Build Agent";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "nix-daemon.service"];
    wants = ["network-online.target"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "build-agent" ''
        set -euo pipefail

        echo "Build agent starting..."

        # Configure networking from kernel cmdline
        CMDLINE=$(cat /proc/cmdline)
        VM_IP=$(echo "$CMDLINE" | grep -oP 'sandbox\.ip=\K[0-9.]+' || true)
        VM_GW=$(echo "$CMDLINE" | grep -oP 'sandbox\.gw=\K[0-9.]+' || true)
        VM_DNS=$(echo "$CMDLINE" | grep -oP 'sandbox\.dns=\K[0-9.]+' || true)

        if [ -n "$VM_IP" ] && [ -n "$VM_GW" ]; then
          echo "Configuring network: IP=$VM_IP GW=$VM_GW DNS=$VM_DNS"
          ip addr add "$VM_IP/24" dev ens3 2>/dev/null || ip addr add "$VM_IP/24" dev eth0 2>/dev/null || true
          ip link set ens3 up 2>/dev/null || ip link set eth0 up 2>/dev/null || true
          ip route add default via "$VM_GW" 2>/dev/null || true
          if [ -n "$VM_DNS" ]; then
            echo "nameserver $VM_DNS" > /etc/resolv.conf
          fi
        fi

        # Wait for metadata
        METADATA="/build/metadata.json"
        for i in $(seq 1 30); do
          if [ -f "$METADATA" ]; then
            break
          fi
          echo "Waiting for metadata... ($i/30)"
          sleep 1
        done

        if [ ! -f "$METADATA" ]; then
          echo "ERROR: No metadata.json found after 30s"
          echo "BUILD_EXIT_CODE=1"
          poweroff
          exit 1
        fi

        # Parse metadata
        SOURCE_TYPE=$(${pkgs.jq}/bin/jq -r '.source_type' "$METADATA")
        COMMAND=$(${pkgs.jq}/bin/jq -r '.command' "$METADATA")
        TARGET=$(${pkgs.jq}/bin/jq -r '.target // ""' "$METADATA")
        URL=$(${pkgs.jq}/bin/jq -r '.url // ""' "$METADATA")
        TARBALL_PATH=$(${pkgs.jq}/bin/jq -r '.tarball_path // ""' "$METADATA")
        TIMEOUT=$(${pkgs.jq}/bin/jq -r '.timeout // 1800' "$METADATA")

        echo "Source type: $SOURCE_TYPE"
        echo "Command: $COMMAND"
        echo "Target: $TARGET"

        # Prepare source
        WORK_DIR="/build/work"
        mkdir -p "$WORK_DIR"

        if [ "$SOURCE_TYPE" = "git" ]; then
          echo "Cloning $URL..."
          ${pkgs.git}/bin/git clone --depth 1 "$URL" "$WORK_DIR/src" 2>&1 || {
            echo "ERROR: git clone failed"
            echo "BUILD_EXIT_CODE=1"
            poweroff
            exit 1
          }
        elif [ "$SOURCE_TYPE" = "tarball" ]; then
          echo "Extracting tarball..."
          mkdir -p "$WORK_DIR/src"
          ${pkgs.gnutar}/bin/tar xzf "$TARBALL_PATH" -C "$WORK_DIR/src" --strip-components=1 2>&1 || {
            echo "ERROR: tarball extraction failed"
            echo "BUILD_EXIT_CODE=1"
            poweroff
            exit 1
          }
        fi

        cd "$WORK_DIR/src"

        # Execute nix command
        EXIT_CODE=0
        if [ "$COMMAND" = "build" ]; then
          if [ -n "$TARGET" ]; then
            echo "Running: nix build $TARGET --no-link"
            timeout "$TIMEOUT" nix build "$TARGET" --no-link 2>&1 || EXIT_CODE=$?
          else
            echo "Running: nix build --no-link"
            timeout "$TIMEOUT" nix build --no-link 2>&1 || EXIT_CODE=$?
          fi
        elif [ "$COMMAND" = "check" ]; then
          echo "Running: nix flake check"
          timeout "$TIMEOUT" nix flake check 2>&1 || EXIT_CODE=$?
        fi

        echo ""
        echo "BUILD_EXIT_CODE=$EXIT_CODE"

        # Shutdown VM
        poweroff
      ''}";

      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyS0";
    };
  };
}
