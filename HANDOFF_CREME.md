# creme handoff — post-libreboot follow-ups

Date: 2026-05-31

Previous agent finished installing libreboot 26.01rev1 on creme (Dell Latitude E6400 ATG, Intel GMA 4500MHD, 4 MiB Macronix MX25L32xx SPI). All work below is post-install cleanup + investigations that the user wants picked up by the next agent.

## Current state to inherit

- Libreboot ROM flashed and verified (`Verifying flash... VERIFIED.` from flashprog).
- ROM variant: `seagrub_e6400_4mb_libgfxinit_corebootfb_usqwerty` (SeaBIOS+GRUB chain, framebuffer splash, US layout).
- GbE MAC at the firmware level: `02:e7:76:66:7b:fc` (random locally-administered).
- OS-level ethernet MAC override: **removed in this session.** Interface is now `eno0` (was `enp0s25` under Dell BIOS — coreboot presents PCIe device info differently, so predictable-naming picked `eno0`). Firmware GbE MAC `02:e7:76:66:7b:fc` is what's visible; that's the random locally-administered value we wanted. NetworkManager wifi randomization on `wlp12s0` is unchanged.
- `boot.kernelParams = ["iomem=relaxed"];`: **removed in this session** alongside the MAC override.
- `nebula-registry.nix` creme `meta` comment updated: was "console-only, no X/Wayland"; now reflects i3 + emacs + libreboot.
- Factory ROM backup is on creme at `~/libreboot/factory_a.rom` + `factory_b.rom` (sha256 `7ca3ab6ba132fde118a68c17c1d387c5fb0e81875dc185a94486d3bbcd73f57a`). Recommend keeping at least one copy in a safe place off-creme (e.g. backed up via restic) so it survives a disk failure — the rest of `~/libreboot/` can be deleted to reclaim space.
- A new module `hosts/creme/disk-encryption.nix` is in-tree but **disabled** (`mkEnableOption` default false). Wired up for the future SSD upgrade. Header comment in the file documents the `cryptsetup luksFormat --cipher xchacha12,aes-adiantum-plain64 ...` invocation that the user should run on the new SSD when they migrate.

## Open follow-ups, in priority order

### 1. Battery investigation (high-priority — user-reported pain)

User reports: "creme looked like it was sleeping properly in my bag but was dead when i took it to the park". User's own suspicion: probably `s2idle` instead of S3 deep sleep.

Verify and fix:

```
ssh kimb@creme.nebula 'cat /sys/power/mem_sleep'
```

Expected (current default on many kernels): `[s2idle] deep` — brackets show active mode is s2idle, which keeps CPU in C-states but doesn't power down RAM. On a Core 2 Duo, this drains the battery in hours.

Fix: set `boot.kernelParams = [ "mem_sleep_default=deep" ];` in creme's config (or in `hosts/profiles/laptop.nix` so marshmallow benefits too — though marshmallow already shows `s2idle [deep]` meaning deep is its active mode, so it might be fine. Check both.)

