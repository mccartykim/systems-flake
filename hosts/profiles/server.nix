# Server-specific configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enhanced SSH configuration for servers
  services.openssh.settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    X11Forwarding = false;
  };

  # Server networking optimizations
  networking.firewall.enable = true;
  services.tailscale.useRoutingFeatures = "server";
  
  # Servers should use systemd-networkd, not NetworkManager
  networking.networkmanager.enable = lib.mkForce false;

  # Performance and maintenance
  services.fstrim.enable = true;
  services.locate.enable = true;
  services.logrotate.enable = true;

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

  # Disable unnecessary desktop services
  services.udisks2.enable = false;
  services.gvfs.enable = false;
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
