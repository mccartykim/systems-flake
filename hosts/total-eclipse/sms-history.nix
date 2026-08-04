# sms-history: read-only SMS reader for the Interrogator, cross-host via the
# fleet ssh key. The Interrogator (rich-evans, vox-organism daemon) ssh'es here
# as kimb; this forced command runs the KDE Connect D-Bus reader AS kimb --
# KDE Connect's conversations live on kimb's *session* bus
# (/run/user/1000/bus, 0600 owner-only), so a different uid cannot connect.
#
# Reuses the shared bridge-fleet-ssh-key: a THIRD prisoned forced-command
# target on that key (alongside navigator-summon on this host and the scribe
# on historian). The tool takes NO args and the forced command ignores
# $SSH_ORIGINAL_COMMAND, so there is no caller-controlled input surface -- the
# prison is the authorized_keys prefix + the fixed read-only reader.
#
# HARDENING (deferred per the least-privilege deferral): a dedicated
# `sms-history` system user + a sudoers rule to busctl AS kimb would drop the
# "runs as kimb" privilege. Today the reader runs as kimb but can do nothing
# but this one read (no pty, no forwarding, fixed command).
{ pkgs, lib, ... }:

let
  # The fleet-internal pubkey (rich-evans vox-organism daemon -> this host).
  # The SAME key navigator-summon and the historian scribe use; the private
  # half is agenix on rich-evans (bridge-fleet-ssh-key.age, owned by
  # vox-organism). See navigator_organism/nixos/module.nix:149.
  fleetKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJkCorkwI7RWuRNFg241GpMSj2ZE2rxgF+IPoPF7E8wN bridge-fleet (rich-evans->total-eclipse navigator-summon, forced-command)";

  # The read-only reader. Queries KDE Connect's activeConversations() on
  # kimb's session bus (busctl --json=short -> jq), filters to unread-incoming
  # (type==1 && read==0, last 14d, cap 40), emits JSONL. Field order per
  # models/conversationmessage.h: [eventF, body, addresses, date, type, read,
  # threadID, uID, subID, attachments]. Fail-closed: if the phone is
  # unreachable / kdeconnectd down, emit one {"error":...} record (honest,
  # no fake texts) and exit 0.
  sms-history-reader = pkgs.writeShellScript "sms-history" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.systemd pkgs.jq pkgs.coreutils]}
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    DEVICE="dc89aafee15644e9b871e4a02e31a474"  # Pixel 9 Pro
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
  # Prisoned forced command: the fleet key authenticates as kimb and can do
  # NOTHING but run this one read-only reader. kimb's normal login keys (set
  # in base.nix / paperless.nix) are unaffected -- the command= prefix is
  # per-key-entry.
  users.users.kimb.openssh.authorizedKeys.keys = [
    ''command="${sms-history-reader}",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${fleetKey}''
  ];
}