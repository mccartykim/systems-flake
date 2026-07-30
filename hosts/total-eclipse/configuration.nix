# Total Eclipse - Gaming desktop (NVIDIA graphics, streaming)
{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/desktop.nix
    ../profiles/gaming.nix

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Restic backups to Backblaze B2
    ../../modules/restic-backup.nix

    # Auto-reload NVIDIA modules after config changes
    ./nvidia-reload.nix

    # Qwen3-TTS voice cloning server (port 8091)
    ./qwen3-tts.nix

    # Paperless-ngx document management (scanned mail from maitred)
    ./paperless.nix

    # Switch emulator (Eden master, x86-64-v3 generic profile)
    ./emulation.nix
  ];

  kimb = {
    # Restic backups
    restic.enable = true;
    restic.extraExclude = [
      "/home/kimb/.android"
      "/home/kimb/.gradle"
    ];

    # Centralized observability — DISABLED: too noisy, low value for now
    # observability.enable = true;

    # Nebula configuration
    nebula = {
      enable = true;
      openToPersonalDevices = true;
      extraInboundRules = [
        {
          port = 11434;
          proto = "tcp";
          host = "any";
        } # Ollama API
        {
          port = 8091;
          proto = "tcp";
          group = "servers";
        } # Qwen3-TTS for life coach on rich-evans
        # Journal-remote sink (maitred → total-eclipse for log aggregation)
        {
          port = 19532;
          proto = "tcp";
          host = "maitred";
        }
      ];
    };
  };

  # Disable sleep/suspend (keeps waking immediately anyway)
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # Host identification and networking configuration
  networking = {
    hostName = "total-eclipse";
    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Network interface configuration
    interfaces.eno2.wakeOnLan = {
      enable = true;
      policy = ["magic" "unicast"];
    };

    # Extended firewall configuration for streaming
    firewall = {
      allowedTCPPorts = [47984 47989 47990 48000 48010];
      allowedUDPPorts = [4242]; # Nebula
      allowedUDPPortRanges = [
        {
          from = 47998;
          to = 48020;
        }
        {
          from = 8000;
          to = 8010;
        }
      ];
      trustedInterfaces = ["nebula1"];
    };
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "kimb";
  };

  kimb.syncthing.enable = true;
  kimb.maitredNameservers.enable = true;

  # NVIDIA graphics hardware configuration
  services.xserver.videoDrivers = ["nvidia"];

  # Headless display: NVIDIA needs a hint that a monitor *might* appear,
  # otherwise the X server exits and the autologin Plasma session never
  # starts — which is why Sunshine (a user unit under graphical-session)
  # never launches until someone logs in in person.
  services.xserver.deviceSection = ''
    Option "AllowEmptyInitialConfiguration" "true"
    Option "ConnectedMonitor" "DFP-0"
  '';

  # CUDA support — kept GLOBAL on purpose. nixpkgs.config.cudaSupport = true is
  # load-bearing for the cache match of the GPU packages (ollama, torchWithCuda):
  # hydra builds the cuda-cache artifacts on cache.nixos-cuda.org in a
  # cudaSupport=true context, so a cuda package forced from a cudaSupport=false
  # global context resolves to different transitive drv hashes (e.g.
  # cuda12.9-libnvshmem) than hydra cached -> it falls off the cuda cache and
  # compiles from source. We tried opt-in (global false + explicit
  # ollama-cuda/torchWithCuda) on 2026-07-29 and it regressed python3.14-torch
  # (torchWithCuda) + libnvshmem from FETCHED to BUILT-from-source — a net loss,
  # since torch-cuda is a far bigger compile than the onnxruntime build the
  # opt-in was meant to avoid. So: global true stays, and the packages that
  # DON'T need GPU (onnxruntime/openvino/opencv, pulled by paperless) are de-cuda'd
  # with the targeted chained override below instead.
  nixpkgs.config.cudaSupport = true;

  # onnxruntime is pulled transitively by paperless (document classification
  # via small ONNX models — CPU inference is plenty, no CUDA needed). With the
  # global cudaSupport=true above it would otherwise build the CUDA variant,
  # which is NOT on cache.nixos-cuda.org (HTTP 404 as of 2026-07-29) and so
  # compiles from source — a long C++ build. Forcing non-CUDA makes it
  # substitute from cache.nixos.org instead (HTTP 200).
  #
  # The override is a CHAIN because cudaSupport is transitive here:
  # openvino's `cudaSupport ? opencv.cudaSupport or false`
  # (openvino/package.nix:5), so under global cudaSupport=true, openvino is
  # CUDA because opencv is CUDA, and onnxruntime depends on openvino. Overriding
  # only onnxruntime's cudaSupport yields a non-cuda onnxruntime linked against
  # CUDA openvino — a hybrid on no cache, still built from source. To reproduce
  # the cached non-cuda onnxruntime, de-cuda the whole sub-chain: onnxruntime +
  # its openvino input + that openvino's opencv input. Each is the cached
  # non-cuda variant on cache.nixos.org (verified 2026-07-29 to produce
  # zhdpsvvk-onnxruntime-1.27.1). The top-level opencv4/openvino stay CUDA
  # (cached on cache.nixos-cuda.org) for other consumers; only onnxruntime's
  # private sub-chain is non-cuda. NB: onnxruntime's arg is `cudaSupport`
  # (package.nix:26), opencv4's is `enableCuda` (4.x.nix:45) — they differ. The
  # python onnxruntime package wraps the lib's wheel (`src = onnxruntime.dist`),
  # so overriding the lib propagates to python313Packages.onnxruntime paperless
  # uses. arg `python3Packages` (not `python3`) selects the python version.
  #
  # MAINTENANCE: this is an optimization (build -> download), not correctness —
  # worst case on a nixpkgs bump is onnxruntime silently rebuilding from source
  # (if a new cuda-resolved dep joins the chain) or a loud eval error (if an arg
  # is renamed). Catch regressions with: nix build --dry-run .#nixosConfigurations\
  # .total-eclipse.config.system.build.toplevel 2>&1 | grep onnxruntime
  nixpkgs.overlays = [
    (final: prev: {
      onnxruntime = prev.onnxruntime.override {
        cudaSupport = false;
        openvino = prev.openvino.override {
          cudaSupport = false;
          opencv = prev.opencv4.override { enableCuda = false; };
        };
        python3Packages = final.python313.pkgs;
      };
    })
  ];

  # Hardware configuration
  hardware = {
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = true; # Use open-source drivers
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # OpenGL and hardware acceleration
    graphics.extraPackages = with pkgs; [
      libva-vdpau-driver
      libvdpau-va-gl
    ];

    # Container support for NVIDIA
    nvidia-container-toolkit.enable = true;
  };

  # Environment configuration
  environment = {
    # Environment variables for NVIDIA
    sessionVariables = {
      LIBVA_DRIVER_NAME = "nvidia";
      VDPAU_DRIVER = "nvidia";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };

    # Additional packages specific to total-eclipse
    systemPackages = with pkgs; [
      # NVIDIA packages
      nvtopPackages.nvidia
      nvidia-container-toolkit
      python3Packages.torchWithCuda
      # Total-eclipse specific packages
      legendary-gl
      sunshine
      toolbox
      tealdeer
      orca-slicer
    ];
  };

  # Boot loader - GRUB for legacy system
  boot.loader = {
    systemd-boot.enable = false;
    grub = {
      enable = true;
      device = "/dev/nvme0n1";
    };
  };

  # Swap configuration
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 32 * 1024; # 32GB
    }
  ];

  # Services configuration
  services = {
    # Enable Sunshine for game streaming
    sunshine.enable = true;

    # Ollama LLM server - exposed over Nebula
    ollama = {
      enable = true;
      host = "0.0.0.0"; # Bind to all interfaces
      openFirewall = true; # Open port 11434
    };
    xrdp = {
      enable = true;
      openFirewall = true;
    };

    # Avahi for service discovery
    avahi.publish = {
      enable = true;
      userServices = true;
    };
  };

  # Additional user groups
  users.users.kimb = {
    description = "Kimberly";
    extraGroups = ["input"];
  };

  system.stateVersion = "23.11";
}
