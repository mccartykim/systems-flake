# interrogator-organism: host enablement for the Interrogator Voke (#53), the
# 10th bridge officer — the read-only mail reader. On request (no heartbeat),
# the vox-organism daemon runs `organic <this-seed> "<msg>"` AS vox-organism
# (uid 998, a member of interrogator-organism + email-digest); the seed's
# TRAFFIC/LISTINGS/CANDIDATES blocks run read-only `mu find`/`mu view` over the
# mu index the email-digest service already maintains, extract the requested
# fields, and reply with an org-mode table. Never sends, never mutates.
#
# The module (interrogator_organism/nixos/module.nix) is self-contained — it
# resolves its own package from pkgs.system, so this file is CONFIG-ONLY and
# needs NO extraSpecialArgs (same shape as the Confessor/Factotum/Explorator/
# Chirurgeon host files). The officer is on-request: there is NO heartbeat
# service/timer + NO ollamaHost/ollamaModel here (the LLM env is inherited on
# the reactive path from the daemon, which inherits voidmaster-heartbeat's
# OLLAMA_*). mu is a host systemPackage (configuration.nix), not a module dep.
#
# Routing to #interrogator (room + route + daemon extraGroups + OFFICER_REPOS +
# org-bridge scope stanza + VIGIL) ships from 40k_bridge; the daemon's
# extraGroups + the org-bridge clientUsers/uidMap are now roster-DERIVED
# (deploy/roster.nix) so this file adds only the enable line.
#
# Rollback: `services.interrogator-organism.enable = false` (one line) +
# revert the routing row / scope stanza / OFFICER_REPOS entry in 40k_bridge +
# rebuild. No mail is ever sent or mutated by this officer, so disable leaves
# no side effects to clean up; the stateDir is inert.
{...}: {
  services.interrogator-organism.enable = true;
}