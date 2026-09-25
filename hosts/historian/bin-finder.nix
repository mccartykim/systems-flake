# HomeBox + bin_finder_ai are configured from the bin_finder_ai flake's own NixOS module.
#
# The module and the package both live in that repo, consumed as `bin-finder-ai.nixosModules.default`
# — the same arrangement as media-classifier, which is the closest precedent (same host, same
# ollama `think: false` lessons, same private-repo input style). Keeping options, unit definition and
# code together means a change to the service's configuration surface happens in one place rather
# than being split across two repos that can drift.
#
# There is deliberately no service definition here. The switch lives in
# hosts/historian/configuration.nix, next to the other `services.*.enable` lines, so everything that
# historian runs is visible in one file.
#
# ## The measurements that decided the architecture (kept here because they are deployment-relevant)
#
# There is NO local inference, despite historian having ROCm. One real photograph, think=false,
# temperature 0:
#
#   ollama.com hosted deepseek-v4.1-flash    0.70s   correctly identified the object
#   historian local gemma4:e4b (warm)        2.05s   vague
#   historian local gemma4:e4b (think on)   68.24s   vague
#   local qwen3-vl:2b / 4b-instruct     11.0s / 7.4s
#
# So the VLM is a cloud call and this host needs no GPU stack for it: no torch, no model files, no
# /dev/kfd. `think=false` alone is a 40x difference.
#
# ## Storage
#
# State lives on /mnt/media-drive (5.5T, ~3.6T free) rather than root, which sits at ~83%.
#
# ## Why HomeBox is not a container
#
# historian's podman overlay storage is currently broken — a pull fails with
# "readlink .../containers/storage/overlay/.../diff: no such file or directory". `podman system reset`
# would repair it but destroys other services' images, so the declarative nixpkgs module is used
# instead. It is also the better answer regardless: systemd supervision, restarts and journald for
# free.
{ ... }:
{
  # Nothing to declare: see hosts/historian/configuration.nix for
  # `services.bin-finder.enable` and its options. This file exists to document the arrangement.
}
