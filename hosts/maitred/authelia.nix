# Authelia authentication service using kimb-services options
{ config, lib, pkgs, ... }:

let
  cfg = config.kimb;

in {
  # Agenix secrets for Authelia
  age.secrets = lib.mkIf cfg.services.authelia.enable {
    authelia-jwt-secret = {
      file = ../../secrets/authelia-jwt-secret.age;
      mode = "0400";
      owner = "authelia-main";
      group = "authelia-main";
    };

    authelia-session-secret = {
      file = ../../secrets/authelia-session-secret.age;
      mode = "0400";
      owner = "authelia-main";
      group = "authelia-main";
    };

    authelia-storage-key = {
      file = ../../secrets/authelia-storage-key.age;
      mode = "0400";
      owner = "authelia-main";
      group = "authelia-main";
    };
  };

  # Authelia authentication service (host network)
  services.authelia.instances.main = lib.mkIf cfg.services.authelia.enable {
    enable = true;
    
    settings = {
      server = {
        address = "tcp://0.0.0.0:${toString cfg.services.authelia.port}";
      };

      log = {
        level = "info";
        format = "text";
      };

      totp = {
        issuer = cfg.domain;
      };

      authentication_backend = {
        file = {
          path = "/var/lib/authelia-main/users_database.yml";
        };
      };

      access_control = 
      let
        # Helper to create access control rule for a service
        mkAccessRule = policy: services: {
          domain = map (service: "${service.subdomain}.${cfg.domain}") services;
          inherit policy;
        };
        
        # Get enabled services by auth policy
        authServices = lib.filterAttrs (name: service: 
          service.enable && 
          service.publicAccess && 
          service.auth == "authelia"
        ) cfg.services;
        
        # Group services by auth requirements
        oneFactorServices = lib.attrValues (lib.filterAttrs (name: service: 
          name == "grafana"  # Grafana only needs one factor
        ) authServices);
        
        twoFactorServices = lib.attrValues (lib.filterAttrs (name: service: 
          name != "grafana"  # All other services need two factor
        ) authServices);
        
        # Generate rules dynamically
        dynamicRules = lib.flatten [
          (lib.optional (oneFactorServices != []) (mkAccessRule "one_factor" oneFactorServices))
          (lib.optional (twoFactorServices != []) (mkAccessRule "two_factor" twoFactorServices))
        ];
        
      in {
        default_policy = "deny";
        rules = [
          {
            domain = ["auth.${cfg.domain}"];
            policy = "bypass";
          }
          {
            domain = ["vacuum.${cfg.domain}"];
            policy = "one_factor";
          }
        ] ++ dynamicRules;
      };

      session = {
        name = "authelia_session";
        domain = cfg.domain;
        same_site = "lax";
        expiration = "1h";
        inactivity = "5m";
        remember_me_duration = "1M";
      };

      regulation = {
        max_retries = 3;
        find_time = "2m";
        ban_time = "5m";
      };

      storage = {
        local = {
          path = "/var/lib/authelia-main/db.sqlite3";
        };
      };

      notifier = {
        disable_startup_check = false;
        filesystem = {
          filename = "/var/lib/authelia-main/notification.txt";
        };
      };
    };

    secrets = {
      jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
      sessionSecretFile = config.age.secrets.authelia-session-secret.path;
      storageEncryptionKeyFile = config.age.secrets.authelia-storage-key.path;
    };
  };

  # Firewall configuration for authelia
  networking.firewall = {
    interfaces = {
      "br-lan".allowedTCPPorts = lib.mkIf cfg.services.authelia.enable [
        cfg.services.authelia.port
      ];
      "nebula-kimb".allowedTCPPorts = lib.mkIf cfg.services.authelia.enable [
        cfg.services.authelia.port
      ];
    };
  };
}