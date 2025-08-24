# Wiki.js configuration for rich-evans
# House knowledge base and documentation system
{
  config,
  pkgs,
  ...
}: {
  # PostgreSQL database for Wiki.js
  services.postgresql = {
    enable = true;
    ensureDatabases = ["wikijs"];
    ensureUsers = [
      {
        name = "wikijs";
        ensureDBOwnership = true;
      }
    ];
  };

  # Wiki.js service - DISABLED
  services.wiki-js = {
    enable = false;
    
    settings = {
      # Network configuration
      port = 3100;
      bindIP = "0.0.0.0"; # Allow access from reverse proxy

      # PostgreSQL database configuration
      db = {
        type = "postgres";
        host = "localhost";
        port = 5432;
        user = "wikijs";
        db = "wikijs";
        pass = "wikijs123"; # Simple password
      };

      # Site configuration
      logLevel = "info";
      offline = false;
      
      # Trust reverse proxy headers for proper authentication
      trustProxy = true;
    };
  };

  # Set up PostgreSQL user password
  system.activationScripts.wiki-db-setup = {
    text = ''
      ${config.services.postgresql.package}/bin/psql -U postgres -d postgres -c \
        "ALTER USER wikijs WITH PASSWORD 'wikijs123';" || true
    '';
    deps = ["specialfs"];
  };

  # Open firewall for Wiki.js
  networking.firewall.allowedTCPPorts = [3100];

  # Ensure PostgreSQL is started before Wiki.js
  systemd.services.wiki-js = {
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
  };
}