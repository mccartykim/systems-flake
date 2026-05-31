{
  config,
  lib,
  ...
}: let
  cfg = config.kimb.creme.diskEncryption;
in {
  # Optional LUKS root + hibernation-capable encrypted swap.
  # Intended for the planned SSD upgrade. Disabled until then.
  #
  # Pre-format steps (do once, from install media):
  #   # E6400 has no AES-NI — Adiantum is ~2-3× faster than AES-XTS here.
  #   cryptsetup luksFormat --cipher xchacha12,aes-adiantum-plain64 \
  #     --key-size 256 /dev/sdXN   # root partition
  #   cryptsetup luksFormat --cipher xchacha12,aes-adiantum-plain64 \
  #     --key-size 256 /dev/sdXM   # swap partition
  # On modern hardware: omit --cipher (AES-XTS default).
  # Then fill in the UUIDs below and set enable = true.

  options.kimb.creme.diskEncryption = {
    enable = lib.mkEnableOption "LUKS root + encrypted swap (hibernate-capable)";

    rootDevice = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
      description = "Encrypted root partition (prefer /dev/disk/by-uuid/...).";
    };

    swapDevice = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-uuid/11111111-1111-1111-1111-111111111111";
      description = "Encrypted swap partition (prefer /dev/disk/by-uuid/...).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.luks.devices = {
      cryptroot = {
        device = cfg.rootDevice;
        allowDiscards = true;
      };
      cryptswap = {
        device = cfg.swapDevice;
        allowDiscards = true;
      };
    };

    # Persistent (not random) encryption on swap so hibernate-to-disk works.
    swapDevices = [{device = "/dev/mapper/cryptswap";}];
    boot.resumeDevice = "/dev/mapper/cryptswap";
  };
}
