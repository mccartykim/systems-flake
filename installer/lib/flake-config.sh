#!/usr/bin/env bash
# Flake structure configuration for the installer
# This file defines the expected directory layout of the target flake
# Users can customize these paths for their own flake structures

# Note: Not using pipefail - this script may be sourced by scripts piped to grep/head/etc

# Default configuration (matches systems-flake structure)
# Override by sourcing a custom config before running the installer

# Directory where host configurations live (relative to flake root)
FLAKE_HOSTS_DIR="${FLAKE_HOSTS_DIR:-hosts}"

# Directory where profiles live (relative to flake root)
FLAKE_PROFILES_DIR="${FLAKE_PROFILES_DIR:-hosts/profiles}"

# Directory where home-manager configs live (relative to flake root)
FLAKE_HOME_DIR="${FLAKE_HOME_DIR:-home}"

# Pattern for profile imports in configuration.nix
# Use {{PROFILE}} as placeholder for profile name
FLAKE_PROFILE_IMPORT_PATTERN="${FLAKE_PROFILE_IMPORT_PATTERN:-../profiles/{{PROFILE}}.nix}"

# Default username for new hosts
FLAKE_DEFAULT_USERNAME="${FLAKE_DEFAULT_USERNAME:-}"

# Whether to generate home-manager config
FLAKE_GENERATE_HOME="${FLAKE_GENERATE_HOME:-true}"

# Whether the flake uses disko
FLAKE_USE_DISKO="${FLAKE_USE_DISKO:-true}"

# State version for generated configs
FLAKE_STATE_VERSION="${FLAKE_STATE_VERSION:-24.11}"

# System architecture (auto-detected if not set)
FLAKE_SYSTEM="${FLAKE_SYSTEM:-}"

# ============================================================================
# Alternative configurations for common flake structures
# ============================================================================

# For flakes with structure: machines/<hostname>/default.nix
use_machines_structure() {
    FLAKE_HOSTS_DIR="machines"
    FLAKE_PROFILES_DIR="profiles"
    FLAKE_HOME_DIR="home"
    FLAKE_PROFILE_IMPORT_PATTERN="../../profiles/{{PROFILE}}.nix"
}

# For flakes with structure: nixos/<hostname>/configuration.nix
use_nixos_structure() {
    FLAKE_HOSTS_DIR="nixos"
    FLAKE_PROFILES_DIR="nixos/profiles"
    FLAKE_HOME_DIR="home-manager"
    FLAKE_PROFILE_IMPORT_PATTERN="../profiles/{{PROFILE}}.nix"
}

# For single-level flakes: <hostname>.nix in root
use_flat_structure() {
    FLAKE_HOSTS_DIR="."
    FLAKE_PROFILES_DIR="profiles"
    FLAKE_HOME_DIR="home"
    FLAKE_PROFILE_IMPORT_PATTERN="./profiles/{{PROFILE}}.nix"
}

# For nix-config style: hosts/<hostname>/default.nix, modules/profiles/*
use_nix_config_structure() {
    FLAKE_HOSTS_DIR="hosts"
    FLAKE_PROFILES_DIR="modules/profiles"
    FLAKE_HOME_DIR="home"
    FLAKE_PROFILE_IMPORT_PATTERN="../../modules/profiles/{{PROFILE}}.nix"
}

# ============================================================================
# Auto-detection of flake structure
# ============================================================================

detect_flake_structure() {
    local flake_root="${1:-$FLAKE_ROOT}"

    if [[ ! -d "$flake_root" ]]; then
        echo "unknown"
        return 1
    fi

    # Check for common patterns
    if [[ -d "$flake_root/hosts/profiles" ]]; then
        echo "systems-flake"
        return 0
    elif [[ -d "$flake_root/machines" ]]; then
        echo "machines"
        return 0
    elif [[ -d "$flake_root/nixos" ]]; then
        echo "nixos"
        return 0
    elif [[ -d "$flake_root/modules/profiles" ]]; then
        echo "nix-config"
        return 0
    else
        echo "unknown"
        return 1
    fi
}

auto_configure_structure() {
    local flake_root="${1:-$FLAKE_ROOT}"
    local structure

    structure=$(detect_flake_structure "$flake_root")

    case "$structure" in
        systems-flake)
            # Default - no changes needed
            ;;
        machines)
            use_machines_structure
            ;;
        nixos)
            use_nixos_structure
            ;;
        nix-config)
            use_nix_config_structure
            ;;
        *)
            # Unknown - keep defaults but warn
            echo "Warning: Could not detect flake structure, using defaults" >&2
            ;;
    esac

    echo "Detected flake structure: $structure"
}

