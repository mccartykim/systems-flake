# Laptop-specific configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Power management
  services.thermald.enable = true;
  services.auto-cpufreq.enable = true;

  # Disable conflicting power service
  services.power-profiles-daemon.enable = false;

  # Firmware updates
  services.fwupd.enable = true;

  # Hardware support
  services.hardware.bolt.enable = true; # Thunderbolt

  # Input devices - touchpad configuration
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      disableWhileTyping = true;
      tapping = true;
    };
  };

  # Laptop-specific packages
  environment.systemPackages = with pkgs; [
    powertop
    acpi
    brightnessctl
  ];

  # Networking - prefer Wi-Fi management
  networking.wireless.iwd.enable = lib.mkDefault false;
  networking.networkmanager.wifi.backend = lib.mkDefault "wpa_supplicant";

  # Battery optimization
  services.upower.enable = true;

  # Suspend/hibernate support
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=1h
  '';
}
