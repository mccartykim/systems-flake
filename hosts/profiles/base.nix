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
  
  # Disable systemd-resolved to respect DHCP-provided DNS servers
  services.resolved.enable = lib.mkDefault false;

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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com"  # Main key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com"  # historian key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJY8TB1PRV5e8e8QgdwFRPbuRIzjeS1oFY1WOUKTYnrj mccartykim@zoho.com"  # total-eclipse key
      # Add marshmallow, bartleby keys when available
    ];
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