# ============================================================================
# Helper functions
# ============================================================================

# Get the full path to hosts directory
get_hosts_path() {
    echo "${FLAKE_ROOT}/${FLAKE_HOSTS_DIR}"
}

# Get the full path to profiles directory
get_profiles_path() {
    echo "${FLAKE_ROOT}/${FLAKE_PROFILES_DIR}"
}

# Get the full path to home configs directory
get_home_path() {
    echo "${FLAKE_ROOT}/${FLAKE_HOME_DIR}"
}

# Generate a profile import line for configuration.nix
make_profile_import() {
    local profile="$1"
    echo "${FLAKE_PROFILE_IMPORT_PATTERN//\{\{PROFILE\}\}/$profile}"
}

# Check if a profile exists
profile_exists_configured() {
    local profile="$1"
    local profiles_path
    profiles_path=$(get_profiles_path)
    [[ -f "$profiles_path/${profile}.nix" ]] || [[ -f "$profiles_path/${profile}/default.nix" ]]
}

# List available profiles
list_profiles_configured() {
    local profiles_path
    profiles_path=$(get_profiles_path)

    if [[ ! -d "$profiles_path" ]]; then
        return
    fi

    for item in "$profiles_path"/*; do
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

# Validate flake structure has minimum required elements
validate_flake_structure() {
    local flake_root="${1:-$FLAKE_ROOT}"
    local errors=()

    if [[ ! -f "$flake_root/flake.nix" ]]; then
        errors+=("Missing flake.nix")
    fi

    # Profiles directory is optional but recommended
    local profiles_path
    profiles_path=$(get_profiles_path)
    if [[ ! -d "$profiles_path" ]]; then
        echo "Note: No profiles directory found at $profiles_path" >&2
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Flake structure validation errors:" >&2
        printf "  - %s\n" "${errors[@]}" >&2
        return 1
    fi

    return 0
}

# Export configuration to environment
export_config() {
    export FLAKE_HOSTS_DIR
    export FLAKE_PROFILES_DIR
    export FLAKE_HOME_DIR
    export FLAKE_PROFILE_IMPORT_PATTERN
    export FLAKE_DEFAULT_USERNAME
    export FLAKE_GENERATE_HOME
    export FLAKE_USE_DISKO
    export FLAKE_STATE_VERSION
    export FLAKE_SYSTEM
}

# Load configuration from file
load_config() {
    local config_file="$1"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        export_config
        return 0
    fi

    return 1
}

# Save current configuration to file
save_config() {
    local config_file="$1"

    cat > "$config_file" <<EOF
# Flake installer configuration
# Generated on $(date)

FLAKE_HOSTS_DIR="$FLAKE_HOSTS_DIR"
FLAKE_PROFILES_DIR="$FLAKE_PROFILES_DIR"
FLAKE_HOME_DIR="$FLAKE_HOME_DIR"
FLAKE_PROFILE_IMPORT_PATTERN="$FLAKE_PROFILE_IMPORT_PATTERN"
FLAKE_DEFAULT_USERNAME="$FLAKE_DEFAULT_USERNAME"
FLAKE_GENERATE_HOME="$FLAKE_GENERATE_HOME"
FLAKE_USE_DISKO="$FLAKE_USE_DISKO"
FLAKE_STATE_VERSION="$FLAKE_STATE_VERSION"
FLAKE_SYSTEM="$FLAKE_SYSTEM"
EOF
}

# If run directly, show current config or detect structure
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-show}" in
        detect)
            auto_configure_structure "${2:-$FLAKE_ROOT}"
            ;;
        validate)
            validate_flake_structure "${2:-$FLAKE_ROOT}"
            ;;
        show)
            echo "Current configuration:"
            echo "  FLAKE_HOSTS_DIR=$FLAKE_HOSTS_DIR"
            echo "  FLAKE_PROFILES_DIR=$FLAKE_PROFILES_DIR"
            echo "  FLAKE_HOME_DIR=$FLAKE_HOME_DIR"
            echo "  FLAKE_PROFILE_IMPORT_PATTERN=$FLAKE_PROFILE_IMPORT_PATTERN"
            echo "  FLAKE_GENERATE_HOME=$FLAKE_GENERATE_HOME"
            echo "  FLAKE_USE_DISKO=$FLAKE_USE_DISKO"
            ;;
        save)
            save_config "${2:-installer.conf}"
            echo "Configuration saved to ${2:-installer.conf}"
            ;;
        *)
            echo "Usage: $0 {detect|validate|show|save} [path/file]"
            ;;
    esac
fi
