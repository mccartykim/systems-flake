{ config, pkgs, lib, ... }:

{
  # Boot configuration for Oracle Cloud
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = false;  # Oracle requires BIOS mode
  };

  boot.kernelParams = [
    "console=ttyS0"
    "console=tty0"
  ];

  # Enable growpart to expand disk on boot
  boot.growPartition = true;
  
  # Filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  # Enable swap file for 1GB RAM instance
  swapDevices = [{
    device = "/var/swapfile";
    size = 2048;
  }];

  # Optimize for low memory
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
  };

  # Network configuration
  networking.useDHCP = true;
  networking.useNetworkd = true;
  networking.hostName = "oracle-lighthouse";
  
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    # allowedUDPPorts = [ 4242 ]; # Nebula lighthouse port
  };

  # Time zone
  time.timeZone = "UTC";

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Ultra-minimal packages
  environment.systemPackages = with pkgs; [
    vim
    git
  ];
  
  # Enable flakes for remote updates
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "admin" ];

  # Optimize journald for low disk usage
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=100M
  '';

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Optimize Nix store
  nix.settings.auto-optimise-store = true;
  
  # Reduce memory usage during builds
  nix.settings.max-jobs = 1;
  nix.settings.cores = 1;

  # Cloud-init for initial setup
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  system.stateVersion = "24.05";
}