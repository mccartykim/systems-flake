# Shared peripheral remappings — accessories used across multiple hosts.
# Import from any host that may have these devices plugged in; the keyd
# matchers (by USB ID) make it a no-op if the device isn't present.
{pkgs, ...}: {
  services.keyd = {
    enable = true;
    keyboards = {
      # Topre RealForce JIS Compact — remap Asian character keys to
      # Western-friendly modifiers. Discover IDs with `keyd -m` or
      # `lsusb | grep -i topre`.
      realforce = {
        ids = ["0853:0200"];
        settings = {
          main = {
            muhenkan = "backspace"; # left of space
            henkan = "esc"; # right of space — pairs with bksp
          };
        };
      };
    };
  };
}
