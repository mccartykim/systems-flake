{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../profiles/base.nix
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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  # Firefox hardware video decoding (Linux blocklist override)
  programs.firefox = {
    enable = true;
    preferences = {
      "media.hardware-video-decoding.force-enabled" = true;
      "gfx.webrender.all" = true;
    };
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
  services.tailscale.enable = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  virtualisation.docker.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  networking.hostName = "cheesecake";

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "kimb";
    dataDir = "/home/kimb";
  };

  programs.gnupg.agent.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.symbols-only
    nerd-fonts.intone-mono
    nerd-fonts.blex-mono
    nerd-fonts.noto
    nerd-fonts.recursive-mono
  ];

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;
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

  nixpkgs.config.allowUnfree = true;

  # Enable sound with pipewire.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  programs.fish.enable = true;
  # Define a user account. Don't forget to set a password with ‘passwd’.
  # Additional packages for kimb (user defined in base.nix)
  users.users.kimb.packages = with pkgs; [
    firefox
    krita
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Ollama LLM server - accessible over Nebula for cloud inference
  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # z.ai API key for the claude-zai wrapper (home/modules/ai-tools.nix).
  # Read at exec-time by the wrapper from /run/agenix/zai-api-key.
  age.secrets.zai-api-key = {
    file = ../../secrets/zai-api-key.age;
    owner = "kimb";
    mode = "0400";
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
}
