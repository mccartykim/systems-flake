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

  # Daemon-driven GC: when free space drops below min-free, the Nix daemon
  # collects until max-free is available. Prevents builds from failing with
  # ENOSPC under 12-parallel CI load. /nix/store has 62k+ gcroots from
  # buildbot-nix, so non-rooted intermediates are what gets collected.
  nix.settings = {
    min-free = 50 * 1024 * 1024 * 1024; # 50 GiB
    max-free = 100 * 1024 * 1024 * 1024; # 100 GiB
  };
}
