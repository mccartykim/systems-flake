# Arbus - Raspberry Pi Gen 1 webcam server
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Hardware configuration (to be generated)
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/server.nix

    # Nebula mesh network
    ./nebula.nix

    # Raspberry Pi hardware support
    inputs.nixos-hardware.nixosModules.raspberry-pi-1
  ];

  # Host identification
  networking.hostName = "arbus";

  # Boot configuration for Raspberry Pi
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  # Webcam streaming with go2rtc
  services.go2rtc = {
    enable = true;
    settings = {
      # WebRTC/RTSP server configuration
      api.listen = ":1984"; # Web UI and API

      # Configure two USB webcams
      streams = {
        camera1 = ["ffmpeg:/dev/video0#video=h264"];
        camera2 = ["ffmpeg:/dev/video1#video=h264"];
      };

      # Enable WebRTC for low-latency browser viewing
      webrtc = {
        listen = ":8555";
      };

      # Enable RTSP server
      rtsp = {
        listen = ":8554";
      };
    };
  };

  # Add user to video group for camera access
  users.users.kimb.extraGroups = ["video"];

  # Firewall configuration - allow camera ports
  networking.firewall = {
    allowedTCPPorts = [
      1984 # go2rtc API/Web UI
      8554 # RTSP
      8555 # WebRTC
    ];
    allowedUDPPorts = [
      8555 # WebRTC
    ];
    trustedInterfaces = ["nebula1" "lo"];
  };

  # DNS configuration
  networking.nameservers = let
    registry = import ../nebula-registry.nix;
  in [
    registry.nodes.maitred.ip # maitred router via Nebula
    "1.1.1.1" # Fallback
  ];

  # Minimal packages for camera server
  environment.systemPackages = with pkgs; [
    v4l-utils # Video4Linux utilities for camera debugging
    ffmpeg # Video processing
  ];

  # Optimize for low-resource Raspberry Pi
  services.journald.extraConfig = ''
    SystemMaxUse=100M
  '';

  system.stateVersion = "24.11";
}
