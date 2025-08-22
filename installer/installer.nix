{
  config,
  pkgs,
  lib,
  ...
}: let
  target_hostname = "rich-evans";
  target_disk = "/dev/sda";
in {
  environment.etc.systems-flake = {
    source = ../.;
  };

  isoImage = {
    compressImage = false;
    makeEfiBootable = true;
    makeUsbBootable = true;
  };

  systemd.services.sshd.enable = true;

  systemd.services.auto-install = {
    description = "Automated install of nixos flake config";
    after = ["getty.target" "nscd.service"];
    wantedBy = ["multi-user.target"];
    path = ["/run/current-system/sw"];

    script = ''
      set -euxo pipefail
      echo "Partitioning Disk"
      parted -s ${target_disk} -- mklabel gpt
      parted -s ${target_disk} -- mkpart primary 512MB 100%
      parted -s ${target_disk} -- mkpart ESP fat32 1MB 512MB
      parted -s ${target_disk} -- set 2 esp on

      echo "Formatting partions"
      mkfs.ext4 -F -L nixos ${target_disk}1
      echo "y" | mkfs.fat -F 32 -n boot ${target_disk}2

      sleep 5

      echo "Mounting partitions"
      mount /dev/disk/by-label/nixos /mnt
      mkdir -p /mnt/boot
      mount /dev/disk/by-label/boot /mnt/boot

      mkdir -p /mnt/etc/nixos
      cp -r /etc/systems-flake/* /mnt/etc/nixos/

      echo "Installing nixos from flake config"
      nixos-install --flake /mnt/etc/nixos#${target_hostname} --no-root-password
      sleep 10
      reboot
    '';
  };
}
