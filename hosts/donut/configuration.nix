# Donut - Steam Deck with Jovian NixOS
# Provides SteamOS-like experience on NixOS with Gaming Mode + Desktop switching
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Disk partitioning (disko)
    inputs.disko.nixosModules.disko
    ./disko.nix

    # Role-based profiles
    ../profiles/base.nix

    # Jovian NixOS modules for Steam Deck
    inputs.jovian-nixos.nixosModules.jovian

    # Nebula mesh network
    ../../modules/nebula-node.nix
  ];

  # Nebula mesh network configuration
  # IMPORTANT: Enable after first boot once you have the SSH host key:
  #   1. Get key: ssh kimb@<deck-ip> 'cat /etc/ssh/ssh_host_ed25519_key.pub'
  #   2. Update hosts/nebula-registry.nix with the publicKey
  #   3. Generate certs: nix run .#generate-nebula-certs
  #   4. Set enable = true below
  #   5. Deploy: nix develop -c colmena apply --on donut
  kimb.nebula = {
    enable = false; # Enable after generating nebula certs (see above)
    openToPersonalDevices = true;
  };

  # Steam Deck hardware support
  jovian = {
    devices.steamdeck = {
      enable = true;
      autoUpdate = true; # Keep firmware updated
    };

    steam = {
      enable = true;
      autoStart = true; # Boot directly into Gaming Mode
      user = "kimb";
      desktopSession = "plasma"; # Switch to Plasma desktop when leaving Gaming Mode
    };

    # Enable Steam Deck UI (gamescope)
    decky-loader.enable = true; # Plugin framework for Gaming Mode
  };

  # Network configuration
  networking = {
    hostName = "donut";

    # Use maitred router for DNS
    nameservers = let
      registry = import ../nebula-registry.nix;
    in [
      registry.nodes.maitred.ip # maitred router via Nebula
      "1.1.1.1" # Fallback
    ];

    # Steam Remote Play and Sunshine streaming
    firewall = {
      allowedTCPPorts = [
        47984
        47989
        48010 # Sunshine
      ];
      allowedUDPPorts = [
        47998
        47999
        48000 # Sunshine
      ];
    };
  };

  # Desktop environment for "Switch to Desktop" mode
  services.desktopManager.plasma6.enable = true;

  # Audio via PipeWire (handled by Jovian, but ensure it's configured)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Steam with extra compatibility layers
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  # Game mode / performance optimization
  programs.gamemode.enable = true;

  # Gaming packages
  environment.systemPackages = with pkgs; [
    mangohud
    gamemode
    wine
    winetricks
    # Utilities
    brightnessctl
    powertop
  ];

  # Power management for handheld
  services = {
    # Battery optimization
    upower.enable = true;
    # Firmware updates (Steam Deck BIOS etc)
    fwupd.enable = true;

    # Disable services that conflict with Jovian's power management
    thermald.enable = lib.mkForce false;
    auto-cpufreq.enable = lib.mkForce false;
    power-profiles-daemon.enable = lib.mkForce false;
  };

  # User configuration
  users.users.kimb = {
    extraGroups = ["video" "audio" "input"];
    initialPassword = "deck"; # Change after first login!
  };

  # Swap for gaming (Steam Deck has limited RAM)
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8 * 1024; # 8GB swap
    }
  ];

  # Trust kimb for nix operations
  nix.settings.trusted-users = ["root" "kimb"];

  system.stateVersion = "24.11";
}
