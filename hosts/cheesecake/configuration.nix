{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Intel microcode updates for better thermal management
  hardware.cpu.intel.updateMicrocode = true;

  # Consider linux-surface kernel for better Surface Go 3 support
  # boot.kernelPackages = pkgs.linuxKernel.packages.linux_surface;

  # Kernel parameters for better thermal management
  boot.kernelParams = [
    "intel_pstate=passive"        # Let thermal subsystem control frequency
    "thermal.tzp=1000"           # Poll thermal zones every 1000ms
    "thermal.off=0"              # Ensure thermal is enabled
    "processor.max_cstate=2"     # Limit C-states to reduce heat
  ];

  environment.systemPackages = with pkgs; [
    neovim
    firefox
    git
    lm_sensors  # For temperature monitoring
    s-tui       # Terminal UI for stress testing and monitoring
    powertop    # Power usage optimization
    stress-ng   # CPU stress testing
  ];

  environment.sessionVariables = {
   PINENTRY_KDE_USE_WALLET=1;
  };

  services.emacs.enable = true;

  system.stateVersion = "23.11";

  # Disable thermald - ACPI zones are broken, use kernel thermal management instead
  services.thermald.enable = false;

  # Aggressive CPU frequency scaling for thermal management
  powerManagement.cpuFreqGovernor = "powersave";


  # Disable conflicting power management
  services.power-profiles-daemon.enable = false;

  # TLP for aggressive power/thermal management
  services.tlp = {
    enable = true;
    settings = {
      # CPU scaling - safe burst performance with thermal limits
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";  # Responsive but thermal-aware
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_MIN_PERF_ON_AC = 20;     # Higher minimum for responsiveness
      CPU_MAX_PERF_ON_AC = 70;     # Conservative max to prevent 100°C spikes
      CPU_MIN_PERF_ON_BAT = 5;
      CPU_MAX_PERF_ON_BAT = 30;

      # Enable turbo boost - temps are stable enough
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;  # Keep disabled on battery for battery life

      # Energy performance preference - balance for safe bursts
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      # Platform profile for thermal management
      PLATFORM_PROFILE_ON_AC = "balanced";  # Allow bursts but thermally aware
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # Critical thermal protection - emergency throttling
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 80;

      # Intel GPU - limit frequencies to reduce thermal load
      INTEL_GPU_MIN_FREQ_ON_AC = 100;
      INTEL_GPU_MAX_FREQ_ON_AC = 400;  # Very conservative
      INTEL_GPU_MIN_FREQ_ON_BAT = 100;
      INTEL_GPU_MAX_FREQ_ON_BAT = 300;
    };
  };
  services.tailscale.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

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
  users.users.kimb = {
    isNormalUser = true;
    description = "Kimb";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      firefox
      krita
    #  thunderbird
    ];
  };

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
  # services.openssh.enable = true;

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
