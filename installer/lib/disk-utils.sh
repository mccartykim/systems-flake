#!/usr/bin/env bash
# Disk detection and utilities for NixOS flake installer
# Provides functions to list, select, and analyze disks

# Note: Not using pipefail - this script is designed to be piped to grep/head/etc
set -eu

# List all available disks suitable for installation
list_disks() {
    local format="${1:-human}"

    # Get block devices that are disks (not partitions, not removable if they're the boot device)
    lsblk -d -n -o NAME,SIZE,TYPE,MODEL,TRAN 2>/dev/null | while read -r name size type model tran; do
        # Skip non-disk types
        [[ "$type" != "disk" ]] && continue

        # Skip the boot device (where we're running from)
        local boot_device=""
        boot_device=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/[0-9]*$//' | xargs basename 2>/dev/null || echo "")
        [[ "$name" == "$boot_device" ]] && continue

        # Skip loop devices and ram disks
        [[ "$name" == loop* ]] && continue
        [[ "$name" == ram* ]] && continue
        [[ "$name" == zram* ]] && continue

        case "$format" in
            human)
                printf "%-10s %-10s %-6s %s\n" "$name" "$size" "${tran:-N/A}" "${model:-Unknown}"
                ;;
            dialog)
                # Format for dialog menu: "tag" "description"
                printf '"%s" "%s - %s (%s)"\n' "/dev/$name" "$size" "${model:-Unknown}" "${tran:-local}"
                ;;
            json)
                printf '{"device":"/dev/%s","size":"%s","model":"%s","transport":"%s"}\n' \
                    "$name" "$size" "${model:-}" "${tran:-}"
                ;;
            simple)
                echo "/dev/$name"
                ;;
        esac
    done
}

# Get detailed info about a specific disk
disk_info() {
    local disk="$1"

    # Normalize device path
    [[ "$disk" != /dev/* ]] && disk="/dev/$disk"

    if [[ ! -b "$disk" ]]; then
        echo "Error: $disk is not a block device" >&2
        return 1
    fi

    local name size_bytes size_human model serial tran rotational
    name=$(basename "$disk")

    # Get size in bytes
    size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
    size_human=$(numfmt --to=iec "$size_bytes" 2>/dev/null || echo "unknown")

    # Get disk attributes
    model=$(cat "/sys/block/$name/device/model" 2>/dev/null | tr -d ' \n' || echo "")
    serial=$(cat "/sys/block/$name/device/serial" 2>/dev/null | tr -d ' \n' || echo "")
    tran=$(cat "/sys/block/$name/device/transport" 2>/dev/null ||
           lsblk -n -o TRAN "$disk" 2>/dev/null | head -1 || echo "")
    rotational=$(cat "/sys/block/$name/queue/rotational" 2>/dev/null || echo "1")

    local disk_type="HDD"
    [[ "$rotational" == "0" ]] && disk_type="SSD"
    [[ "$tran" == "nvme" ]] && disk_type="NVMe"

    echo "DISK_DEVICE=$disk"
    echo "DISK_SIZE_BYTES=$size_bytes"
    echo "DISK_SIZE_HUMAN=$size_human"
    echo "DISK_MODEL=$model"
    echo "DISK_SERIAL=$serial"
    echo "DISK_TRANSPORT=$tran"
    echo "DISK_TYPE=$disk_type"
    echo "DISK_ROTATIONAL=$rotational"
}

# List existing partitions on a disk
list_partitions() {
    local disk="$1"

    [[ "$disk" != /dev/* ]] && disk="/dev/$disk"

    lsblk -n -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$disk" 2>/dev/null | tail -n +2
}

# Check if disk has existing partitions/data
disk_has_data() {
    local disk="$1"

    [[ "$disk" != /dev/* ]] && disk="/dev/$disk"

    # Check for partition table
    if parted -s "$disk" print 2>/dev/null | grep -q "Partition Table:"; then
        local part_table
        part_table=$(parted -s "$disk" print 2>/dev/null | grep "Partition Table:" | awk '{print $3}')
        if [[ "$part_table" != "unknown" ]]; then
            return 0  # Has partition table
        fi
    fi

    # Check for filesystem directly on disk
    if blkid "$disk" 2>/dev/null | grep -q "TYPE="; then
        return 0  # Has filesystem
    fi

    return 1  # No data detected
}

# Calculate partition sizes for different schemes
calculate_partitions() {
    local disk="$1"
    local scheme="${2:-standard}"
    local boot_mode="${3:-uefi}"

    [[ "$disk" != /dev/* ]] && disk="/dev/$disk"

    local total_size
    total_size=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
    local total_gb=$((total_size / 1024 / 1024 / 1024))

    local boot_size=512  # MB
    local swap_size=0
    local root_size=0

    # Calculate swap based on RAM
    local ram_gb
    ram_gb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024/1024)}' || echo 8)

    case "$scheme" in
        simple)
            # Just boot + root
            swap_size=0
            root_size=$((total_gb * 1024 - boot_size))
            ;;
        standard)
            # Boot + swap + root
            if [[ $ram_gb -le 4 ]]; then
                swap_size=$((ram_gb * 2 * 1024))
            elif [[ $ram_gb -le 16 ]]; then
                swap_size=$((ram_gb * 1024))
            else
                swap_size=$((16 * 1024))
            fi
            root_size=$((total_gb * 1024 - boot_size - swap_size))
            ;;
        with-home)
            # Boot + swap + root (50GB or 50%) + home
            if [[ $ram_gb -le 16 ]]; then
                swap_size=$((ram_gb * 1024))
            else
                swap_size=$((16 * 1024))
            fi
            if [[ $total_gb -gt 100 ]]; then
                root_size=$((50 * 1024))
            else
                root_size=$(((total_gb * 1024 - boot_size - swap_size) / 2))
            fi
            ;;
    esac

    echo "BOOT_SIZE_MB=$boot_size"
    echo "SWAP_SIZE_MB=$swap_size"
    echo "ROOT_SIZE_MB=$root_size"
    echo "TOTAL_SIZE_GB=$total_gb"
    echo "BOOT_MODE=$boot_mode"
    echo "PARTITION_SCHEME=$scheme"
}

# Wipe disk (careful!)
wipe_disk() {
    local disk="$1"
    local confirm="${2:-false}"

    [[ "$disk" != /dev/* ]] && disk="/dev/$disk"

    if [[ "$confirm" != "true" ]]; then
        echo "Error: Must pass 'true' as second argument to confirm wipe" >&2
        return 1
    fi

    # Unmount any mounted partitions
    for part in "${disk}"*; do
        if mountpoint -q "$part" 2>/dev/null || grep -q "^$part " /proc/mounts; then
            umount -f "$part" 2>/dev/null || true
        fi
    done

    # Wipe partition table and first MB
    dd if=/dev/zero of="$disk" bs=1M count=1 status=none 2>/dev/null || true

    # Clear any remaining signatures
    wipefs -a "$disk" 2>/dev/null || true

    echo "Disk $disk wiped"
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-list}" in
        list) list_disks "${2:-human}" ;;
        info) disk_info "${2:-}" ;;
        partitions) list_partitions "${2:-}" ;;
        hasdata) disk_has_data "${2:-}" && echo "yes" || echo "no" ;;
        calculate) calculate_partitions "${2:-}" "${3:-standard}" "${4:-uefi}" ;;
        wipe) wipe_disk "${2:-}" "${3:-false}" ;;
        *) echo "Usage: $0 {list|info|partitions|hasdata|calculate|wipe} [args...]" ;;
    esac
fi
