# Plaid Link callback — the HTTPS name for the money_checker workspace's link
# server. The server itself is NOT managed here: money_checker starts it for
# one link session (`scripts/plaid.sh link`) and stops it after. The registry
# entry in services/default.nix publishes the name; this file opens the Nebula
# path that maitred's socat forwarder needs to reach the process.
#
# The server must bind 0.0.0.0:<port>, not 127.0.0.1:<port>. maitred
# terminates TLS and connects over Nebula at 10.100.0.10, so a loopback bind
# accepts the TCP connection and then refuses it. The host firewall already
# trusts nebula1, so the Nebula ACL below is the only gate; same shape as
# kjv.nix, borges.nix, and knitwork.nix.
{
  config,
  lib,
  ...
}: let
  plaidLink = config.kimb.services.plaid-link;
in {
  config = lib.mkIf plaidLink.enable {
    kimb.nebula.extraInboundRules = [
      {
        port = plaidLink.port;
        proto = "tcp";
        host = "maitred";
      }
    ];
  };
}
