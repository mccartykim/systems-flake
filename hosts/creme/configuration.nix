# creme - Dell Latitude E6400 ATG writerdeck
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
  networking.networkmanager.enable = true;

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

  # No kmscon. We run X on tty1 with emacs as the only client, so the
  # kernel VT doesn't need the fancy font treatment. tty2-6 stay as
  # plain getty (16 colors, kernel font) for the rare console use.

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
    # mu4e stack — `mu` provides both the binary and emacsPackages.mu4e
    mu
    isync
    gnupg
    # acpi + brightnessctl already provided by laptop profile
    git
    gh
    jujutsu
    helix
  ];

  # gpg-agent for mbsync PassCmd (decrypts ~/.authinfo.gpg).
  programs.gnupg.agent.enable = true;

  # X server with `startx` only — no display manager, no window manager.
  # emacs is the sole X client; vterm/eat host any shells you want.
  # Deliberate: no WM means no easy browser-tab goofing.
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    xkb.layout = "us";
  };

  # After logging in on tty1, fish auto-execs startx → emacs fullscreen.
  # tty2-6 stay as plain login prompts for the occasional console need.
  # Override by writing your own ~/.xinitrc on creme (startx prefers that).
  environment.etc."X11/xinit/xinitrc".text = ''
    exec ${pkgs.emacs}/bin/emacs
  '';
  programs.fish.loginShellInit = ''
    if test -z "$DISPLAY"; and test (tty) = /dev/tty1
      exec startx
    end
  '';

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

  # MPD as a user-owned service needs its dirs to exist; systemd won't
  # create paths under /home automatically.
  systemd.tmpfiles.rules = [
    "d /home/kimb/Music                 0755 kimb users -"
    "d /home/kimb/.local                0755 kimb users -"
    "d /home/kimb/.local/share          0755 kimb users -"
    "d /home/kimb/.local/share/mpd      0755 kimb users -"
    "d /home/kimb/.local/share/mpd/playlists 0755 kimb users -"
  ];

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

  # tty: lets `startx` open /dev/tty0 without setuid Xorg.
  # NOTE: start X from a non-kmscon VT (Ctrl+Alt+F2 → login → `startx`),
  # otherwise kmscon@tty1 holds the DRM device.
  users.users.kimb.extraGroups = ["audio" "video" "tty"];

  system.stateVersion = "25.11";
}
