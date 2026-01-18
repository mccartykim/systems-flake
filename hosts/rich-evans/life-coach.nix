# Life Coach Agent
# AI-powered sleep schedule monitor that watches via webcam and yells at you
#
# SETUP: After deploying, SSH in and run:
#   sudo -u life-coach claude login
# Select "Claude account with subscription" and authenticate.
# The service will use your Max subscription credits.
#
# When auth expires, the service will fail. Re-run `claude login` to fix.
#
# HOME ASSISTANT TOKEN: Create a long-lived access token in Home Assistant,
# then encrypt it: echo "TOKEN" | agenix -e secrets/ha-life-coach-token.age
{
  config,
  lib,
  pkgs,
  claude_yapper,
  ...
}: {
  # Agenix secret for HA token
  age.secrets.ha-life-coach-token = {
    file = ../../secrets/ha-life-coach-token.age;
    owner = "life-coach";
    mode = "0400";
  };
  # NOTE: claude_yapper.nixosModules.default is imported at the flake level
  # (in flake-modules/nixos-configurations.nix) to avoid infinite recursion

  # Create dedicated user for the agent (regular user so claude login works)
  users.users.life-coach = {
    isNormalUser = true;
    group = "life-coach";
    home = "/var/lib/life-coach-agent";
    homeMode = "0750"; # Allow life-coach group (hass) to access for interrupt signals
    createHome = true;
    # Allow kimb to sudo as this user for login
    extraGroups = [];
  };
  users.groups.life-coach = {
    members = ["hass"]; # Allow HA to write interrupt events
  };

  # Make state directory accessible to life-coach group (for HA interrupt signals)
  # Use 'z' (not 'd') to fix permissions on existing directory
  systemd.tmpfiles.rules = [
    "z /var/lib/life-coach-agent 0750 life-coach life-coach -"
    "z /var/lib/life-coach-agent/state.db 0660 life-coach life-coach -"
    "z /var/lib/life-coach-agent/state.db-wal 0660 life-coach life-coach -"
    "z /var/lib/life-coach-agent/state.db-shm 0660 life-coach life-coach -"
  ];

  # Belt-and-suspenders: ensure directory permissions on every activation
  system.activationScripts.life-coach-agent-perms = lib.stringAfter ["users"] ''
    chmod 0750 /var/lib/life-coach-agent 2>/dev/null || true
  '';

  # Life Coach Agent service configuration
  services.life-coach-agent = {
    enable = true;
    user = "life-coach";

    # Camera URLs - webcam server is on this same host
    # cam0 = bed camera, cam1 = desk camera
    cameraBedUrl = "http://127.0.0.1:8554/cam0";
    cameraDeskUrl = "http://127.0.0.1:8554/cam1";

    # Smart lamp on LAN
    lampIP = "192.168.69.152";

    # Home Assistant for presence sensor (same host)
    homeAssistantUrl = "http://127.0.0.1:8123";
    homeAssistantTokenFile = config.age.secrets.ha-life-coach-token.path;

    # State directory for context persistence
    stateDir = "/var/lib/life-coach-agent";

    # Package from claude_yapper flake
    # The prompt is defined in claude_yapper/life_coach_prompt.txt
    package = claude_yapper.packages.${pkgs.stdenv.hostPlatform.system}.life-coach-agent;
    skillsPackage = claude_yapper.packages.${pkgs.stdenv.hostPlatform.system}.claude-skills;

    # Hybrid mode: use Haiku for speed/cost, with Sonnet oversight every 30 min
    hybridMode = {
      enable = true;
      fastModel = "haiku";
      oversightModel = "sonnet";
      interval = 1800;  # 30 minutes
    };
  };

  # Override systemd service for better failure handling
  systemd.services.life-coach-agent = {
    # Set HOME so claude can find its credentials
    # Set SHELL so Claude Code can use Bash tool
    # Set PYTHONUNBUFFERED so logs appear immediately in journald
    environment = {
      HOME = "/var/lib/life-coach-agent";
      SHELL = "${pkgs.bash}/bin/bash";
      PYTHONUNBUFFERED = "1";
    };

    # Add sqlite and jq to PATH for logging scripts
    path = [pkgs.sqlite pkgs.jq];

    serviceConfig = {
      # On failure, wait longer before restart to avoid spam
      RestartSec = lib.mkForce "5min";
    };
  };

  # Add claude-code to system so life-coach user can run `claude login`
  environment.systemPackages = [pkgs.claude-code];

  # kimb is in wheel group, so can already sudo. No extra rules needed.
  # To manage the service:
  #   sudo systemctl restart life-coach-agent
  #   sudo -u life-coach -i   (then run: claude login)

  # Open port for TTS audio serving to Chromecast devices
  networking.firewall.allowedTCPPorts = [8555];

  # Life Coach Dashboard - web UI showing agent sessions
  # Note: System prompt is read from the source directory (dashboard.py does cd to source)
  systemd.services.life-coach-dashboard = {
    description = "Life Coach Agent Dashboard";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    environment = {
      LIFE_COACH_DB = "/var/lib/life-coach-agent/state.db";
    };
    serviceConfig = {
      ExecStart = "${claude_yapper.packages.${pkgs.stdenv.hostPlatform.system}.life-coach-dashboard}/bin/life-coach-dashboard";
      User = "life-coach";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Stable wrapper script for HA to signal button presses
  # Path: /etc/life-coach-agent/signal_button_press.sh
  # Usage: signal_button_press.sh <button_id>
  environment.etc."life-coach-agent/signal_button_press.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      # Signal a button press interrupt to the life coach agent
      # Called by Home Assistant automation when button state changes
      set -euo pipefail
      BUTTON_ID="''${1:-}"
      if [ -z "$BUTTON_ID" ]; then
        echo "Usage: signal_button_press.sh <button_id>" >&2
        exit 1
      fi
      DB_PATH="/var/lib/life-coach-agent/state.db"
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" \
        "INSERT INTO interrupt_events (event_type, payload) VALUES ('button_press', '{\"button\": \"$BUTTON_ID\"}');"
      echo "Signaled button press: $BUTTON_ID"
    '';
  };

  # Signal script for user input from HA text box
  # Path: /etc/life-coach-agent/signal_user_input.sh
  environment.etc."life-coach-agent/signal_user_input.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      # Signal that user input was submitted via Home Assistant
      # Called by Home Assistant automation when input_text.life_coach_input changes
      set -euo pipefail
      DB_PATH="/var/lib/life-coach-agent/state.db"
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" \
        "INSERT INTO interrupt_events (event_type, payload) VALUES ('user_input', '{}');"
      echo "Signaled user input received"
    '';
  };

  # Signal script for location changes from HA geofencing
  # Path: /etc/life-coach-agent/signal_location_change.sh
  # Usage: signal_location_change.sh <home|at_office|wfh>
  environment.etc."life-coach-agent/signal_location_change.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      # Signal a location change to the life coach agent
      # Called by Home Assistant automation when phone enters/leaves zones
      set -euo pipefail
      LOCATION="''${1:-}"
      if [[ ! "$LOCATION" =~ ^(home|at_office|wfh)$ ]]; then
        echo "Usage: signal_location_change.sh <home|at_office|wfh>" >&2
        exit 1
      fi
      DB_PATH="/var/lib/life-coach-agent/state.db"
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" \
        "INSERT INTO interrupt_events (event_type, payload) VALUES ('location_change', '{\"location\": \"$LOCATION\"}');"
      echo "Signaled location: $LOCATION"
    '';
  };
}
