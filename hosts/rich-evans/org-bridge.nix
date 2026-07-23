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
    clientUsers = ["voidmaster-organism" "factotum-organism" "confessor-organism" "explorator-organism" "chirurgeon-organism" "vox-organism"];
    # Fixed uids assigned to each officer's service user in the respective
    # organism flake module. Value is the officer NAME (matching the
    # [<name>] key in deploy/org-bridge-scope.toml) — NOT the service-user
    # name. voidmaster-organism = 987 (voidmaster_organism/nixos/module.nix);
    # factotum-organism = 989 (factotum_organism/nixos/module.nix; sits
    # after voidmaster 987 + nebula-mesh 988); confessor-organism = 990
    # (confessor_organism/nixos/module.nix; sits after factotum 989);
    # explorator-organism = 991 (explorator_organism/nixos/module.nix; sits
    # after confessor 990); chirurgeon-organism = 984
    # (chirurgeon_organism/nixos/module.nix; below webcam 986, clear of the
    # other officers); vox-organism = 998 (40k_bridge/deploy/vox-organism.nix;
    # 992 is copyparty, 993-997 are nixpkgs defaults, so 998 is the next free
    # uid in band — the Phase-2 Astropath comms-bridge daemon, distinct from
    # voidmaster by THIS cross-check: broker.py maps SO_PEERCRED uid→name vs
    # the request's `officer` field, so a vox-organism bridge_log append
    # attributes under "astropath", not "voidmaster").
    uidMap = {
      "984" = "chirurgeon";
      "987" = "voidmaster";
      "989" = "factotum";
      "990" = "confessor";
      "991" = "explorator";
      "998" = "astropath";
    };
    # vox-organism (998) is the router: it runs every routed officer's organic
    # cycle under its own uid and forwards their view/append, so it must be
    # trusted to name the routed officer (strict uid-match would deny every
    # routed officer). It already controls every cycle, so this adds no
    # capability beyond router compromise. See org-bridge.nix relayUids.
    relayUids = [ "998" ];
  };
}