# Arbus - Raspberry Pi Webcam Server

Raspberry Pi Gen 1 (ARMv6) running dual USB webcam streaming via go2rtc.

## Deployment Guide

### 1. Pre-generate SSH Host Key

Before building the SD card image, generate an SSH host key that will be used:
- As the machine's SSH identity
- As an agenix recipient for encrypted Nebula certificates

```bash
# Generate the SSH host key pair
ssh-keygen -t ed25519 -f ssh_host_ed25519_key -N "" -C "root@arbus"

# Display the public key to add to nebula-registry.nix
cat ssh_host_ed25519_key.pub
```

### 2. Update Registry with Public Key

Update `hosts/nebula-registry.nix` with the public key:

```nix
arbus = {
  ip = networkIPs.nebula.hosts.arbus;
  isLighthouse = false;
  role = "camera";
  groups = ["cameras" "nixos"];
  publicKey = "ssh-ed25519 AAAA..."; # Add the public key here
};
```

### 3. Encrypt Nebula Certificates

Use the SSH public key as an agenix recipient to encrypt the Nebula certificates:

```bash
# Add the SSH public key to secrets/secrets.nix
# Then encrypt the certificates:
cat nebula-arbus.crt | agenix -e secrets/nebula-arbus-cert.age -i ssh_host_ed25519_key
cat nebula-arbus.key | agenix -e secrets/nebula-arbus-key.age -i ssh_host_ed25519_key
```

### 4. Build SD Card Image

Build the SD card image (on x86_64 or aarch64 host):

```bash
nix build .#arbus-sd-image
```

The image will be in `result/sd-image/nixos-sd-image-*.img`

### 5. Flash SD Card

```bash
# Identify your SD card device (e.g., /dev/sdX)
lsblk

# Flash the image (be careful with the device name!)
sudo dd if=result/sd-image/nixos-sd-image-*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### 6. Add SSH Key to Boot Partition

Mount the FAT32 boot partition and copy the SSH host key:

```bash
# Mount the boot partition (usually /dev/sdX1)
sudo mount /dev/sdX1 /mnt

# Copy the pre-generated SSH keys
sudo cp ssh_host_ed25519_key /mnt/
sudo cp ssh_host_ed25519_key.pub /mnt/

# Unmount
sudo umount /mnt
```

The systemd service `bootstrap-ssh-key.service` will automatically:
- Copy the keys from `/boot` to `/etc/ssh` on first boot
- Set correct permissions (600 for private, 644 for public)
- Run before sshd and agenix services

### 7. Boot the Raspberry Pi

Insert the SD card and power on the Pi. On first boot:
1. The SSH key is copied from `/boot` to `/etc/ssh`
2. Agenix decrypts the Nebula certificates using the SSH key
3. Nebula connects to the mesh network
4. go2rtc starts streaming the webcams

## Accessing Camera Streams

Once the Pi is connected to the Nebula mesh (IP: `10.100.0.20`):

- **Web UI**: http://10.100.0.20:1984
- **Camera 1 RTSP**: rtsp://10.100.0.20:8554/camera1
- **Camera 2 RTSP**: rtsp://10.100.0.20:8554/camera2
- **WebRTC**: http://10.100.0.20:8555

Access is restricted to hosts in the `desktops` and `laptops` Nebula groups.

## Hardware Requirements

- Raspberry Pi 1 Model B/B+ (ARMv6)
- microSD card (8GB minimum)
- Two USB webcams (V4L2 compatible)
- Power supply (5V 2A recommended with USB peripherals)

## Troubleshooting

### Check SSH key bootstrap
```bash
ssh kimb@10.100.0.20
systemctl status bootstrap-ssh-key
journalctl -u bootstrap-ssh-key
```

### Check Nebula connection
```bash
systemctl status nebula@mesh
journalctl -u nebula@mesh
```

### Check camera detection
```bash
v4l2-ctl --list-devices
ls -la /dev/video*
```

### Check go2rtc service
```bash
systemctl status go2rtc
journalctl -u go2rtc
```

## Security Notes

- SSH key on FAT32 partition is visible to anyone with physical access
- After first successful boot, you can optionally remove the keys from `/boot`
- Camera streams are only accessible via Nebula mesh (not exposed to LAN)
- Firewall rules restrict camera ports to desktops and laptops groups only
