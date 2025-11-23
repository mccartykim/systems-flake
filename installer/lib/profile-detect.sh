#!/usr/bin/env bash
# Profile detection for NixOS flake installer
# Scans the flake for available profiles and suggests appropriate ones

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="${FLAKE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# List available profiles from hosts/profiles/
list_profiles() {
    local profiles_dir="$FLAKE_ROOT/hosts/profiles"

    if [[ ! -d "$profiles_dir" ]]; then
        echo "base"
        return
    fi

    for profile in "$profiles_dir"/*.nix; do
        [[ -f "$profile" ]] || continue
        basename "$profile" .nix
    done
}

# Get profile description by parsing comments
get_profile_description() {
    local profile="$1"
    local profile_path="$FLAKE_ROOT/hosts/profiles/${profile}.nix"

    if [[ ! -f "$profile_path" ]]; then
        echo "Unknown profile"
        return
    fi

    # Try to extract first comment line as description
    local desc
    desc=$(head -5 "$profile_path" | grep -E "^#" | head -1 | sed 's/^# *//' || echo "")

    if [[ -z "$desc" ]]; then
        # Generate description from name
        case "$profile" in
            base) desc="Core configuration for all hosts" ;;
            desktop) desc="KDE Plasma desktop environment" ;;
            server) desc="Server with SSH hardening" ;;
            laptop) desc="Power management for laptops" ;;
            gaming) desc="Gaming packages and drivers" ;;
            i3-desktop) desc="Minimal i3 window manager" ;;
            *) desc="Custom profile" ;;
        esac
    fi

    echo "$desc"
}

# List profiles formatted for dialog menu
list_profiles_dialog() {
    for profile in $(list_profiles); do
        local desc
        desc=$(get_profile_description "$profile")
        printf '"%s" "%s"\n' "$profile" "$desc"
    done
}

# Get profiles that should be preselected based on hardware
suggest_profiles_for_hardware() {
    local hw_file="${1:-}"
    local suggestions="base"

    # Source hardware detection if available
    if [[ -f "$SCRIPT_DIR/hardware-detect.sh" ]]; then
        source "$SCRIPT_DIR/hardware-detect.sh"

        # Get hardware info
        eval "$(detect_all 2>/dev/null || true)"

        # Always include base
        suggestions="base"

        # Add laptop profile if battery detected
        if [[ "${IS_LAPTOP:-false}" == "true" ]]; then
            if profile_exists "laptop"; then
                suggestions="$suggestions laptop"
            fi
        fi

        # Add desktop if we have a real GPU
        if [[ "${GPU_TYPE:-generic}" != "generic" ]]; then
            if profile_exists "desktop"; then
                suggestions="$suggestions desktop"
            fi

            # Suggest gaming for capable GPUs
            if [[ "${NEEDS_NVIDIA:-false}" == "true" ]] || [[ "${GPU_TYPE:-}" == "amd" ]]; then
                if profile_exists "gaming"; then
                    suggestions="$suggestions gaming"
                fi
            fi
        fi
    fi

    echo "$suggestions"
}

# Check if a profile exists
profile_exists() {
    local profile="$1"
    [[ -f "$FLAKE_ROOT/hosts/profiles/${profile}.nix" ]]
}

# List existing hosts from flake
list_hosts() {
    local hosts_dir="$FLAKE_ROOT/hosts"

    for host in "$hosts_dir"/*/; do
        [[ -d "$host" ]] || continue
        local name
        name=$(basename "$host")

        # Skip profiles directory and special entries
        [[ "$name" == "profiles" ]] && continue
        [[ "$name" == "default.nix" ]] && continue

        # Check if it's a real host (has configuration.nix)
        if [[ -f "$host/configuration.nix" ]]; then
            echo "$name"
        fi
    done
}

# Get imports from an existing host as reference
get_host_imports() {
    local host="$1"
    local config="$FLAKE_ROOT/hosts/$host/configuration.nix"

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    # Extract imports section (basic parsing)
    grep -E "^\s*\.\./profiles/" "$config" 2>/dev/null | \
        sed 's/.*profiles\/\([^.]*\)\.nix.*/\1/' | \
        sort -u
}

# Validate hostname
validate_hostname() {
    local hostname="$1"

    # Check length
    if [[ ${#hostname} -lt 1 ]] || [[ ${#hostname} -gt 63 ]]; then
        echo "Hostname must be 1-63 characters"
        return 1
    fi

    # Check characters (RFC 1123)
    if ! [[ "$hostname" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo "Hostname must contain only lowercase letters, numbers, and hyphens"
        return 1
    fi

    # Check if already exists
    if [[ -d "$FLAKE_ROOT/hosts/$hostname" ]]; then
        echo "Host '$hostname' already exists in this flake"
        return 1
    fi

    return 0
}

# Get srvos modules based on role
get_srvos_modules() {
    local role="${1:-desktop}"

    case "$role" in
        server)
            cat <<'EOF'
srvos.nixosModules.server
srvos.nixosModules.mixins-trusted-nix-caches
srvos.nixosModules.mixins-systemd-boot
srvos.nixosModules.mixins-nix-experimental
EOF
            ;;
        desktop)
            cat <<'EOF'
srvos.nixosModules.desktop
srvos.nixosModules.mixins-trusted-nix-caches
srvos.nixosModules.mixins-systemd-boot
srvos.nixosModules.mixins-nix-experimental
EOF
            ;;
        *)
            cat <<'EOF'
srvos.nixosModules.mixins-trusted-nix-caches
srvos.nixosModules.mixins-systemd-boot
srvos.nixosModules.mixins-nix-experimental
EOF
            ;;
    esac
}

# Get nixos-hardware module suggestion
get_hardware_module() {
    local vendor="${1:-}"
    local product="${2:-}"

    # This would need to be expanded based on nixos-hardware catalog
    case "$vendor" in
        *Lenovo*)
            if [[ "$product" == *ThinkPad*T490* ]]; then
                echo "nixos-hardware.nixosModules.lenovo-thinkpad-t490"
            elif [[ "$product" == *ThinkPad* ]]; then
                echo "nixos-hardware.nixosModules.lenovo-thinkpad"
            fi
            ;;
        *Framework*)
            echo "nixos-hardware.nixosModules.framework"
            ;;
    esac
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-list}" in
        list) list_profiles ;;
        dialog) list_profiles_dialog ;;
        suggest) suggest_profiles_for_hardware "${2:-}" ;;
        hosts) list_hosts ;;
        host-imports) get_host_imports "${2:-}" ;;
        validate) validate_hostname "${2:-}" ;;
        srvos) get_srvos_modules "${2:-desktop}" ;;
        hardware-module) get_hardware_module "${2:-}" "${3:-}" ;;
        *) echo "Usage: $0 {list|dialog|suggest|hosts|host-imports|validate|srvos|hardware-module} [args...]" ;;
    esac
fi
