# Donut (Steam Deck) installer
# Creates a bootable ISO that auto-installs NixOS with Jovian to the Steam Deck
#
# Usage:
#   1. Build: nix build .#donut-installer
#   2. Flash to SD card: dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
#   3. Boot Steam Deck from SD (hold Vol- and tap Power)
#   4. Wait for automatic installation
#   5. Remove SD card and reboot
#
# WARNING: This will ERASE the Steam Deck's internal storage!
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  target_hostname = "donut";
  # Steam Deck internal NVMe
  target_disk = "/dev/nvme0n1";
in {
  # Include the flake source in the ISO
  environment.etc.systems-flake = {
    source = ../.;
  };

  # ISO configuration
  isoImage = {
    compressImage = false; # Faster to write, larger file
    makeEfiBootable = true;
    makeUsbBootable = true;
    # Identify this as the donut installer
    isoName = "donut-nixos-installer.iso";
  };

  # Include Jovian overlay for building
  nixpkgs.overlays = [inputs.jovian-nixos.overlays.default];

  # Enable SSH for debugging if needed
  systemd.services.sshd.enable = true;
  users.users.nixos.openssh.authorizedKeys.keys = [
    # Add your SSH key here for remote debugging during install
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U"
  ];

  # Useful packages in the installer environment
  environment.systemPackages = with pkgs; [
    neovim
    git
    parted
    gptfdisk
    dosfstools
    e2fsprogs
  ];

  # Automatic installation service
  systemd.services.auto-install = {
    description = "Automated NixOS installation for Steam Deck (donut)";
    after = ["getty.target" "nscd.service" "network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    path = ["/run/current-system/sw"];

    script = ''
      set -euxo pipefail

      echo "=========================================="
      echo "  Steam Deck NixOS Installer (donut)"
      echo "=========================================="
      echo ""
      echo "WARNING: This will ERASE ${target_disk}!"
      echo "Starting in 10 seconds... (Ctrl+C to abort)"
      echo ""

      # Give user a chance to abort
      sleep 10

      echo "Step 1: Wiping and partitioning ${target_disk}..."

      # Wipe existing partition table
      wipefs -a ${target_disk} || true
      sgdisk --zap-all ${target_disk} || true

      # Create GPT partition table with:
      # - 512MB EFI System Partition
      # - Rest for root filesystem
      parted -s ${target_disk} -- mklabel gpt
      parted -s ${target_disk} -- mkpart ESP fat32 1MB 512MB
      parted -s ${target_disk} -- set 1 esp on
      parted -s ${target_disk} -- mkpart primary ext4 512MB 100%

      # Wait for partition devices to appear
      sleep 3
      partprobe ${target_disk} || true
      sleep 2

      echo "Step 2: Formatting partitions..."

      # Format EFI partition
      mkfs.fat -F 32 -n boot ${target_disk}p1

      # Format root partition
      mkfs.ext4 -F -L nixos ${target_disk}p2

      # Wait for labels to be recognized
      sleep 3

      echo "Step 3: Mounting filesystems..."

      mount /dev/disk/by-label/nixos /mnt
      mkdir -p /mnt/boot
      mount /dev/disk/by-label/boot /mnt/boot

      echo "Step 4: Copying flake configuration..."

      mkdir -p /mnt/etc/nixos
      cp -r /etc/systems-flake/* /mnt/etc/nixos/

      echo "Step 5: Installing NixOS..."
      echo "This may take a while depending on network speed..."

      # Install NixOS from flake
      nixos-install \
        --flake /mnt/etc/nixos#${target_hostname} \
        --no-root-password \
        --no-channel-copy

      echo "=========================================="
      echo "  Installation Complete!"
      echo "=========================================="
      echo ""
      echo "Next steps:"
      echo "  1. Remove the SD card"
      echo "  2. Reboot: systemctl reboot"
      echo "  3. Log in as 'kimb' with password 'deck'"
      echo "  4. CHANGE PASSWORD IMMEDIATELY: passwd"
      echo ""
      echo "To enable Nebula mesh network:"
      echo "  5. Get SSH host key: cat /etc/ssh/ssh_host_ed25519_key.pub"
      echo "  6. Update hosts/nebula-registry.nix with the key for 'donut'"
      echo "  7. Generate certs: nix run .#generate-nebula-certs"
      echo "  8. Edit hosts/donut/configuration.nix: set kimb.nebula.enable = true"
      echo "  9. Deploy: nix develop -c colmena apply --on donut"
      echo ""

      # Wait a bit before potential auto-reboot
      sleep 30

      echo "Rebooting in 10 seconds..."
      sleep 10
      reboot
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };
}
