#!/usr/bin/env bash
# Profile detection for NixOS flake installer
# Scans the flake for available profiles and suggests appropriate ones
# Uses configurable paths from flake-config.sh

# Note: Not using pipefail - this script is designed to be piped to grep/head/etc
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="${FLAKE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source configuration
if [[ -f "$SCRIPT_DIR/flake-config.sh" ]]; then
    source "$SCRIPT_DIR/flake-config.sh"
fi

# List available profiles from configured profiles directory
list_profiles() {
    local profiles_dir
    profiles_dir="${FLAKE_ROOT}/${FLAKE_PROFILES_DIR:-hosts/profiles}"

    if [[ ! -d "$profiles_dir" ]]; then
        echo "base"
        return
    fi

    for item in "$profiles_dir"/*; do
        [[ -e "$item" ]] || continue

        local name
        name=$(basename "$item")

        # Handle both file.nix and directory/default.nix patterns
        if [[ -f "$item" ]] && [[ "$name" == *.nix ]]; then
            echo "${name%.nix}"
        elif [[ -d "$item" ]] && [[ -f "$item/default.nix" ]]; then
            echo "$name"
        fi
    done
}

# Get profile description by parsing comments
get_profile_description() {
    local profile="$1"
    local profiles_dir="${FLAKE_ROOT}/${FLAKE_PROFILES_DIR:-hosts/profiles}"
    local profile_path="$profiles_dir/${profile}.nix"

    # Also check for directory-style profiles
    if [[ ! -f "$profile_path" ]] && [[ -f "$profiles_dir/$profile/default.nix" ]]; then
        profile_path="$profiles_dir/$profile/default.nix"
    fi

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
            desktop) desc="Desktop environment" ;;
            server) desc="Server with SSH hardening" ;;
            laptop) desc="Power management for laptops" ;;
            gaming) desc="Gaming packages and drivers" ;;
            i3|i3-desktop) desc="i3 window manager" ;;
            hyprland) desc="Hyprland compositor" ;;
            gnome) desc="GNOME desktop" ;;
            kde|plasma) desc="KDE Plasma desktop" ;;
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
    local suggestions=""

    # Source hardware detection if available
    if [[ -f "$SCRIPT_DIR/hardware-detect.sh" ]]; then
        source "$SCRIPT_DIR/hardware-detect.sh"

        # Get hardware info
        eval "$(detect_all 2>/dev/null || true)"

        # Always include base if it exists
        if profile_exists "base"; then
            suggestions="base"
        fi

        # Add laptop profile if battery detected
        if [[ "${IS_LAPTOP:-false}" == "true" ]]; then
            if profile_exists "laptop"; then
                suggestions="${suggestions:+$suggestions }laptop"
            fi
        fi

        # Add desktop if we have a real GPU
        if [[ "${GPU_TYPE:-generic}" != "generic" ]]; then
            if profile_exists "desktop"; then
                suggestions="${suggestions:+$suggestions }desktop"
            fi

            # Suggest gaming for capable GPUs
            if [[ "${NEEDS_NVIDIA:-false}" == "true" ]] || [[ "${GPU_TYPE:-}" == "amd" ]]; then
                if profile_exists "gaming"; then
                    suggestions="${suggestions:+$suggestions }gaming"
                fi
            fi
        fi
    fi

    # Default to base if nothing suggested
    echo "${suggestions:-base}"
}

# Check if a profile exists
profile_exists() {
    local profile="$1"
    local profiles_dir="${FLAKE_ROOT}/${FLAKE_PROFILES_DIR:-hosts/profiles}"

    [[ -f "$profiles_dir/${profile}.nix" ]] || [[ -f "$profiles_dir/${profile}/default.nix" ]]
}

# List existing hosts from flake
list_hosts() {
    local hosts_dir="${FLAKE_ROOT}/${FLAKE_HOSTS_DIR:-hosts}"

    if [[ ! -d "$hosts_dir" ]]; then
        return
    fi

    for host in "$hosts_dir"/*/; do
        [[ -d "$host" ]] || continue
        local name
        name=$(basename "$host")

        # Skip profiles directory and special entries
        [[ "$name" == "profiles" ]] && continue
        [[ "$name" == "default.nix" ]] && continue
        [[ "$name" == "common" ]] && continue
        [[ "$name" == "modules" ]] && continue

        # Check if it's a real host (has configuration.nix or default.nix)
        if [[ -f "$host/configuration.nix" ]] || [[ -f "$host/default.nix" ]]; then
            echo "$name"
        fi
    done
}

# Get imports from an existing host as reference
get_host_imports() {
    local host="$1"
    local hosts_dir="${FLAKE_ROOT}/${FLAKE_HOSTS_DIR:-hosts}"
    local config="$hosts_dir/$host/configuration.nix"

    # Also check default.nix
    if [[ ! -f "$config" ]]; then
        config="$hosts_dir/$host/default.nix"
    fi

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    # Extract imports section (basic parsing)
    grep -E "^\s*\.\./(profiles|modules)/" "$config" 2>/dev/null | \
        sed 's/.*\/\([^/.]*\)\.nix.*/\1/' | \
        sort -u
}

# Validate hostname
validate_hostname() {
    local hostname="$1"
    local hosts_dir="${FLAKE_ROOT}/${FLAKE_HOSTS_DIR:-hosts}"

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

    # Check if already exists (only if hosts_dir exists)
    if [[ -d "$hosts_dir/$hostname" ]]; then
        echo "Host '$hostname' already exists in this flake"
        return 1
    fi

    return 0
}

# Get srvos modules based on role (optional - only if using srvos)
get_srvos_modules() {
    local role="${1:-desktop}"
    local use_srvos="${FLAKE_USE_SRVOS:-true}"

    if [[ "$use_srvos" != "true" ]]; then
        return
    fi

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

    case "$vendor" in
        *Lenovo*)
            if [[ "$product" == *ThinkPad*T490* ]]; then
                echo "nixos-hardware.nixosModules.lenovo-thinkpad-t490"
            elif [[ "$product" == *ThinkPad*X1* ]]; then
                echo "nixos-hardware.nixosModules.lenovo-thinkpad-x1"
            elif [[ "$product" == *ThinkPad* ]]; then
                echo "nixos-hardware.nixosModules.lenovo-thinkpad"
            fi
            ;;
        *Dell*)
            if [[ "$product" == *XPS* ]]; then
                echo "nixos-hardware.nixosModules.dell-xps-15"
            fi
            ;;
        *Framework*)
            echo "nixos-hardware.nixosModules.framework"
            ;;
        *Apple*)
            echo "nixos-hardware.nixosModules.apple"
            ;;
        *ASUS*)
            echo "nixos-hardware.nixosModules.asus"
            ;;
    esac
}

# Generate profile import line using configured pattern
make_profile_import() {
    local profile="$1"
    local pattern="${FLAKE_PROFILE_IMPORT_PATTERN:-../profiles/{{PROFILE}}.nix}"
    echo "${pattern//\{\{PROFILE\}\}/$profile}"
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
        import) make_profile_import "${2:-base}" ;;
        *) echo "Usage: $0 {list|dialog|suggest|hosts|host-imports|validate|srvos|hardware-module|import} [args...]" ;;
    esac
fi
