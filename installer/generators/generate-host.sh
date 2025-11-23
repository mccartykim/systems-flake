#!/usr/bin/env bash
# Host configuration generator for NixOS flake installer
# Generates all necessary files for adding a new host to the flake

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
FLAKE_ROOT="${FLAKE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source library functions
source "$LIB_DIR/hardware-detect.sh"
source "$LIB_DIR/disk-utils.sh"
source "$LIB_DIR/profile-detect.sh"

# Default values
HOSTNAME=""
DISK_DEVICE=""
PARTITION_SCHEME="standard"
BOOT_MODE=""
PROFILES="base"
USERNAME="kimb"
SYSTEM="x86_64-linux"
OUTPUT_DIR=""
DRY_RUN=false
SWAP_SIZE=""

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generate NixOS host configuration files for a new machine.

Options:
  -h, --hostname NAME     Hostname for the new machine (required)
  -d, --disk DEVICE       Target disk device (e.g., /dev/sda)
  -s, --scheme SCHEME     Partition scheme: simple, standard, luks (default: standard)
  -p, --profiles LIST     Comma-separated list of profiles (default: base)
  -u, --username NAME     Primary username (default: kimb)
  -o, --output DIR        Output directory (default: \$FLAKE_ROOT/generated/<hostname>)
  -n, --dry-run           Show what would be generated without writing files
  --swap SIZE             Swap size (e.g., 8G, 16G) - auto-calculated if not specified
  --help                  Show this help message

Examples:
  $0 --hostname myserver --disk /dev/sda --scheme standard --profiles base,server
  $0 --hostname mylaptop --disk /dev/nvme0n1 --profiles base,laptop,desktop

EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            -d|--disk)
                DISK_DEVICE="$2"
                shift 2
                ;;
            -s|--scheme)
                PARTITION_SCHEME="$2"
                shift 2
                ;;
            -p|--profiles)
                PROFILES="$2"
                shift 2
                ;;
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --swap)
                SWAP_SIZE="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    if [[ -z "$HOSTNAME" ]]; then
        echo "Error: hostname is required" >&2
        exit 1
    fi

    local validation_error
    if ! validation_error=$(validate_hostname "$HOSTNAME" 2>&1); then
        echo "Error: $validation_error" >&2
        exit 1
    fi

    if [[ -n "$DISK_DEVICE" ]] && [[ ! -b "$DISK_DEVICE" ]]; then
        echo "Error: $DISK_DEVICE is not a valid block device" >&2
        exit 1
    fi

    # Validate profiles exist
    IFS=',' read -ra profile_array <<< "$PROFILES"
    for profile in "${profile_array[@]}"; do
        if ! profile_exists "$profile"; then
            echo "Warning: profile '$profile' does not exist in $FLAKE_ROOT/hosts/profiles/" >&2
        fi
    done
}

# Detect boot mode if not set
detect_boot() {
    if [[ -z "$BOOT_MODE" ]]; then
        eval "$(detect_boot_mode)"
    fi
}

# Calculate swap size if not set
calculate_swap() {
    if [[ -z "$SWAP_SIZE" ]]; then
        local ram_gb
        ram_gb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024/1024)}' || echo 8)

        if [[ $ram_gb -le 4 ]]; then
            SWAP_SIZE="$((ram_gb * 2))G"
        elif [[ $ram_gb -le 16 ]]; then
            SWAP_SIZE="${ram_gb}G"
        else
            SWAP_SIZE="16G"
        fi
    fi
}

# Generate disko.nix
generate_disko() {
    local template_file

    case "$BOOT_MODE-$PARTITION_SCHEME" in
        uefi-simple)
            template_file="$TEMPLATE_DIR/disko-uefi-simple.nix"
            ;;
        uefi-standard)
            template_file="$TEMPLATE_DIR/disko-uefi-standard.nix"
            ;;
        uefi-luks)
            template_file="$TEMPLATE_DIR/disko-uefi-luks.nix"
            ;;
        bios-simple)
            template_file="$TEMPLATE_DIR/disko-bios-simple.nix"
            ;;
        bios-standard)
            template_file="$TEMPLATE_DIR/disko-bios-standard.nix"
            ;;
        *)
            echo "Error: Unknown partition scheme: $BOOT_MODE-$PARTITION_SCHEME" >&2
            exit 1
            ;;
    esac

    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template not found: $template_file" >&2
        exit 1
    fi

    sed -e "s|{{DISK_DEVICE}}|${DISK_DEVICE:-/dev/sda}|g" \
        -e "s|{{SWAP_SIZE}}|${SWAP_SIZE}|g" \
        "$template_file"
}

# Generate profile imports
generate_profile_imports() {
    local imports=""
    IFS=',' read -ra profile_array <<< "$PROFILES"

    for profile in "${profile_array[@]}"; do
        imports="${imports}    ../profiles/${profile}.nix\n"
    done

    echo -e "$imports"
}

