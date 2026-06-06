# Emulators for the NVIDIA gaming desktop. Switch via Eden nightly (built
# from source with the generic x86-64-v3 profile); Dreamcast via standalone
# Flycast. User state lives under ~/.local/share/<emu>/ and ~/.config/<emu>/
# and is not managed by Nix.
{pkgs, inputs, ...}: {
  environment.systemPackages = [
    inputs.eden-nightly-flake.packages.x86_64-linux.eden-nightly
    pkgs.flycast
  ];
}