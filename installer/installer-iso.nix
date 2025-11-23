# NixOS Flake-Aware Installer ISO Configuration
# Creates a bootable USB/ISO with the interactive TUI installer
{
  config,
  pkgs,
  lib,
  ...
}: let
  # Path to this installer directory
  installerDir = ./.;

  # Create a wrapped installer script with correct paths
  installerScript = pkgs.writeShellScriptBin "flake-installer" ''
    export FLAKE_ROOT="''${FLAKE_ROOT:-/mnt/flake}"
    exec ${installerDir}/tui/installer.sh "$@"
  '';

  # Create a package with all installer scripts
  installerPackage = pkgs.stdenv.mkDerivation {
    name = "flake-installer-scripts";
    src = installerDir;

    installPhase = ''
      mkdir -p $out/lib $out/tui $out/templates $out/generators

      # Install library scripts
      cp lib/*.sh $out/lib/
      chmod +x $out/lib/*.sh

      # Install TUI
      cp tui/*.sh $out/tui/
      chmod +x $out/tui/*.sh

      # Install templates
      cp templates/* $out/templates/

      # Install generators
      cp generators/*.sh $out/generators/
      chmod +x $out/generators/*.sh

      # Create wrapper that sets up paths
      mkdir -p $out/bin
      cat > $out/bin/flake-installer <<'EOF'
      #!/usr/bin/env bash
      SCRIPT_DIR="$(dirname "$(readlink -f "$0")")/.."
      export FLAKE_ROOT="''${FLAKE_ROOT:-/mnt/flake}"

      # Source libs
      export LIB_DIR="$SCRIPT_DIR/lib"

      exec "$SCRIPT_DIR/tui/installer.sh" "$@"
      EOF
      chmod +x $out/bin/flake-installer

      # Non-interactive generator
      cat > $out/bin/generate-host <<'EOF'
      #!/usr/bin/env bash
      SCRIPT_DIR="$(dirname "$(readlink -f "$0")")/.."
      export FLAKE_ROOT="''${FLAKE_ROOT:-/mnt/flake}"
      exec "$SCRIPT_DIR/generators/generate-host.sh" "$@"
      EOF
      chmod +x $out/bin/generate-host
    '';
  };
in {
  # ISO image configuration
  isoImage = {
    # Create a proper bootable ISO
    makeEfiBootable = true;
    makeUsbBootable = true;

    # Don't compress - faster writes to USB
    compressImage = false;

    # Include the flake on the ISO
    contents = [
      {
        source = "${installerDir}/..";
        target = "/flake";
      }
    ];

    # Add a README to the root
    appendToMenuLabel = " - Flake Installer";
  };

  # Copy the flake to /etc/systems-flake as backup
  environment.etc.systems-flake = {
    source = "${installerDir}/..";
  };

  # Enable SSH for remote installation support
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # Set a default root password for SSH access (change in production!)
  users.users.root.initialPassword = "nixos";

  # Create nixos user for convenience
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    initialPassword = "nixos";
  };

  # Passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Essential packages for installation
  environment.systemPackages = with pkgs; [
    # TUI tools
    dialog
    ncurses

    # Disk tools
    parted
    gptfdisk
    dosfstools
    e2fsprogs
    btrfs-progs
    cryptsetup
    lvm2

    # System tools
    pciutils
    usbutils
    lshw
    dmidecode

    # Network tools
    networkmanager
    iproute2
    wget
    curl

    # Editor
    neovim
    nano

    # Git for flake operations
    git
    jq

    # Nix tools
    nix-output-monitor

    # Our installer
    installerPackage
    installerScript
  ];

  # Auto-start the installer on boot (optional)
  # Uncomment to auto-launch TUI on boot
  # systemd.services.auto-installer = {
  #   description = "Auto-launch flake installer";
  #   after = ["getty@tty1.service"];
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #     StandardInput = "tty";
  #     StandardOutput = "tty";
  #     TTYPath = "/dev/tty1";
  #     ExecStart = "${installerScript}/bin/flake-installer";
  #   };
  # };

  # Show helpful message on login
  environment.etc."motd".text = ''

    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                     NixOS Flake-Aware Installer                              ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    ║                                                                              ║
    ║  To start the interactive installer, run:                                    ║
    ║                                                                              ║
    ║      flake-installer                                                         ║
    ║                                                                              ║
    ║  For non-interactive generation:                                             ║
    ║                                                                              ║
    ║      generate-host --hostname myhost --disk /dev/sda                         ║
    ║                                                                              ║
    ║  Your flake is mounted at: /mnt/flake (USB) or /etc/systems-flake (ISO)      ║
    ║                                                                              ║
    ║  SSH is enabled - connect remotely:                                          ║
    ║      ssh root@<ip-address>   (password: nixos)                               ║
    ║                                                                              ║
    ╚══════════════════════════════════════════════════════════════════════════════╝

  '';

  # Networking
  networking = {
    hostName = "nixos-installer";
    networkmanager.enable = true;
    wireless.enable = lib.mkForce false;
    firewall.enable = false;  # Disable for installation
  };

  # Enable flakes
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  # System version
  system.stateVersion = "24.11";
}
