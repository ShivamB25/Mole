#!/bin/bash
# Mole - Terminal Control Utilities
# Consolidated terminal control functions: screen management, TTY state, ANSI helpers
# This module extracts common patterns from menu_simple.sh, menu_paginated.sh, and clean/project.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_UI_TERMINAL_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_UI_TERMINAL_LOADED=1

# Ensure base.sh is loaded for colors (ui_terminal.sh is a low-level module)
_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_BASE_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/base.sh"

# ============================================================================
# ANSI Escape Sequences (Constants)
# ============================================================================
readonly ANSI_CLEAR_LINE=$'\r\033[2K'
readonly ANSI_CLEAR_SCREEN=$'\033[2J\033[H'
readonly ANSI_CURSOR_HOME=$'\033[H'
readonly ANSI_HIDE_CURSOR=$'\033[?25l'
readonly ANSI_SHOW_CURSOR=$'\033[?25h'

# ============================================================================
# Basic Cursor Control (moved from ui.sh to break dependency cycle)
# ============================================================================

# Clear entire screen and move cursor to home position
clear_screen() { printf '%s' "$ANSI_CLEAR_SCREEN"; }

# Hide cursor (useful during menu rendering to prevent flicker)
hide_cursor() { [[ -t 1 ]] && printf '%s' "$ANSI_HIDE_CURSOR" >&2 || true; }

# Show cursor (must be called before exit to restore terminal state)
show_cursor() { [[ -t 1 ]] && printf '%s' "$ANSI_SHOW_CURSOR" >&2 || true; }

# ============================================================================
# Alternative Screen Mode
# ============================================================================

# Enter alternative screen buffer (preserves main screen content)
terminal_enter_alt_screen() {
    if command -v tput > /dev/null 2>&1 && [[ -t 1 ]]; then
        tput smcup 2> /dev/null || true
    fi
}

# Leave alternative screen buffer (restores main screen content)
terminal_leave_alt_screen() {
    if command -v tput > /dev/null 2>&1 && [[ -t 1 ]]; then
        tput rmcup 2> /dev/null || true
    fi
}

# ============================================================================
# Terminal Dimensions
# ============================================================================

# Get terminal height with reliable fallback chain
# Returns: integer height (minimum 24)
terminal_get_height() {
    local height=0

    # Try stty size first (most reliable, real-time)
    # Use </dev/tty to ensure we read from terminal even if stdin is redirected
    if [[ -t 0 ]] || [[ -t 2 ]]; then
        height=$(stty size < /dev/tty 2> /dev/null | awk '{print $1}')
    fi

    # Fallback to tput
    if [[ -z "$height" || $height -le 0 ]]; then
        if command -v tput > /dev/null 2>&1; then
            height=$(tput lines 2> /dev/null || echo "24")
        else
            height=24
        fi
    fi

    echo "$height"
}

# Get terminal width with reliable fallback chain
# Returns: integer width (minimum 80)
terminal_get_width() {
    local width="${COLUMNS:-}"

    if [[ -z "$width" || $width -le 0 ]]; then
        if command -v tput > /dev/null 2>&1; then
            width=$(tput cols 2> /dev/null || echo "80")
        else
            width=80
        fi
    fi

    echo "$width"
}

# Calculate items per page based on terminal height
# Args: $1 - reserved lines for header/footer (default: 6)
# Returns: integer items per page (minimum 1, maximum 50)
terminal_calculate_items_per_page() {
    local reserved="${1:-6}"
    local term_height
    term_height=$(terminal_get_height)
    local available=$((term_height - reserved))

    # Ensure minimum and maximum bounds
    if [[ $available -lt 1 ]]; then
        echo 1
    elif [[ $available -gt 50 ]]; then
        echo 50
    else
        echo "$available"
    fi
}

# ============================================================================
# TTY State Management
# ============================================================================

# Global variable to store original TTY state
MOLE_ORIGINAL_STTY=""

# Save current TTY state for later restoration
# Call this before modifying terminal settings
terminal_save_state() {
    if [[ -t 0 ]] && command -v stty > /dev/null 2>&1; then
        MOLE_ORIGINAL_STTY=$(stty -g 2> /dev/null || echo "")
    fi
}

