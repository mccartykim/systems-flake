# factor-organism: host enablement for the Factor Voss, the 14th bridge
# officer — ship's Treasurer (finance axis). hledger double-entry ledger
# (Factor SOLE writer via hledger-import + ledger-commit; local
# git-versioned, NO remote/push). The reactive #factor cycle runs on
# request via the vox-organism daemon (uid 998, a member of
# factor-organism via the roster's daemonExtraGroups); the daemon env
# carries FACTOR_STATE/FACTOR_LEDGER/FACTOR_CSV_DIR (vox-organism.nix) so
# the cycle reads/writes the REAL ledger, not /tmp.
#
# The module (factor_organism/nixos/module.nix) is self-contained — it
# resolves its own package from pkgs.system, so this file is CONFIG-ONLY
# and needs NO extraSpecialArgs (same shape as the other self-contained
# officer host files). hledger + hledger-utils + git for the finance
# tools are on the daemon's PATH (hosts/rich-evans/vox-organism.nix).
#
# enableHeartbeat = false: the proactive 15min nudge timer is WIRED but
# OFF at first deploy. The Factor is the one new officer that COULD act
# unprompted (a proactive nudge), so the persona is validated by the
# Lord-Captain's first #factor round-trip BEFORE the timer turns on. The
# systemd.services.factor-heartbeat unit is still defined (so `systemctl
# start factor-heartbeat` works for a manual cycle); only the TIMER is
# gated. Flip to true (the module default) — or just remove this
# override — once the persona is signed off.
#
# Routing to #factor (room + route + daemon extraGroups + org-bridge
# scope stanza + bridge-log heading) ships from 40k_bridge; roster-DERIVED.
#
# Rollback: `services.factor-organism.enable = false` (one line) + revert
# the routing row / scope stanza in 40k_bridge + rebuild. The ledger +
# its .git live in /var/lib/factor-organism (syncthing carries it off-host
# for backup when configured); disable leaves the ledger inert, NO remote
# ever pushed.
{...}: {
  services.factor-organism = {
    enable = true;
    # Proactive heartbeat OFF at first deploy; the reactive #factor cycle
    # (via the daemon) runs now. Flip to true (default) after the user's
    # first #factor round-trip validates the persona.
    enableHeartbeat = false;
  };
}