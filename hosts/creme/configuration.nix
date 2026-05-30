# creme - Dell Latitude E6400 ARG writerdeck
# Console-only network appliance — no X/Wayland; syncthing will sync text later.
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/laptop.nix
    ../../modules/nebula-node.nix
  ];

  networking.hostName = "creme";

  # BIOS boot on /dev/sda (no EFI on the E6400)
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = false;
  };

  # Use latest kernel for hardware compat on this old box
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Nebula mesh - reachable from your other personal devices
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
  };

  # Allow kimb to push closures via `nixos-rebuild --target-host`
  nix.settings.trusted-users = ["root" "kimb"];

  # Writerdeck console: kmscon replaces the kernel VT for custom fonts
  # and >16 colors. Required since this box has no X/Wayland.
  services.kmscon = {
    enable = true;
    hwRender = true;
    fonts = [
      {
        name = "BlexMono Nerd Font Mono";
        package = pkgs.nerd-fonts.blex-mono;
      }
    ];
    extraConfig = ''
      font-size=14
      xkb-layout=us
    '';
  };

  # Syncthing for syncing writing across devices.
  # First-run: web UI on http://creme.nebula:8384 to pair folders/devices.
  services.syncthing = {
    enable = true;
    user = "kimb";
    dataDir = "/home/kimb";
    configDir = "/home/kimb/.config/syncthing";
    openDefaultPorts = true;
  };

  # Neovim with vimwiki preloaded; init.lua is yours to write.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    configure.packages.creme.start = with pkgs.vimPlugins; [vimwiki];
  };

  environment.systemPackages = with pkgs; [
    tmux
    ncmpcpp
    mpc
    alsa-utils
    # acpi + brightnessctl already provided by laptop profile
  ];

  # Bare X server for ad-hoc GUI apps via `startx`. No display manager,
  # no window manager — `startx /run/current-system/sw/bin/emacs` (or a
  # ~/.xinitrc that does `exec emacs`) launches a single fullscreen app.
  # Deliberate: no WM means no easy browser-tab goofing.
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    xkb.layout = "us";
  };

  # Emacs daemon so `emacsclient -c` opens instantly. Starts on login.
  services.emacs.enable = true;

  # Fonts. Blex Mono Nerd Font as primary; Google monochrome emoji noto
  # so emoji render cleanly without dragging in colored fallback bitmaps.
  fonts.packages = with pkgs; [
    nerd-fonts.blex-mono
    noto-fonts-monochrome-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = ["BlexMono Nerd Font Mono"];
    emoji = ["Noto Emoji"];
  };

  # Sound — pipewire with alsa+pulse compat. Skipping rtkit (low-latency
  # RT priority is irrelevant for a music-player-only use case).
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # MPD runs as user kimb so the music dir can live in $HOME (where
  # syncthing drops files from shared_music / compressed_music).
  # Change musicDirectory after syncthing is set up if the path differs.
  services.mpd = {
    enable = true;
    user = "kimb";
    musicDirectory = "/home/kimb/Music";
    dataDir = "/home/kimb/.local/share/mpd";
    network.listenAddress = "127.0.0.1";
  };

  # Media + brightness keys via actkbd. Works in TTY and X — no WM needed.
  # actkbd runs as root, so brightnessctl + amixer + mpc all work without
  # user-session perms. Pipewire respects ALSA Master, so amixer keys do
  # what you'd expect.
  services.actkbd = {
    enable = true;
    bindings = [
      # Brightness (Fn keys → /sys/class/backlight)
      {keys = [224]; events = ["key"]; command = "${pkgs.brightnessctl}/bin/brightnessctl set 10%-";}
      {keys = [225]; events = ["key"]; command = "${pkgs.brightnessctl}/bin/brightnessctl set +10%";}
      # Volume (ALSA Master — pipewire honors it)
      {keys = [113]; events = ["key"]; command = "${pkgs.alsa-utils}/bin/amixer -q set Master toggle";}
      {keys = [114]; events = ["key"]; command = "${pkgs.alsa-utils}/bin/amixer -q set Master 5%-";}
      {keys = [115]; events = ["key"]; command = "${pkgs.alsa-utils}/bin/amixer -q set Master 5%+";}
      # Media (mpc → mpd on localhost:6600)
      {keys = [164]; events = ["key"]; command = "${pkgs.mpc}/bin/mpc toggle";}
      {keys = [163]; events = ["key"]; command = "${pkgs.mpc}/bin/mpc next";}
      {keys = [165]; events = ["key"]; command = "${pkgs.mpc}/bin/mpc prev";}
    ];
  };

  users.users.kimb.extraGroups = ["audio" "video"];

  system.stateVersion = "25.11";
}
