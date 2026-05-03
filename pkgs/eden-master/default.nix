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
  fetchzip,
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
          hash = "sha512-/5f7aIfou0gvtttWKKnaWOAzdqn0Egtn+8mcmyrKCFVSvlCmzXfuarKubo1+OhHwKylVfvHYZzVTIVne7W8mxA==";
        };
      };
      generic = {
        archFlags = "-march=x86-64-v3 -O3";
        buildPreset = "v3";
        systemProfile = "generic";
        sdlEntry = "sdl2_generic";
        sdlSpec = {
          url = "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.32.10.tar.gz";
          hash = "sha512-kUezWZLlYEOCQWLEpQMGAFUGE8hMrqayhQAh3idfBUmLzSZFS4x6GUKbVr57LPV0ALutQpTEm329omAgX9ON1A==";
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
  #
  # Note on httplib: nixpkgs has it (0.30.2) but eden's cpmfile uses
  # `find_args = "MODULE GLOBAL"`, and eden's Findhttplib.cmake shim doesn't
  # propagate the version constraint to its inner `find_package(... CONFIG)`
  # call, so version-aware MODULE-mode lookups fail in
  # CPM_LOCAL_PACKAGES_ONLY mode. Patching the shim is more invasive than
  # bundling, so we bundle.
  baseBundled = {
    # cpmfile pins git_version=0.37.0 and version=0.18.7 — the latter is the
    # find_package min_version, the former is what %VERSION% in `tag` resolves
    # to (CPMUtil line 184). URL is v0.37.0.
    httplib = {
      url = "https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.37.0.tar.gz";
      hash = "sha512-e7cVrhSKKpVa4m1ipFmdnLVnXMqP3vq2gBXIFXd4ihH30LSDqmMotKxsUv767mpMRM6TZVIyBQvkDlAyM+cbzg==";
    };

    # Pulled in by USE_DISCORD_PRESENCE=ON; eden's fork is not in nixpkgs.
    # Note: cpmfile key is "discord-rpc" but the cmake package name (and thus
    # the var watched by CPMUtil) is "DiscordRPC".
    DiscordRPC = {
      url = "https://github.com/eden-emulator/discord-rpc/archive/0d8b2d6a37.tar.gz";
      hash = "sha512-uI/baM81wrE/hA9FkZlozCDSlbLJ4XLXuaVQX4uGYPhzJLweyuNyTsE19UqP7+vksdGADScm8BKDHqmXdcox6A==";
    };
  };

  bundled =
    baseBundled
    // {
      ${profileSpec.sdlEntry} = profileSpec.sdlSpec;
    };

  unpackDep = name: spec:
    fetchzip {
      name = "eden-cpm-${name}";
      inherit (spec) url hash;
      stripRoot = true;
    };

  # CPM applies patches in-place into the source dir, which fails on /nix/store
  # paths (read-only). Copy each pre-fetched source into the build tree at
  # configure time and point CMake at that writable copy. The CUSTOM_DIR
  # paths use $NIX_BUILD_TOP which only exists at build time, so flags must be
  # appended via cmakeFlagsArray in preConfigure rather than set declaratively.
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

    # Drop conflicting flags from the upstream rc2 derivation: it sets
    # YUZU_USE_EXTERNAL_SDL2=FALSE and BUILD_TESTING=TRUE, which we override
    # below. CMake honors the last value but the compile cost of the tests
    # we then skip via doCheck=false adds up.
    cmakeFlags =
      (lib.filter (f:
        !(lib.hasPrefix "-DYUZU_USE_EXTERNAL_SDL2:" f)
        && !(lib.hasPrefix "-DBUILD_TESTING:" f))
      old.cmakeFlags)
      ++ [
        "-DCMAKE_BUILD_TYPE=Release"
        "-DBUILD_TESTING=OFF"
        "-DYUZU_BUILD_PRESET=${profileSpec.buildPreset}"
        "-DYUZU_SYSTEM_PROFILE=${profileSpec.systemProfile}"
        "-DYUZU_USE_EXTERNAL_SDL2=ON"
        "-DYUZU_USE_BUNDLED_SDL2=OFF"
        "-DYUZU_USE_FASTER_LD=ON"
        "-DENABLE_LTO=ON"
        "-DUSE_DISCORD_PRESENCE=ON"
      ];

    # Append rather than replace so future upstream additions to NIX_CFLAGS_COMPILE
    # aren't clobbered.
    env =
      (old.env or {})
      // {
        NIX_CFLAGS_COMPILE = lib.concatStringsSep " " [
          (old.env.NIX_CFLAGS_COMPILE or "")
          profileSpec.archFlags
        ];
      };

    preConfigure =
      (old.preConfigure or "")
      + ''
        mkdir -p "$NIX_BUILD_TOP/cpm-deps"
        ${copyAndFlagsScript}
      '';

    doCheck = false;
  })
