# Host enablement for the Phase-1 vox-bridge (Matrix) on #voidmaster.
#
# DISABLED 2026-07-22 — REPLACED by the Phase-2 vox-organism daemon (the
# Astropath; see hosts/rich-evans/vox-organism.nix + 40k_bridge/deploy/vox-organism.nix).
# The Phase-1 bridge was a one-room/one-seed placeholder; Phase-2 routes
# between every officer channel + every officer seed, with the vigil,
# seed→seed routing, and the #bridge-events bus. This file + its import are
# KEPT for an easy revert: `enable = true` here + `enable = false` on
# vox-organism + flip the token owner back to voidmaster-organism (the
# age.secrets stanza moved to vox-organism.nix with owner vox-organism).
# The clean rollback, though, is `git revert` of the cutover commit (restores
# this file's enable=true + its age.secrets stanza + removes vox-organism.nix).
#
# The bridge module ships from the 40k_bridge source as deploy/vox-bridge.nix
# (imported in flake-modules/nixos-configurations.nix). This file is
# config-only. Phase 1 is Matrix-first: the bridge is a /sync polling client
# over loopback (127.0.0.1:6167, same host as Tuwunel), consuming the
# @vox-bridge:kimb.dev access token. Discord is deferred to Phase 2.
#
# The room + @vox-bridge:kimb.dev account were minted 2026-07-22 (transient
# allow_registration flip; see 40k_bridge/deploy/GO_NOGO.md §3 + the
# matrix-token-mint memory). matrixRoomId + the token are filled in below.
{
  config,
  lib,
  pkgs,
  organism,
  ...
}: {
  services.voidmaster-vox-bridge = {
    enable = false; # Phase-2 cutover: replaced by services.vox-organism.
    # The live Void-Master seed. The bridge shells out to
    # `organic <seed> "<message>"` per room message; the reply is read from
    # <dir(seed)>/.organism/last-run.json (full_out field).
    seed = "/var/lib/voidmaster-organism/agent.org";
    # The #voidmaster:kimb.dev room (created 2026-07-22; @vox-bridge joined,
    # @kimb:kimb.dev invited). Using the room ID directly so the bridge skips
    # alias resolution at startup — the alias #voidmaster:kimb.dev also resolves
    # to this room.
    matrixRoomId = "!3G8AV0aN4zJ4ttbIGQ:kimb.dev";
    matrixUserId = "@vox-bridge:kimb.dev";
    matrixHomeserverUrl = "http://127.0.0.1:6167";
    # @vox-bridge:kimb.dev access token (agenix secret; minted via a
    # transient allow_registration flip — see deploy/GO_NOGO.md §3 + the
    # matrix-token-mint-requires-registration-flip memory).
    matrixBotTokenFile = config.age.secrets.matrix-vox-bridge-token.path;
    # nixpkgs has no `organism` package; the binary ships from the organism
    # flake input. The `organism` specialArg is threaded via rich-evans's
    # extraSpecialArgs in nixos-configurations.nix.
    organicBin = "${organism.packages.x86_64-linux.default}/bin/organic";
    officer = "voidmaster";
  };

  # The age.secrets.matrix-vox-bridge-token stanza MOVED to vox-organism.nix
  # (owner flipped voidmaster-organism → vox-organism for the Phase-2 daemon).
  # Defining it here too would be a duplicate `age.secrets` attr — Nix would
  # reject the merge. On rollback (git revert of the cutover commit), this
  # stanza is restored here with owner "voidmaster-organism".
}