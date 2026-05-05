# Emulators for the NVIDIA gaming desktop. Switch via Eden master (built
# from source with the generic x86-64-v3 profile matching the
# eden-ci/nightly amd64-gcc-standard AppImage); Dreamcast via standalone
# Flycast. User state lives under ~/.local/share/<emu>/ and ~/.config/<emu>/
# and is not managed by Nix.
{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.callPackage ../../pkgs/eden-master {profile = "generic";})
    pkgs.flycast
  ];
}
