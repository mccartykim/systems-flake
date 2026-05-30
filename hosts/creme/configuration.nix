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

  # Writerdeck console: kmscon replaces the kernel VT for custom fonts
  # and >16 colors. Required since this box has no X/Wayland.
  services.kmscon = {
    enable = true;
    hwRender = true;
    fonts = [{name = "Iosevka"; package = pkgs.iosevka;}];
    extraConfig = ''
      font-size=14
      xkb-layout=us
    '';
  };

  # Syncthing for syncing writing across devices.
  # First-run: web UI on http://creme.nebula:8384 to pair folders/devices.
  services.syncthing = {
    enable = true;
    user = "kimb";
    dataDir = "/home/kimb";
    configDir = "/home/kimb/.config/syncthing";
    openDefaultPorts = true;
  };

  # Neovim with vimwiki preloaded; init.lua is yours to write.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    configure.packages.creme.start = with pkgs.vimPlugins; [vimwiki];
  };

  environment.systemPackages = with pkgs; [
    tmux
    # acpi + brightnessctl already provided by laptop profile
  ];

  # Bare X server for ad-hoc GUI apps via `startx`. No display manager,
  # no window manager — `startx /run/current-system/sw/bin/emacs` (or a
  # ~/.xinitrc that does `exec emacs`) launches a single fullscreen app.
  # Deliberate: no WM means no easy browser-tab goofing.
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    xkb.layout = "us";
  };

  # Emacs daemon so `emacsclient -c` opens instantly.
  services.emacs.enable = true;

  system.stateVersion = "25.11";
}
