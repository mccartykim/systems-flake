# Eden built from upstream master against a pinned commit. Mirrors
# nixpkgs's `pkgs.eden` derivation structure (which is at 0.1.1, too far
# behind master to use as an `overrideAttrs` base) plus master-specific
# additions: qt6.qtcharts (added in 0.2.x), per-profile arch flags, and
# SDL3 (upstream migrated from SDL2 in the 0.3.x era).
#
# CPM strategy:
#   - `CPMUTIL_FORCE_SYSTEM=ON` makes every CPM dep try a system package
#     via find_package; nixpkgs provides almost all of them as buildInputs.
#   - DiscordRPC (eden's fork) isn't in nixpkgs, so we mark it
#     `_FORCE_BUNDLED=ON` and supply a writable copy at
#     `$NIX_BUILD_TOP/cpm-deps/<name>/` via `<NAME>_CUSTOM_DIR`.
#     CPM applies the .patch/<name>/ patches in-place into that copy.
#   - httplib was previously bundled because of a version-constraint
#     propagation bug in eden's Findhttplib.cmake shim. The current shim
#     first tries CONFIG mode (which finds nixpkgs's httplib) and falls
#     back to pkg-config; the cpmfile no longer passes a version constraint
#     for httplib, so SameMinorVersion rejection no longer triggers.
#     nixpkgs httplib (0.30.2) is found and used as a system package.
#
# Profile values (matching upstream YUZU_BUILD_PRESET):
#   - "steamdeck": Zen 2 march (-march=znver2)
#   - "generic":   x86-64-v3 march
#   Other targets (zen4, native) can be added by extending the profile
#   case statement below.
#
# Bump procedure:
#   1. Update `commit` and `srcHash` for new master HEAD or fix branch.
#   2. Re-vendor both cpmfile JSONs from upstream:
#        curl -sL https://git.eden-emu.dev/eden-emu/eden/raw/branch/master/cpmfile.json \
#          -o pkgs/eden-master/cpmfile.json
#        curl -sL https://git.eden-emu.dev/eden-emu/eden/raw/branch/master/externals/cpmfile.json \
#          -o pkgs/eden-master/cpmfile-externals.json
#   3. Diff the upstream cpmfile against `bundled` below + nixpkgs eden's
#      buildInputs. New CPM deps surface as configure-time fetch failures;
#      add to `buildInputs` if nixpkgs has them (preferred) or to `bundled`
#      with a fetched URL + SRI hash if not.
#   4. nix-prefetch-url for new bundled entries; convert to SRI; paste in.
{
  stdenv,
  lib,
  fetchzip,
  fetchFromGitea,
  cmake,
  ninja,
  glslang,
  pkg-config,
  python3,
  qt6,
  sdl3,
  boost,
  cpp-jwt,
  cubeb,
  enet,
  ffmpeg-headless,
  fmt,
  frozen-containers,
  gamemode,
  httplib,
  kdePackages,
  libopus,
  libusb1,
  lz4,
  mbedtls,
  mcl-cpp-utility-lib,
  nlohmann_json,
  oaknut,
  openssl,
  pipewire,
  simpleini,
  sirit,
  spirv-headers,
  spirv-tools,
  stb,
  unordered_dense,
  vulkan-headers,
  vulkan-loader,
  vulkan-memory-allocator,
  vulkan-utility-libraries,
  xbyak,
  zlib,
  zstd,
  tzdata,
  profile ? "generic",
}: let
  commit = "470d43df6da19e5f48687087f1a8cc378bbe90ee";
  srcHash = "sha256-cnWXpr4V5BzYbCNiL+VgApBDtRwgqdg5l6w8Jd2nVeM=";
  shortSha = builtins.substring 0 10 commit;

  # Eden's externals/nx_tzdb/CMakeLists.txt fetches tzdb_to_nx via CPM
  # unless YUZU_TZDB_PATH is set to a prebuilt nx_tzdb directory. We build
  # it locally (mirrors nixpkgs eden's pattern) using nixpkgs's tzdata.
  # Rev pinned via cpmfile-externals.json's `git_version` for tzdb_to_nx;
  # bump together with a master commit bump.
  nx_tzdb = stdenv.mkDerivation (finalAttrs: {
    name = "tzdb_to_nx";
    version = "230326";

    src = fetchFromGitea {
      domain = "git.eden-emu.dev";
      owner = "eden-emu";
      repo = "tzdb_to_nx";
      tag = finalAttrs.version;
      hash = "sha256-koz7C63oHVfrhrf9lfdUqw6idJWi21XRKQnb5PdoEb4=";
    };

    nativeBuildInputs = [cmake ninja];

    cmakeFlags = [
      (lib.cmakeFeature "TZDB2NX_ZONEINFO_DIR" "${tzdata}/share/zoneinfo")
      (lib.cmakeFeature "TZDB2NX_VERSION" tzdata.version)
    ];

    ninjaFlags = ["x80e"];

    installPhase = ''
      runHook preInstall
      cp -r src/tzdb/nx $out
      runHook postInstall
    '';
  });

  # Per-profile compile flags + cmake preset, matching upstream
  # YUZU_BUILD_PRESET values in CMakeLists.txt.
  profileSpec =
    {
      steamdeck = {
        archFlags = "-march=znver2 -mtune=znver2 -O3";
        buildPreset = "zen2";
      };
      generic = {
        archFlags = "-march=x86-64-v3 -O3";
        buildPreset = "v3";
      };
    }
    .${
      profile
    };

  # CPM deps that aren't in nixpkgs. GitHub regenerates archive
  # tarballs over time, so the sha512 in upstream cpmfile.json drifts;
  # SRI hashes here come from `nix-prefetch-url` against the live URL,
  # not the cpmfile values. Patches at eden's `.patch/<name>/` apply
  # automatically once CPM resolves the source.
  bundled = {
    # Pulled in by USE_DISCORD_PRESENCE=ON; eden's fork is not in nixpkgs.
    # cpmfile key is "discord-rpc" but the cmake package name (and thus
    # the var watched by CPMUtil) is "DiscordRPC".
    DiscordRPC = {
      url = "https://github.com/eden-emulator/discord-rpc/archive/0d8b2d6a37.tar.gz";
      hash = "sha512-uI/baM81wrE/hA9FkZlozCDSlbLJ4XLXuaVQX4uGYPhzJLweyuNyTsE19UqP7+vksdGADScm8BKDHqmXdcox6A==";
    };
  };

  unpackDep = name: spec:
    fetchzip {
      name = "eden-cpm-${name}";
      inherit (spec) url hash;
      stripRoot = true;
    };

  # CPM applies patches in-place into the source dir, which fails on
  # /nix/store paths (read-only). Copy each pre-fetched source into the
  # build tree at configure time and point CMake at that writable copy.
  # The CUSTOM_DIR paths use $NIX_BUILD_TOP which only exists at build
  # time, so flags must be appended via cmakeFlagsArray in preConfigure
  # rather than set declaratively.
  copyAndFlagsScript =
    lib.concatStrings
    (lib.mapAttrsToList
      (name: spec: ''
        cp -r ${unpackDep name spec}/. "$NIX_BUILD_TOP/cpm-deps/${name}/"
        chmod -R u+w "$NIX_BUILD_TOP/cpm-deps/${name}"
        cmakeFlagsArray+=(
          "-D${name}_CUSTOM_DIR=$NIX_BUILD_TOP/cpm-deps/${name}"
          "-D${name}_FORCE_BUNDLED=ON"
        )
      '')
      bundled);
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "eden-master";
    version = "unstable-2026-06-05-${shortSha}-${profile}";

    src = fetchFromGitea {
      domain = "git.eden-emu.dev";
      owner = "eden-emu";
      repo = "eden";
      rev = commit;
      hash = srcHash;
    };

    nativeBuildInputs = [
      cmake
      ninja
      glslang
      pkg-config
      python3
      qt6.qttools
      qt6.wrapQtAppsHook
    ];

    buildInputs =
      [
        boost
        cpp-jwt
        cubeb
        enet
        ffmpeg-headless
        fmt
        frozen-containers
        gamemode
        httplib
        kdePackages.quazip
        libopus
        libusb1
        lz4
        mbedtls
        mcl-cpp-utility-lib
        nlohmann_json
        openssl
        qt6.qtbase
        qt6.qtcharts # added in eden 0.2.x
        qt6.qtmultimedia
        qt6.qtwayland
        qt6.qtwebengine
        sdl3
        simpleini
        sirit
        spirv-headers
        spirv-tools
        stb
        unordered_dense
        vulkan-headers
        vulkan-memory-allocator
        vulkan-utility-libraries
        zlib
        zstd
      ]
      ++ lib.optionals stdenv.hostPlatform.isx86_64 [xbyak]
      ++ lib.optionals stdenv.hostPlatform.isAarch64 [oaknut];

    __structuredAttrs = true;

    cmakeFlags = [
      (lib.cmakeBool "BUILD_TESTING" false)
      (lib.cmakeBool "YUZU_TESTS" false)

      # Make CPMUtil prefer system packages for everything not explicitly
      # marked _FORCE_BUNDLED via cmakeFlagsArray below.
      (lib.cmakeBool "CPMUTIL_FORCE_SYSTEM" true)

      # Don't let CPM fetch SDL3 or FFmpeg — we provide them as buildInputs.
      (lib.cmakeBool "YUZU_USE_BUNDLED_SDL3" false)
      (lib.cmakeBool "YUZU_USE_BUNDLED_FFMPEG" false)
      (lib.cmakeFeature "YUZU_TZDB_PATH" "${nx_tzdb}")

      # Profile-specific build preset (matches .ci/linux/build.sh)
      (lib.cmakeFeature "YUZU_BUILD_PRESET" profileSpec.buildPreset)

      (lib.cmakeBool "YUZU_USE_FASTER_LD" true)
      (lib.cmakeBool "ENABLE_LTO" true)
      (lib.cmakeBool "USE_DISCORD_PRESENCE" true)

      # Optional features — match nixpkgs eden's choices
      (lib.cmakeBool "YUZU_USE_QT_WEB_ENGINE" true)
      (lib.cmakeBool "YUZU_USE_QT_MULTIMEDIA" true)
      (lib.cmakeBool "ENABLE_QT_TRANSLATION" true)
      (lib.cmakeBool "YUZU_ENABLE_COMPATIBILITY_REPORTING" false)
    ];

    env.NIX_CFLAGS_COMPILE = profileSpec.archFlags;

    preConfigure = ''
      mkdir -p "$NIX_BUILD_TOP/cpm-deps"
      ${copyAndFlagsScript}
    '';

    postInstall = ''
      install -Dm444 $src/dist/72-eden-input.rules $out/lib/udev/rules.d/72-eden-input.rules
    '';

    preFixup = ''
      qtWrapperArgs+=(--prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          pipewire
        ]
      })
    '';

    doCheck = false;

    meta = {
      description = "Switch 1 emulator (eden master, built from source)";
      homepage = "https://eden-emu.dev/";
      mainProgram = "eden";
      license = with lib.licenses; [gpl3Plus];
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  })