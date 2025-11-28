# ESPHome Camera Configurations

Declarative firmware configurations for ESP32-CAM devices, managed with Nix.

## Setup

1. **Create secrets file:**
   ```bash
   cp secrets.yaml.example secrets.yaml
   # Edit secrets.yaml with your WiFi credentials and passwords
   ```

2. **Generate API encryption key:**
   ```bash
   nix run nixpkgs#esphome -- \
     esphome-configs/esp32-cam-01.yaml config
   ```
   Copy the generated encryption key to `secrets.yaml`

## Building Firmware

Build firmware using Nix (includes toolchain):

```bash
# Build firmware for esp32-cam-01
nix build .#esp32-cam-01-firmware

# Firmware binary will be in: result/esp32-cam-01/.pioenvs/esp32-cam-01/firmware.bin
```

## Flashing

### Initial Flash (USB)

Connect ESP32-CAM via USB (using FTDI adapter or USB programmer):

```bash
# Build and flash in one command
nix run .#flash-esp32-cam-01
```

Or manually with esptool:

```bash
# Find USB device
ls /dev/ttyUSB*

# Flash firmware
nix run nixpkgs#esptool -- \
  --port /dev/ttyUSB0 \
  write_flash 0x10000 result/esp32-cam-01/.pioenvs/esp32-cam-01/firmware.bin
```

### OTA Updates (Over WiFi)

After initial flash, update over WiFi:

```bash
nix run nixpkgs#esphome -- \
  run esphome-configs/esp32-cam-01.yaml --device esp32-cam-01.local
```

## Integration with go2rtc

After flashing, add to rich-evans go2rtc configuration:

```nix
services.go2rtc.settings.streams = {
  camera1 = ["ffmpeg:/dev/video0#video=h264"];
  camera2 = ["ffmpeg:/dev/video1#video=h264"];
  esp32cam1 = ["http://esp32-cam-01.local"];  # ESPHome stream
};
```

## Accessing Camera

- **Direct stream:** http://esp32-cam-01.local
- **Via rich-evans:** http://10.100.0.40:8554 (webcam server)
- **Home Assistant:** Auto-discovered via mDNS

## Hardware Notes

**ESP32-CAM Pinout:**
- GPIO0: External clock
- GPIO26/27: I2C (SDA/SCL)
- GPIO4: Built-in LED/Flash
- GPIO32: Power down pin

**Common Issues:**
- Camera won't boot: Check power supply (needs 5V 2A minimum)
- No video: Ensure camera ribbon cable is properly seated
- WiFi weak: ESP32-CAM has poor antenna, keep close to AP initially
