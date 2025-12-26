#!/bin/bash
# Mole - Shell/Go Interface
# Standardized communication between Shell scripts and Go binaries
# Provides a clear boundary and contract between the two components

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_GO_INTERFACE_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_GO_INTERFACE_LOADED=1

# Ensure dependencies are loaded
_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_BASE_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/base.sh"
[[ -z "${MOLE_LOG_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/log.sh"
[[ -z "${MOLE_ERRORS_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/errors.sh"

# ============================================================================
# Go Binary Paths
# ============================================================================

# Get the path to the bin directory
_get_bin_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$(dirname "$script_dir")")/bin"
}

# Cache the bin directory path
readonly MOLE_BIN_DIR="$(_get_bin_dir)"

# Known Go binaries
readonly MOLE_GO_ANALYZE="${MOLE_BIN_DIR}/analyze-go"
readonly MOLE_GO_STATUS="${MOLE_BIN_DIR}/status-go"

# ============================================================================
# Go Binary Validation
# ============================================================================

# Check if a Go binary exists and is executable
# Args: $1 - binary name (e.g., "analyze" or "status")
# Returns: 0 if valid, error code otherwise
validate_go_binary() {
    local name="$1"
    local binary_path

    case "$name" in
        analyze)
            binary_path="$MOLE_GO_ANALYZE"
            ;;
        status)
            binary_path="$MOLE_GO_STATUS"
            ;;
        *)
            record_error "Unknown Go binary: $name" "$MOLE_ERR_INVALID_ARG"
            return "$MOLE_ERR_INVALID_ARG"
            ;;
    esac

    if [[ ! -f "$binary_path" ]]; then
        record_error "Go binary not found: $binary_path" "$MOLE_ERR_FILE_NOT_FOUND"
        return "$MOLE_ERR_FILE_NOT_FOUND"
    fi

    if [[ ! -x "$binary_path" ]]; then
        record_error "Go binary not executable: $binary_path" "$MOLE_ERR_PERMISSION_DENIED"
        return "$MOLE_ERR_PERMISSION_DENIED"
    fi

    return 0
}

# ============================================================================
# Environment Variable Contract
# ============================================================================
#
# Shell -> Go environment variables:
#   MO_ANALYZE_PATH    : Path for analyze-go to scan
#   MO_DEBUG           : Enable debug mode (1 = enabled)
#   MO_DRY_RUN         : Enable dry run mode (1 = enabled)
#   MO_TIMEOUT         : Command timeout in seconds
#   MO_COLOR           : Color output (auto, always, never)
#   MO_SPINNER_CHARS   : Custom spinner characters
#
# Go -> Shell exit codes:
#   0   : Success
#   1   : General error
#   2   : Invalid arguments
#   130 : User cancelled (Ctrl+C)
#
# ============================================================================

# Set standard environment for Go binaries
# This ensures consistent configuration across all Go invocations
setup_go_environment() {
    # Propagate debug mode
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        export MO_DEBUG=1
    fi

    # Propagate dry run mode
    if [[ "${MO_DRY_RUN:-}" == "1" ]]; then
        export MO_DRY_RUN=1
    fi

    # Set color mode based on terminal
    if [[ -t 1 ]]; then
        export MO_COLOR="${MO_COLOR:-auto}"
    else
        export MO_COLOR="${MO_COLOR:-never}"
    fi

    # Set default timeout if not specified
    export MO_TIMEOUT="${MO_TIMEOUT:-300}"
}

# ============================================================================
# Go Binary Invocation
# ============================================================================

# Run the analyze-go binary
# Args: $1 - path to analyze (optional, defaults to current directory)
# Returns: exit code from analyze-go
run_analyze() {
    local target_path="${1:-$(pwd)}"

    if ! validate_go_binary "analyze"; then
        show_last_error
        return "$MOLE_LAST_ERROR_CODE"
    fi

    setup_go_environment

    # Set the path for analyze-go
    export MO_ANALYZE_PATH="$target_path"

    debug_log "Running analyze-go with path: $target_path"

    # Execute the binary
    "$MOLE_GO_ANALYZE"
    local exit_code=$?

    # Handle exit codes
    case $exit_code in
        0)
            debug_log "analyze-go completed successfully"
            ;;
        130)
            debug_log "analyze-go cancelled by user"
            ;;
        *)
            record_error "analyze-go failed with exit code $exit_code" "$exit_code"
            ;;
    esac

    return $exit_code
}

