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
    # Disabled 2026-06-22 along with the master on rich-evans — see
    # hosts/rich-evans/buildbot-master.nix. Flip back to true (and
    # redeploy) to re-enable.
    enable = false;
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

  # Fine-grained PAT for fetching private flake inputs from
  # mccartykim/* over HTTPS. The decrypted file is included verbatim
  # into nix.conf via `nix.extraOptions`, so its content must be a
  # valid nix.conf line — currently:
  #   access-tokens = github.com=<the-pat>
  # nix-daemon runs as root, so root:root 0400 (the agenix default)
  # is what we need.
  age.secrets.buildbot-worker-github-token = {
    file = ../../secrets/buildbot-worker-github-token.age;
  };

  # Same PAT in .netrc format, decrypted to the buildbot-worker user's
  # home so that `git` (invoked by nix's git+https:// fetcher) can
  # authenticate private-repo clones. nix-eval-jobs runs in the
  # buildbot-worker user context (not nix-daemon's root context), so
  # the netrc must live at $HOME/.netrc for *that* user. Root can
  # still read this file via the bypass-permissions rule, so any
  # daemon-side fetches also work — single decryption serves both.
  age.secrets.buildbot-worker-git-netrc = {
    file = ../../secrets/buildbot-worker-git-netrc.age;
    path = "/var/lib/buildbot-worker/.netrc";
    owner = "buildbot-worker";
    group = "buildbot-worker";
    mode = "0400";
  };

  nix.extraOptions = ''
    !include ${config.age.secrets.buildbot-worker-github-token.path}
  '';

  # Daemon-driven GC: when free space drops below min-free, the Nix daemon
  # collects until max-free is available. Prevents builds from failing with
  # ENOSPC under 12-parallel CI load. /nix/store has 62k+ gcroots from
  # buildbot-nix, so non-rooted intermediates are what gets collected.
  nix.settings = {
    min-free = 50 * 1024 * 1024 * 1024; # 50 GiB
    max-free = 100 * 1024 * 1024 * 1024; # 100 GiB
  };
}
