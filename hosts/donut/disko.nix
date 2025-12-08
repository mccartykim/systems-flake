# Disko configuration for Steam Deck (donut)
# Simple layout: EFI boot + ext4 root
#
# Usage from installer:
#   nix run github:nix-community/disko -- --mode disko /etc/systems-flake/hosts/donut/disko.nix
#   nixos-install --flake /etc/systems-flake#donut --no-root-password
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Steam Deck internal NVMe
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["fmask=0022" "dmask=0022"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
