# Host enablement for the Phase-2 vox-organism comms bridge (the Astropath) on
# rich-evans. Replaces the Phase-1 placeholder services.voidmaster-vox-bridge
# (disabled in voidmaster-vox-bridge.nix — one-line rollback).
#
# The module ships from the 40k_bridge source as deploy/vox-organism.nix
# (imported in flake-modules/nixos-configurations.nix; takes bridgeCrewSrc as
# a module arg, threaded via specialArgs). This file is config-only.
#
# Phase 2 is Matrix-first: the daemon is a /sync polling client over loopback
# (127.0.0.1:6167, same host as Tuwunel), reusing the existing @vox-bridge:kimb.dev
# access token — NO @astropath mint, NO registration flip. The .age file is NOT
# re-encrypted; only the Nix `owner` attr flips from voidmaster-organism to
# vox-organism so the daemon (uid 992) can read its token.
{
  config,
  lib,
  pkgs,
  organism,
  ...
}: {
  services.vox-organism = {
    enable = true;
    # The live Astropath seed. The daemon parses the routing table from this
    # file at startup; the module's syncAgentLine copies it from the 40k_bridge
    # source sample (seeds/astropath.org) on first run + re-syncs the
    # immutable head each cycle.
    seedPath = "/var/lib/vox-organism/vox.seed.org";
    matrixUserId = "@vox-bridge:kimb.dev";
    matrixHomeserverUrl = "http://127.0.0.1:6167";
    matrixOwnerMxid = "@kimb:kimb.dev";
    # @vox-bridge:kimb.dev access token — REUSED from Phase 1 (agenix secret;
    # minted via a transient allow_registration flip — see deploy/GO_NOGO.md §3
    # + the matrix-token-mint-requires-registration-flip memory). Only the
    # owner flips (below); the .age file is not re-encrypted.
    matrixBotTokenFile = config.age.secrets.matrix-vox-bridge-token.path;
    # nixpkgs has no `organism` package; the binary ships from the organism
    # flake input. The `organism` specialArg is threaded via rich-evans's
    # extraSpecialArgs in nixos-configurations.nix.
    organicBin = "${organism.packages.x86_64-linux.default}/bin/organic";
    # The 6 rooms the daemon joins at startup (4 officer dialogue rooms + the
    # vox-bridge vigil room + the bridge-events structured bus). The daemon
    # auto-creates any that do not yet exist + invites @kimb:kimb.dev (the
    # Phase-2 cutover creates the 5 rooms beyond #voidmaster).
    rooms = [
      "#vox-bridge:kimb.dev"
      "#voidmaster:kimb.dev"
      "#factotum:kimb.dev"
      "#ships-log:kimb.dev"
      "#enginearium:kimb.dev"
      "#bridge-events:kimb.dev"
    ];
    autoCreateRooms = true;
  };

  # Flip the token owner from voidmaster-organism (Phase 1) to vox-organism
  # (Phase 2). The age-encrypted file (../../secrets/matrix-vox-bridge-token.age)
  # is UNCHANGED — only the decrypted-file owner changes so the daemon (uid
  # 992) can read it. Rollback: set owner back to "voidmaster-organism".
  age.secrets.matrix-vox-bridge-token = {
    file = ../../secrets/matrix-vox-bridge-token.age;
    owner = "vox-organism";
    mode = "0400";
  };
}