# Laptop-specific configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Services configuration
  services = {
    # Power management
    thermald.enable = true;
    auto-cpufreq = {
      enable = true;
      settings = {
        charger = {
          governor = "powersave";
          energy_performance_preference = "balance_performance";
          turbo = "auto";
        };
        battery = {
          governor = "powersave";
          energy_performance_preference = "power";
          turbo = "never";
        };
      };
    };

    # Disable conflicting power service
    power-profiles-daemon.enable = false;

    # Firmware updates
    fwupd.enable = true;

    # Hardware support
    hardware.bolt.enable = true; # Thunderbolt

    # Input devices - touchpad configuration
    libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        disableWhileTyping = true;
        tapping = true;
      };
    };

    # Battery optimization
    upower.enable = true;
  };

  # Laptop-specific packages
  environment.systemPackages = with pkgs; [
    powertop
    acpi
    brightnessctl
    lm_sensors
  ];

  # Networking - prefer Wi-Fi management
  networking.wireless.iwd.enable = lib.mkDefault false;
  networking.networkmanager.wifi.backend = lib.mkDefault "wpa_supplicant";

  # Suspend/hibernate support
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=1h
  '';
}