# Setup terminal for interactive menu (raw mode)
# Args: $1 - whether to use alt screen ("true" or "false", default "true")
terminal_setup_interactive() {
    local use_alt_screen="${1:-true}"

    terminal_save_state

    # Setup raw mode: no echo, no canonical mode, preserve interrupt
    stty -echo -icanon intr ^C 2> /dev/null || true

    # Enter alt screen if requested
    if [[ "$use_alt_screen" == "true" ]]; then
        terminal_enter_alt_screen
        printf "%s" "$ANSI_CLEAR_SCREEN" >&2
    else
        printf "%s" "$ANSI_CURSOR_HOME" >&2
    fi

    hide_cursor
}

# Restore terminal to normal state
# Args: $1 - whether alt screen was used ("true" or "false", default "true")
terminal_restore() {
    local used_alt_screen="${1:-true}"

    show_cursor

    if [[ -n "${MOLE_ORIGINAL_STTY:-}" ]]; then
        stty "${MOLE_ORIGINAL_STTY}" 2> /dev/null || \
            stty sane 2> /dev/null || \
            stty echo icanon 2> /dev/null || true
    else
        stty sane 2> /dev/null || stty echo icanon 2> /dev/null || true
    fi

    if [[ "$used_alt_screen" == "true" ]]; then
        terminal_leave_alt_screen
    fi
}

# ============================================================================
# ANSI Output Helpers
# ============================================================================

# Print a line with clear-to-end (for menu rendering)
# Args: $1 - format string, $@ - printf arguments
# Output: to stderr
print_cleared_line() {
    local format="$1"
    shift
    printf "${ANSI_CLEAR_LINE}${format}\n" "$@" >&2
}

# Print text without newline with clear-to-end
# Args: $1 - format string, $@ - printf arguments
# Output: to stderr
print_cleared() {
    local format="$1"
    shift
    printf "${ANSI_CLEAR_LINE}${format}" "$@" >&2
}

# Move cursor to home position
cursor_home() {
    printf "%s" "$ANSI_CURSOR_HOME" >&2
}

# Clear entire screen and move cursor to home
screen_clear() {
    printf "%s" "$ANSI_CLEAR_SCREEN" >&2
}

# ============================================================================
# Menu Item Rendering
# ============================================================================

# Render a menu item with checkbox and optional selection indicator
# Args: $1 - item text
#       $2 - is_selected ("true" or "false")
#       $3 - is_current ("true" or "false")
#       $4 - checkbox style: "circle" (default), "square", "none"
# Output: to stderr
render_menu_item() {
    local text="$1"
    local is_selected="${2:-false}"
    local is_current="${3:-false}"
    local checkbox_style="${4:-circle}"

    local checkbox=""
    case "$checkbox_style" in
        circle)
            if [[ "$is_selected" == "true" ]]; then
                checkbox="$ICON_SOLID"
            else
                checkbox="$ICON_EMPTY"
            fi
            ;;
        square)
            if [[ "$is_selected" == "true" ]]; then
                checkbox="[x]"
            else
                checkbox="[ ]"
            fi
            ;;
        none)
            checkbox=""
            ;;
    esac

    if [[ "$is_current" == "true" ]]; then
        if [[ -n "$checkbox" ]]; then
            print_cleared_line "${CYAN}${ICON_ARROW} %s %s${NC}" "$checkbox" "$text"
        else
            print_cleared_line "${CYAN}${ICON_ARROW} %s${NC}" "$text"
        fi
    else
        if [[ -n "$checkbox" ]]; then
            print_cleared_line "  %s %s" "$checkbox" "$text"
        else
            print_cleared_line "  %s" "$text"
        fi
    fi
}

# ============================================================================
# Selection Array Helpers
# ============================================================================

# Initialize a selection array with all items set to false
# Args: $1 - total item count
#       $2 - name of array variable to populate
# Usage: declare -a selected; init_selection_array 10 selected
init_selection_array() {
    local count="$1"
    local -n arr="$2"
    local i
    for ((i = 0; i < count; i++)); do
        arr[i]=false
    done
}

