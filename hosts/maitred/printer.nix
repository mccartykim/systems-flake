# Printer configuration for maitred
{
  config,
  lib,
  pkgs,
  ...
}: {
  hardware.printers = {
    ensurePrinters = [
      {
        name = "Brother-HL-L2400D";
        description = "Brother HL-L2400D Laser Printer";
        location = "Living Room";
        deviceUri = "usb://Brother/HL-L2400D?serial=U67272B4N433863";
        model = "drv:///brlaser.drv/brl2400d.ppd";
        ppdOptions = {
          PageSize = "Letter";
        };
      }
    ];
    ensureDefaultPrinter = "Brother-HL-L2400D";
  };
}
