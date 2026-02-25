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

  # Probe USB printer every 15 minutes to prevent auto power-off
  systemd.services.printer-keepalive = {
    description = "Probe USB printer to prevent auto power-off";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/env lpinfo -v";
    };
    path = [config.services.printing.package];
  };

  systemd.timers.printer-keepalive = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
    };
  };
}