# Generate extra config based on hardware detection
generate_extra_config() {
    local config=""

    eval "$(detect_all 2>/dev/null || true)"

    # Add NVIDIA config if needed
    if [[ "${NEEDS_NVIDIA:-false}" == "true" ]]; then
        config="${config}
  # NVIDIA GPU support
  services.xserver.videoDrivers = [\"nvidia\"];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
  };
"
    fi

    # Add AMD GPU config if needed
    if [[ "${NEEDS_AMDGPU:-false}" == "true" ]]; then
        config="${config}
  # AMD GPU support
  services.xserver.videoDrivers = [\"amdgpu\"];
"
    fi

    echo "$config"
}

# Generate configuration.nix
generate_configuration() {
    local template_file="$TEMPLATE_DIR/configuration.nix.tmpl"
    local state_version
    state_version=$(nixos-version 2>/dev/null | cut -d. -f1,2 || echo "24.11")
    local date
    date=$(date +%Y-%m-%d)
    local profile_imports
    profile_imports=$(generate_profile_imports)
    local extra_config
    extra_config=$(generate_extra_config)

    sed -e "s|{{HOSTNAME}}|${HOSTNAME}|g" \
        -e "s|{{DATE}}|${date}|g" \
        -e "s|{{STATE_VERSION}}|${state_version}|g" \
        -e "s|{{PROFILE_IMPORTS}}|${profile_imports}|g" \
        -e "s|{{EXTRA_CONFIG}}|${extra_config}|g" \
        "$template_file"
}

# Generate hardware-configuration.nix
generate_hardware_config() {
    if [[ -d /mnt/etc/nixos ]]; then
        # Use existing generated config if available
        if [[ -f /mnt/etc/nixos/hardware-configuration.nix ]]; then
            cat /mnt/etc/nixos/hardware-configuration.nix
            return
        fi
    fi

    # Generate fresh config
    # Note: This requires running on actual hardware or with --root /mnt
    if command -v nixos-generate-config &>/dev/null; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        nixos-generate-config --root / --dir "$tmp_dir" 2>/dev/null || true
        if [[ -f "$tmp_dir/hardware-configuration.nix" ]]; then
            cat "$tmp_dir/hardware-configuration.nix"
            rm -rf "$tmp_dir"
            return
        fi
        rm -rf "$tmp_dir"
    fi

    # Fallback: generate minimal hardware config
    cat <<'EOF'
# Hardware configuration - PLACEHOLDER
# Run nixos-generate-config on the target machine to generate this file
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # TODO: Add detected hardware modules
  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "sd_mod"];
  boot.kernelModules = ["kvm-intel"];  # or kvm-amd

  # Filesystem configuration will be handled by disko
  # fileSystems."/" = { ... };
  # fileSystems."/boot" = { ... };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
EOF
}

# Determine role from profiles
get_role_from_profiles() {
    if [[ "$PROFILES" == *"server"* ]]; then
        echo "server"
    elif [[ "$PROFILES" == *"desktop"* ]] || [[ "$PROFILES" == *"laptop"* ]]; then
        echo "desktop"
    else
        echo "desktop"  # default
    fi
}

# Generate flake.nix entry
generate_flake_entry() {
    local template_file="$TEMPLATE_DIR/flake-entry.nix.tmpl"
    local role
    role=$(get_role_from_profiles)

    # Get srvos modules
    local srvos_modules=""
    while IFS= read -r module; do
        srvos_modules="${srvos_modules}              ${module}\n"
    done < <(get_srvos_modules "$role")

    # Get hardware module if suggested
    eval "$(detect_system_info 2>/dev/null || true)"
    local hw_module=""
    if [[ -n "${SUGGESTED_HW_MODULE:-}" ]]; then
        hw_module="              nixos-hardware.nixosModules.${SUGGESTED_HW_MODULE}\n"
    fi

    sed -e "s|{{HOSTNAME}}|${HOSTNAME}|g" \
        -e "s|{{SYSTEM}}|${SYSTEM}|g" \
        -e "s|{{USERNAME}}|${USERNAME}|g" \
        -e "s|{{SRVOS_MODULES}}|${srvos_modules}|g" \
        -e "s|{{HARDWARE_MODULE}}|${hw_module}|g" \
        "$template_file"
}

# Generate home-manager config placeholder
generate_home_config() {
    cat <<EOF
# Home configuration for $HOSTNAME
# Generated by flake-installer
{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./modules/shell-essentials.nix
    ./modules/development.nix
  ];

  home.username = "$USERNAME";
  home.homeDirectory = "/home/$USERNAME";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;
}
EOF
}

