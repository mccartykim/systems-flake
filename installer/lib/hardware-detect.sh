#!/usr/bin/env bash
# Hardware detection utilities for NixOS flake installer
# Provides functions to detect CPU, GPU, battery, and other hardware

# Note: Not using pipefail - this script is designed to be piped to grep/head/etc
set -eu

# Detect CPU vendor and features
detect_cpu() {
    local vendor model cores

    if [[ -f /proc/cpuinfo ]]; then
        vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | tr -d ' ')
        model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
        cores=$(grep -c "^processor" /proc/cpuinfo)
    else
        vendor="unknown"
        model="unknown"
        cores="1"
    fi

    echo "CPU_VENDOR=$vendor"
    echo "CPU_MODEL=$model"
    echo "CPU_CORES=$cores"

    # Detect specific features for NixOS hardware modules
    if [[ "$vendor" == "GenuineIntel" ]]; then
        echo "CPU_TYPE=intel"
    elif [[ "$vendor" == "AuthenticAMD" ]]; then
        echo "CPU_TYPE=amd"
    else
        echo "CPU_TYPE=generic"
    fi
}

# Detect GPU(s) and driver recommendations
detect_gpu() {
    local gpu_info=""
    local gpu_type="generic"
    local needs_nvidia=false
    local needs_amdgpu=false

    if command -v lspci &>/dev/null; then
        # Check for NVIDIA
        if lspci | grep -qi "nvidia"; then
            needs_nvidia=true
            gpu_type="nvidia"
            gpu_info=$(lspci | grep -i "nvidia" | head -1)
        fi

        # Check for AMD GPU
        if lspci | grep -qi "AMD.*VGA\|AMD.*Display\|Radeon"; then
            needs_amdgpu=true
            if [[ "$gpu_type" == "nvidia" ]]; then
                gpu_type="hybrid"
            else
                gpu_type="amd"
            fi
            gpu_info="${gpu_info:+$gpu_info; }$(lspci | grep -iE "AMD.*VGA|AMD.*Display|Radeon" | head -1)"
        fi

        # Check for Intel integrated
        if lspci | grep -qi "Intel.*VGA\|Intel.*Graphics"; then
            if [[ "$gpu_type" == "generic" ]]; then
                gpu_type="intel"
            fi
            gpu_info="${gpu_info:+$gpu_info; }$(lspci | grep -iE "Intel.*VGA|Intel.*Graphics" | head -1)"
        fi
    fi

    echo "GPU_TYPE=$gpu_type"
    echo "GPU_INFO=$gpu_info"
    echo "NEEDS_NVIDIA=$needs_nvidia"
    echo "NEEDS_AMDGPU=$needs_amdgpu"
}

