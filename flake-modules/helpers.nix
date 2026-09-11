# Helper functions and common module lists for NixOS configurations
{
  inputs,
  self,
  ...
}: let
  inherit (inputs) nixpkgs home-manager srvos nix-index-database firefox-nightly nix-topology lix-module claude-wrapper;

  # Overlay to fix Python packages with build/test issues
  pythonFixesOverlay = final: prev: {
    # torch 2.13 requires AOTriton 0.12b (v3-only API: LazyTensor cookie,
    # attn_options.deterministic, VarlenType::StridedVarlen, seq_strides_*).
    # nixpkgs still ships 0.11.1b, so the ROCm attention sources fail to
    # compile against it. Bump aotriton; torch picks it up via
    # AOTRITON_INSTALLED_PREFIX = rocmPackages.aotriton.
    rocmPackages = prev.rocmPackages.overrideScope (rfinal: rprev: {
      # torch 2.13 requires AOTriton 0.12b (v3-only API: LazyTensor cookie,
      # attn_options.deterministic, VarlenType::StridedVarlen, seq_strides_*);
      # gfx1151 flash attention is promoted out of experimental in 0.12b.
      # nixpkgs still ships 0.11.1b. Source-building 0.12b in the sandbox is
      # impractical: its v3src/CMakeLists.txt clones ROCm/aiter from the
      # NETWORK at configure time (sandbox-blocked; the vendoring patch is
      # nontrivial), and the v3 kernel compile needs a triton venv + hours
      # with a real ENOSPC failure record on hydra (nixpkgs #453992).
      # Instead consume AMD's official prebuilt artifacts — the same approach
      # as huggingface/kernels' nix-builder aotriton_0_12: the rocm7.2 shim
      # tarball (cmake-install layout: lib/libaotriton_v2.so, headers, cmake
      # config) + the amd-gfx115x image pack (.aks2 kernels for the Radeon
      # 890M family). nixpkgs torch picks this up unchanged via
      # AOTRITON_INSTALLED_PREFIX = rocmPackages.aotriton (see
      # pkgs/development/python-modules/torch/source/default.nix) — no
      # bundling (BUILD_AOTRITON_INTO_WHEEL=false, already patched upstream).
      aotriton = prev.stdenv.mkDerivation (finalAttrs: {
        pname = "aotriton";
        version = "0.12b";

        src = prev.fetchurl {
          url = "https://github.com/ROCm/aotriton/releases/download/0.12b/aotriton-0.12b-manylinux_2_28_x86_64-rocm7.2-shared.tar.gz";
          hash = "sha256-W5fo0EGxYMhAhZYfPTvXuYkGQrFGussEyZGqmtao3Kg=";
        };
        # Only our arch family (Radeon 890M = gfx1151) — the other five
        # image packs (~720MB) are unnecessary. Hash from huggingface/kernels.
        images = prev.fetchurl {
          url = "https://github.com/ROCm/aotriton/releases/download/0.12b/aotriton-0.12b-images-amd-gfx115x.tar.gz";
          hash = "sha256-MXc4ehXGeLMAV/RYTR/BuPjbVhY4kMtcmPJ0UCCfWns=";
        };

        nativeBuildInputs = [prev.autoPatchelfHook];
        buildInputs = [prev.stdenv.cc.cc.lib prev.xz rprev.clr];

        dontConfigure = true;
        dontBuild = true;
        # Keep the prebuilt .so's symbols intact (torch binds them at link).
        dontStrip = true;

        installPhase = ''
          runHook preInstall

          # Shim tarball: aotriton/{lib,include} -> cmake-install layout.
          mkdir -p "$out"
          tar -C "$out" -zxf "$src" --strip-components=1

          # Image pack: aotriton/lib/aotriton.images/amd-gfx115x/... ->
          # $out/lib/aotriton.images/amd-gfx115x/... (runtime resolves
          # kernels relative to the .so).
          mkdir -p "$out/lib"
          tar -C "$out/lib" -zxf "$images" --strip-components=2 aotriton/lib/aotriton.images

          runHook postInstall
        '';

        meta = with prev.lib; {
          description = "Ahead of Time (AOT) Triton Math Library (prebuilt shim + gfx115x images)";
          homepage = "https://github.com/ROCm/aotriton";
          license = licenses.mit;
          platforms = ["x86_64-linux"];
          sourceProvenance = with sourceTypes; [binaryNativeCode];
        };
      });
    });

    python3Packages = prev.python3Packages.override {
      overrides = pyFinal: pyPrev: {
        # extract_msg requires beautifulsoup4<4.14 but nixpkgs has 4.14.x
        # The package works fine with newer versions, just has strict bounds
        extract-msg = pyPrev.extract-msg.overridePythonAttrs (old: {
          nativeBuildInputs =
            (old.nativeBuildInputs or [])
            ++ [
              pyFinal.pythonRelaxDepsHook
            ];
          pythonRelaxDeps = ["beautifulsoup4"];
        });

        # duckdb-engine tests fail because DuckDB doesn't implement all
        # PostgreSQL system catalogs (pg_collation, etc). The package itself
        # works fine; only the test suite has compatibility issues.
        duckdb-engine = pyPrev.duckdb-engine.overridePythonAttrs (old: {
          doCheck = false;
        });

        # torchWithRocm (torch 2.13, python3.14) fails on historian (Strix
        # Point, gfx1151):
        # 1. Upstream CK flash-attn script add_make_kernel_pt.sh has a
        #    #!/bin/bash shebang that doesn't exist in the sandbox — patch it.
        # 2. CK FMHA primarily targets gfx9 (CDNA); on gfx1151 kernel
        #    generation fails later anyway, and AOTriton (the preferred SDPA
        #    backend) supports RDNA, so disable CK SDPA.
        # 3. Restrict build to gfx1151 via gpuTargets override.
        torchWithRocm =
          (pyPrev.torchWithRocm.override {
            # Setting PYTORCH_ROCM_ARCH via env would be pointless: the torch
            # derivation re-exports it from gpuTargets (which takes priority),
            # so override gpuTargets directly.
            gpuTargets = ["gfx1151"];
          }).overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + ''
                patchShebangs aten/src/ATen/native/transformers/hip/flash_attn/ck/
              '';
            env =
              (old.env or {})
              // {
                USE_ROCM_CK_SDPA = "0";
              };
          });
      };
    };
  };

  # Overlay to use Firefox Nightly and override pkgs.firefox to point to nightly
  firefoxNightlyOverlay = final: prev: let
    nightlyPkgs = firefox-nightly.packages.${prev.system};
  in {
    firefox = nightlyPkgs.firefox-nightly-bin;
  };
