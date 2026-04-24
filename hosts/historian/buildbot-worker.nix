# Buildbot worker: runs CI builds. Master lives on rich-evans.
# Worker name defaults to config.networking.hostName = "historian" and must
# match the "name" field in the workers.json encrypted for rich-evans.
{
  config,
  inputs,
  ...
}: {
  imports = [inputs.buildbot-nix.nixosModules.buildbot-worker];

  services.buildbot-nix.worker = {
    enable = true;
    masterUrl = "tcp:host=rich-evans.nebula:port=9989";
    workerPasswordFile = config.age.secrets.buildbot-worker-password.path;
    # 24-thread Ryzen; Jellyfin/Sunshine transcoding is GPU-accelerated and
    # Ollama is mostly idle, so 12 concurrent builds leaves comfortable headroom.
    workers = 12;
  };

  age.secrets.buildbot-worker-password = {
    file = ../../secrets/buildbot-worker-password.age;
    owner = "buildbot-worker";
    group = "buildbot-worker";
  };
}
