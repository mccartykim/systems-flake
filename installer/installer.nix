
{ config, pkgs, lib, ... }:
let
  target_hostname = "rich-evans";
  target_disk = "/dev/sda";
in
{
  environment.etc.systems-flake = {
    source = ../.;
  };

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  systemd.services.auto-install = {
    description = "Automated install of nixos flake config";
    after = ["multi-user.target"];
    wantedBy = [ "multi-user.target" ];

    script = ''
    #!/usr/bin/env bash

    # TODO - try disko?
    echo "Partitioning Disk"
    parted ${target_disk} -- mklabel gpt
    parted ${target_disk} -- mkpart primary 512MB -8GB
    parted ${target_disk} -- mkpart primary linux-swap -8GB 100%
    parted ${target_disk} -- mkpart ESP fat32 1MB 512MB
    parted ${target_disk} -- set 3 esp on

    echo "Formatting partions"
    mkfs.ext4 -L nixos ${target_disk}1
    mkswap -L swap ${target_disk}2
    mkfs.fat -F 32 -n boot ${target_disk}3

    echo "Mounting partitions"
    mount /dev/disk/by-label/nixos /mnt
    mkdir -p /mnt/boot
    mount /dev/disk/by-label/boot /mnt/boot
    mount /dev/disk/by-label/swap /mnt/swap
    swapon /dev/disk/by-label/swap

    mkdir -p /mnt/etc/nixos
    cp -r /etc/systems-flake/* /mnt/etc/nixos/

    echo "Installing nixos from flake config"
    nixos-install --flake /mnt/etc/nixos#${target_hostname} --no-root-password
    sleep 10
    reboot
    '';
  };
}
