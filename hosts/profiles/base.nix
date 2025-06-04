# Base configuration for all NixOS hosts
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Bootloader - can be overridden by hosts
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Performance optimizations
  boot.tmp.useTmpfs = true;
  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";
  services.fstrim.enable = true;
  services.dbus.implementation = "broker";

  # Networking
  networking.networkmanager.enable = true;
  networking.nftables.enable = true;
  services.tailscale.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Locale and timezone
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Nix configuration
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
    trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    substituters = [
      "https://cache.garnix.io"
      "https://cache.nixos.org/"
    ];
  };

  # Package configuration
  nixpkgs.config.allowUnfree = true;

  # Essential system packages
  environment.systemPackages = with pkgs; [
    neovim
    git
    wget
    tailscale
  ];

  # Essential programs
  programs.fish.enable = true;

  # Basic user configuration pattern
  users.users.kimb = {
    isNormalUser = true;
    description = lib.mkDefault "Kimb";
    extraGroups = ["wheel" "networkmanager"];
    shell = pkgs.fish;
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