# Generate git patch
generate_patch() {
    local output_dir="$1"

    cat <<EOF
--- a/flake.nix
+++ b/flake.nix
@@ -XXX,X +XXX,XX @@ in {
+
$(generate_flake_entry | sed 's/^/+/')

--- /dev/null
+++ b/hosts/$HOSTNAME/configuration.nix
@@ -0,0 +1,XXX @@
$(generate_configuration | sed 's/^/+/')

--- /dev/null
+++ b/hosts/$HOSTNAME/disko.nix
@@ -0,0 +1,XXX @@
$(generate_disko | sed 's/^/+/')

--- /dev/null
+++ b/hosts/$HOSTNAME/hardware-configuration.nix
@@ -0,0 +1,XXX @@
$(generate_hardware_config | sed 's/^/+/')
EOF
}

# Generate install log
generate_install_log() {
    cat <<EOF
# Installation Log for $HOSTNAME

Generated: $(date)
Generator: flake-installer

## Configuration

- **Hostname**: $HOSTNAME
- **Disk**: ${DISK_DEVICE:-not specified}
- **Boot Mode**: $BOOT_MODE
- **Partition Scheme**: $PARTITION_SCHEME
- **Swap Size**: $SWAP_SIZE
- **Profiles**: $PROFILES
- **Username**: $USERNAME
- **System**: $SYSTEM

## Hardware Detection

$(detect_all 2>/dev/null | sed 's/^/- /' || echo "- Hardware detection not available")

## Files Generated

- hosts/$HOSTNAME/configuration.nix
- hosts/$HOSTNAME/disko.nix
- hosts/$HOSTNAME/hardware-configuration.nix
- home/$HOSTNAME.nix (placeholder)

## Next Steps

1. Review generated files in \`$OUTPUT_DIR/\`
2. Copy files to your flake:
   \`\`\`bash
   cp -r $OUTPUT_DIR/hosts/$HOSTNAME $FLAKE_ROOT/hosts/
   cp $OUTPUT_DIR/home/$HOSTNAME.nix $FLAKE_ROOT/home/
   \`\`\`
3. Add the flake.nix entry (see \`$OUTPUT_DIR/flake-entry.nix\`)
4. Run \`nixos-rebuild build --flake .#$HOSTNAME\` to test
5. Deploy with \`nixos-install --flake .#$HOSTNAME\` or colmena

## To apply the patch instead:

\`\`\`bash
cd $FLAKE_ROOT
git apply $OUTPUT_DIR/$HOSTNAME.patch
\`\`\`
EOF
}

# Main function
main() {
    parse_args "$@"
    validate_inputs
    detect_boot
    calculate_swap

    # Set output directory
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$FLAKE_ROOT/generated/$HOSTNAME"
    fi

    echo "Generating configuration for '$HOSTNAME'..."
    echo "  Boot mode: $BOOT_MODE"
    echo "  Partition scheme: $PARTITION_SCHEME"
    echo "  Profiles: $PROFILES"
    echo "  Output: $OUTPUT_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "=== DRY RUN - Would generate: ==="
        echo ""
        echo "--- hosts/$HOSTNAME/disko.nix ---"
        generate_disko
        echo ""
        echo "--- hosts/$HOSTNAME/configuration.nix ---"
        generate_configuration
        echo ""
        echo "--- flake.nix entry ---"
        generate_flake_entry
        return
    fi

    # Create output directories
    mkdir -p "$OUTPUT_DIR/hosts/$HOSTNAME"
    mkdir -p "$OUTPUT_DIR/home"

    # Generate files
    generate_disko > "$OUTPUT_DIR/hosts/$HOSTNAME/disko.nix"
    generate_configuration > "$OUTPUT_DIR/hosts/$HOSTNAME/configuration.nix"
    generate_hardware_config > "$OUTPUT_DIR/hosts/$HOSTNAME/hardware-configuration.nix"
    generate_home_config > "$OUTPUT_DIR/home/$HOSTNAME.nix"
    generate_flake_entry > "$OUTPUT_DIR/flake-entry.nix"
    generate_patch "$OUTPUT_DIR" > "$OUTPUT_DIR/$HOSTNAME.patch"
    generate_install_log > "$OUTPUT_DIR/INSTALL_LOG.md"

    echo ""
    echo "Generated files in $OUTPUT_DIR/"
    echo ""
    ls -la "$OUTPUT_DIR/"
    ls -la "$OUTPUT_DIR/hosts/$HOSTNAME/"

    echo ""
    echo "Next steps:"
    echo "  1. Review the generated files"
    echo "  2. Copy to your flake: cp -r $OUTPUT_DIR/hosts/$HOSTNAME $FLAKE_ROOT/hosts/"
    echo "  3. Add flake.nix entry from: $OUTPUT_DIR/flake-entry.nix"
    echo "  4. Test build: nixos-rebuild build --flake .#$HOSTNAME"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
