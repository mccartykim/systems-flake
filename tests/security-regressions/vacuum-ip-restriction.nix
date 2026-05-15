# Security regression — pins N-1 from docs/security-audit.md.
#
# `hosts/maitred/reverse-proxy.nix:106-114` exposes `vacuum.kimb.dev` on the
# public internet behind Authelia 1FA only. The audit fix is to add an
# `@allowed { remote_ip ... }` block (LAN/Nebula/Tailscale) so the dashboard
# is only reachable from trusted networks.
#
# This derivation inspects the rendered Caddy `extraConfig` for the
# `vacuum.kimb.dev` virtual host on the real maitred config and asserts
# that an IP allowlist is present.
#
# A boot-and-curl VM test would require booting the nested reverse-proxy
# NixOS container; out of scope here. The static check is sufficient to
# surface the gap in CI.
{
  pkgs,
  maitredCfg,
  ...
}: let
  vhosts = maitredCfg.containers.reverse-proxy.config.services.caddy.virtualHosts;
  vacuum = vhosts."vacuum.kimb.dev" or null;
  vacuumExtraConfig =
    if vacuum == null
    then ""
    else vacuum.extraConfig;
in
  pkgs.runCommand "security-regression-vacuum-ip-restriction"
  {
    inherit vacuumExtraConfig;
    passAsFile = ["vacuumExtraConfig"];
  } ''
    if [ -z "${vacuumExtraConfig}" ]; then
      echo "FAIL: N-1 — vacuum.kimb.dev vhost is missing entirely from maitred Caddy config."
      echo "      Cannot evaluate the IP-restriction fix; expected vhost to exist."
      echo "      See docs/security-audit.md section 2, finding N-1."
      exit 1
    fi

    if ! grep -q "remote_ip" "$vacuumExtraConfigPath"; then
      echo "FAIL: N-1 — vacuum.kimb.dev has no IP allowlist (no 'remote_ip' clause)."
      echo "      The vacuum dashboard is a LAN-only IoT device but is currently"
      echo "      exposed to the public internet behind Authelia 1FA only."
      echo "      Expected fix: add a Caddy '@allowed { remote_ip ... }' matcher"
      echo "      restricting to LAN/Nebula/Tailscale CIDRs."
      echo "      See docs/security-audit.md section 2, finding N-1."
      echo ""
      echo "      Rendered extraConfig for vacuum.kimb.dev:"
      sed 's/^/        /' "$vacuumExtraConfigPath"
      exit 1
    fi

    echo "PASS: vacuum.kimb.dev has IP allowlist clause"
    touch $out
  ''
