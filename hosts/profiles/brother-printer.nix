# Brother HL-L2400D printer profile — shared hardware.printers entry.
# All three hosts (marshmallow, bartleby, cheesecake) point at the same IPP
# Everywhere queue on maitred. printing.enable + avahi come from desktop.nix.
# Local CUPS driver packages (brlaser/brgenml1) are NOT set here: bartleby
# relies on server-side rendering, so hosts that want local drivers set
# services.printing.drivers themselves.
{...}: {
  hardware.printers = {
    ensurePrinters = [
      {
        name = "Brother-HL-L2400D";
        description = "Brother HL-L2400D Laser Printer";
        location = "Living Room";
        deviceUri = "ipp://maitred.nebula:631/printers/Brother-HL-L2400D";
        model = "everywhere";
      }
    ];
    ensureDefaultPrinter = "Brother-HL-L2400D";
  };
}