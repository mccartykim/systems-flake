# Marshmallow - ThinkPad T490 (Intel graphics, gaming laptop)
{
  config,
  lib,
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
    ../profiles/laptop.nix
    ../profiles/gaming.nix
    ../profiles/brother-printer.nix

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Restic backups to Backblaze B2
    ../../modules/restic-backup.nix
  ];

  kimb = {
    # Enable restic backups
    restic.enable = true;
    restic.extraExclude = [
      "/home/kimb/.platformio" # ESP32 toolchains - reinstallable
      "/home/kimb/.android" # Android emulator images
      "/home/kimb/Android" # Android SDK
      "/home/kimb/.gradle" # Build cache
    ];

    # Nebula configuration
    nebula = {
      enable = true;
      openToPersonalDevices = true;
    };

    # Syncthing — shared config via kimb.syncthing module
    syncthing.enable = true;

    # z.ai API key for the claude-zai wrapper — shared via kimb.zaiApiKey module.
    zaiApiKey.enable = true;
  };

  # Power management - use laptop profile's auto-cpufreq defaults
  # (turbo=auto on charger, turbo=never on battery, thermald as safety net)

  # Boot configuration
  boot = {
    kernelModules = ["i915" "uinput"];

    kernelPackages = pkgs.linuxKernel.packages.linux_6_18;

    # i915: Disable Panel Self Refresh - fixes Wayland freezes on KWin
    #   https://wiki.archlinux.org/title/Intel_graphics
    # nvme: Disable APST. The SPCC budget SSD misreports its power-state
    #   latency table; the controller sleeps between commands and stalls writes
    #   on wake, causing the periodic whole-system freezes (kernel logs
    #   "nvme ... timeout, aborting req_op:WRITE"; diskstats shows ~100% busy
    #   with ~0 ops during the stall).
    kernelParams = [
      "i915.enable_psr=0"
      "nvme_core.default_ps_max_latency_us=0"
    ];

    # systemd initrd
    initrd.systemd.enable = true;

    # Boot loader customizations
    loader.systemd-boot = {
      netbootxyz.enable = true;
      memtest86.enable = true;
    };

    plymouth = {
      enable = true;
      themePackages = [
        pkgs.adi1090x-plymouth-themes
      ];
      theme = "dna";
    };
  };

  # throttled 0.12 imports dbus_next, but nixpkgs' package.nix lists only
  # dbus-python in pythonPath -> "ModuleNotFoundError: No module named 'dbus_next'".
  # Upstream packaging bug, present even at nixpkgs-unstable tip. Add the missing
  # dep here until nixpkgs ships the fix.
  nixpkgs.overlays = [
    (final: prev: {
      throttled = prev.throttled.overrideAttrs (old: {
        pythonPath = old.pythonPath ++ [final.python3Packages.dbus-next];
      });
    })
  ];

  # Network configuration
  networking = {
    # Host identification
    hostName = "marshmallow";

    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Put maitred (via Nebula) first in resolv.conf so .nebula names
    # resolve on any network. NM dispatcher rewrites resolv.conf on
    # every connection change, inserting this before DHCP-provided DNS.
    networkmanager.insertNameservers = let
      registry = import ../nebula-registry.nix;
    in [registry.nodes.maitred.ip];

    # Firewall configuration
    firewall = {
      allowedTCPPorts = [9001 1701];
      allowedUDPPorts = [65535];
    };
  };

  # Services configuration
  services = {
    # Thermal management - bypass DYTC platform check
    thermald.ignoreCpuidCheck = true;

    # nixos-hardware's lenovo-thinkpad-t490 module enables services.throttled
    # implicitly. Its upstream defaults (PL1=44W AC, trip 95°C) assume a
    # chassis that can cool sustained 44W — the T490's single heatpipe
    # cannot, so the core was hitting 94°C on idle-ish load. These limits
    # are sized for the 15W base TDP of the i5-8365U with a little headroom
    # for bursts, and trip earlier than the 95°C default.
    throttled.extraConfig = ''
      [GENERAL]
      Enabled: True
      Sysfs_Power_Path: /sys/class/power_supply/AC*/online
      Autoreload: True
      [BATTERY]
      Update_Rate_s: 30
      PL1_Tdp_W: 15
      PL1_Duration_s: 28
      PL2_Tdp_W: 25
      PL2_Duration_S: 0.002
      Trip_Temp_C: 80
      [AC]
      Update_Rate_s: 5
      PL1_Tdp_W: 20
      PL1_Duration_s: 28
      PL2_Tdp_W: 30
      PL2_Duration_S: 0.002
      Trip_Temp_C: 85
    '';

    # Thunderbolt dock support
    hardware.bolt.enable = true;

    # Touchpad configuration
    libinput.mouse.naturalScrolling = true;

    # Wayland support for SDDM
    displayManager.sddm.wayland.enable = true;
    illum.enable = false;

    # Marshmallow-specific services
    yggdrasil = {
      enable = false;
      persistentKeys = true;
      openMulticastPort = true;
      group = "wheel";
      settings = {
        Peers = [
          "tcp://longseason.1200bps.xyz:13121"
          "tls://longseason.1200bps.xyz:13122"
          "quic://198.23.229.154:9003"
        ];
        LinkLocalTCPPort = 65535;
      };
    };

    keybase.enable = true;
    kbfs.enable = true;
    input-remapper.enable = true;

    # Ollama LLM server - accessible over Nebula for cloud inference
    ollama = {
      enable = true;
      host = "0.0.0.0"; # Bind to all interfaces
      openFirewall = true; # Open port 11434
    };
  };

  # Programs configuration
  programs = {
    chromium.enable = true;
    sway.enable = false;

    # Additional programs
    nix-ld.enable = true;
    mosh.enable = true;

    # Fish shell vendor configuration
    fish.vendor = {
      config.enable = true;
      functions.enable = true;
      completions.enable = true;
    };
  };

  # Intel graphics hardware configuration
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # For Broadwell+ iGPUs
    intel-gmmlib # Intel Graphics Memory Management Library
    intel-vaapi-driver # VAAPI driver for Intel graphics
    libva-vdpau-driver
    libvdpau-va-gl
    intel-compute-runtime # OpenCL support
  ];

  services.printing.drivers = [
    pkgs.brlaser
    pkgs.brgenml1lpr
    pkgs.brgenml1cupswrapper
  ];

  # ensure-printers needs nebula for maitred.nebula DNS
  systemd.services.ensure-printers = {
    after = ["nebula@nebula1.service"];
    wants = ["nebula@nebula1.service"];
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = "10s";
  };

  # Hardware acceleration for media
  environment = {
    sessionVariables = {
      VDPAU_DRIVER = "va_gl";
      LIBVA_DRIVER_NAME = "iHD"; # For newer Intel graphics
    };

    # Additional packages specific to marshmallow
    systemPackages = with pkgs; [
      keybase-gui
      kbfs
      gparted
      niri
      nh
      weylus
      orca-slicer
    ];
  };

  # Swap configuration
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # 16GB
    }
  ];

  # zram compressed swap - used before file swap (priority 5 vs -2)
  zramSwap.enable = true;

  # Kill memory-hogging cgroups before kwin starves and the cursor freezes.
  # This machine hit memory pressure 06-17/06-25/06-26; on 06-26 Android
  # Studio's EDT froze 42s and took the Wayland compositor with it.
  systemd.oomd = {
    enable = true;
    enableSystemSlice = true;
    enableUserSlices = true;
    settings.OOM = {
      DefaultMemoryPressureDurationSec = "20s";
      SwapUsedLimit = "90%";
    };
  };

  # Poll top-RSS procs every 60s into the journal so a future hard-reset leaves
  # evidence of what ate the RAM (the journal can't show per-process RSS
  # post-mortem on its own; systemd-oomd only logs the kill, not the buildup).
  # Permanent fixture. Query: journalctl -u mem-hog-log
  systemd.services.mem-hog-log = {
    description = "Snapshot top RSS processes for post-crash diagnosis";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/sh -c '${pkgs.procps}/bin/ps -eo pid,rss,args --sort=-rss --no-headers | ${pkgs.coreutils}/bin/head -n 15'";
    };
  };
  systemd.timers.mem-hog-log = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "60s";
    };
  };

  # User configuration
  users = {
    users.kimb = {
      extraGroups = ["docker" "dialout" "input"];
      initialPassword = "recovery";
    };
    groups.dialout.members = ["kimb"];
  };

  # Trusted users for nix
  nix.settings.trusted-users = ["root" "kimb"];

  system.stateVersion = "24.11";
}