Other suspects to rule out if the kernel param doesn't help:
- Lid switch wake-on-lid-open misconfigured → laptop wakes up in the bag, drains
- USB peripherals causing wakeups (check `cat /proc/acpi/wakeup`)
- WiFi card BIOS-side wake (no longer possible post-libreboot, but worth checking — libreboot's SeaBIOS doesn't do WoL)
- Bluetooth radio left on (BAT0 shows ~89% design capacity, batteries 16+ years old don't help)

Also worth running `journalctl -b -1 -u systemd-suspend` after a sleep cycle to see what actually happened.

### 2. i3 dusty magenta background

Set the i3 background. (The stale "console-only" comment in `nebula-registry.nix` is already fixed in this session.) Options:
- If the user wants this Nix-managed: add a wallpaper file under `hosts/creme/` and have i3 `exec --no-startup-id feh --bg-solid '#7e4a6e'` or similar in `i3/config`. Or use `xsetroot -solid '#7e4a6e'`.
- "Dusty magenta" is roughly `#a05c7b` or `#7e4a6e` (more saturated vs muted). Ask the user which they prefer.

The home-manager i3 config is likely at `home/creme.nix` or `home/<user>.nix`. Find and edit there, not in `/etc/i3/config`.

### 3. Clean login (no X scrollback on boot)

User asked about `plymouth` and a display manager. Quick framing:

- **Plymouth**: hides kernel boot messages and shows a splash. NixOS option: `boot.plymouth.enable = true;`. Works fine with libreboot+SeaBIOS+GRUB chainload. Will hide all the systemd-boot output.
- **Display manager**: would launch a graphical login screen instead of TTY autologin → startx. Options: `lightdm`, `sddm`, `greetd` (lightweight, can run greeters in TTY). For a writerdeck with i3, `greetd` + `tuigreet` is the minimal-footprint choice; `lightdm` is the most polished GUI.

The combination user wants is likely: plymouth for boot, greetd+tuigreet (or lightdm) for login, i3 starts the session. Confirm with user before implementing — they may want plymouth-only and keep TTY autologin.

### 3.5. Wire brightness Fn keys to `brightnessctl`

User-reported: Fn+F8/F9 brightness keys no longer change brightness post-libreboot. This is a known libreboot+Dell quirk — Dell's EC SCI handler that translated Fn-key combos into ACPI brightness events isn't part of libreboot, so the kernel doesn't see brightness keypress events from the EC.

Fix in i3 config (in home/creme.nix or wherever i3 keybinds live):

```
bindsym XF86MonBrightnessUp exec brightnessctl set +10%
bindsym XF86MonBrightnessDown exec brightnessctl set 10%-
```

Wait — those `XF86MonBrightness*` symbols are exactly what's NOT being generated. Better path: see what keysym Fn+F8/F9 actually produce post-libreboot via `xev` (might be raw F8/F9, or nothing at all). If they produce no keysym at all, brightness keys are dead from i3's perspective — workaround is to bind brightnessctl to a different combo (Mod+Shift+F8 etc) or use `acpid` to react to the underlying ACPI events if any are still firing.

`brightnessctl` is in `pkgs.brightnessctl`; the sysfs backlight control path (`/sys/class/backlight/intel_backlight/brightness`) still works fine, only the keyboard input chain is broken.

### 4. Build the libreboot-install flake (the actual scoped project)

User wants this packaged as a reusable NixOS module + flake app post-success. See subagent reports referenced below for the full design. Headline:

- **Prior art**: nobody has built this in the Nix ecosystem. Closest is Snowboot (codeberg.org/hustlerone/Snowboot, builds coreboot, not installer). Even `dell-flash-unlock` and `nvmutil` aren't packaged in nixpkgs — that's the first PR.
- **Effort**: ~3 person-days for E6400-only MVP; ~5–7 days for full Dell Latitude family.
- **Module shape**: one module `kimb.libreboot.<machine>` with `machine` as enum, MAC as `"random" | "<hex>"`, optional `factoryDumpPath` for Sandy/Ivy/Haswell machines that need vendor blob extraction. Per-machine modules are overkill since variation is data, not logic.
- **Non-NixOS systemd-link mode**: v2, not MVP. Firmware install is already distro-agnostic (`nix run`), MAC persistence across distros (`systemd.link` vs `NetworkManager` vs `interfaces`) is a separate project.

### 5. Address `mk inject` complications encountered

Documenting what didn't go smoothly so the next agent doesn't redo my detour:

- `./mk inject <tarball> setmac <mac>` is the canonical command. It needs lots of build deps: python3, cmake, autoconf, automake, libtool, m4, bzip2, zstd, nettle, plus gcc/make/pkg-config. Building libarchive/uefitool/bios_extract on a 800MHz-throttled Core 2 is too slow to be practical.
- I bailed to a manual equivalent: `cp $LBMK/config/ifd/ich9m/gbe gbe_modified && nvm gbe_modified setmac <mac> && ifdtool -i GbE:gbe_modified <rom> -O <rom>`, then trimmed the trailing null byte (libreboot's release ROMs are 4194305 bytes for some reason; flash chip needs exactly 4194304). This worked.
- For the flake: probably package `lbmk` + its build deps as a single derivation so the user doesn't have to figure out the dep tree. Or skip `mk inject` entirely in the flake and use the manual ifdtool path — way cleaner and faster.

## Subagent reports referenced

Three subagents I dispatched while preparing the flash. Their findings live in `/tmp/claude-1000/-home-kimb-shared-projects-systems-flake/52670205-4064-4087-bc85-c2722f319486/tasks/`:

- `a29dd0dcbfdd2c62c.output` — inventory of libreboot-supported machines, install-method buckets
- `a28dd4c91137dba0e.output` — scoping memo for multi-machine flake, effort estimates
- `a05c27ef7c4e94337.output` — prior-art search (verdict: greenfield)

These are full JSONL transcripts. If the next agent needs them, the key conclusions are summarized above.

## What I'm NOT touching (deliberately)

- The disk-encryption module stays disabled. Will turn on at SSD upgrade time per its header comment.
- `iomem=relaxed` stays in config until the user explicitly says to drop it (they OK'd "whenever" but wanted me to wait for confirmation post-libreboot).
- No tweaks to creme's emacs/doom config — outside this thread's scope.
