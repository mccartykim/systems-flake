# Headless KDE Connect + the sms-history reader — the a3j.9.4 move from
# total-eclipse.
#
# kdeconnectd only needs a D-Bus *session* bus, not a graphical session, so it
# runs as a kimb systemd USER service with lingering enabled — no SDDM/Plasma
# dependency. The phone (mochi / Pixel 9 Pro, device dc89aafee...) pairs once
# (the user taps "accept" on the phone), after which KDE Connect syncs SMS to
# historian and the sms-history forced command below exposes a read-only JSONL
# reader on kimb's session bus.
#
# NOTE: the Interrogator's SMS tool is not wired yet (agent.org: "gated on
# mochi ... no SMS tool in your envelope yet"), so this is preparation — when
# the tool lands it reads from historian, not total-eclipse.
{
  pkgs,
  lib,
  ...
}: let
  # The fleet-internal pubkey (rich-evans vox-organism daemon). Same key the
  # navigator-summon + historian scribe use; the private half is agenix on
  # rich-evans (bridge-fleet-ssh-key.age, owned by vox-organism).
  fleetKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJkCorkwI7RWuRNFg241GpMSj2ZE2rxgF+IPoPF7E8wN bridge-fleet (rich-evans->historian sms-history, forced-command)";

  # Read-only reader: queries KDE Connect's activeConversations() on kimb's
  # session bus (busctl --json=short -> jq), filters to unread-incoming
  # (type==1 && read==0, last 14d, cap 40), emits JSONL. Field order per
  # models/conversationmessage.h: [eventF, body, addresses, date, type, read,
  # threadID, uID, subID, attachments]. Fail-closed: if the phone is
  # unreachable / kdeconnectd down, emit one {"error":...} record and exit 0.
  sms-history-reader = pkgs.writeShellScript "sms-history" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.systemd pkgs.jq pkgs.coreutils]}
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    DEVICE="dc89aafee15644e9b871e4a02e31a474"  # Pixel 9 Pro (mochi)
    SVC=org.kde.kdeconnect.daemon
    OBJ="/modules/kdeconnect/devices/$DEVICE"
    IFACE=org.kde.kdeconnect.device.conversations
    if ! OUT=$(busctl call --user --json=short "$SVC" "$OBJ" "$IFACE" activeConversations 2>/dev/null) || [ -z "$OUT" ]; then
      echo '{"error":"kdeconnect activeConversations unavailable (phone unreachable or daemon down)"}'
      exit 0
    fi
    printf '%s' "$OUT" | jq -c --argjson days 14 --argjson lim 40 '
        .data[0] // []
        | map(.data)
        | map(select(.[4] == 1 and .[5] == 0 and .[3] > ((now - ($days*86400))*1000)))
        | sort_by(.[3]) | reverse | .[0:$lim]
        | map({threadID: .[6], date_ms: .[3],
               date_iso: (.[3] / 1000 | todate),
               from: (.[2] | map(.[0]) | unique | join(",")),
               body: .[1]})
        | .[]'
  '';
in {
  # Installs kdePackages.kdeconnect-kde (kdeconnectd + kdeconnect-cli) and
  # opens the firewall (1714-1764 tcp+udp) for LAN discovery/transfer.
  programs.kdeconnect.enable = true;

  # Keep kimb's user manager (and thus the session bus) alive at boot without
  # a login session, and run kdeconnectd headless in it.
  users.users.kimb.linger = true;
  systemd.user.services.kdeconnectd = {
    description = "KDE Connect daemon (headless)";
    wantedBy = ["default.target"];
    serviceConfig = {
      ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnectd";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Prisoned forced command: the fleet key authenticates as kimb and can do
  # NOTHING but run this one read-only reader.
  users.users.kimb.openssh.authorizedKeys.keys = [
    ''command="${sms-history-reader}",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${fleetKey}''
  ];
}
