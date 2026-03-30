# Qwen3-TTS server - zero-shot voice cloning via OpenAI-compatible API
#
# Uses faster-qwen3-tts (CUDA graph capture) for realtime inference.
# Built via uv2nix from PEP-723 inline metadata, with CUDA autopatchelf.
#
# Model: configurable via QWEN3_TTS_MODEL env (0.6B or 1.7B Base)
# Endpoint: POST http://total-eclipse.nebula:8091/v1/audio/speech
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Load PEP-723 script + its lock file via uv2nix
  script = inputs.uv2nix.lib.scripts.loadScript {
    script = ./qwen3-tts-server.py;
  };

  # Create overlay from locked deps (prefer pre-built wheels)
  overlay = script.mkOverlay {
    sourcePreference = "wheel";
  };

  # CUDA overlay: make autopatchelf find CUDA libs in torch/nvidia wheels
  cudaOverlay = self: super: {
    torch = super.torch.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.cudaPackages.cudatoolkit
        pkgs.cudaPackages.cudnn
        pkgs.cudaPackages.libcusparse
        pkgs.cudaPackages.libcusparse_lt
        pkgs.cudaPackages.libcufile
        pkgs.cudaPackages.libnvshmem
        pkgs.cudaPackages.nccl
        pkgs.addDriverRunpath
      ];
      autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [])
        ++ [
          "libcuda.so.1"
          "libnvshmem_host.so.*"
        ];
      postFixup = (old.postFixup or "") + ''
        addDriverRunpath $out/lib/python*/site-packages/torch/lib/libtorch_cuda*.so
      '';
    });
    nvidia-cusparse-cu12 = super.nvidia-cusparse-cu12.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.cudaPackages.libnvjitlink
      ];
    });
    nvidia-cusolver-cu12 = super.nvidia-cusolver-cu12.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.cudaPackages.libnvjitlink
        pkgs.cudaPackages.libcusparse
        pkgs.cudaPackages.libcublas
      ];
    });
    nvidia-cufile-cu12 = super.nvidia-cufile-cu12.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.rdma-core
      ];
      autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [])
        ++ ["libcuda.so.1"];
    });
    nvidia-nvshmem-cu12 = super.nvidia-nvshmem-cu12.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.openmpi
        pkgs.pmix
        pkgs.ucx
        pkgs.libfabric
        pkgs.rdma-core
      ];
    });
    numba = super.numba.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.tbb_2022
      ];
    });
    # torchaudio/torchvision link against libtorch*.so at runtime via Python's
    # import mechanism (torch is loaded first, adds its lib dir to search path).
    # Safe to ignore at build time.
    torchaudio = super.torchaudio.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.cudaPackages.cudatoolkit
      ];
      autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [])
        ++ ["libcuda.so.1" "libtorch*.so" "libc10*.so" "libcudart.so.*" "libtorch_python.so"];
    });
    torchvision = super.torchvision.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.cudaPackages.cudatoolkit
      ];
      autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [])
        ++ ["libcuda.so.1" "libtorch*.so" "libc10*.so" "libcudart.so.*" "libtorch_python.so"];
    });
    # soundfile needs libsndfile.so at runtime
    soundfile = super.soundfile.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.libsndfile
      ];
    });
    sox = super.sox.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        self.setuptools
      ];
    });
  };

  # Build Python package set with all overlays
  baseSet = pkgs.callPackage inputs.pyproject-nix.build.packages {
    python = pkgs.python312;
  };

  pythonSet = baseSet.overrideScope (
    lib.composeManyExtensions [
      inputs.pyproject-build-systems.overlays.wheel
      overlay
      cudaOverlay
    ]
  );

  # Create virtualenv with all deps, then render script with shebang
  venv = script.mkVirtualEnv {inherit pythonSet;};
  serverExecutable = pkgs.writeScript script.name (
    script.renderScript {inherit venv;}
  );
  voiceRefDir = "/home/kimb/shared_projects/claude_yapper/assets/voice-references";
in {
  # Copy voice reference files to /var/lib/voice-references/ for the TTS server
  system.activationScripts.voice-references = lib.stringAfter ["users"] ''
    mkdir -p /var/lib/voice-references
    for voice in soup-short jet2; do
      for ext in wav txt; do
        src="${voiceRefDir}/$voice.$ext"
        # soup-short.wav -> soup.wav (legacy naming)
        dest="/var/lib/voice-references/''${voice%-short}.$ext"
        if [ -f "$src" ]; then
          cp "$src" "$dest"
          chmod 644 "$dest"
        fi
      done
    done
  '';

  users.users.qwen3-tts = {
    isSystemUser = true;
    group = "qwen3-tts";
    home = "/var/lib/qwen3-tts";
  };
  users.groups.qwen3-tts = {};

  systemd.services.qwen3-tts = {
    description = "Qwen3 TTS OpenAI-compatible Server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    path = [pkgs.sox];

    environment = {
      HF_HOME = "/var/lib/qwen3-tts/huggingface";
      QWEN3_TTS_MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-Base";
      PYTHONUNBUFFERED = "1";
      VOICES_DIR = "/var/lib/voice-references";
      HOME = "/var/lib/qwen3-tts";
      # libcuda.so.1 from NVIDIA driver, libsndfile for soundfile, libcudnn_graph for cuDNN
      LD_LIBRARY_PATH = lib.makeLibraryPath [
        (lib.getLib pkgs.libsndfile)
        (lib.getLib pkgs.cudaPackages.cudnn)
      ] + ":/run/opengl-driver/lib";
    };

    serviceConfig = {
      Type = "simple";
      User = "qwen3-tts";
      Group = "qwen3-tts";
      ExecStart = "${serverExecutable}";
      Restart = "on-failure";
      RestartSec = 30;
      # First start downloads ~4.5GB model from HuggingFace
      TimeoutStartSec = "10min";
      WorkingDirectory = "/var/lib/qwen3-tts";
      StateDirectory = "qwen3-tts";

      # Hardening
      NoNewPrivileges = true;
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
