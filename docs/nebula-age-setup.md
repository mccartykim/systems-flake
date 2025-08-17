# Nebula + Age Secrets Setup Guide

## Overview
This guide explains how to set up automatic Nebula mesh network deployment using age encryption for secure certificate management across all your NixOS machines.

## How It Works

### 1. Certificate Storage
- Raw certificates are stored in `../flake_keys/nebula/` (outside the repo)
- Encrypted versions are stored in `secrets/` (safe to commit to git)
- Each machine only gets access to its own certificates + the CA

### 2. Age Encryption Flow
```
Raw Certs → Age Encryption → Git Repo → Age Decryption → Nebula Service
```

## Initial Setup

### Step 1: Generate Age Keys
Each machine needs its own age key. You have two options:

**Option A: Use SSH host keys (recommended)**
```bash
# On each machine, convert SSH host key to age
sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /etc/age-key.txt
sudo chmod 600 /etc/age-key.txt

# Get the public key
sudo ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
```

**Option B: Generate dedicated age keys**
```bash
# Run on each machine
age-keygen -o ~/.config/age/keys.txt
```

### Step 2: Collect Public Keys
Create a file with all your machines' age public keys:

```nix
# secrets/age-keys.nix
{
  historian = "age1xxxxxxxxx...";    # from ssh-to-age or age-keygen
  marshmallow = "age1yyyyyyyyy...";
  bartleby = "age1zzzzzzzzz...";
}
```

### Step 3: Encrypt Certificates
```bash
# Run the setup script
./scripts/setup-nebula-age.sh

# Or manually encrypt for specific recipients
age -r age1xxx -r age1yyy -o secrets/ca.crt.age ../flake_keys/nebula/ca.crt
```

## Machine Configuration

### Step 1: Add agenix to your flake
```nix
# flake.nix
{
  inputs = {
    agenix.url = "github:ryantm/agenix";
    # ... other inputs
  };
}
```

### Step 2: Update machine configs
```nix
# hosts/historian/configuration.nix
{
  imports = [
    ../../modules/nebula-with-age.nix
    inputs.agenix.nixosModules.default
  ];

  # Tell agenix where the age key is
  age.identityPaths = [ "/etc/age-key.txt" ];
  
  # Enable Nebula with age secrets
  services.nebula-mesh = {
    enable = true;
    ageSecretsFile = true;  # Enable age integration
  };
}
```

## Key Management Best Practices

### 1. Age Key Storage Options
- **SSH-based**: Keys derived from `/etc/ssh/ssh_host_ed25519_key`
  - Pro: Already exists, tied to machine identity
  - Con: Requires root access to decrypt
  
- **User keys**: Stored in home directory
  - Pro: User-level access
  - Con: Need to manage separately from SSH

### 2. Multi-recipient Encryption
For shared secrets (like ca.crt), encrypt for all machines:
```bash
age -r age1xxx -r age1yyy -r age1zzz -o ca.crt.age ca.crt
```

### 3. Key Rotation
When adding a new machine:
1. Generate its Nebula certificates
2. Get its age public key
3. Re-encrypt all shared secrets to include the new recipient
4. Commit the updated encrypted files

## Deployment Process

### New Machine Setup
1. Install NixOS with age key configured
2. Add machine to `secrets/nebula-secrets.nix`
3. Generate Nebula certificates
4. Encrypt certificates with machine's age key
5. Commit encrypted certificates
6. Deploy configuration: `nixos-rebuild switch`

### Existing Machine Update
1. Update configuration in git
2. Run `nixos-rebuild switch`
3. Nebula automatically restarts with new config

## Troubleshooting

### "Permission denied" errors
- Check age key permissions: should be 600
- Verify nebula service user can read decrypted secrets
- Check systemd service dependencies

### "Cannot decrypt" errors  
- Verify the secret was encrypted for this machine's key
- Check age.identityPaths points to correct key file
- Try manual decryption: `age -d -i /etc/age-key.txt secret.age`

### Service not starting
```bash
# Check age decryption
sudo systemctl status agenix

# Check nebula logs
sudo journalctl -u nebula@mesh -f

# Verify certificates were decrypted
sudo ls -la /etc/nebula/
```

## Security Notes

1. **Never commit**:
   - Raw certificates
   - Age private keys
   - Decrypted secrets

2. **Safe to commit**:
   - Encrypted .age files
   - Age public keys
   - This documentation

3. **Backup**:
   - Keep secure backups of age keys
   - Store CA key separately (for adding new nodes)
   - Consider key escrow for recovery