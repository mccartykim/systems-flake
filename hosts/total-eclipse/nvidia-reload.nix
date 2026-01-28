{ config, lib, pkgs, ... }:

{
  # Systemd service to reload NVIDIA modules
  systemd.services.nvidia-module-reload = {
    description = "Reload NVIDIA kernel modules";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "reload-nvidia" ''
        set -e

        echo "Stopping display manager to release GPU..."
        systemctl stop display-manager.service

        # Wait for processes to release the GPU
        sleep 2

        echo "Unloading NVIDIA kernel modules..."
        # Unload modules in reverse dependency order
        ${pkgs.kmod}/bin/rmmod nvidia_drm || true
        ${pkgs.kmod}/bin/rmmod nvidia_uvm || true
        ${pkgs.kmod}/bin/rmmod nvidia_modeset || true
        ${pkgs.kmod}/bin/rmmod nvidia || true

        echo "Reloading NVIDIA kernel modules..."
        # Reload modules (nvidia-drm will load dependencies)
        ${pkgs.kmod}/bin/modprobe nvidia
        ${pkgs.kmod}/bin/modprobe nvidia_modeset
        ${pkgs.kmod}/bin/modprobe nvidia_drm
        ${pkgs.kmod}/bin/modprobe nvidia_uvm

        echo "Restarting display manager..."
        systemctl start display-manager.service

        echo "NVIDIA modules reloaded successfully"
      '';
    };
  };

  # Trigger the service on every activation
  system.activationScripts.nvidia-reload = lib.stringAfter [ "specialfs" ] ''
    echo "nvidia-module-reload.service" >> /run/nixos/activation-reload-list
  '';
}
