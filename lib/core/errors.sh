#!/bin/bash
# Mole - Standardized Error Handling
# Consistent error handling patterns across all Shell modules

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_ERRORS_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_ERRORS_LOADED=1

# Ensure base.sh is loaded for colors
_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_BASE_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/base.sh"
[[ -z "${MOLE_LOG_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/log.sh"

# ============================================================================
# Error Codes (Standardized across all modules)
# ============================================================================
readonly MOLE_ERR_SUCCESS=0
readonly MOLE_ERR_GENERAL=1
readonly MOLE_ERR_INVALID_ARG=2
readonly MOLE_ERR_FILE_NOT_FOUND=3
readonly MOLE_ERR_PERMISSION_DENIED=4
readonly MOLE_ERR_COMMAND_FAILED=5
readonly MOLE_ERR_TIMEOUT=6
readonly MOLE_ERR_NETWORK=7
readonly MOLE_ERR_DEPENDENCY=8
readonly MOLE_ERR_USER_CANCELLED=130

# ============================================================================
# Error Context (for detailed error messages)
# ============================================================================
MOLE_LAST_ERROR=""
MOLE_LAST_ERROR_CODE=0
MOLE_LAST_ERROR_FILE=""
MOLE_LAST_ERROR_LINE=""
MOLE_LAST_ERROR_FUNC=""

# ============================================================================
# Core Error Functions
# ============================================================================

# Set error context (call before operations that might fail)
# Args: $1 - operation description
set_error_context() {
    MOLE_LAST_ERROR_FUNC="${FUNCNAME[1]:-unknown}"
    MOLE_LAST_ERROR_FILE="${BASH_SOURCE[1]:-unknown}"
    MOLE_LAST_ERROR_LINE="${BASH_LINENO[0]:-0}"
}

# Record an error with full context
# Args: $1 - error message
#       $2 - error code (optional, default: MOLE_ERR_GENERAL)
record_error() {
    local message="$1"
    local code="${2:-$MOLE_ERR_GENERAL}"

    MOLE_LAST_ERROR="$message"
    MOLE_LAST_ERROR_CODE="$code"
    MOLE_LAST_ERROR_FUNC="${FUNCNAME[1]:-unknown}"
    MOLE_LAST_ERROR_FILE="${BASH_SOURCE[1]:-unknown}"
    MOLE_LAST_ERROR_LINE="${BASH_LINENO[0]:-0}"

    # Log error if debug mode is enabled
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_log "ERROR[$code] in ${MOLE_LAST_ERROR_FUNC}() at ${MOLE_LAST_ERROR_FILE}:${MOLE_LAST_ERROR_LINE}: $message"
    fi
}

# Get the last error message
get_last_error() {
    echo "$MOLE_LAST_ERROR"
}

# Get the last error code
get_last_error_code() {
    echo "$MOLE_LAST_ERROR_CODE"
}

# Clear error state
clear_error() {
    MOLE_LAST_ERROR=""
    MOLE_LAST_ERROR_CODE=0
    MOLE_LAST_ERROR_FILE=""
    MOLE_LAST_ERROR_LINE=""
    MOLE_LAST_ERROR_FUNC=""
}

# ============================================================================
# Error Handling Wrappers
# ============================================================================

# Execute command and handle errors gracefully
# Args: $1 - error message on failure
#       $@ - command to execute
# Returns: command exit code
# Usage: try_cmd "Failed to remove file" rm -f "$file"
try_cmd() {
    local error_msg="$1"
    shift

    set_error_context

    if ! "$@" 2>/dev/null; then
        local exit_code=$?
        record_error "$error_msg" "$exit_code"
        return "$exit_code"
    fi

    return 0
}

# Execute command silently, ignoring errors
# This is explicit about ignoring errors (better than `|| true` scattered everywhere)
# Args: $@ - command to execute
# Returns: always 0
ignore_errors() {
    "$@" 2>/dev/null || true
}

# Execute command with timeout and error handling
# Args: $1 - timeout in seconds
#       $2 - error message on failure
#       $@ - command to execute
# Returns: command exit code or MOLE_ERR_TIMEOUT
try_cmd_timeout() {
    local timeout_secs="$1"
    local error_msg="$2"
    shift 2

    set_error_context

    local timeout_bin="${MOLE_TIMEOUT_BIN:-}"
    local exit_code=0

    if [[ -n "$timeout_bin" ]]; then
        if ! "$timeout_bin" "$timeout_secs" "$@" 2>/dev/null; then
            exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                record_error "Timeout: $error_msg" "$MOLE_ERR_TIMEOUT"
                return "$MOLE_ERR_TIMEOUT"
            else
                record_error "$error_msg" "$exit_code"
                return "$exit_code"
            fi
        fi
    else
        if ! "$@" 2>/dev/null; then
            exit_code=$?
            record_error "$error_msg" "$exit_code"
            return "$exit_code"
        fi
    fi

    return 0
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate that a file exists
# Args: $1 - file path
#       $2 - description (optional)
# Returns: 0 if exists, MOLE_ERR_FILE_NOT_FOUND otherwise
require_file() {
    local filepath="$1"
    local description="${2:-file}"

    if [[ ! -f "$filepath" ]]; then
        record_error "Required $description not found: $filepath" "$MOLE_ERR_FILE_NOT_FOUND"
        return "$MOLE_ERR_FILE_NOT_FOUND"
    fi
    return 0
}

# Validate that a directory exists
# Args: $1 - directory path
#       $2 - description (optional)
# Returns: 0 if exists, MOLE_ERR_FILE_NOT_FOUND otherwise
require_dir() {
    local dirpath="$1"
    local description="${2:-directory}"

    if [[ ! -d "$dirpath" ]]; then
        record_error "Required $description not found: $dirpath" "$MOLE_ERR_FILE_NOT_FOUND"
        return "$MOLE_ERR_FILE_NOT_FOUND"
    fi
    return 0
}

# Validate that a command exists
# Args: $1 - command name
#       $2 - package/install hint (optional)
# Returns: 0 if exists, MOLE_ERR_DEPENDENCY otherwise
require_command() {
    local cmd="$1"
    local hint="${2:-}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        local msg="Required command not found: $cmd"
        [[ -n "$hint" ]] && msg+=". Install with: $hint"
        record_error "$msg" "$MOLE_ERR_DEPENDENCY"
        return "$MOLE_ERR_DEPENDENCY"
    fi
    return 0
}

# Validate that we have write permission to a path
# Args: $1 - path to check
# Returns: 0 if writable, MOLE_ERR_PERMISSION_DENIED otherwise
require_writable() {
    local path="$1"

    if [[ ! -w "$path" ]]; then
        record_error "Permission denied: cannot write to $path" "$MOLE_ERR_PERMISSION_DENIED"
        return "$MOLE_ERR_PERMISSION_DENIED"
    fi
    return 0
}

# ============================================================================
# Safe Operation Wrappers
# ============================================================================

# Safe file removal with error handling
# Args: $1 - file path
# Returns: 0 on success, error code on failure
safe_rm() {
    local filepath="$1"

    [[ ! -e "$filepath" ]] && return 0

    if ! rm -f "$filepath" 2>/dev/null; then
        record_error "Failed to remove file: $filepath" "$MOLE_ERR_COMMAND_FAILED"
        return "$MOLE_ERR_COMMAND_FAILED"
    fi
    return 0
}

# Safe directory removal with error handling
# Args: $1 - directory path
# Returns: 0 on success, error code on failure
safe_rmdir() {
    local dirpath="$1"

    [[ ! -d "$dirpath" ]] && return 0

    if ! rm -rf "$dirpath" 2>/dev/null; then
        record_error "Failed to remove directory: $dirpath" "$MOLE_ERR_COMMAND_FAILED"
        return "$MOLE_ERR_COMMAND_FAILED"
    fi
    return 0
}

# Safe file copy with error handling
# Args: $1 - source path
#       $2 - destination path
# Returns: 0 on success, error code on failure
safe_cp() {
    local src="$1"
    local dest="$2"

    if ! require_file "$src" "source file"; then
        return "$MOLE_ERR_FILE_NOT_FOUND"
    fi

    if ! cp "$src" "$dest" 2>/dev/null; then
        record_error "Failed to copy $src to $dest" "$MOLE_ERR_COMMAND_FAILED"
        return "$MOLE_ERR_COMMAND_FAILED"
    fi
    return 0
}

# Safe file move with error handling
# Args: $1 - source path
#       $2 - destination path
# Returns: 0 on success, error code on failure
safe_mv() {
    local src="$1"
    local dest="$2"

    if [[ ! -e "$src" ]]; then
        record_error "Source not found: $src" "$MOLE_ERR_FILE_NOT_FOUND"
        return "$MOLE_ERR_FILE_NOT_FOUND"
    fi

    if ! mv "$src" "$dest" 2>/dev/null; then
        record_error "Failed to move $src to $dest" "$MOLE_ERR_COMMAND_FAILED"
        return "$MOLE_ERR_COMMAND_FAILED"
    fi
    return 0
}

# ============================================================================
# Error Reporting
# ============================================================================

# Display error message to user
# Args: $1 - error message
#       $2 - suggestion (optional)
show_error() {
    local message="$1"
    local suggestion="${2:-}"

    echo -e "${RED}${ICON_ERROR}${NC} $message" >&2
    [[ -n "$suggestion" ]] && echo -e "  ${GRAY}$suggestion${NC}" >&2
}

# Display warning message to user
# Args: $1 - warning message
show_warning() {
    local message="$1"
    echo -e "${YELLOW}${ICON_WARNING}${NC} $message" >&2
}

# Display error with last recorded context
show_last_error() {
    if [[ -n "$MOLE_LAST_ERROR" ]]; then
        show_error "$MOLE_LAST_ERROR"
        if [[ "${MO_DEBUG:-}" == "1" ]]; then
            echo -e "  ${GRAY}at ${MOLE_LAST_ERROR_FUNC}() in ${MOLE_LAST_ERROR_FILE}:${MOLE_LAST_ERROR_LINE}${NC}" >&2
        fi
    fi
}

# ============================================================================
# Cleanup on Error
# ============================================================================

# Stack of cleanup functions to call on error
declare -a MOLE_CLEANUP_STACK=()

# Push a cleanup function onto the stack
# Args: $1 - cleanup command/function to call
push_cleanup() {
    MOLE_CLEANUP_STACK+=("$1")
}

# Pop and execute the last cleanup function
pop_cleanup() {
    if [[ ${#MOLE_CLEANUP_STACK[@]} -gt 0 ]]; then
        local last_idx=$((${#MOLE_CLEANUP_STACK[@]} - 1))
        local cleanup_cmd="${MOLE_CLEANUP_STACK[$last_idx]}"
        unset 'MOLE_CLEANUP_STACK[last_idx]'
        eval "$cleanup_cmd" 2>/dev/null || true
    fi
}

# Execute all cleanup functions (typically called on error)
run_all_cleanups() {
    while [[ ${#MOLE_CLEANUP_STACK[@]} -gt 0 ]]; do
        pop_cleanup
    done
}

# ============================================================================
# Error Handler Setup
# ============================================================================

# Global error handler (set with: trap 'global_error_handler $LINENO' ERR)
global_error_handler() {
    local lineno="$1"
    local exit_code=$?

    record_error "Command failed at line $lineno" "$exit_code"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        show_last_error
    fi

    # Run cleanups
    run_all_cleanups
}
