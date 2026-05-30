# creme - Dell Latitude E6400 ARG writerdeck
# Console-only network appliance — no X/Wayland; syncthing will sync text later.
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/laptop.nix
    ../../modules/nebula-node.nix
  ];

  networking.hostName = "creme";

  # BIOS boot on /dev/sda (no EFI on the E6400)
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = false;
  };

  # Use latest kernel for hardware compat on this old box
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Nebula mesh - reachable from your other personal devices
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
  };

  # Allow kimb to push closures via `nixos-rebuild --target-host`
  nix.settings.trusted-users = ["root" "kimb"];

  system.stateVersion = "25.11";
}
