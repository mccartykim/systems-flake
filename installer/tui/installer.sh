#!/usr/bin/env bash
# NixOS Flake-Aware Installer TUI
# Interactive installer for adding new hosts to a NixOS flake

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
GENERATOR="$SCRIPT_DIR/../generators/generate-host.sh"

# Detect flake location
if [[ -d "/mnt/flake" ]]; then
    FLAKE_ROOT="/mnt/flake"
elif [[ -d "/etc/systems-flake" ]]; then
    FLAKE_ROOT="/etc/systems-flake"
else
    FLAKE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

export FLAKE_ROOT

# Source library functions
source "$LIB_DIR/hardware-detect.sh"
source "$LIB_DIR/disk-utils.sh"
source "$LIB_DIR/profile-detect.sh"

# Dialog dimensions
DIALOG_HEIGHT=20
DIALOG_WIDTH=70
DIALOG_MENU_HEIGHT=10

# Temp file for dialog results
DIALOG_RESULT=$(mktemp)
trap 'rm -f "$DIALOG_RESULT"' EXIT

# State variables
HOSTNAME=""
DISK_DEVICE=""
PARTITION_SCHEME="standard"
PROFILES=""
USERNAME="kimb"
BOOT_MODE=""
SWAP_SIZE=""
DO_INSTALL=false
OUTPUT_DIR=""

# Check for required tools
check_dependencies() {
    local missing=()

    for cmd in dialog parted lsblk; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}" >&2
        echo "Install with: nix-shell -p ${missing[*]}" >&2
        exit 1
    fi
}

# Show a message box
msg_box() {
    dialog --backtitle "NixOS Flake Installer" \
           --title "${2:-Information}" \
           --msgbox "$1" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show an input box and return result
input_box() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    dialog --backtitle "NixOS Flake Installer" \
           --title "$title" \
           --inputbox "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH "$default" 2>"$DIALOG_RESULT"

    cat "$DIALOG_RESULT"
}

