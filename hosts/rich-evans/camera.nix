# Webcam snapshot server
# On-demand capture via HTTP - camera LED only active during capture
#
# Cameras:
#   /cam0 (/dev/video0) - Desk camera, monitors workspace
#   /cam1 (/dev/video2) - Bed camera, for sleep tracking/routine analysis
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Webcam snapshot HTTP server script
  environment.etc."webcam/server.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Simple HTTP server that captures on-demand
      # Reads HTTP request, serves fresh snapshot

      read request
      url=$(echo "$request" | cut -d' ' -f2)

      case "$url" in
        /cam0|/cam0.jpg)
          ${pkgs.fswebcam}/bin/fswebcam -d /dev/video0 --skip 30 -r 1280x720 --no-banner -q - 2>/dev/null | {
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: image/jpeg"
            echo "Cache-Control: no-cache"
            echo "Connection: close"
            echo ""
            cat
          }
          ;;
        /cam1|/cam1.jpg)
          ${pkgs.fswebcam}/bin/fswebcam -d /dev/video2 --skip 30 -r 1280x720 --no-banner -q - 2>/dev/null | {
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: image/jpeg"
            echo "Cache-Control: no-cache"
            echo "Connection: close"
            echo ""
            cat
          }
          ;;
        *)
          echo "HTTP/1.1 200 OK"
          echo "Content-Type: text/html"
          echo ""
          echo "<html><body>"
          echo "<h1>Webcams</h1>"
          echo "<p><a href='/cam0'>Camera 0</a></p>"
          echo "<p><a href='/cam1'>Camera 1</a></p>"
          echo "</body></html>"
          ;;
      esac
    '';
  };

  # Socket-activated webcam server
  systemd.sockets.webcam = {
    wantedBy = ["sockets.target"];
    listenStreams = ["8554"]; # Different port than arbus to avoid conflict with existing 8080
    socketConfig = {
      Accept = true;
      MaxConnections = 4;
    };
  };

  systemd.services."webcam@" = {
    description = "Webcam HTTP Handler";
    serviceConfig = {
      ExecStart = "/etc/webcam/server.sh";
      StandardInput = "socket";
      StandardOutput = "socket";
      User = "webcam";
      Group = "video";
    };
  };

  # Service user for webcam
  users.users.webcam = {
    isSystemUser = true;
    group = "video";
  };

  # Firewall - allow webcam port
  networking.firewall.allowedTCPPorts = [8554];
}
