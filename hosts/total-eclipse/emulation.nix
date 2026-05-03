# Switch emulator (Eden) for the NVIDIA gaming desktop. Built from upstream
# master with the generic x86-64-v3 profile (matches the eden-ci/nightly
# `amd64-gcc-standard` AppImage). User state lives under ~/.local/share/eden/
# and is not managed by Nix.
{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.callPackage ../../pkgs/eden-master {profile = "generic";})
  ];
}