# Detect if this is a laptop (battery present)
detect_laptop() {
    local is_laptop=false
    local battery_present=false

    # Check for battery
    if [[ -d /sys/class/power_supply ]]; then
        for supply in /sys/class/power_supply/*/type; do
            if [[ -f "$supply" ]] && grep -qi "battery" "$supply" 2>/dev/null; then
                battery_present=true
                is_laptop=true
                break
            fi
        done
    fi

    # Check DMI for laptop indicators
    if [[ -f /sys/class/dmi/id/chassis_type ]]; then
        local chassis_type
        chassis_type=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
        # Chassis types 8-14 are various laptop types
        if [[ "$chassis_type" -ge 8 && "$chassis_type" -le 14 ]]; then
            is_laptop=true
        fi
    fi

    echo "IS_LAPTOP=$is_laptop"
    echo "BATTERY_PRESENT=$battery_present"
}

# Detect boot mode (UEFI vs BIOS)
detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "BOOT_MODE=uefi"
    else
        echo "BOOT_MODE=bios"
    fi
}

# Detect network interfaces
detect_network() {
    local interfaces=""
    local has_wifi=false
    local has_ethernet=false

    for iface in /sys/class/net/*; do
        local name
        name=$(basename "$iface")
        [[ "$name" == "lo" ]] && continue

        if [[ -d "$iface/wireless" ]]; then
            has_wifi=true
            interfaces="${interfaces:+$interfaces }$name:wifi"
        elif [[ -f "$iface/type" ]]; then
            local type
            type=$(cat "$iface/type")
            if [[ "$type" == "1" ]]; then
                has_ethernet=true
                interfaces="${interfaces:+$interfaces }$name:ethernet"
            fi
        fi
    done

    echo "NETWORK_INTERFACES=$interfaces"
    echo "HAS_WIFI=$has_wifi"
    echo "HAS_ETHERNET=$has_ethernet"
}

# Detect system vendor/model for hardware module matching
detect_system_info() {
    local vendor="" product="" family=""

    if [[ -f /sys/class/dmi/id/sys_vendor ]]; then
        vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
    fi
    if [[ -f /sys/class/dmi/id/product_name ]]; then
        product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
    fi
    if [[ -f /sys/class/dmi/id/product_family ]]; then
        family=$(cat /sys/class/dmi/id/product_family 2>/dev/null || echo "")
    fi

    echo "SYSTEM_VENDOR=$vendor"
    echo "SYSTEM_PRODUCT=$product"
    echo "SYSTEM_FAMILY=$family"

    # Suggest nixos-hardware modules based on vendor/product
    local hw_module=""
    case "$vendor" in
        *Lenovo*)
            if [[ "$product" == *ThinkPad* ]]; then
                hw_module="lenovo-thinkpad"
                # Try to match specific model
                if [[ "$product" == *T490* ]]; then
                    hw_module="lenovo-thinkpad-t490"
                elif [[ "$product" == *X1* ]]; then
                    hw_module="lenovo-thinkpad-x1"
                fi
            fi
            ;;
        *Dell*)
            hw_module="dell"
            if [[ "$product" == *XPS* ]]; then
                hw_module="dell-xps"
            fi
            ;;
        *HP*)
            hw_module="hp"
            ;;
        *ASUS*)
            hw_module="asus"
            ;;
        *Framework*)
            hw_module="framework"
            ;;
    esac

    echo "SUGGESTED_HW_MODULE=$hw_module"
}

# Detect RAM size
detect_memory() {
    local total_kb total_gb

    if [[ -f /proc/meminfo ]]; then
        total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        total_gb=$((total_kb / 1024 / 1024))
    else
        total_gb=0
    fi

    echo "RAM_GB=$total_gb"

    # Suggest swap size based on RAM
    local swap_size
    if [[ $total_gb -le 4 ]]; then
        swap_size=$((total_gb * 2))
    elif [[ $total_gb -le 16 ]]; then
        swap_size=$total_gb
    else
        swap_size=16
    fi
    echo "SUGGESTED_SWAP_GB=$swap_size"
}

# Run all detection and output as shell variables
detect_all() {
    detect_boot_mode
    detect_cpu
    detect_gpu
    detect_laptop
    detect_network
    detect_system_info
    detect_memory
}

# Suggest profiles based on detected hardware
suggest_profiles() {
    local profiles="base"

    # Source detection results
    eval "$(detect_all)"

    # Add laptop profile if battery detected
    if [[ "$IS_LAPTOP" == "true" ]]; then
        profiles="$profiles laptop"
    fi

    # Suggest desktop vs server based on GPU
    if [[ "$GPU_TYPE" != "generic" ]] && [[ "$GPU_TYPE" != "" ]]; then
        profiles="$profiles desktop"

        # Add gaming if NVIDIA or good AMD GPU
        if [[ "$NEEDS_NVIDIA" == "true" ]] || [[ "$GPU_TYPE" == "amd" ]]; then
            profiles="$profiles gaming"
        fi
    fi

    echo "$profiles"
}

# If sourced, just export functions. If run directly, detect all.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-all}" in
        cpu) detect_cpu ;;
        gpu) detect_gpu ;;
        laptop) detect_laptop ;;
        boot) detect_boot_mode ;;
        network) detect_network ;;
        system) detect_system_info ;;
        memory) detect_memory ;;
        profiles) suggest_profiles ;;
        all) detect_all ;;
        *) echo "Usage: $0 {cpu|gpu|laptop|boot|network|system|memory|profiles|all}" ;;
    esac
fi
