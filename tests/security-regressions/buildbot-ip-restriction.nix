# Security regression — pins N-3 from docs/security-audit.md.
#
# `services/default.nix:134-142` declares `buildbot.kimb.dev` with
# `auth = "none"`, relying entirely on Buildbot's built-in GitHub OAuth
# (`hosts/rich-evans/buildbot-master.nix:22`). The audit fix is to add an
# `@allowed { remote_ip ... }` block in Caddy restricting the buildbot UI
# to LAN/Nebula, OR layer Authelia forward_auth on top.
#
# This derivation inspects the rendered Caddy `extraConfig` for the
# `buildbot.kimb.dev` virtual host on the real maitred config and
# asserts that either an IP allowlist or a `forward_auth` to Authelia is
# present.
{
  pkgs,
  maitredCfg,
  ...
}: let
  vhosts = maitredCfg.containers.reverse-proxy.config.services.caddy.virtualHosts;
  buildbot = vhosts."buildbot.kimb.dev" or null;
  buildbotExtraConfig =
    if buildbot == null
    then ""
    else buildbot.extraConfig;
in
  pkgs.runCommand "security-regression-buildbot-ip-restriction"
  {
    inherit buildbotExtraConfig;
    passAsFile = ["buildbotExtraConfig"];
  } ''
    if [ -z "${buildbotExtraConfig}" ]; then
      echo "FAIL: N-3 — buildbot.kimb.dev vhost is missing entirely from maitred Caddy config."
      echo "      Cannot evaluate the IP-restriction fix; expected vhost to exist."
      echo "      See docs/security-audit.md section 2, finding N-3."
      exit 1
    fi

    if ! grep -qE "remote_ip|forward_auth" "$buildbotExtraConfigPath"; then
      echo "FAIL: N-3 — buildbot.kimb.dev has neither an IP allowlist nor Authelia forward_auth."
      echo "      Buildbot's web UI is on the public internet authenticated by a single"
      echo "      GitHub OAuth app. Buildbot has had auth-bypass / RCE history."
      echo "      Expected fix: add a Caddy '@allowed { remote_ip ... }' matcher OR"
      echo "      route through Authelia forward_auth in addition to GitHub OAuth."
      echo "      See docs/security-audit.md section 2, finding N-3."
      echo ""
      echo "      Rendered extraConfig for buildbot.kimb.dev:"
      sed 's/^/        /' "$buildbotExtraConfigPath"
      exit 1
    fi

    echo "PASS: buildbot.kimb.dev has either IP allowlist or Authelia forward_auth"
    touch $out
  ''
