# Rich-Evans services configuration using kimb-services options system
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
in {
  # Copyparty — REMOVED at a3j.6 phase 6b: moved to historian with the
  # seagate (hosts/historian/copyparty.nix; volume now local there).

  # Home Assistant + mosquitto — REMOVED at a3j.6 phase 6a: moved to historian
  # as a unit (hosts/historian/home-assistant.nix; the registry entry lives
  # in the historian bucket now). The consumers still on this host (organism
  # daemons until a3j.7) point their haUrl at http://10.100.0.10:8123; the
  # vacuum's valetudo broker setting repoints to 192.168.69.167:1883.

  # Firewall configuration for enabled services
  networking.firewall = {
    allowedTCPPorts = lib.flatten [



      # CUPS printing
      [631]

    ];


  };

  # Create necessary directories
  systemd.tmpfiles.rules = lib.flatten [
  ];
}
