# Server-specific configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Services configuration
  services = {
    # Enhanced SSH configuration for servers
    openssh.settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };

    # Server networking optimizations
    tailscale.useRoutingFeatures = "server";

    # Performance and maintenance
    fstrim.enable = true;
    locate.enable = true;
    logrotate.enable = true;

    # Disable unnecessary desktop services
    udisks2.enable = false;
    gvfs.enable = false;
  };

  # Server networking optimizations
  networking = {
    firewall.enable = true;
    # Servers should use systemd-networkd, not NetworkManager
    networkmanager.enable = lib.mkForce false;
  };

  # Monitoring and maintenance packages
  environment.systemPackages = with pkgs; [
    htop
    iotop
    nmap
    tcpdump
    lsof
    strace
    tmux
    rsync
  ];

  hardware.bluetooth.enable = false;

  # Security hardening
  security.sudo.execWheelOnly = true;

  # Automatic updates for security
  system.autoUpgrade = {
    enable = lib.mkDefault false; # Can be enabled per-host
    dates = "04:00";
    allowReboot = false;
  };

  # Optimize for server workloads
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
  };
}
