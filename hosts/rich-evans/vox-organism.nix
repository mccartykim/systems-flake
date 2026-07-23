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
# vox-organism so the daemon (uid 998) can read its token.
{
  config,
  lib,
  pkgs,
  organism,
  ...
}: {
  services.vox-organism = {
    enable = true;
    # @vox-bridge:kimb.dev access token — REUSED from Phase 1 (agenix secret;
    # minted via a transient allow_registration flip — see deploy/GO_NOGO.md §3
    # + the matrix-token-mint-requires-registration-flip memory). Only the
    # owner flips (below); the .age file is not re-encrypted.
    matrixBotTokenFile = config.age.secrets.matrix-vox-bridge-token.path;
    # nixpkgs has no `organism` package; the binary ships from the organism
    # flake input. The `organism` specialArg is threaded via rich-evans's
    # extraSpecialArgs in nixos-configurations.nix.
    organicBin = "${organism.packages.x86_64-linux.default}/bin/organic";
    # The rooms the daemon joins at startup (officer dialogue rooms + the
    # vox-bridge vigil room + the bridge-events structured bus). The daemon
    # auto-creates any that do not yet exist + invites @kimb:kimb.dev. The
    # Chirurgeon (#62) joins the crew as the 5th officer dialogue room.
    rooms = [
      "#vox-bridge:kimb.dev"
      "#voidmaster:kimb.dev"
      "#factotum:kimb.dev"
      "#ships-log:kimb.dev"
      "#enginearium:kimb.dev"
      "#chirurgeon:kimb.dev"
      "#bridge-events:kimb.dev"
    ];
    # Authoring hop: the daemon SSHes to this host (bridge-scribe on historian,
    # a forced-command servitor — see hosts/historian/bridge-scribe.nix) to
    # materialize an officer's `author` request (clone -> commit on
    # proposed/<slug> -> push). rich-evans is an antique mini PC that must not
    # run builds or grow clones, so the scratch clone + git push happen on
    # historian. Fleet-internal, over Nebula.
    historianHost = "historian.nebula";
    # The fleet-internal ssh key (agenix below, owned by vox-organism) the
    # daemon uses for that hop. The per-repo GitHub deploy keys live ONLY on
    # historian (agenix, owned by bridge-scribe) — this daemon never sees them.
    fleetSshKeyFile = config.age.secrets.bridge-fleet-ssh-key.path;
  };

  # Flip the token owner from voidmaster-organism (Phase 1) to vox-organism
  # (Phase 2). The age-encrypted file (../../secrets/matrix-vox-bridge-token.age)
  # is UNCHANGED — only the decrypted-file owner changes so the daemon (uid
  # 998) can read it. Rollback: set owner back to "voidmaster-organism".
  age.secrets.matrix-vox-bridge-token = {
    file = ../../secrets/matrix-vox-bridge-token.age;
    owner = "vox-organism";
    mode = "0400";
  };

  # Fleet-internal ssh key (rich-evans -> historian) the vox-organism daemon
  # uses to reach the bridge-scribe forced-command servitor and materialize an
  # officer's `author` request. Owner is vox-organism (the daemon reads it);
  # mode 0400 (private key). This is NOT a GitHub key — it never touches github;
  # it only authenticates the in-fleet hop to the scribe. Private half encrypted
  # to rich-evans + bootstrap in secrets/bridge-fleet-ssh-key.age.
  age.secrets.bridge-fleet-ssh-key = {
    file = ../../secrets/bridge-fleet-ssh-key.age;
    owner = "vox-organism";
    mode = "0400";
  };
}