# Host enablement for the Phase-1 vox-bridge (Matrix) on #voidmaster.
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
    enable = true;
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

  # @vox-bridge:kimb.dev Matrix access token. Minted via a transient
  # allow_registration flip on the homeserver; the token VALUE is never
  # committed in plaintext — only this age-encrypted file is. Encrypted to
  # rich-evans + bootstrap; the bridge runs as the voidmaster-organism
  # service user (the module's default `user`), so the secret is owned by
  # that user. See deploy/GO_NOGO.md §3 step 3.
  age.secrets.matrix-vox-bridge-token = {
    file = ../../secrets/matrix-vox-bridge-token.age;
    owner = "voidmaster-organism";
    mode = "0400";
  };
}