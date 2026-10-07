# keyed james bible — keys a question into a span of KJV verses using Jev
# (TypeSafe System One), then clips the passage from a local KJV corpus.
#
# Runs as a HOST service on historian, the same shape as borges.nix: the package
# comes from the keyed-james-bible flake input, and the systemd unit is declared
# here rather than in that flake so the secret path and state directory stay
# beside the service registry entry that gates them.
#
# Named for the *subdomain* (kjv.kimb.dev, the Bible version) rather than the
# project (keyed james bible), so the registry key, the unit, and the state
# directory all match the name people actually type.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  kjv = config.kimb.services.kjv;
  package = inputs.keyed-james-bible.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  config = lib.mkIf kjv.enable {
    # A dedicated unprivileged account whose PRIMARY group is "media". That
    # group is what makes the OpenRouter key readable: the secret is encrypted
    # only for historian + bootstrap, and its declaration gives it root:media
    # 0440. Joining the group is therefore how this service gets the key, rather
    # than re-encrypting the secret for new recipients or widening the file.
    users.users.kjv = {
      isSystemUser = true;
      group = "media";
      description = "keyed james bible service";
    };

    systemd.services.kjv = {
      description = "keyed james bible — a question keyed into a KJV verse span via Jev";
      wantedBy = ["multi-user.target"];
      # agenix must have decrypted the key before the unit reads its path.
      after = ["network-online.target" "agenix.service"];
      wants = ["network-online.target" "agenix.service"];

      serviceConfig = {
        ExecStart = "${package}/bin/keyed-james-bible --host 127.0.0.1 --port ${toString kjv.port}";

        # Deliberately not root: this is the only unit in the fleet that both
        # faces the network and holds an OpenRouter key. It needs read access to
        # the decrypted secret and nothing else.
        User = "kjv";
        Group = "media";

        # StateDirectory creates /var/lib/kjv owned by User:Group above. The app
        # is pointed there explicitly because its default cache path sits beside
        # its own source, which the (read-only) Nix store does not allow.
        StateDirectory = "kjv";
        Environment = [
          "KJB_CACHE_PATH=/var/lib/kjv/cache.json"
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

        # The app's own limits are the only thing between a public endpoint and
        # a bill, so allow room for a Jev round trip without being killed.
        TimeoutStartSec = 30;
      };
    };

    # Let maitred's socat forwarder reach this service over Nebula. Without this
    # the forwarder listens but every connection times out: the host firewall
    # already trusts nebula1, so the Nebula ACL is the only gate, and maitred is
    # not a personal device so openToPersonalDevices does not cover it. Same
    # rule borges.nix declares for its own port.
    kimb.nebula.extraInboundRules = lib.mkIf kjv.enable [
      {
        port = kjv.port;
        proto = "tcp";
        host = "maitred";
      }
    ];
  };
}
