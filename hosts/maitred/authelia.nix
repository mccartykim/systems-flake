# Authelia authentication service for maitred
# Provides SSO for monitoring and dashboard services
{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  # Authelia secrets
  age.secrets = {
    authelia-jwt-secret = {
      file = ../../secrets/authelia-jwt-secret.age;
      path = "/etc/authelia/jwt-secret";
      mode = "0444";  # World-readable since container will access it
    };
    authelia-session-secret = {
      file = ../../secrets/authelia-session-secret.age;
      path = "/etc/authelia/session-secret";
      mode = "0444";
    };
    authelia-storage-key = {
      file = ../../secrets/authelia-storage-key.age;
      path = "/etc/authelia/storage-key";
      mode = "0444";
    };
    authelia-users = {
      file = ../../secrets/authelia-users.age;
      path = "/etc/authelia/users.yml";
      mode = "0444";
    };
  };

  # NixOS container for Authelia
  containers.authelia = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "192.168.100.1";      # Router's container bridge IP
    localAddress = "192.168.100.4";     # Authelia container IP
    
    bindMounts = {
      "/etc/authelia/jwt-secret" = {
        hostPath = "/run/agenix/authelia-jwt-secret";
        isReadOnly = true;
      };
      "/etc/authelia/session-secret" = {
        hostPath = "/run/agenix/authelia-session-secret";
        isReadOnly = true;
      };
      "/etc/authelia/storage-key" = {
        hostPath = "/run/agenix/authelia-storage-key";
        isReadOnly = true;
      };
      "/etc/authelia/users.yml" = {
        hostPath = "/run/agenix/authelia-users";
        isReadOnly = true;
      };
    };
    
    config = { config, pkgs, ... }: {
      # Authelia service
      services.authelia.instances.main = {
        enable = true;
        
        secrets = {
          jwtSecretFile = "/etc/authelia/jwt-secret";
          sessionSecretFile = "/etc/authelia/session-secret";
          storageEncryptionKeyFile = "/etc/authelia/storage-key";
        };
        
        settings = {
          theme = "dark";
          default_2fa_method = "webauthn";
          
          server = {
            address = "tcp://0.0.0.0:9091";
          };
          
          log = {
            level = "info";
            format = "text";
          };
          
          authentication_backend = {
            password_reset.disable = true;
            file = {
              path = "/etc/authelia/users.yml";
              watch = true;
              password = {
                algorithm = "argon2";
                argon2 = {
                  variant = "argon2id";
                  iterations = 3;
                  memory = 65536;
                  parallelism = 4;
                  key_length = 32;
                  salt_length = 16;
                };
              };
            };
          };
          
          session = {
            name = "authelia_session";
            same_site = "lax";
            expiration = "1M";
            inactivity = "2h";
            remember_me = "30d";
            cookies = [
              {
                domain = "kimb.dev";
                authelia_url = "https://auth.kimb.dev";
              }
            ];
          };
          
          storage = {
            local = {
              path = "/var/lib/authelia-main/db.sqlite3";
            };
          };
          
          notifier = {
            disable_startup_check = true;
            filesystem = {
              filename = "/var/lib/authelia-main/notifications.txt";
            };
          };
          
          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = ["auth.kimb.dev"];
                policy = "bypass";
              }
              {
                domain = ["home.kimb.dev"];
                policy = "one_factor";
                subject = ["group:admins" "group:users"];
              }
              {
                domain = ["grafana.kimb.dev"];
                policy = "one_factor";
                subject = ["group:admins"];
              }
              {
                domain = ["prometheus.kimb.dev"];
                policy = "one_factor";
                subject = ["group:admins"];
              }
              {
                domain = ["copyparty.kimb.dev"];
                policy = "one_factor";
                subject = ["group:admins" "group:users"];
              }
            ];
          };
          
          webauthn = {
            disable = false;
            display_name = "kimb.dev Authentication";
            attestation_conveyance_preference = "direct";
            user_verification = "required";
            timeout = "60s";
          };
          
          totp = {
            disable = false;
            issuer = "kimb.dev";
            algorithm = "sha1";
            digits = 6;
            period = 30;
            skew = 1;
            secret_size = 32;
          };
        };
      };
      
      # Open firewall for Authelia
      networking.firewall.allowedTCPPorts = [ 9091 ];
      
      # Minimal system packages
      environment.systemPackages = with pkgs; [
        curl
        htop
      ];
      
      system.stateVersion = "24.11";
    };
  };
}