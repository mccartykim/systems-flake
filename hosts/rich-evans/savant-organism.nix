# savant-organism: host enablement for the Savant Quine, the 12th bridge
# officer — read-only reference librarian (web-search + ebook-search over
# the borges db) + print_file (lp to the LAN Brother). On request (no
# heartbeat): the vox-organism daemon runs `organic <this-seed> "<msg>"`
# AS vox-organism (uid 998, a member of savant-organism + borges via the
# roster's daemonExtraGroups); the seed's web-search/ebook-search tools
# run read-only, print_file prints a stateDir-prisoned file. Never mutates
# the ebook db, never sends mail, never authors a branch.
#
# The module (savant_organism/nixos/module.nix) is self-contained — it
# resolves its own package from pkgs.system, so this file is CONFIG-ONLY
# and needs NO extraSpecialArgs (same shape as the Interrogator/Confessor/
# Factotum/Explorator/Chirurgeon host files). The officer is on-request:
# NO heartbeat service/timer + NO ollamaHost/ollamaModel here (the LLM env
# is inherited on the reactive path from the daemon, which inherits
# voidmaster-heartbeat's OLLAMA_*). cups (lp) + poppler-utils + file(1)
# for print-file are on the daemon's PATH (hosts/rich-evans/vox-organism.nix).
#
# Routing to #savant (room + route + daemon extraGroups + org-bridge scope
# stanza + bridge-log heading) ships from 40k_bridge; the daemon's
# extraGroups (incl. borges, so the reactive cycle reads the ebook db) +
# the org-bridge clientUsers/uidMap + the daemon's startup rooms are
# roster-DERIVED (deploy/roster.nix) so this file adds only the enable line.
#
# Rollback: `services.savant-organism.enable = false` (one line) + revert
# the routing row / scope stanza in 40k_bridge + rebuild. The Savant never
# mutates anything but its own state, so disable leaves no side effects;
# the stateDir is inert.
{...}: {
  services.savant-organism.enable = true;
}