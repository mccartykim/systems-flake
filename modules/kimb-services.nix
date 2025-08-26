# Kimb Services NixOS Module
# Defines all service options for kimb.dev infrastructure
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.kimb;
  
  # Helper types
  serviceType = types.submodule ({ name, config, ... }: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable this service";
      };
      
      port = mkOption {
        type = types.port;
        description = "Port number for the service";
      };
      
      subdomain = mkOption {
        type = types.str;
        default = name;
        description = "Subdomain for the service (without .kimb.dev)";
      };
      
      host = mkOption {
        type = types.str;
        default = "maitred";
        description = "Which host runs this service";
      };
      
      container = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this service runs in a container";
      };
      
      publicAccess = mkOption {
        type = types.bool;
        default = true;
        description = "Whether service should be accessible from internet";
      };
      
      auth = mkOption {
        type = types.enum [ "none" "authelia" "builtin" ];
        default = "authelia";
        description = "Authentication method required";
      };
      
      websockets = mkOption {
        type = types.bool;
        default = false;
        description = "Whether service needs WebSocket support";
      };
    };
  });

in {
  options.kimb = {
    # Domain configuration
    domain = mkOption {
      type = types.str;
      default = "kimb.dev";
      description = "Primary domain for all services";
    };
    
    # User configuration  
    admin = {
      name = mkOption {
        type = types.str;
        default = "kimb";
        description = "Admin username";
      };
      
      email = mkOption {
        type = types.str;
        default = "mccartykim@zoho.com";
        description = "Admin email address";
      };
      
      displayName = mkOption {
        type = types.str;
        default = "Kimberly";
        description = "Admin display name";
      };
      
      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com"
        ];
        description = "SSH public keys for admin user";
      };
    };
    
    # Service definitions using the serviceType
    services = mkOption {
      type = types.attrsOf serviceType;
      default = {};
      description = "Service configurations";
    };
    
    # DNS configuration
    dns = {
      provider = mkOption {
        type = types.str;
        default = "cloudflare";
        description = "DNS provider";
      };
      
      ttl = mkOption {
        type = types.int;
        default = 1;
        description = "DNS TTL in minutes";
      };
      
      updatePeriod = mkOption {
        type = types.int;
        default = 300;
        description = "Dynamic DNS update period in seconds";
      };
      
      servers = {
        primary = mkOption {
          type = types.str;
          default = "192.168.69.1";
          description = "Primary DNS server (usually maitred)";
        };
        
        fallback = mkOption {
          type = types.listOf types.str;
          default = [ "8.8.8.8" "8.8.4.4" ];
          description = "Fallback DNS servers";
        };
      };
    };
    
    # Network configuration
    networks = {
      containerBridge = mkOption {
        type = types.str;
        default = "192.168.100.1";
        description = "Container bridge IP address";
      };
      
      reverseProxyIP = mkOption {
        type = types.str;
        default = "192.168.100.2";
        description = "Reverse proxy container IP";
      };
      
      trustedNetworks = mkOption {
        type = types.listOf types.str;
        default = [
          "192.168.0.0/16"   # LAN
          "10.100.0.0/16"    # Nebula
          "100.64.0.0/10"    # Tailscale
        ];
        description = "Networks that bypass certain restrictions";
      };
    };
    
    # Computed values (read-only)
    computed = mkOption {
      type = types.attrs;
      readOnly = true;
      description = "Computed values derived from service configurations";
    };
  };
  
  # Computed/derived values available to other modules  
  config.kimb.computed = {
      # Full domain names for all services
      serviceDomains = mapAttrs (name: service: 
        "${service.subdomain}.${cfg.domain}"
      ) cfg.services;
      
      # Only enabled services
      enabledServices = filterAttrs (name: service: 
        service.enable
      ) cfg.services;
      
      # Services grouped by authentication requirement
      publicServices = filterAttrs (name: service:
        service.enable && service.auth == "none"
      ) cfg.services;
      
      authenticatedServices = filterAttrs (name: service:
        service.enable && service.auth == "authelia"
      ) cfg.services;
      
      # Services grouped by host
      servicesByHost = groupBy (service: service.host) 
        (attrValues cfg.services);
      
      # Container services
      containerServices = filterAttrs (name: service:
        service.enable && service.container
      ) cfg.services;
      
      # Services with resolved host IP addresses
      servicesWithIPs = let
        registry = import ../hosts/nebula-registry.nix;
        addIP = name: service: service // {
          hostIP = registry.nodes.${service.host}.ip or "127.0.0.1";
        };
      in mapAttrs addIP cfg.services;
      
      # All domains that need DNS records  
      allDomains = [ cfg.domain ] ++ (attrValues (mapAttrs (name: service: 
        "${service.subdomain}.${cfg.domain}"
      ) (filterAttrs (name: service: service.enable) cfg.services)));
      
      # Services that need WebSocket support
      websocketServices = filterAttrs (name: service:
        service.enable && service.websockets
      ) cfg.services;
  };
}