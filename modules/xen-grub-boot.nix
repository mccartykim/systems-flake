# Boot Xen via GRUB-multiboot2 chainloaded from systemd-boot.
#
# Why this exists (bd systems-flake-a3j.2):
#   historian's GmkTec EVO-X1 firmware (BIOS 1.04, the latest published for
#   the base model) kills xen.efi instantly at the firmware->xen.efi handoff
#   (pre-kernel black screen; identical artifacts boot fine under OVMF).
#   The ONLY viable alternative UEFI boot path for Xen today is GRUB's
#   multiboot2 loader: Xen's multiboot2 kernel requests the
#   "do-not-ExitBootServices" EFI tag, which only GRUB implements
#   (Limine can't: limine-bootloader#490). GRUB 2.14 (current nixpkgs) has
#   two relocator regressions that make multiboot2 Xen boot page-fault;
#   the vendored patch in pkgs/patches/grub-2.14-xen-multiboot2-relocator.patch
#   is Jiaqing Zhao's (AMD) grub-devel series "fix multiboot2 Xen boot
#   failure on GRUB 2.14" (2026-05), rebased to match shipped sources.
#   Drop the patch once nixpkgs' grub ships the fix.
#
# What this module does, per generation (mirrors nixpkgs' xenBootBuilder):
#   * writes /boot/EFI/nixos/xengrub-<hash>/{grubx64.efi,xen.gz,grub.cfg}
#   * writes /boot/loader/entries/xengrub-<hash>.conf pointing sd-boot at it
#   * DELETES the upstream xen-*.conf/xen-*.efi UKI entries (black-screen
#     bait on this firmware; nothing should ever pick them)
#   * fixes loader.conf: upstream flips `default nixos-` -> `default xen-`;
#     we rewrite that to `xengrub-` (if setXenDefault) or back to the
#     newest `nixos-` entry.
# systemd-boot stays primary; no GRUB menu is ever shown (timeout 0).

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.boot.xenGrubBoot;
  xenCfg = config.virtualisation.xen;

  grubXen = pkgs.grub2_efi.overrideAttrs (old: {
    pname = "grub2-efi-xen-mb2";
    patches = (old.patches or [ ]) ++ [
      ../pkgs/patches/grub-2.14-xen-multiboot2-relocator.patch
    ];
  });

  grubModules = toString [
    "multiboot2"
    "multiboot"
    "linux"
    "relocator"
    "mmap"
    "normal"
    "configfile"
    "efi_gop"
    "efi_uga"
    "video"
    "video_bochs"
    "video_cirrus"
    "gfxterm"
    "font"
    "terminal"
    "ext2"
    "fat"
    "iso9660"
    "part_gpt"
    "part_msdos"
    "gzio"
    "xzio"
    "lzopio"
    "zstd"
    "chain"
    "boot"
    "help"
    "search"
    "search_fs_file"
    "search_fs_uuid"
    "search_label"
    "echo"
    "ls"
    "test"
  ];

  builder = pkgs.writeShellApplication {
    name = "xenGrubBootBuilder";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
      jq
      grubXen
    ];
    runtimeEnv = {
      efiMountPoint = config.boot.loader.efi.efiSysMountPoint;
      setXenDefault = if cfg.setXenDefault then "1" else "0";
      inherit grubModules;
    };
    excludeShellChecks = [ "SC2016" ];
    text = builtins.readFile ./xen-grub-boot-builder.sh;
  };
in
{
  options.boot.xenGrubBoot = {
    enable = lib.mkEnableOption ''
      GRUB-multiboot2 chainload boot entries for Xen, for UEFI firmwares
      that cannot launch xen.efi (e.g. GmkTec EVO-X1). Requires
      virtualisation.xen.enable and systemd-boot.
    '';
    setXenDefault = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Make the Xen-via-GRUB entry the systemd-boot default. Leave false
        while validating; flip true once a Xen boot has been confirmed at
        the desk, so unattended reboots land on the hypervisor.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = xenCfg.enable;
        message = "boot.xenGrubBoot requires virtualisation.xen.enable = true.";
      }
      {
        assertion = config.boot.loader.systemd-boot.enable;
        message = "boot.xenGrubBoot requires systemd-boot (chainload entries are written into its menu).";
      }
    ];

    boot.loader.systemd-boot.extraInstallCommands =
      lib.mkAfter (lib.getExe builder);
  };
}
