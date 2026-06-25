# Knitwork — lexicon host + firehose indexer, running as a host service on
# rich-evans. Mirrors buildbot-master.nix: a flake-input-backed NixOS module run
# as a host service (NOT a maitred container like blog). The knitwork binary
# serves the dev.kimb.knit.* lexicons over HTTP and, in parallel, an unlinked
# process holds an *outbound* wss to the relay firehose to self-fill its SQLite
# index — plain HTTP inbound, no inbound websockets.
#
# Caddy on maitred terminates TLS for knit.kimb.dev and reverse-proxies to this
# host over Nebula. maitred runs a socat forwarder (containerBridge:8080 →
# 10.100.0.40:8080, see hosts/maitred/configuration.nix `mkProxyService`) driven by
# the duplicate `knit` entry in services/default.nix under the maitred bucket.
{
  config,
  lib,
  inputs,
  ...
}: let
  knit = config.kimb.services.knit;
in {
  # knitwork's NixOS module references `self.packages.${pkgs.system}.default`
  # for the binary; pass its flake in as a module arg (same idea as the blog
  # container's `_module.args.self`, just at host scope here).
  _module.args.self = inputs.knitwork;

  imports = [inputs.knitwork.nixosModules.default];

  services.knitwork = lib.mkIf knit.enable {
    enable = true;
    port = knit.port;
    # Bind all interfaces so maitred's socat can reach us over Nebula
    # (10.100.0.40). The host firewall already trusts nebula1, so no iptables
    # rule is needed — same as buildbot-master.nix.
    host = "0.0.0.0";
    # dbPath / firehoseUrl default to the module's own options — it sets
    # StateDirectory=knitwork + KNIT_DB_PATH + KNIT_FIREHOSE_URL env from them,
    # so no extra wiring is needed here.
  };

  # Let maitred's socat proxy reach the indexer over Nebula (port 8080).
  # Host firewall already trusts nebula1, so no iptables rule is needed —
  # same as buildbot-master.nix.
  kimb.nebula.extraInboundRules = lib.mkIf knit.enable [
    {
      port = knit.port;
      proto = "tcp";
      host = "maitred";
    }
  ];
}