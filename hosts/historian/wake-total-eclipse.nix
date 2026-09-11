# Wake-on-LAN helper for total-eclipse (a3j.9.6).
#
# total-eclipse (the gaming PC) powers off on demand; its eno2 WoL is armed
# (kernel `enable` + ACPI PEG0). Moonlight clients send their own magic packet
# on session start, so this helper is for convenience / orchestration — e.g.
# `systemctl start wake-total-eclipse` from a script or an HA shell_command.
#
# The MAC is pinned here (the nebula-registry has no MAC column). historian is
# on the same LAN broadcast domain, so the default 255.255.255.255 broadcast
# reaches total-eclipse.
{
  config,
  lib,
  pkgs,
  ...
}: {
  systemd.services.wake-total-eclipse = {
    description = "Send a Wake-on-LAN magic packet to total-eclipse";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.wakeonlan}/bin/wakeonlan a8:a1:59:26:75:a4";
    };
  };
}