# Show a yes/no dialog
yes_no() {
    local title="$1"
    local prompt="$2"

    dialog --backtitle "NixOS Flake Installer" \
           --title "$title" \
           --yesno "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show a menu and return selection
menu() {
    local title="$1"
    local prompt="$2"
    shift 2

    dialog --backtitle "NixOS Flake Installer" \
           --title "$title" \
           --menu "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
           "$@" 2>"$DIALOG_RESULT"

    cat "$DIALOG_RESULT"
}

# Show a checklist and return selections
checklist() {
    local title="$1"
    local prompt="$2"
    shift 2

    dialog --backtitle "NixOS Flake Installer" \
           --title "$title" \
           --checklist "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
           "$@" 2>"$DIALOG_RESULT"

    cat "$DIALOG_RESULT"
}

# Show hardware info in a text box
show_hardware_info() {
    local hw_info
    hw_info=$(detect_all 2>/dev/null | column -t -s= || echo "Hardware detection failed")

    dialog --backtitle "NixOS Flake Installer" \
           --title "Detected Hardware" \
           --textbox <(echo "$hw_info") $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Welcome screen
screen_welcome() {
    local flake_status="Flake found at: $FLAKE_ROOT"

    if [[ ! -f "$FLAKE_ROOT/flake.nix" ]]; then
        flake_status="WARNING: No flake.nix found at $FLAKE_ROOT"
    fi

    dialog --backtitle "NixOS Flake Installer" \
           --title "Welcome to NixOS Flake Installer" \
           --yes-label "Continue" \
           --no-label "Exit" \
           --yesno "
This installer will help you add a new host to your NixOS flake.

$flake_status

The installer will:
  1. Detect your hardware
  2. Let you choose a hostname and target disk
  3. Select a partition scheme and profiles
  4. Generate configuration files

Files will be saved for review before any changes are made.

Press 'Continue' to start or 'Exit' to quit.
" 18 70

    return $?
}

# Hostname selection
screen_hostname() {
    local suggested=""
    eval "$(detect_system_info 2>/dev/null || true)"

    # Suggest hostname based on system product
    if [[ -n "${SYSTEM_PRODUCT:-}" ]]; then
        suggested=$(echo "$SYSTEM_PRODUCT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 15)
    fi

    while true; do
        HOSTNAME=$(input_box "Hostname" "Enter hostname for this machine:" "$suggested")

        if [[ -z "$HOSTNAME" ]]; then
            if yes_no "Exit?" "No hostname entered. Do you want to exit?"; then
                return 1
            fi
            continue
        fi

        # Validate hostname
        local validation
        if validation=$(validate_hostname "$HOSTNAME" 2>&1); then
            break
        else
            msg_box "Invalid hostname: $validation" "Error"
        fi
    done

    return 0
}

# Disk selection
screen_disk() {
    # Get list of disks
    local disks=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local dev size model tran
        read -r dev size _ model tran <<< "$line"
        disks+=("$dev" "$size ${model:-Unknown} (${tran:-local})")
    done < <(list_disks human)

    if [[ ${#disks[@]} -eq 0 ]]; then
        msg_box "No suitable disks found for installation." "Error"
        return 1
    fi

    DISK_DEVICE=$(menu "Select Disk" "Choose the target disk for installation:" "${disks[@]}")

    if [[ -z "$DISK_DEVICE" ]]; then
        return 1
    fi

    DISK_DEVICE="/dev/$DISK_DEVICE"

    # Warn if disk has data
    if disk_has_data "$DISK_DEVICE"; then
        if ! yes_no "Warning" "Disk $DISK_DEVICE appears to contain data.\n\nAll data will be DESTROYED during installation.\n\nContinue?"; then
            return 1
        fi
    fi

    return 0
}

# Boot mode detection and partition scheme selection
screen_partition() {
    # Detect boot mode
    eval "$(detect_boot_mode)"

    local boot_desc
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        boot_desc="UEFI mode detected"
    else
        boot_desc="Legacy BIOS mode detected"
    fi

    # Build scheme options based on boot mode
    local schemes=()
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        schemes+=(
            "simple" "ESP + Root (no swap)"
            "standard" "ESP + Swap + Root (recommended)"
            "luks" "ESP + Encrypted (Swap + Root)"
        )
    else
        schemes+=(
            "simple" "Boot + Root (no swap)"
            "standard" "Boot + Swap + Root (recommended)"
        )
    fi

    PARTITION_SCHEME=$(menu "Partition Scheme" "$boot_desc\n\nSelect partition layout:" "${schemes[@]}")

    if [[ -z "$PARTITION_SCHEME" ]]; then
        PARTITION_SCHEME="standard"
    fi

    return 0
}

# Profile selection
screen_profiles() {
    # Get suggested profiles based on hardware
    local suggested
    suggested=$(suggest_profiles_for_hardware 2>/dev/null || echo "base")

    # Build checklist options
    local options=()
    for profile in $(list_profiles); do
        local desc
        desc=$(get_profile_description "$profile")
        local selected="off"

        # Pre-select suggested profiles
        if [[ " $suggested " == *" $profile "* ]]; then
            selected="on"
        fi

        options+=("$profile" "$desc" "$selected")
    done

    local selected_profiles
    selected_profiles=$(checklist "Select Profiles" "Choose configuration profiles to include:" "${options[@]}")

    if [[ -z "$selected_profiles" ]]; then
        PROFILES="base"
    else
        # Convert space-separated list to comma-separated
        PROFILES=$(echo "$selected_profiles" | tr -d '"' | tr ' ' ',')
    fi

    return 0
}

# Swap size configuration
screen_swap() {
    if [[ "$PARTITION_SCHEME" == "simple" ]]; then
        SWAP_SIZE="0"
        return 0
    fi

    # Calculate suggested swap
    local ram_gb
    ram_gb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024/1024)}' || echo 8)
    local suggested

    if [[ $ram_gb -le 4 ]]; then
        suggested="$((ram_gb * 2))G"
    elif [[ $ram_gb -le 16 ]]; then
        suggested="${ram_gb}G"
    else
        suggested="16G"
    fi

    SWAP_SIZE=$(input_box "Swap Size" "Enter swap partition size (e.g., 8G, 16G):\n\nDetected RAM: ${ram_gb}GB\nSuggested swap: $suggested" "$suggested")

    if [[ -z "$SWAP_SIZE" ]]; then
        SWAP_SIZE="$suggested"
    fi

    return 0
}

# Username configuration
screen_username() {
    USERNAME=$(input_box "Username" "Enter primary username:" "$USERNAME")

    if [[ -z "$USERNAME" ]]; then
        USERNAME="kimb"
    fi

    return 0
}

# Installation mode selection
screen_install_mode() {
    local choice
    choice=$(menu "Installation Mode" "What would you like to do?" \
        "generate" "Generate config files only (review first)" \
        "install" "Generate and install NixOS now")

    case "$choice" in
        install)
            DO_INSTALL=true
            ;;
        *)
            DO_INSTALL=false
            ;;
    esac

    return 0
}

# Summary and confirmation
screen_confirm() {
    local disk_info
    disk_info=$(disk_info "$DISK_DEVICE" 2>/dev/null | grep -E "DISK_(SIZE|TYPE|MODEL)" | column -t -s= || echo "Unknown")

    local summary="
Configuration Summary:

  Hostname:     $HOSTNAME
  Target Disk:  $DISK_DEVICE
  Boot Mode:    $BOOT_MODE
  Partitioning: $PARTITION_SCHEME
  Swap Size:    $SWAP_SIZE
  Profiles:     $PROFILES
  Username:     $USERNAME

Disk Info:
$disk_info

"

    if [[ "$DO_INSTALL" == "true" ]]; then
        summary="${summary}
ACTION: Generate configs AND install NixOS

WARNING: This will ERASE all data on $DISK_DEVICE!
"
    else
        summary="${summary}
ACTION: Generate configuration files only

Files will be saved to: $FLAKE_ROOT/generated/$HOSTNAME/
You can review and modify before installing.
"
    fi

    if yes_no "Confirm" "$summary\n\nProceed?"; then
        return 0
    fi

    return 1
}

# Generate configs
do_generate() {
    clear
    echo "Generating configuration for $HOSTNAME..."
    echo ""

    OUTPUT_DIR="$FLAKE_ROOT/generated/$HOSTNAME"

    "$GENERATOR" \
        --hostname "$HOSTNAME" \
        --disk "$DISK_DEVICE" \
        --scheme "$PARTITION_SCHEME" \
        --profiles "$PROFILES" \
        --username "$USERNAME" \
        --swap "$SWAP_SIZE" \
        --output "$OUTPUT_DIR"

    return $?
}

# Run disko to partition disk
do_partition() {
    echo ""
    echo "Partitioning disk with disko..."

    local disko_config="$OUTPUT_DIR/hosts/$HOSTNAME/disko.nix"

    if [[ ! -f "$disko_config" ]]; then
        echo "Error: disko config not found at $disko_config" >&2
        return 1
    fi

    # Run disko
    nix run github:nix-community/disko -- --mode disko "$disko_config"

    return $?
}

# Run nixos-install
do_install() {
    echo ""
    echo "Running nixos-install..."

    # Copy generated config to /mnt/etc/nixos
    mkdir -p /mnt/etc/nixos
    cp -r "$OUTPUT_DIR/hosts/$HOSTNAME"/* /mnt/etc/nixos/

    # Copy the flake
    mkdir -p /mnt/etc/nixos
    cp -r "$FLAKE_ROOT"/* /mnt/etc/nixos/ 2>/dev/null || true

    # Add the new host configuration to the flake
    # This is a simplified approach - in practice you'd patch the flake
    cp "$OUTPUT_DIR/hosts/$HOSTNAME"/* "/mnt/etc/nixos/hosts/$HOSTNAME/"

    nixos-install --flake "/mnt/etc/nixos#$HOSTNAME" --no-root-password

    return $?
}

# Final screen
screen_done() {
    if [[ "$DO_INSTALL" == "true" ]]; then
        msg_box "
Installation complete!

The system will now reboot into your new NixOS installation.

Generated files are saved to:
  $OUTPUT_DIR/

Remember to:
  1. Merge the changes into your flake repository
  2. Set up any secrets (agenix, nebula, etc.)
  3. Configure home-manager user settings
" "Installation Complete"
    else
        msg_box "
Configuration files generated successfully!

Files saved to: $OUTPUT_DIR/

Next steps:
  1. Review the generated files
  2. Copy to your flake:
     cp -r $OUTPUT_DIR/hosts/$HOSTNAME $FLAKE_ROOT/hosts/
  3. Add the flake entry from:
     $OUTPUT_DIR/flake-entry.nix
  4. Test build:
     nixos-rebuild build --flake .#$HOSTNAME
  5. Install:
     nixos-install --flake .#$HOSTNAME
" "Generation Complete"
    fi
}

# Main installer flow
main() {
    check_dependencies

    # Welcome
    if ! screen_welcome; then
        clear
        echo "Installation cancelled."
        exit 0
    fi

    # Gather information
    screen_hostname || exit 1
    screen_disk || exit 1
    screen_partition || exit 1
    screen_swap || exit 1
    screen_profiles || exit 1
    screen_username || exit 1
    screen_install_mode || exit 1

    # Confirm
    if ! screen_confirm; then
        clear
        echo "Installation cancelled."
        exit 0
    fi

    # Generate
    if ! do_generate; then
        msg_box "Failed to generate configuration files." "Error"
        exit 1
    fi

    # Install if requested
    if [[ "$DO_INSTALL" == "true" ]]; then
        if ! do_partition; then
            msg_box "Disk partitioning failed." "Error"
            exit 1
        fi

        if ! do_install; then
            msg_box "NixOS installation failed." "Error"
            exit 1
        fi
    fi

    # Done
    screen_done

    clear
    echo "Done! Configuration files are in: $OUTPUT_DIR/"

    if [[ "$DO_INSTALL" == "true" ]]; then
        echo ""
        read -rp "Press Enter to reboot..." _
        reboot
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo ""
        echo "Interactive TUI installer for NixOS flakes."
        echo ""
        echo "Options:"
        echo "  --help    Show this help message"
        echo ""
        echo "For non-interactive usage, use generate-host.sh directly."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
