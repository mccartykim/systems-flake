# Gaming configuration for Steam and related services
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Steam configuration
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  programs.gamescope.enable = true;

  # Virtualization for gaming
  virtualisation = {
    waydroid.enable = true;
    podman.enable = true;
  };

  # Game streaming service (Sunshine)
  services.sunshine = {
    enable = lib.mkDefault false; # Enable per-host as needed
    openFirewall = true;
    capSysAdmin = true;
  };

  # Gaming-specific packages
  environment.systemPackages = with pkgs; [
    mangohud
    gamemode
    # lutris  # Disabled - causing issues
    wine
    winetricks
  ];

  # Performance optimizations for gaming
  programs.gamemode.enable = true;

  # Additional firewall rules for game streaming
  networking.firewall = {
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

  # Hardware acceleration and graphics optimizations
  hardware.graphics.extraPackages = with pkgs; [
    libva-vdpau-driver
    libvdpau-va-gl
  ];
}
