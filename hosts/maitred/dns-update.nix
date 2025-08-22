# Dynamic DNS configuration for maitred
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  # Cloudflare API token secret
  age.secrets.cloudflare-api-token = {
    file = ../../secrets/cloudflare-api-token.age;
    path = "/etc/inadyn/cloudflare-token";
    mode = "0400";
    owner = "inadyn";
    group = "inadyn";
  };

  # Create inadyn config file that substitutes agenix token
  system.activationScripts.inadyn-config = lib.stringAfter [ "agenix" ] ''
    # Read token and create config file
    token=$(cat "${config.age.secrets.cloudflare-api-token.path}")
    mkdir -p /etc/inadyn
    cat > /etc/inadyn/inadyn.conf << EOF
# In-A-Dyn configuration with agenix token
period = 300

provider cloudflare.com:1 {
    username = kimb.dev
    password = $token
    hostname = "kimb.dev"
    ttl = 1
    proxied = false
}

provider cloudflare.com:2 {
    username = kimb.dev
    password = $token
    hostname = "auth.kimb.dev"
    ttl = 1
    proxied = false
}

provider cloudflare.com:3 {
    username = kimb.dev
    password = $token
    hostname = "blog.kimb.dev"
    ttl = 1
    proxied = false
}

provider cloudflare.com:4 {
    username = kimb.dev
    password = $token
    hostname = "home.kimb.dev"
    ttl = 1
    proxied = false
}

provider cloudflare.com:5 {
    username = kimb.dev
    password = $token
    hostname = "grafana.kimb.dev"
    ttl = 1
    proxied = false
}

provider cloudflare.com:6 {
    username = kimb.dev
    password = $token
    hostname = "prometheus.kimb.dev"
    ttl = 1
    proxied = false
}

provider cloudflare.com:7 {
    username = kimb.dev
    password = $token
    hostname = "copyparty.kimb.dev"
    ttl = 1
    proxied = false
}
EOF
    chmod 600 /etc/inadyn/inadyn.conf
    chown inadyn:inadyn /etc/inadyn/inadyn.conf
  '';

  # Use the standard inadyn service with configFile
  services.inadyn = {
    enable = true;
    configFile = "/etc/inadyn/inadyn.conf";
  };

  # Ensure inadyn service runs after agenix
  systemd.services.inadyn = {
    after = [ "agenix.service" ];
    wants = [ "agenix.service" ];
  };

  # Create inadyn user and group
  users.users.inadyn = {
    isSystemUser = true;
    group = "inadyn";
  };
  users.groups.inadyn = {};
}