# Apply preselected indices to a selection array
# Args: $1 - comma-separated indices (e.g., "0,2,5")
#       $2 - name of selection array
#       $3 - total item count
# Usage: apply_preselection "0,2,5" selected 10
apply_preselection() {
    local indices_csv="$1"
    local -n arr="$2"
    local total="$3"

    [[ -z "$indices_csv" ]] && return 0

    local cleaned="${indices_csv//[[:space:]]/}"
    local -a indices
    IFS=',' read -ra indices <<< "$cleaned"

    for idx in "${indices[@]}"; do
        if [[ "$idx" =~ ^[0-9]+$ && $idx -ge 0 && $idx -lt $total ]]; then
            arr[idx]=true
        fi
    done
}

# Count selected items in a selection array
# Args: $1 - name of selection array
#       $2 - total item count
# Returns: count of selected items
count_selected() {
    local -n arr="$1"
    local total="$2"
    local count=0
    local i

    for ((i = 0; i < total; i++)); do
        [[ "${arr[i]:-false}" == "true" ]] && ((count++))
    done

    echo "$count"
}

# Get indices of selected items as comma-separated string
# Args: $1 - name of selection array
#       $2 - total item count
# Returns: comma-separated indices (e.g., "0,2,5")
get_selected_indices() {
    local -n arr="$1"
    local total="$2"
    local result=""
    local i

    for ((i = 0; i < total; i++)); do
        if [[ "${arr[i]:-false}" == "true" ]]; then
            [[ -n "$result" ]] && result+=","
            result+="$i"
        fi
    done

    echo "$result"
}

# ============================================================================
# Cursor Position Management
# ============================================================================

# Clamp cursor position within visible range
# Args: $1 - current cursor position
#       $2 - visible item count
# Returns: clamped cursor position
clamp_cursor() {
    local cursor="$1"
    local visible="$2"

    if [[ $visible -le 0 ]]; then
        echo 0
        return
    fi

    if [[ $cursor -ge $visible ]]; then
        cursor=$((visible - 1))
    fi

    if [[ $cursor -lt 0 ]]; then
        cursor=0
    fi

    echo "$cursor"
}

# ============================================================================
# Trap and Cleanup Helpers
# ============================================================================

# Standard cleanup handler for menu functions
# Args: $1 - whether alt screen was used ("true" or "false")
# Usage: trap 'menu_cleanup true' EXIT
menu_cleanup() {
    local used_alt_screen="${1:-true}"
    trap - EXIT INT TERM
    terminal_restore "$used_alt_screen"
    unset MOLE_READ_KEY_FORCE_CHAR 2> /dev/null || true
}

# Standard interrupt handler
# Usage: trap 'menu_interrupt_handler' INT TERM
menu_interrupt_handler() {
    menu_cleanup "${MOLE_MENU_ALT_SCREEN:-true}"
    exit 130
}

# Setup standard menu traps
# Args: $1 - whether using alt screen ("true" or "false")
setup_menu_traps() {
    local use_alt_screen="${1:-true}"
    export MOLE_MENU_ALT_SCREEN="$use_alt_screen"
    trap 'menu_cleanup "$MOLE_MENU_ALT_SCREEN"' EXIT
    trap 'menu_interrupt_handler' INT TERM
}

# ============================================================================
# Footer Rendering
# ============================================================================

# Strip ANSI codes and calculate display length
# Args: $1 - text with potential ANSI codes
# Returns: visible character count
strip_ansi_length() {
    local text="$1"
    local stripped
    stripped=$(printf "%s" "$text" | LC_ALL=C awk '{gsub(/\033\[[0-9;]*[A-Za-z]/,""); print}')
    printf "%d" "${#stripped}"
}

# Print footer controls with intelligent wrapping
# Args: $1 - separator (e.g., " | ")
#       $@ - control segments
# Output: to stderr
print_footer_controls() {
    local sep="$1"
    shift
    local -a segs=("$@")

    local cols
    cols=$(terminal_get_width)

    local line="" s candidate
    for s in "${segs[@]}"; do
        if [[ -z "$line" ]]; then
            candidate="$s"
        else
            candidate="$line${sep}${s}"
        fi
        if (( $(strip_ansi_length "$candidate") > cols )); then
            print_cleared_line "%s" "$line"
            line="$s"
        else
            line="$candidate"
        fi
    done
    print_cleared_line "%s" "$line"
}
