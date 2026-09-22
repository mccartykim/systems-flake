# Laptop-specific configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Push-to-talk dictation, ScrollLock-triggered, on every laptop. Hosts that
    # never activate graphical-session.target (creme's bare startx) override
    # startTarget downstream — see hosts/creme/configuration.nix.
    ../../modules/voxtype.nix
  ];

  kimb.voxtype = {
    enable = true;
    key = "SCROLLLOCK";
  };

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
          energy_performance_preference = "balance_power";
          turbo = "auto";
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
  systemd.sleep.settings.Sleep.HibernateDelaySec = "1h";
}
