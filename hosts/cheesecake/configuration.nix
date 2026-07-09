{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/desktop.nix
    ../../modules/nebula-node.nix
    ../../modules/restic-backup.nix
  ];

  # Restic backups
  kimb.restic.enable = true;

  # Nebula mesh network configuration (same as other laptops)
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
  };

  # Intel microcode updates for better thermal management
  hardware.cpu.intel.updateMicrocode = true;

  # VA-API hardware video decoding for Intel UHD Graphics 615 (Amber Lake, Gen 9.5)
  # intel-media-driver (iHD) is the current driver; i965 was discontinued Oct 2024
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-gmmlib
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
    VDPAU_DRIVER = "va_gl";
  };

  # Consider linux-surface kernel for better Surface Go 3 support
  # boot.kernelPackages = pkgs.linuxKernel.packages.linux_surface;

  boot.kernelParams = [
    "intel_pstate=passive"
    # Fix i915 atomic update failures: PSR/DC state race condition causes
    # display register corruption and frame drops on Amber Lake
    "i915.enable_psr=0"
    "i915.enable_dc=0"
  ];

  environment.systemPackages = with pkgs; [
    neovim
    firefox
    git
    lm_sensors # For temperature monitoring
    s-tui # Terminal UI for stress testing and monitoring
    powertop # Power usage optimization
    stress-ng # CPU stress testing
    kdePackages.qtvirtualkeyboard
    mu
    isync
  ];

  environment.sessionVariables = {
    PINENTRY_KDE_USE_WALLET = 1;
  };

  services.emacs.enable = true;

  system.stateVersion = "23.11";

  # Disable thermald - ACPI zones are broken on Surface Go 3, use TLP instead
  services.thermald.enable = false;

  # CPU frequency scaling managed by TLP
  powerManagement.cpuFreqGovernor = "schedutil";

  # Disable conflicting power management
  services.power-profiles-daemon.enable = false;

  # TLP for aggressive power/thermal management
  services.tlp = {
    enable = true;
    settings = {
      # CPU scaling - trust the thermal governor to throttle when hot
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_MIN_PERF_ON_AC = 20;
      CPU_MAX_PERF_ON_AC = 100; # Let intel_pstate throttle on temperature, not a hard cap
      CPU_MIN_PERF_ON_BAT = 20;
      CPU_MAX_PERF_ON_BAT = 70;

      # Enable turbo boost - temps are stable enough
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0; # Keep disabled on battery for battery life

      # Energy performance preference - balance for safe bursts
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      # Platform profile for thermal management
      PLATFORM_PROFILE_ON_AC = "balanced"; # Allow bursts but thermally aware
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # Battery charge thresholds for longevity
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  virtualisation.docker.enable = true;

  networking.hostName = "cheesecake";

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "kimb";
    dataDir = "/home/kimb";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.symbols-only
    nerd-fonts.intone-mono
    nerd-fonts.blex-mono
    nerd-fonts.noto
    nerd-fonts.recursive-mono
  ];

  # Configure CUPS to print documents (printing.enable + avahi come from desktop.nix).
  services.printing = {
    drivers = [
      pkgs.brlaser
      pkgs.brgenml1lpr
      pkgs.brgenml1cupswrapper
    ];
  };

  hardware.printers = {
    ensurePrinters = [
      {
        name = "Brother-HL-L2400D";
        description = "Brother HL-L2400D Laser Printer";
        location = "Living Room";
        deviceUri = "ipp://maitred.nebula:631/printers/Brother-HL-L2400D";
        model = "everywhere";
      }
    ];
    ensureDefaultPrinter = "Brother-HL-L2400D";
  };

  # z.ai API key for the claude-zai wrapper (home/modules/ai-tools.nix).
  # Read at exec-time by the wrapper from /run/agenix/zai-api-key.
  age.secrets.zai-api-key = {
    file = ../../secrets/zai-api-key.age;
    owner = "kimb";
    mode = "0400";
  };

  # Additional packages for kimb (user defined in base.nix)
  users.users.kimb.packages = with pkgs; [
    firefox
    krita
  ];

  # Ollama LLM server - accessible over Nebula for cloud inference
  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };
}