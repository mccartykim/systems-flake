# Eden built from upstream master against a pinned commit, with cpmfile.json
# dependencies pre-fetched and exposed via CMake `<NAME>_CUSTOM_DIR` so the
# build never reaches the network.
#
# Configuration matches the upstream `.ci/linux/build.sh <profile>` script.
# Two `profile` values are wired up:
#   - "steamdeck": Zen 2 march, sdl2_steamdeck CPM dep, YUZU_SYSTEM_PROFILE
#   - "generic":   x86-64-v3 march, sdl2_generic CPM dep
# Other targets (rog-ally, legacy, native, aarch64) can be added by extending
# the profile case statement below.
#
# Bump procedure:
#   1. Update `commit` and `srcHash` for new master HEAD or fix branch.
#   2. Re-vendor both cpmfile JSONs from upstream:
#        curl -sL https://git.eden-emu.dev/eden-emu/eden/raw/branch/master/cpmfile.json \
#          -o pkgs/eden-master/cpmfile.json
#        curl -sL https://git.eden-emu.dev/eden-emu/eden/raw/branch/master/externals/cpmfile.json \
#          -o pkgs/eden-master/cpmfile-externals.json
#   3. Add new entries to `bundled` below as needed (build will surface them
#      one at a time as configure-time CPM fetch failures).
#   4. nix-prefetch-url for each entry; convert to SRI; paste into `bundled`.
{
  stdenv,
  lib,
  fetchurl,
  fetchFromGitea,
  eden, # nixpkgs base derivation we override
  qt6,
  profile ? "generic",
}: let
  commit = "44fa2805d6c6d2b1a7e838d27d7d6eafb9c57420";
  srcHash = "sha256-PF16gdsg5/AfG0pA8ybV0j6gwrT1YbDjrrWoaAiPFzU=";
  shortSha = builtins.substring 0 10 commit;

  # Per-profile compile flags + CPM SDL2 variant + cmake preset, matching
  # eden's `.ci/linux/build.sh`.
  profileSpec =
    {
      steamdeck = {
        archFlags = "-march=znver2 -mtune=znver2 -O3";
        buildPreset = "zen2";
        systemProfile = "steamdeck";
        sdlEntry = "sdl2_steamdeck";
        sdlSpec = {
          url = "https://github.com/libsdl-org/SDL/archive/cc016b0046.tar.gz";
          hash = "sha512-uNmHNEbNuSI4dHHfmWjgeHFGgwRmdO8NDt3fjiXaZaU5o7roPWNUlrlwI3+QsHs2pp+NeFXUUN5ZMR1tbow9vA==";
        };
      };
      generic = {
        archFlags = "-march=x86-64-v3 -O3";
        buildPreset = "v3";
        systemProfile = "generic";
        sdlEntry = "sdl2_generic";
        sdlSpec = {
          url = "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.32.10.tar.gz";
          hash = "sha512-1WIta7cmb3lCp7itQ+iiJSSJO/DC6hr5EgSDjZt40ydohD9vqiSHV0J7hAS4xkQ3dtSvprZyzYVxpODAOoKTgw==";
        };
      };
    }
    .${
      profile
    };

  # Bundled CPM dependencies (independent of profile). Patches at
  # eden's `.patch/<name>/` apply automatically once CPM resolves the source.
  # GitHub regenerates archive tarballs over time, so the sha512 in upstream
  # cpmfile.json drifts; SRI hashes here come from `nix-prefetch-url` against
  # the live URL, not the cpmfile values.
  baseBundled = {
    # cpmfile pins git_version=0.37.0 and version=0.18.7 — the latter is the
    # find_package min_version, the former is what %VERSION% in `tag` resolves
    # to (CPMUtil line 184). URL is v0.37.0; hash matches cpmfile.
    httplib = {
      url = "https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.37.0.tar.gz";
      hash = "sha512-XvqBQKrf/hBdzzmTW3MkdulXVfbHRzraPQtk3yvALFV2M645SKJbReHPZ+iaP/Yyn7MDYuSsAzuaHR5FOqLt7Q==";
    };

    # Pulled in by USE_DISCORD_PRESENCE=ON; eden's fork is not in nixpkgs.
    # Note: cpmfile key is "discord-rpc" but the cmake package name (and thus
    # the var watched by CPMUtil) is "DiscordRPC".
    DiscordRPC = {
      url = "https://github.com/eden-emulator/discord-rpc/archive/0d8b2d6a37.tar.gz";
      hash = "sha512-ghPEPcsPfUefWGEJHREe0S+97B5i5tcp1lpLwYHYL0ijXV/TzVwpHyOTrHyWgeq8a3Zgl1X1U3YoTIqNZ+FI8w==";
    };
  };

  bundled =
    baseBundled
    // {
      ${profileSpec.sdlEntry} = profileSpec.sdlSpec;
    };

  unpackDep = name: spec:
    stdenv.mkDerivation {
      name = "eden-cpm-${name}";
      src = fetchurl {inherit (spec) url hash;};
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r . $out/
        runHook postInstall
      '';
    };

  # CPM applies patches in-place into the source dir, which fails on /nix/store
  # paths (read-only). Copy each pre-fetched source into the build tree at
  # configure time and point CMake at that writable copy.
  copyAndFlagsScript =
    lib.concatStrings
    (lib.mapAttrsToList
      (name: spec: ''
        cp -r ${unpackDep name spec}/. "$NIX_BUILD_TOP/cpm-deps/${name}/"
        chmod -R u+w "$NIX_BUILD_TOP/cpm-deps/${name}"
        cmakeFlagsArray+=("-D${name}_CUSTOM_DIR=$NIX_BUILD_TOP/cpm-deps/${name}")
      '')
      bundled);
in
  eden.overrideAttrs (old: {
    pname = "eden-master";
    version = "unstable-2026-05-03-${shortSha}-${profile}";

    src = fetchFromGitea {
      domain = "git.eden-emu.dev";
      owner = "eden-emu";
      repo = "eden";
      rev = commit;
      hash = srcHash;
    };

    # rc2 backports don't apply on master.
    patches = [];

    # 0.2.x added a Qt6Charts dependency.
    buildInputs = old.buildInputs ++ [qt6.qtcharts];

    env =
      (old.env or {})
      // {
        NIX_CFLAGS_COMPILE = profileSpec.archFlags;
      };

    cmakeFlags =
      old.cmakeFlags
      ++ [
        "-DCMAKE_BUILD_TYPE=Release"
        "-DYUZU_BUILD_PRESET=${profileSpec.buildPreset}"
        "-DYUZU_SYSTEM_PROFILE=${profileSpec.systemProfile}"
        "-DYUZU_USE_EXTERNAL_SDL2=ON"
        "-DYUZU_USE_BUNDLED_SDL2=OFF"
        "-DYUZU_USE_FASTER_LD=ON"
        "-DENABLE_LTO=ON"
        "-DUSE_DISCORD_PRESENCE=ON"
      ];

    preConfigure =
      (old.preConfigure or "")
      + ''
        mkdir -p "$NIX_BUILD_TOP/cpm-deps"
        ${copyAndFlagsScript}
      '';

    doCheck = false;
  })
