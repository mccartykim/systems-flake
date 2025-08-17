# Nebula configuration with agenix secrets
{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.nebula-mesh;
in
{
  imports = [ 
    ./nebula-mesh.nix
    inputs.agenix.nixosModules.default
  ];

  config = mkIf cfg.enable {
    # Agenix secrets for Nebula
    age.secrets = {
      nebula-ca = {
        file = ../secrets/nebula-ca.age;
        path = "/etc/nebula/ca.crt";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0644";
      };
      
      nebula-cert = {
        file = ../secrets/nebula-${config.networking.hostName}-cert.age;
        path = "/etc/nebula/${config.networking.hostName}.crt";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0644";
      };
      
      nebula-key = {
        file = ../secrets/nebula-${config.networking.hostName}-key.age;
        path = "/etc/nebula/${config.networking.hostName}.key";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0600";
      };
    };

    # Update Nebula service to use agenix paths
    services.nebula.networks.mesh = {
      ca = config.age.secrets.nebula-ca.path;
      cert = config.age.secrets.nebula-cert.path;
      key = config.age.secrets.nebula-key.path;
    };

    # Ensure Nebula starts after agenix
    systemd.services."nebula@mesh" = {
      after = [ "agenix.service" ];
      wants = [ "agenix.service" ];
    };
  };
}