in {
  # Export helpers via flake.lib for use by other modules
  flake.lib = rec {
    # Common modules applied to all NixOS configurations.
    # lix-module goes first so its overlay (nixVersions.stable → Lix + the
    # CppNix-keep list) is applied before anything else consults nix. This covers
    # every NixOS host, including creme/donut which use commonModules directly
    # rather than mkDesktop/mkServer. (Darwin uses darwinModules.lixFromNixpkgs
    # separately if ever wanted.)
    commonModules = [
      lix-module.nixosModules.lixFromNixpkgs
      nix-index-database.nixosModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
      (self + "/modules/distributed-builds.nix")
      {kimb.distributedBuilds.enable = true;}
      (self + "/modules/agenix.nix")
      (self + "/modules/sre-agent.nix")
      (self + "/modules/observability.nix")
      (self + "/modules/syncthing.nix")
      (self + "/modules/maitred-nameservers.nix")
      (self + "/modules/zai-api-key.nix")
      # kimb.* option declarations + per-host service auto-injection
      (self + "/modules/kimb-services.nix")
      (self + "/services/default.nix")
      # Fix Python packages with strict version bounds + Firefox Nightly +
      # the generic claude-code wrapper generator (pkgs.mkClaudeWrapper).
      {nixpkgs.overlays = [pythonFixesOverlay firefoxNightlyOverlay claude-wrapper.overlays.default];}
      # Infrastructure/network diagram generation
      nix-topology.nixosModules.default
      # Static nebula host entries so hostname.nebula resolves without maitred DNS
      (_: let
        registry = import (self + "/hosts/nebula-registry.nix");
        names = builtins.attrNames registry.nodes;
        # Nodes that carry an SSH host key in the registry (tachikoma doesn't).
        pinned = builtins.filter (n: (registry.nodes.${n}.publicKey or null) != null) names;
      in {
        networking.extraHosts =
          builtins.concatStringsSep "\n"
          (builtins.map (name: "${registry.nodes.${name}.ip} ${name}.nebula") names);
        # Pin every fleet host's SSH host key fleet-wide so `ssh …@<host>.nebula`
        # never TOFU-prompts and never breaks when a host rekeys. This caught
        # oracle 2026-07-25: total-eclipse had drifted off oracle's key and colmena
        # couldn't SSH to it → oracle's authorized_keys went stale → phone→oracle
        # failed auth. mochi is included here too — it's a nebula host but NOT
        # NixOS-managed (AVF Debian), so its key never enters via the normal NixOS
        # host-key path; the AVF restore script bakes this STABLE key. Registry
        # keys verified 2026-07-25 to match live `ssh-keyscan` for oracle +
        # historian + mochi.
        programs.ssh.knownHosts = builtins.listToAttrs (builtins.map (n: {
            name = n;
            value = {
              hostNames = ["${n}.nebula" registry.nodes.${n}.ip];
              publicKey = registry.nodes.${n}.publicKey;
            };
          })
          pinned);
      })
    ];

    # Desktop-specific modules (srvos desktop + common mixins)
    # NB: mixins-nix-experimental deliberately omitted — it enables CppNix-only
    # experimental features (ca-derivations, impure-derivations, recursive-nix,
    # fetch-closure, blake3-hashes, configurable-impure-env) that Lix doesn't
    # implement, which hard-fails the nix.conf build-time validator under Lix.
    desktopModules = [
      srvos.nixosModules.desktop
      srvos.nixosModules.mixins-trusted-nix-caches
    ];

    # Server-specific modules (see desktopModules note re: nix-experimental)
    serverModules = [
      srvos.nixosModules.server
      srvos.nixosModules.mixins-trusted-nix-caches
      srvos.nixosModules.mixins-systemd-boot
    ];

    # Darwin common modules
    darwinCommon = [
      home-manager.darwinModules.home-manager
      nix-index-database.darwinModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
    ];

    # Home-manager configuration helper
    mkHomeManager = {
      user ? "kimb",
      homeConfig,
      useGlobalPkgs ? true,
    }: [
      home-manager.nixosModules.home-manager
      {
        home-manager = {
          backupFileExtension = "backup";
          inherit useGlobalPkgs;
          useUserPackages = true;
          users.${user} = homeConfig;
        };
      }
    ];

    # Helper to create a desktop NixOS configuration
    mkDesktop = {
      hostname,
      system ? "x86_64-linux",
      extraModules ? [],
      extraSpecialArgs ? {},
      hardwareModules ? [],
      homeConfig ? (self + "/home/${hostname}.nix"),
      useGlobalPkgs ? true,
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs =
          {
            inherit inputs;
            outputs = self;
          }
          // extraSpecialArgs;
        modules =
          desktopModules
          ++ commonModules
          ++ hardwareModules
          ++ [(self + "/hosts/${hostname}/configuration.nix")]
          ++ mkHomeManager {inherit homeConfig useGlobalPkgs;}
          ++ extraModules;
      };

    # Helper to create a server NixOS configuration
    mkServer = {
      hostname,
      system ? "x86_64-linux",
      extraModules ? [],
      extraSpecialArgs ? {},
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs =
          {
            inherit inputs;
            outputs = self;
          }
          // extraSpecialArgs;
        modules =
          serverModules
          ++ commonModules
          ++ [(self + "/hosts/${hostname}/configuration.nix")]
          ++ extraModules;
      };
  };
}
