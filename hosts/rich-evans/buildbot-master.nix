# Buildbot master: schedules CI builds for systems-flake main + PRs.
# Worker runs on historian (see hosts/historian/buildbot-worker.nix).
# HTTPS terminates on maitred's Caddy; this host's nginx serves HTTP on :80.
{
  config,
  inputs,
  ...
}: {
  imports = [inputs.buildbot-nix.nixosModules.buildbot-master];

  services.buildbot-nix.master = {
    enable = true;
    domain = "buildbot.kimb.dev";
    admins = ["mccartykim"];
    workersFile = config.age.secrets.buildbot-workers.path;
    buildSystems = ["x86_64-linux"];

    # Caddy on maitred terminates TLS and proxies HTTP to this host's nginx.
    # useHTTPS = true so buildbot emits https:// URLs for OAuth callbacks.
    useHTTPS = true;

    authBackend = "github";
    github = {
      appId = 3486605;
      appSecretKeyFile = config.age.secrets.buildbot-github-app-key.path;
      webhookSecretFile = config.age.secrets.buildbot-webhook-secret.path;
      oauthId = "Iv23liOdnTsmRP7ngl68";
      oauthSecretFile = config.age.secrets.buildbot-oauth-secret.path;
      topic = "buildbot-nix";
    };
  };

  age.secrets = {
    buildbot-github-app-key = {
      file = ../../secrets/buildbot-github-app-key.age;
      owner = "buildbot";
      group = "buildbot";
    };
    buildbot-webhook-secret = {
      file = ../../secrets/buildbot-webhook-secret.age;
      owner = "buildbot";
      group = "buildbot";
    };
    buildbot-oauth-secret = {
      file = ../../secrets/buildbot-oauth-secret.age;
      owner = "buildbot";
      group = "buildbot";
    };
    buildbot-workers = {
      file = ../../secrets/buildbot-workers.age;
      owner = "buildbot";
      group = "buildbot";
    };
  };

  # Nebula firewall: allow maitred socat to hit nginx (port 80) and
  # historian's worker to connect to the worker protocol (port 9989).
  # Host firewall is trustedInterfaces=["nebula1"] already, so no iptables rule needed.
  kimb.nebula.extraInboundRules = [
    {
      port = 80;
      proto = "tcp";
      host = "maitred";
    }
    {
      port = 9989;
      proto = "tcp";
      host = "historian";
    }
  ];
}
