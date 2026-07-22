# Base configuration for all NixOS hosts
{
  config,
  lib,
  pkgs,
  ...
}: let
  sshKeys = import ../ssh-keys.nix;
in {
  # Boot configuration
  boot = {
    # Bootloader - can be overridden by hosts
    loader = {
      systemd-boot.enable = lib.mkDefault true;
      efi.canTouchEfiVariables = lib.mkDefault true;
    };

    # Performance optimizations
    tmp.useTmpfs = true;
  };

  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";

  # Networking
  networking = {
    networkmanager.enable = true;
    nftables.enable = true;
  };

  # System services
  services = {
    fstrim.enable = true;
    dbus.implementation = "broker";

    # Disable systemd-resolved to respect DHCP-provided DNS servers
    # Use mkForce to override systemd-networkd's default enabling of resolved
    resolved.enable = lib.mkForce false;

    # SSH
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = false;
      };
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
  #
  # Binary caches: keys/URLs verified against the Cachix REST API
  # (app.cachix.org/api/v1/cache/<name>). Order matters — most-hit first.
  #   - cache.nixos.org:     nixpkgs (incl. nvidia drivers on stock kernel)
  #   - cache.nixos-cuda.org: CUDA-enabled builds (total-eclipse)
  #   - nix-community:        home-manager, srvos, disko, buildbot-nix,
  #                          nixos-facter-modules, flake-firefox-nightly
  #   - jovian:               Jovian NixOS (donut Steam Deck) — mesa/kernel
  #   - mccartykim:           own flakes (eden-nightly, borges, knitwork,
  #                          kokoro, qwen3-tts, media-classifier, org-*, etc.)
  #                          NOTE: buildbot push is currently disabled, so this
  #                          only serves artifacts pushed before 2026-06-22.
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "jovian.cachix.org-1:8Vq4Txku6VZIRhYrHYki3Ab9XHJRoWmdYqMqj4rB/Uc="
      "mccartykim.cachix.org-1:WzHencScmSzp4YOayeZBCqqNoM98LXFpf9wqUZf0e4s="
    ];
    substituters = [
      "https://cache.nixos.org/"
      "https://cache.nixos-cuda.org"
      "https://nix-community.cachix.org"
      "https://jovian.cachix.org"
      "https://mccartykim.cachix.org"
    ];
  };

  # Package configuration
  nixpkgs.config.allowUnfree = true;

  # Environment variables for unfree packages and Firefox gestures
  environment.sessionVariables = {
    # Allow unfree for comma/nix-run/nix-shell
    NIXPKGS_ALLOW_UNFREE = "1";
    # Better touchpad gestures and smooth scrolling in Firefox
    MOZ_USE_XINPUT2 = "1";
  };

  # Essential system packages
  environment.systemPackages = with pkgs; [
    neovim
    git
    gh
    wget
    jq
  ];

  # Essential programs
  programs.fish.enable = true;

  # Basic user configuration pattern
  users.users.kimb = {
    isNormalUser = true;
    description = lib.mkDefault "Kimb";
    extraGroups = ["wheel" "networkmanager"];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = sshKeys.authorizedKeys;
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
