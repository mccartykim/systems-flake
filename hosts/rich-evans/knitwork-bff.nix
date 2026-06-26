# Knitwork BFF — the ATProto OAuth write relay, running as a host service on
# rich-evans next to the AppView (hosts/rich-evans/knitwork.nix). Same shape as
# knitwork.nix: a flake-input-backed NixOS module run as a host service, with the
# one secret (the confidential client P-256 key) pointed at an agenix path.
#
# Caddy on maitred terminates TLS for knit.kimb.dev and routes /api/* to this
# service over Nebula via a socat forwarder (the `knit-bff` entry in
# services/default.nix under the maitred bucket, publicAccess=false so it
# generates only the forwarder, not a vhost — the knit.kimb.dev vhost itself is
# hand-written in hosts/maitred/reverse-proxy.nix to split /api/* off).
#
# The BFF holds the DPoP keys + refresh tokens in SQLite under its state
# directory; the KMP client holds only a revocable sid / cookie.
{
  config,
  lib,
  inputs,
  ...
}: let
  bff = config.kimb.services.knit-bff;
in {
  # The BFF module references `self.packages.${pkgs.system}.knitwork-bff`. The
  # `self` module arg is already provided by hosts/rich-evans/knitwork.nix
  # (`_module.args.self = inputs.knitwork`), which is always imported alongside
  # this file — so we only import the module here, not re-set the arg (setting it
  # twice is a module-system error even with identical values).
  imports = [inputs.knitwork.nixosModules.bff];

  services.knitwork-bff = lib.mkIf bff.enable {
    enable = true;
    port = bff.port;
    # Bind all interfaces so maitred's socat can reach us over Nebula
    # (10.100.0.40). The host firewall trusts nebula1 (rule below), same as
    # the AppView.
    host = "0.0.0.0";
    publicUrl = "https://knit.kimb.dev";
    appviewUrl = "https://knit.kimb.dev";
    cookieDomain = "knit.kimb.dev";
    nativeScheme = "knitwork";
    # Confidential client key (P-256 multibase). The value is age-encrypted to
    # rich-evans's host key (see age.secrets below); only the path is referenced
    # here. Generate the key with `cmd/genkey` in the knitwork repo, then:
    #   agenix -e secrets/knit-bff-client-key.age
    # pipe the multibase key in and add the file + recipient to secrets/secrets.nix.
    clientKeyFile = config.age.secrets.knit-bff-client-key.path;
  };

  # The confidential client key, age-encrypted to rich-evans's SSH host key (+ the
  # bootstrap key, recipients in secrets/secrets.nix). The BFF service runs as
  # root (no User= in the module's serviceConfig), so the decrypted file is
  # root-owned 0400 — no `owner` needed (agenix defaults to root). Only the path
  # is referenced above; the value is never in the flake.
  age.secrets.knit-bff-client-key = {
    file = ../../secrets/knit-bff-client-key.age;
    mode = "0400";
  };

  # Let maitred's socat proxy reach the BFF over Nebula (port 8787). Host
  # firewall already trusts nebula1, so no iptables rule is needed — same as
  # the AppView in knitwork.nix.
  kimb.nebula.extraInboundRules = lib.mkIf bff.enable [
    {
      port = bff.port;
      proto = "tcp";
      host = "maitred";
    }
  ];
}