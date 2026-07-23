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
  bridgeCrewSrc,
  ...
}: let
  # The bridge-crew roster — single source of truth for officer uids +
  # org-bridge identity (deploy/roster.nix in the 40k_bridge source). The
  # broker's clientUsers + uidMap below are DERIVED from it (the officers on
  # this host that use the broker), not hand-listed, so adding an officer is
  # one roster entry, not an edit here. relayUids stays literal (the daemon
  # 998 is the one router; roster-independent).
  roster = import "${bridgeCrewSrc}/deploy/roster.nix" { inherit lib; };
in {
  services.org-bridge = {
    enable = true;
    emacsPackage = inputs.org-agent.packages.${pkgs.system}.emacs;
    orgAgentInit = "${inputs.org-agent}/elisp/init.el";
    # Roster-DERIVED (deploy/roster.nix): the service-user groups of every
    # officer ON rich-evans that uses the broker (orgBridge != null).
    # SO_PEERCRED identifies the caller by uid; `uidMap` below maps that uid
    # to the officer name. Adding an officer = one roster entry, not an edit
    # here.
    clientUsers = roster.orgBridgeClientUsers "rich-evans";
    # uid-to-officer-name map for the same officers, roster-DERIVED. Value is
    # the officer NAME (matching the [<name>] key in org-bridge-scope.toml),
    # NOT the service-user name. The daemon (998, the router) is included so
    # it can forward routed officers' bridge_log via the relay (relayUids
    # below). See roster.nix for the per-officer uid cross-checks.
    uidMap = roster.orgBridgeUidMap "rich-evans";
    # vox-organism (998) is the router: it runs every routed officer's organic
    # cycle under its own uid and forwards their view/append, so it must be
    # trusted to name the routed officer (strict uid-match would deny every
    # routed officer). It already controls every cycle, so this adds no
    # capability beyond router compromise. See org-bridge.nix relayUids.
    relayUids = [ "998" ];
  };
}