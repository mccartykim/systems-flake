# Arbus - Raspberry Pi Gen 1 webcam server
# Minimal config - no base/server profiles (Pi 1 resource constraints)
# Cross-compiled from x86_64-linux to armv6l-linux
{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}: let
  sshKeys = import ../ssh-keys.nix;
in {
  imports = [
    # SD image module for Raspberry Pi 1/Zero
    (modulesPath + "/installer/sd-card/sd-image-raspberrypi.nix")

    # Nebula mesh network
    ./nebula.nix
  ];

  # Disable heavy default modules for minimal armv6l image
  disabledModules = [
    "${modulesPath}/profiles/all-hardware.nix"
    "${modulesPath}/profiles/base.nix"
  ];

  # Host identification
  networking.hostName = "arbus";

  # Cross-compilation settings
  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs.config.allowBroken = true;

  # Overlays for cross-compilation fixes
  nixpkgs.overlays = [
    (final: super: {
      # cmake needs -latomic for ARM cross-compilation
      cmake = super.cmake.overrideAttrs (old: {
        env.NIX_CFLAGS_COMPILE = "-latomic";
      });

      # libcap Go bindings fail cross-compilation (wrong -m64 flag)
      # Disable Go support entirely for cross-compilation
      libcap = super.libcap.overrideAttrs (old: {
        # Force disable Go by overriding makeFlags
        makeFlags = builtins.filter (x: !(lib.hasPrefix "GOLANG" x || lib.hasPrefix "GOARCH" x || lib.hasPrefix "GOOS" x || lib.hasPrefix "GOFLAGS" x || lib.hasPrefix "GOCACHE" x)) (old.makeFlags or []) ++ ["GOLANG=no"];
      });

      # pytest-xdist has a flaky test (test_workqueue_ordered_by_input)
      # that fails due to worker assignment race conditions
      pythonPackagesExtensions = super.pythonPackagesExtensions ++ [
        (python-final: python-prev: {
          pytest-xdist = python-prev.pytest-xdist.overrideAttrs (old: {
            disabledTests = (old.disabledTests or []) ++ ["test_workqueue_ordered_by_input"];
          });
        })
      ];
    })
  ];

  # Hardware - minimal boot config for cross-compilation
  boot = {
    growPartition = true;
    # Minimal initrd for cross-compilation compatibility
    initrd.includeDefaultModules = false;
    initrd.kernelModules = ["ext4" "mmc_block"];
    supportedFilesystems = lib.mkForce ["vfat" "ext4"];

    # Disable RP1 modules (Pi 5 chip) - they cause armv6l cross-compilation errors
    # (missing __aeabi_uldivmod/__aeabi_ldivmod due to 64-bit division in armv6l)
    kernelPatches = [
      {
        name = "disable-rp1-for-armv6l";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          # Disable RP1 (Raspberry Pi 5) specific drivers
          PWM_RP1 = lib.mkForce no;
          I2C_DESIGNWARE_PLATFORM = lib.mkForce no;
          VIDEO_RP1_CFE = lib.mkForce no;
        };
      }
    ];
  };
  hardware.enableRedistributableFirmware = true;

  # On-demand webcam snapshots with fswebcam
  # Camera LED only on during capture (~2 seconds), not continuously
  # Uses a simple shell script HTTP server

  # Webcam snapshot HTTP server script
  environment.etc."webcam/server.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Simple HTTP server that captures on-demand
      # Reads HTTP request, serves fresh snapshot

      read request
      url=$(echo "$request" | cut -d' ' -f2)

      case "$url" in
        /cam0|/cam0.jpg)
          ${pkgs.fswebcam}/bin/fswebcam -d /dev/video0 --skip 30 -r 1280x720 --no-banner -q - 2>/dev/null | {
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: image/jpeg"
            echo "Cache-Control: no-cache"
            echo "Connection: close"
            echo ""
            cat
          }
          ;;
        /cam1|/cam1.jpg)
          ${pkgs.fswebcam}/bin/fswebcam -d /dev/video2 --skip 30 -r 1280x720 --no-banner -q - 2>/dev/null | {
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: image/jpeg"
            echo "Cache-Control: no-cache"
            echo "Connection: close"
            echo ""
            cat
          }
          ;;
        *)
          echo "HTTP/1.1 200 OK"
          echo "Content-Type: text/html"
          echo ""
          echo "<html><body>"
          echo "<h1>Arbus Webcams</h1>"
          echo "<p><a href='/cam0'>Camera 0</a></p>"
          echo "<p><a href='/cam1'>Camera 1</a></p>"
          echo "</body></html>"
          ;;
      esac
    '';
  };

  # Socket-activated webcam server using systemd + inetd-style
  systemd.sockets.webcam = {
    description = "Webcam HTTP Socket";
    wantedBy = ["sockets.target"];
    listenStreams = ["8080"];
    socketConfig = {
      Accept = true;
      MaxConnections = 4;
    };
  };

  systemd.services."webcam@" = {
    description = "Webcam HTTP Handler";
    serviceConfig = {
      ExecStart = "/etc/webcam/server.sh";
      StandardInput = "socket";
      StandardOutput = "socket";
      User = "webcam";
      Group = "video";
    };
  };

  # Service user for webcam
  users.users.webcam = {
    isSystemUser = true;
    group = "video";
  };

  # User configuration (minimal, from base profile)
  users.users.kimb = {
    isNormalUser = true;
    description = "Kimb";
    extraGroups = ["wheel" "video"];
    openssh.authorizedKeys.keys = sshKeys.authorizedKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  # SSH access
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Firewall configuration - allow camera port
  networking.firewall = {
    allowedTCPPorts = [
      8080 # webcam snapshot server
    ];
    trustedInterfaces = ["nebula1" "lo"];
  };

  # DNS configuration
  networking.nameservers = let
    registry = import ../nebula-registry.nix;
  in [
    registry.nodes.maitred.ip # maitred router via Nebula
    "1.1.1.1" # Fallback
  ];

  # Minimal packages - ustreamer handles streaming directly
  # NOTE: v4l-utils excluded - Qt dependencies have cross-compilation issues (libpq)
  environment.systemPackages = with pkgs; [
    # Minimal system - ustreamer is pulled in by systemd services
  ];

  # Optimize for low-resource Raspberry Pi
  services.journald.extraConfig = ''
    SystemMaxUse=100M
  '';

  # Bootstrap SSH host key from boot partition
  # This allows pre-generating the key and using it as an agenix recipient
  # before the system is deployed
  systemd.services.bootstrap-ssh-key = {
    description = "Copy pre-generated SSH host key from boot partition";
    wantedBy = ["multi-user.target"];
    before = ["sshd.service" "agenix.service"];
    unitConfig.ConditionPathExists = "!/etc/ssh/ssh_host_ed25519_key";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if [ -f /boot/ssh_host_ed25519_key ]; then
        echo "Copying pre-generated SSH host key from boot partition..."
        mkdir -p /etc/ssh
        cp /boot/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
        cp /boot/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
        chmod 600 /etc/ssh/ssh_host_ed25519_key
        chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
        chown root:root /etc/ssh/ssh_host_ed25519_key*
        echo "SSH host key installed successfully"
      else
        echo "No pre-generated SSH key found at /boot/ssh_host_ed25519_key"
        echo "Key will be generated by sshd on first start"
      fi
    '';
  };

  system.stateVersion = "24.11";
}
