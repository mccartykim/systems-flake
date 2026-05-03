# Eden master built from source against a pinned commit, with cpmfile-based
# dependencies pre-fetched and exposed via CMake `<NAME>_CUSTOM_DIR` so the
# build never reaches the network.
#
# Bump procedure:
#   1. Update `commit` and `srcHash` for new master HEAD (or fix branch).
#   2. Re-vendor both cpmfile JSONs from upstream:
#        curl -sL https://git.eden-emu.dev/eden-emu/eden/raw/branch/master/cpmfile.json \
#          -o hosts/donut/eden-master-cpmfile.json
#        curl -sL https://git.eden-emu.dev/eden-emu/eden/raw/branch/master/externals/cpmfile.json \
#          -o hosts/donut/eden-master-cpmfile-externals.json
#   3. Add new entries to `bundled` / `disabled` below as needed.
#   4. nix-prefetch-url for each `bundled` entry to get the sha512.
#   5. Iterate: build, observe which `<NAME>_CUSTOM_DIR` is missing, add it.
{
  stdenv,
  lib,
  fetchurl,
  fetchFromGitea,
  eden, # base nixpkgs derivation we're overriding
  qt6,
}: let
  commit = "44fa2805d6c6d2b1a7e838d27d7d6eafb9c57420";
  srcHash = "sha256-PF16gdsg5/AfG0pA8ybV0j6gwrT1YbDjrrWoaAiPFzU=";
  shortSha = builtins.substring 0 10 commit;

  # `bundled`: cpmfile entries we pre-fetch ourselves and expose to CMake via
  # <NAME>_CUSTOM_DIR. Use this when the system version is wrong or absent.
  # Each value: { url, sha512 } from the upstream cpmfile.json. Patches are
  # applied automatically by CPM from eden's `.patch/<name>/` directory.
  bundled = {
    httplib = {
      url = "https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.18.7.tar.gz";
      sha512 = "5efa8140aadffe105dcf39935b732476e95755f6c7473ada3d0b64df2bc02c557633ae3948a25b45e1cf67e89a3ff6329fb30362e4ac033b9a1d1e453aa2eded";
    };
  };

  unpackDep = name: spec:
    stdenv.mkDerivation {
      name = "eden-cpm-${name}";
      src = fetchurl {inherit (spec) url sha512;};
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r . $out/
        runHook postInstall
      '';
    };

  customDirArgs =
    lib.mapAttrsToList
    (name: spec: "-D${name}_CUSTOM_DIR=${unpackDep name spec}")
    bundled;
in
  eden.overrideAttrs (old: {
    pname = "eden-master";
    version = "unstable-2026-05-03-${shortSha}";

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

    cmakeFlags = old.cmakeFlags ++ customDirArgs;

    doCheck = false;
  })
