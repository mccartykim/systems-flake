# Apache Guacamole remote desktop gateway for rich-evans
# Provides web-based RDP, VNC, and SSH access to network hosts
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Guacamole services - DISABLED for now
  # TODO: Re-enable when proper OIDC/SSO integration is implemented
  services.guacamole-server = {
    enable = false;
    host = "0.0.0.0";
    port = 4822;
  };

  services.guacamole-client = {
    enable = false;
    enableWebserver = true;
    settings = {};
  };

  # Tomcat service - DISABLED (used by Guacamole client)
  # services.tomcat.enable = false;  # Implicit when guacamole-client is disabled

  # Guacamole data directory - not needed when disabled
  # systemd.tmpfiles.rules = [
  #   "d /var/lib/guacamole 0750 tomcat tomcat"
  # ];

  # Firewall configuration - DISABLED (ports not needed when Guacamole is disabled)
  # networking.firewall.allowedTCPPorts = [
  #   4822  # Guacamole daemon
  #   8080  # Guacamole web interface (Tomcat)
  # ];
}
