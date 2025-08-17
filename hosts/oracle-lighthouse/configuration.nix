{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    ./disk-config.nix
    ../../modules/nebula-mesh.nix
  ];

  # Oracle ARM instance configuration
  networking.hostName = "oracle-lighthouse";

  # Boot configuration for Oracle Cloud ARM
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = [ "net.ifnames=0" ];
    initrd.systemd.enable = false;  # Disable for first boot compatibility
  };
  
  # Re-enable firewall with specific rules
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 4242 ]; # Nebula lighthouse
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # Our admin user
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com"
    ];
  };

  # Minimal packages
  environment.systemPackages = with pkgs; [
    vim
    htop
  ];

  # Standard GC settings for ARM instance
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Nebula lighthouse configuration using our module
  services.nebula-mesh = {
    enable = true;
    hostName = "oracle-lighthouse";
    hostIP = "10.100.0.1";
    groups = [ "lighthouse" ];
    lighthouse = {
      enable = true;
      externalIP = "1.2.3.4"; # Update this with Oracle instance IP
    };
  };

  system.stateVersion = "24.05";
}