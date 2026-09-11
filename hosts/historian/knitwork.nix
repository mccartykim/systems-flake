# Knitwork — lexicon host + firehose indexer, running as a host service on
# historian. Ported from hosts/rich-evans/knitwork.nix at a3j.5 (same shape —
# the source pattern is preserved exactly). The knitwork binary serves the
# dev.kimb.knit.* lexicons over HTTP and, in parallel, an unlinked process
# holds an *outbound* wss to the relay firehose to self-fill its SQLite index
# — plain HTTP inbound, no inbound websockets.
#
# Caddy on maitred terminates TLS for knit.kimb.dev and reverse-proxies to
# this host over Nebula. maitred runs a socat forwarder (containerBridge:8080
# → 10.100.0.10:8080, see hosts/maitred/configuration.nix `mkProxyService`)
# driven by the duplicate `knit` entry in services/default.nix under the
# maitred bucket — repointed from rich-evans to historian at the a3j.5
# cutover. The knit-web SPA nspawn already on this box is untouched.
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
  # container's `_module.args.self`, just at host scope here — and shared by
  # hosts/historian/knitwork-bff.nix, which must NOT re-set it).
  _module.args.self = inputs.knitwork;

  imports = [inputs.knitwork.nixosModules.default];

  services.knitwork = lib.mkIf knit.enable {
    enable = true;
    port = knit.port;
    # Bind all interfaces so maitred's socat can reach us over Nebula
    # (10.100.0.10). The host firewall already trusts nebula1, so the
    # kimb.nebula extraInboundRule below is the only gate.
    host = "0.0.0.0";
    # dbPath / firehoseUrl default to the module's own options — it sets
    # StateDirectory=knitwork + KNIT_DB_PATH + KNIT_FIREHOSE_URL env from
    # them, so no extra wiring is needed here. The SQLite state was rsynced
    # from rich-evans at the a3j.5 cutover (rsync -aHAX --numeric-ids,
    # root-owned like the source).
    # Moderation admin bearer token (Stage 4) — points at the agenix secret
    # so the token value never lives in the repo/flake, only this path does.
    adminTokenFile = config.age.secrets.knit-admin-token.path;
  };

  # The moderation admin token (Stage 4): age-encrypted to the fleet-core
  # recipient set (rich-evans + historian + bootstrap, recipients in
  # secrets/secrets.nix). The knitwork service runs as root (no User= in the
  # module's serviceConfig), so the decrypted file is root-owned 0400 — no
  # `owner` needed (agenix defaults to root).
  age.secrets.knit-admin-token = {
    file = ../../secrets/knit-admin-token.age;
    mode = "0400";
  };

  # Let maitred's socat proxy reach the indexer over Nebula (port 8080).
  kimb.nebula.extraInboundRules = lib.mkIf knit.enable [
    {
      port = knit.port;
      proto = "tcp";
      host = "maitred";
    }
  ];
}
