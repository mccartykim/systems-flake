# remembrancer-organism: host enablement for the Remembrancer Olesia, the
# 11th bridge officer — the chronicler of the public record (the writer
# officer). Composes public-facing prose (README copy, blog posts, dispatches)
# + proposes it via the bridge-scribe PR loop (the `author` verb); does NOT
# push directly or mutate the fleet.
#
# The module (remembrancer_organism/nixos/module.nix) is self-contained — it
# resolves its own package from pkgs.system, so this file is CONFIG-ONLY and
# needs NO extraSpecialArgs (same shape as the Interrogator/Confessor/Factotum/
# Explorator host files). On-request (no heartbeat): the vox-organism daemon
# runs `organic <this-seed>` AS vox-organism (uid 998, a member of
# remembrancer-organism) only when #remembrancer is addressed or a prose
# petition is auto-relayed from #vox-bridge — so there is NO heartbeat
# service/timer here, and NO ollamaHost/ollamaModel option is set (the module
# is Interrogator-form, not Chirurgeon-form: the LLM env is inherited on the
# reactive path from the daemon, which inherits voidmaster-heartbeat's
# OLLAMA_*).
#
# CLOUD-ONLY pinning (NEVER a local model, esp. while the Lord-Captain games)
# is enforced TWO layers below this file, not here: (1) the remembrancer-infer
# shell wrapper sets OLLAMA_HOST/OLLAMA_MODEL defaults to
# http://historian.nebula:11434 + kimi-k2.7-code:cloud via --set-default in
# the flake packaging, and (2) the daemon's inherited OLLAMA_* env on the
# reactive path. If explicit ollamaHost/ollamaModel options are ever desired
# here, the module must grow those options first (a coordinated change with
# the officer repo) — until then this file stays Interrogator-form.
#
# Routing to #remembrancer (room + route + daemon extraGroups + OFFICER_REPOS +
# org-bridge scope stanza + VIGIL) ships from 40k_bridge; the daemon's
# extraGroups + the org-bridge clientUsers/uidMap are roster-DERIVED
# (deploy/roster.nix) so this file adds only the enable line.
#
# Rollback: `services.remembrancer-organism.enable = false` (one line) + revert
# the routing row / scope stanza / OFFICER_REPOS entry in 40k_bridge + rebuild.
# No prose is ever published by this officer (drafts await the Lord-Captain's
# word at the PR), so disable leaves no side effects to clean up; the stateDir
# is inert.
{...}: {
  services.remembrancer-organism.enable = true;
}