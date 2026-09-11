# Matrix homeserver (Tuwunel) + Discord bridge (mautrix-discord) — the a3j.6
# phase-6a migration from rich-evans (ported from hosts/rich-evans/matrix.nix).
#
# Storage correction vs the original plan: Tuwunel does NOT use postgres —
# its state is an embedded Go store at /var/lib/private/tuwunel (5.3G,
# systemd DynamicUser path), including the federation signing keys (DO NOT
# ROTATE — they ride the state rsync untouched, preserving kimb.dev's
# federation identity). mautrix-discord keeps its sqlite at
# /var/lib/mautrix-discord. Both are file-copy migrations: stop on
# rich-evans, delta rsync, start here.
#
# Consumers: maitred's socat forwarder (matrix-proxy) repoints to this
# host via the registry (matrix.kimb.dev); the vox-organism daemon on
# rich-evans polls http://10.100.0.10:6167 over Nebula until the a3j.7
# organisms domU (bridge-crew module rev f5b35200 added the remote-
# homeserver support: sameHostHomeserver gates the unit bindings +
# assertion). Federation endpoint matrix.kimb.dev:443 + the root-domain
# .well-known delegation are unchanged (reverse-proxy.nix is static).
{
  config,
  lib,
  pkgs,
  ...
}: {
  # mautrix-discord depends on olm which is deprecated but still functional
  # The security concerns are about theoretical side-channel attacks, not remote exploits
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"
  ];

  services.matrix-tuwunel = {
    enable = true;
    settings.global = {
      server_name = "kimb.dev"; # Matrix ID domain (NOT matrix.kimb.dev)
      port = [6167];
      address = ["0.0.0.0"]; # Accessible via Nebula + LAN
      allow_registration = false;
      allow_federation = true;
    };
  };

  services.mautrix-discord = {
    enable = true;
    settings = {
      homeserver = {
        address = "http://127.0.0.1:6167"; # same host here, as on rich-evans
        domain = "kimb.dev";
      };
      appservice = {
        hostname = "127.0.0.1";
        port = 29334;
        database = {
          type = "sqlite3";
          uri = "file:/var/lib/mautrix-discord/mautrix-discord.db?_txlock=immediate";
        };
      };
      bridge.permissions = {
        "@kimb:kimb.dev" = "admin";
      };
    };
  };

  # Ensure mautrix-discord starts after tuwunel (same-host unit names are
  # valid here)
  systemd.services.mautrix-discord = {
    after = ["tuwunel.service"];
    requires = ["tuwunel.service"];
  };

  # Historian has 58G/24 cores — the rich-evans conservative limits
  # (MemoryMax=1G, CPUQuota=50%) are dropped; the homeserver can breathe
  # during the federation sync catch-up after the cutover.
  #
  # Firewall: 6167 LAN (parity with rich-evans) + Nebula from any mesh node
  # (maitred's socat for matrix.kimb.dev, the rich-evans organisms' interim
  # vox-organism polling, personal devices).
  networking.firewall.allowedTCPPorts = [6167];

  kimb.nebula.extraInboundRules = [
    {
      port = 6167;
      proto = "tcp";
      host = "any";
    }
  ];
}
