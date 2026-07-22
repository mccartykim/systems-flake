# Host enablement for the org-bridge broker (officer <-> ~/org trust
# boundary) on rich-evans.
#
# The module ships from the 40k_bridge source as deploy/org-bridge.nix
# (imported in nixos-configurations.nix; takes bridgeCrewSrc as a module
# arg, threaded via specialArgs). This file is config-only.
#
# emacsPackage + orgAgentInit come from the `org-agent` flake input
# (already wired in systems-flake/flake.nix), reached here via `inputs`.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.org-bridge = {
    enable = true;
    emacsPackage = inputs.org-agent.packages.${pkgs.system}.emacs;
    orgAgentInit = "${inputs.org-agent}/elisp/init.el";
    # Officer service users granted socket access. SO_PEERCRED identifies
    # the caller by uid; `uidMap` below maps that uid to the officer name.
    clientUsers = ["voidmaster-organism" "factotum-organism" "confessor-organism"];
    # Fixed uids assigned to each officer's service user in the respective
    # organism flake module. Value is the officer NAME (matching the
    # [<name>] key in deploy/org-bridge-scope.toml) — NOT the service-user
    # name. voidmaster-organism = 987 (voidmaster_organism/nixos/module.nix);
    # factotum-organism = 989 (factotum_organism/nixos/module.nix; sits
    # after voidmaster 987 + nebula-mesh 988); confessor-organism = 990
    # (confessor_organism/nixos/module.nix; sits after factotum 989).
    uidMap = {
      "987" = "voidmaster";
      "989" = "factotum";
      "990" = "confessor";
    };
  };
}