# Run the status-go binary
# Returns: exit code from status-go
run_status() {
    if ! validate_go_binary "status"; then
        show_last_error
        return "$MOLE_LAST_ERROR_CODE"
    fi

    setup_go_environment

    debug_log "Running status-go"

    # Execute the binary
    "$MOLE_GO_STATUS"
    local exit_code=$?

    # Handle exit codes
    case $exit_code in
        0)
            debug_log "status-go completed successfully"
            ;;
        130)
            debug_log "status-go cancelled by user"
            ;;
        *)
            record_error "status-go failed with exit code $exit_code" "$exit_code"
            ;;
    esac

    return $exit_code
}

# ============================================================================
# Architecture Detection (for binary selection)
# ============================================================================

# Get the appropriate architecture suffix for binaries
# Returns: architecture string (e.g., "arm64", "amd64")
get_arch_suffix() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        arm64|aarch64)
            echo "arm64"
            ;;
        x86_64|amd64)
            echo "amd64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Check if we're running on Apple Silicon
is_apple_silicon() {
    [[ "$(uname -m)" == "arm64" ]]
}

# ============================================================================
# Go Binary Version Info
# ============================================================================

# Get version of a Go binary
# Args: $1 - binary name (e.g., "analyze" or "status")
# Returns: version string or "unknown"
get_go_binary_version() {
    local name="$1"
    local binary_path

    case "$name" in
        analyze)
            binary_path="$MOLE_GO_ANALYZE"
            ;;
        status)
            binary_path="$MOLE_GO_STATUS"
            ;;
        *)
            echo "unknown"
            return
            ;;
    esac

    if [[ ! -x "$binary_path" ]]; then
        echo "not installed"
        return
    fi

    # Try to get version (Go binaries may support --version)
    local version
    version=$("$binary_path" --version 2>/dev/null || echo "")

    if [[ -n "$version" ]]; then
        echo "$version"
    else
        echo "installed"
    fi
}

# ============================================================================
# Shared Data Paths
# ============================================================================

# Get the shared cache directory for Shell/Go data exchange
get_shared_cache_dir() {
    local cache_dir="${HOME}/.cache/mole"
    mkdir -p "$cache_dir" 2>/dev/null || true
    echo "$cache_dir"
}

# Get the shared config directory
get_shared_config_dir() {
    local config_dir="${HOME}/.config/mole"
    mkdir -p "$config_dir" 2>/dev/null || true
    echo "$config_dir"
}

# ============================================================================
# Data Exchange Functions
# ============================================================================

# Write data for Go binary to read
# Args: $1 - key name
#       $2 - value
write_shared_data() {
    local key="$1"
    local value="$2"
    local data_file
    data_file="$(get_shared_cache_dir)/${key}.dat"

    echo "$value" > "$data_file" 2>/dev/null || {
        record_error "Failed to write shared data: $key" "$MOLE_ERR_COMMAND_FAILED"
        return "$MOLE_ERR_COMMAND_FAILED"
    }
}

# Read data written by Go binary
# Args: $1 - key name
# Returns: value or empty string
read_shared_data() {
    local key="$1"
    local data_file
    data_file="$(get_shared_cache_dir)/${key}.dat"

    if [[ -f "$data_file" ]]; then
        cat "$data_file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Clear shared data
# Args: $1 - key name (optional, clears all if not specified)
clear_shared_data() {
    local key="${1:-}"
    local cache_dir
    cache_dir="$(get_shared_cache_dir)"

    if [[ -n "$key" ]]; then
        rm -f "${cache_dir}/${key}.dat" 2>/dev/null || true
    else
        rm -f "${cache_dir}"/*.dat 2>/dev/null || true
    fi
}

# ============================================================================
# Health Check
# ============================================================================

# Verify all Go binaries are properly installed
# Returns: 0 if all binaries valid, 1 otherwise
verify_go_installation() {
    local all_valid=true

    if ! validate_go_binary "analyze" 2>/dev/null; then
        log_warning "analyze-go binary not available"
        all_valid=false
    fi

    if ! validate_go_binary "status" 2>/dev/null; then
        log_warning "status-go binary not available"
        all_valid=false
    fi

    if [[ "$all_valid" == "true" ]]; then
        debug_log "All Go binaries verified"
        return 0
    else
        return 1
    fi
}
