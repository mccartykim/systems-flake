# Migrated homepage dashboard using kimb-services options
{ config, lib, pkgs, ... }:

let
  cfg = config.kimb;
  
  # Generate service entries for enabled services
  generateServiceEntry = serviceName: service: {
    name = serviceName;
    group = "Services";
    href = "https://${service.subdomain}.${cfg.domain}";
    description = "Service running on ${service.host}:${toString service.port}";
    server = 
      if service.host == "maitred" then "localhost"
      else if service.host == "rich-evans" then "10.100.0.40"
      else if service.host == "bartleby" then "10.100.0.30"
      else "localhost";
    container = service.container;
  };
  
  # Filter enabled public services for homepage display
  enabledServices = lib.filterAttrs (name: service: 
    service.enable && 
    service.publicAccess && 
    name != "reverse-proxy" &&  # Don't show reverse proxy
    name != "homepage"          # Don't show homepage itself
  ) cfg.services;

in {
  services.homepage-dashboard = lib.mkIf cfg.services.homepage.enable {
    enable = true;

    openFirewall = false; # Manually control access

    listenPort = cfg.services.homepage.port;

    # Allow access through reverse proxy
    environmentFile = pkgs.writeText "homepage-env" ''
      HOMEPAGE_ALLOWED_HOSTS=home.${cfg.domain},localhost,127.0.0.1
    '';
    
    # Homepage configuration - map over enabled services
    settings = 
    let
      # Helper to create homepage entry for a service
      mkHomepageEntry = name: service: 
      let
        # Map service names to display names and descriptions
        serviceInfo = {
          authelia = { title = "Authelia SSO"; description = "Single Sign-On Authentication"; };
          grafana = { title = "Grafana"; description = "Metrics visualization and dashboards"; };
          prometheus = { title = "Prometheus"; description = "Metrics collection and alerting"; };
          blog = { title = "Blog"; description = "Personal blog and articles"; };
          homepage = { title = "Dashboard"; description = "Services dashboard"; };
          copyparty = { title = "Copyparty"; description = "File sharing and upload service"; };
          homeassistant = { title = "Home Assistant"; description = "Smart home automation platform"; };
        };
        
        info = serviceInfo.${name} or { title = name; description = "Service on ${service.host}"; };
        
        # Determine server for homepage display
        server = 
          if service.host == "maitred" && service.container then "192.168.100.3"  # blog container
          else if service.host == "maitred" then "localhost"
          else if service.host == "rich-evans" then "10.100.0.40"
          else if service.host == "bartleby" then "10.100.0.30"
          else "localhost";
          
      in lib.nameValuePair info.title {
        href = "https://${service.subdomain}.${cfg.domain}";
        description = info.description;
        inherit server;
        container = service.container;
        
        # Add widgets for specific services
        widget = lib.optionalAttrs (name == "grafana") {
          type = "grafana";
          url = "http://localhost:${toString service.port}";
          username = cfg.admin.name;
          password = "admin"; # TODO: Use secrets
        } // lib.optionalAttrs (name == "prometheus") {
          type = "prometheus";
          url = "http://localhost:${toString service.port}";
        } // lib.optionalAttrs (name == "homeassistant") {
          type = "homeassistant";
          url = "http://10.100.0.40:${toString service.port}";
          # key = "your_api_key"; # TODO: Add API key via secrets
        };
      };
      
      # Group services by category
      servicesByCategory = {
        "Authentication & Access" = ["authelia"];
        "Monitoring & Analytics" = ["grafana" "prometheus"];
        "Content & Media" = ["blog"];
        "File Storage & Sharing" = ["copyparty"];  
        "Home Automation" = ["homeassistant"];
      };
      
      # Create service entries for enabled services
      mkCategoryServices = category: serviceNames:
        let
          categoryServices = lib.filterAttrs (name: service: 
            service.enable && lib.elem name serviceNames
          ) cfg.services;
        in lib.optionalAttrs (categoryServices != {}) {
          ${category} = lib.mapAttrsToList mkHomepageEntry categoryServices;
        };
      
    in {
      title = "Kimb's Services";
      
      # Generate service groups by mapping over categories
      services = lib.mapAttrsToList mkCategoryServices servicesByCategory;
      
      # Widgets for system monitoring
      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
        {
          datetime = {
            text_size = "xl";
            format = {
              dateStyle = "short";
              timeStyle = "short";
              hour12 = false;
            };
          };
        }
      ];

      # Bookmarks
      bookmarks = [
        {
          "Development" = [
            {
              "GitHub" = [
                {
                  abbr = "GH";
                  href = "https://github.com/${cfg.admin.name}";
                }
              ];
            }
            {
              "NixOS Search" = [
                {
                  abbr = "NS";
                  href = "https://search.nixos.org";
                }
              ];
            }
          ];
        }
        {
          "Infrastructure" = [
            {
              "Nebula Certificate Authority" = [
                {
                  abbr = "CA";
                  href = "https://github.com/slackhq/nebula";
                }
              ];
            }
            {
              "Cloudflare Dashboard" = [
                {
                  abbr = "CF";
                  href = "https://dash.cloudflare.com";
                }
              ];
            }
          ];
        }
      ];
    };
  };

  # Firewall rules for homepage access
  networking.firewall = {
    interfaces = {
      # Allow homepage access from LAN and Nebula
      "br-lan".allowedTCPPorts = lib.mkIf cfg.services.homepage.enable [
        cfg.services.homepage.port
      ];
      "nebula-kimb".allowedTCPPorts = lib.mkIf cfg.services.homepage.enable [
        cfg.services.homepage.port
      ];
    };
  };
}