#!/usr/bin/env bash
# Common utilities and helper functions for Jito validator automation

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Root directory of the project (only set if not already defined)
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# Default paths
KEYS_DIR="${PROJECT_ROOT}/keys"
LOGS_DIR="${PROJECT_ROOT}/logs"
CONFIG_DIR="${PROJECT_ROOT}/config"
STATE_FILE="${PROJECT_ROOT}/deployment.state"

# Log file setup
LOG_FILE="${LOG_FILE:-${LOGS_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log}"

# Create log directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# ============================================================================
# Colors using tput (portable across terminals)
# ============================================================================

if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    GRAY=$(tput setaf 8)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    # Fallback to no colors if tput unavailable
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" GRAY="" BOLD="" RESET=""
fi

# ============================================================================
# Logging Functions
# ============================================================================

_log() {
    local level=$1
    local color=$2
    shift 2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${color}[${timestamp}] [${level}]${RESET} ${*:-}" | tee -a "$LOG_FILE"
}

log_debug() {
    [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] && _log "DEBUG" "$GRAY" "$@"
    return 0
}

log_info() {
    _log "INFO" "$BLUE" "$@"
}

log_success() {
    _log "SUCCESS" "$GREEN" "$@"
}

log_warn() {
    _log "WARN" "$YELLOW" "$@"
}

log_error() {
    _log "ERROR" "$RED" "$@" >&2
}

log_section() {
    local message=$1
    echo ""
    echo "${BOLD}${CYAN}========================================${RESET}" | tee -a "$LOG_FILE"
    echo "${BOLD}${CYAN}  $message${RESET}" | tee -a "$LOG_FILE"
    echo "${BOLD}${CYAN}========================================${RESET}" | tee -a "$LOG_FILE"
    echo ""
}

# ============================================================================
# Dependency Checking
# ============================================================================

check_command() {
    local cmd=$1
    local install_hint=${2:-""}

    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        if [[ -n "$install_hint" ]]; then
            log_info "Install with: $install_hint"
        fi
        return 1
    fi
    log_debug "Found command: $cmd"
    return 0
}

check_dependencies() {
    local deps=("$@")
    local missing=()

    log_info "Checking dependencies..."

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
            log_error "Missing dependency: $dep"
        else
            log_debug "✓ $dep"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing ${#missing[@]} required dependencies"
        return 1
    fi

    log_success "All dependencies found"
    return 0
}

# ============================================================================
# Configuration Loading
# ============================================================================

load_config() {
    local config_file=$1

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    log_debug "Loading configuration from: $config_file"

    # Source the config file
    # shellcheck disable=SC1090
    source "$config_file"

    log_debug "Configuration loaded successfully"
    return 0
}

validate_config() {
    local required_vars=("$@")
    local missing=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
            log_error "Required configuration variable not set: $var"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing ${#missing[@]} required configuration variables"
        return 1
    fi

    return 0
}

# ============================================================================
# User Interaction
# ============================================================================

prompt_confirmation() {
    local message=$1
    local default=${2:-"n"}

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -n "${YELLOW}${message} ${prompt}:${RESET} "
    read -r response

    # Use default if empty response
    response=${response:-$default}

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

prompt_input() {
    local message=$1
    local default=${2:-""}
    local var_name=$3

    if [[ -n "$default" ]]; then
        echo -n "${CYAN}${message} [${default}]:${RESET} "
    else
        echo -n "${CYAN}${message}:${RESET} "
    fi

    read -r response
    response=${response:-$default}

    if [[ -n "$var_name" ]]; then
        eval "$var_name='$response'"
    fi

    echo "$response"
}

# ============================================================================
# Retry Logic
# ============================================================================

retry_command() {
    local max_attempts=${1:-3}
    local delay=${2:-5}
    shift 2
    local cmd=("$@")

    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}"

        if "${cmd[@]}"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Command failed, retrying in ${delay}s..."
            sleep "$delay"
            # Exponential backoff
            delay=$((delay * 2))
        fi

        attempt=$((attempt + 1))
    done

    log_error "Command failed after $max_attempts attempts"
    return 1
}

# ============================================================================
# SSH Helper
# ============================================================================

ssh_exec() {
    local host=$1
    local ssh_key=$2
    shift 2
    local cmd="$*"

    log_debug "Executing on $host: $cmd"

    # SSH with common options
    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$host" \
        "$cmd"
}

ssh_exec_script() {
    local host=$1
    local ssh_key=$2
    local script=$3

    log_debug "Executing script on $host: $script"

    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$host" \
        'bash -s' < "$script"
}

# ============================================================================
# State Management
# ============================================================================

save_state() {
    local key=$1
    local value=$2

    # Create empty state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{}' > "$STATE_FILE"
    fi

    # Update state using jq
    local temp_file
    temp_file=$(mktemp)

    jq --arg key "$key" --arg value "$value" \
        'setpath($key | split("."); $value)' \
        "$STATE_FILE" > "$temp_file"

    mv "$temp_file" "$STATE_FILE"

    log_debug "Saved state: $key = $value"
}

get_state() {
    local key=$1
    local default=${2:-""}

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "$default"
        return
    fi

    local value
    value=$(jq -r --arg key "$key" 'getpath($key | split(".")) // ""' "$STATE_FILE")

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# ============================================================================
# File Operations
# ============================================================================

ensure_directory() {
    local dir=$1

    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

backup_file() {
    local file=$1

    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "Backing up $file to $backup"
        cp "$file" "$backup"
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_ip() {
    local ip=$1
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ $ip =~ $ip_regex ]]; then
        return 0
    else
        return 1
    fi
}

validate_pubkey() {
    local pubkey=$1

    # Solana pubkeys are base58 encoded, typically 32-44 characters
    if [[ ${#pubkey} -ge 32 && ${#pubkey} -le 44 ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Time/Cost Tracking
# ============================================================================

start_timer() {
    echo "$(date +%s)"
}

end_timer() {
    local start_time=$1
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))

    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

calculate_cost() {
    local hours=$1
    local hourly_rate=${2:-0.8064}  # Default to m7i.4xlarge rate

    local cost
    cost=$(echo "$hours * $hourly_rate" | bc -l)
    printf "%.2f" "$cost"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code: $exit_code"
    fi
}

trap cleanup_on_exit EXIT

# ============================================================================
# Banner
# ============================================================================

print_banner() {
    cat << "EOF"
     _ _ _          ____        _
    | (_) |_ ___   | __ )  ___ | |_
 _  | | | __/ _ \  |  _ \ / _ \| __|
| |_| | | || (_) | | |_) | (_) | |_
 \___/|_|\__\___/  |____/ \___/ \__|

    Jito-Solana Validator Automation
EOF
}

# ============================================================================
# Exports
# ============================================================================

# Mark as loaded to prevent multiple sourcing
COMMON_LIB_LOADED=1

# Make these variables available to scripts that source this file
export PROJECT_ROOT KEYS_DIR LOGS_DIR CONFIG_DIR STATE_FILE LOG_FILE
export RED GREEN YELLOW BLUE MAGENTA CYAN GRAY BOLD RESET COMMON_LIB_LOADED
