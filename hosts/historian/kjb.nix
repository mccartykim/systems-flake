# keyed james bible — keys a question into a span of KJV verses using Jev
# (TypeSafe System One), then clips the passage from a local KJV corpus.
#
# Runs as a HOST service on historian, the same shape as borges.nix: the package
# comes from the keyed-james-bible flake input, and the systemd unit is declared
# here rather than in that flake so the secret path and state directory stay
# beside the service registry entry that gates them.
#
# Unlike borges, no Nebula inbound rule or socat hop is needed. maitred is no
# longer the public edge — the a3j.8.2 flip landed, and historian's own Caddy
# holds the kimb.dev certificates and binds :80/:443. The registry entry in
# services/default.nix generates the kjb.kimb.dev vhost in reverse-proxy.nix,
# where targetIP resolves to 127.0.0.1 for `host = "historian"` with no
# containerIP, so Caddy reaches this unit directly over loopback.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  kjb = config.kimb.services.kjb;
  package = inputs.keyed-james-bible.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  config = lib.mkIf kjb.enable {
    # A dedicated unprivileged account whose PRIMARY group is "media". That
    # group is what makes the OpenRouter key readable: the secret is encrypted
    # only for historian + bootstrap, and the existing declaration gives it
    # root:media 0440. Joining the group is therefore how this service gets the
    # key, rather than re-encrypting the secret for new recipients or widening
    # the file's mode.
    users.users.kjb = {
      isSystemUser = true;
      group = "media";
      description = "keyed james bible service";
    };

    systemd.services.kjb = {
      description = "keyed james bible — a question keyed into a KJV verse span via Jev";
      wantedBy = ["multi-user.target"];
      # agenix must have decrypted the key before the unit reads its path.
      after = ["network-online.target" "agenix.service"];
      wants = ["network-online.target" "agenix.service"];

      serviceConfig = {
        ExecStart = "${package}/bin/keyed-james-bible --host 127.0.0.1 --port ${toString kjb.port}";

        # Deliberately not root: this is the only unit in the fleet that both
        # faces the network and holds an OpenRouter key. It needs read access to
        # the decrypted secret and nothing else.
        User = "kjb";
        Group = "media";

        # StateDirectory creates /var/lib/kjb and chowns it to User:Group above.
        # The app is pointed there explicitly because its default cache path sits
        # beside its own source, which the (read-only) Nix store does not allow.
        StateDirectory = "kjb";
        Environment = [
          "KJB_CACHE_PATH=/var/lib/kjb/cache.json"
          # Passed as a PATH, not as a value. agenix writes this secret as a bare
          # token with no `KEY=value` wrapper, and systemd's EnvironmentFile
          # silently ignores any line without an `=` in it — pointing an
          # EnvironmentFile at the key would leave the app with no key and fail
          # every question. The app reads the file itself instead, the same way
          # media-classifier takes its own key (jevApiKeyFile).
          "OPENROUTER_API_KEY_FILE=${config.age.secrets.openrouter-api-key.path}"
        ];

        Restart = "on-failure";
        RestartSec = 5;

        # The app's limits are the only thing between a public endpoint and a
        # bill, so give it room to hold connections open across a Jev round trip
        # without being killed mid-request.
        TimeoutStartSec = 30;
      };
    };
  };
}
