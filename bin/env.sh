#!/usr/bin/env bash
# ==============================================================================
# Portable Environment & Path Initializer
# Ensures 100% portable, isolated execution inside the script directory.
# ==============================================================================

# Determine base repository directory
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
CURRENT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
if [[ "$(basename "$CURRENT_DIR")" == "bin" ]]; then
    BASE_DIR="$(cd "$CURRENT_DIR/.." && pwd)"
else
    BASE_DIR="$CURRENT_DIR"
fi
BIN_DIR="$BASE_DIR/bin"

# Define portable sub-directories
export BASE_DIR
export BIN_DIR
export SDK_DIR="$BASE_DIR/sdk"
export DATA_DIR="$BASE_DIR/data"
export CONFIG_DIR="$BASE_DIR/config"
export KERNELS_DIR="$BASE_DIR/kernels"
export SHARED_DIR="$BASE_DIR/shared"
export SHARED_TO_DEVICE="$SHARED_DIR/to_device"
export SHARED_FROM_DEVICE="$SHARED_DIR/from_device"
export JDK_DIR="$BASE_DIR/jdk"
export LOGS_DIR="$BASE_DIR/logs"

# Ensure all portable directories exist
mkdir -p "$SDK_DIR" \
         "$DATA_DIR/.android" \
         "$DATA_DIR/avd" \
         "$KERNELS_DIR" \
         "$SHARED_TO_DEVICE" \
         "$SHARED_FROM_DEVICE" \
         "$LOGS_DIR"

# ==============================================================================
# Isolate Android SDK & AVD Environment Variables
# Prevent any contamination of ~/.android or global host configuration
# ==============================================================================
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
export ANDROID_USER_HOME="$DATA_DIR/.android"
export ANDROID_AVD_HOME="$DATA_DIR/avd"
export ANDROID_EMULATOR_HOME="$DATA_DIR/.android"
export ANDROID_PREFS_ROOT="$DATA_DIR"

# Prevent adb from using system keys by isolating adb vendor/keys
export ADB_VENDOR_KEYS="$DATA_DIR/.android"

# Export portable SDK tools to PATH
export PATH="$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/emulator:$SDK_DIR/platform-tools:$PATH"

# Setup portable Java if present
if [[ -d "$JDK_DIR" && -x "$JDK_DIR/bin/java" ]]; then
    export JAVA_HOME="$JDK_DIR"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Load user settings if file exists
if [[ -f "$CONFIG_DIR/settings.conf" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_DIR/settings.conf"
fi

# ==============================================================================
# Portable Relocatability Fix
# Whenever the portable folder is moved or copied to a different path/machine,
# avdmanager .ini files contain stale absolute paths. This dynamically fixes them.
# ==============================================================================
fix_avd_portable_paths() {
    if [[ -d "$ANDROID_AVD_HOME" ]]; then
        for ini_file in "$ANDROID_AVD_HOME"/*.ini; do
            [[ -e "$ini_file" ]] || continue
            local avd_basename
            avd_basename="$(basename "$ini_file" .ini)"
            local target_avd_dir="$ANDROID_AVD_HOME/${avd_basename}.avd"
            if [[ -d "$target_avd_dir" ]]; then
                # Update path entry in .ini to current location
                sed -i -E "s|^path=.*|path=${target_avd_dir}|g" "$ini_file"
            fi
        done
    fi
}

# ==============================================================================
# Container & Device Permissions Fix (KVM and Intel iGPU)
# In Docker / Selkies containers, non-root users (like 'abc') cannot access /dev/kvm
# or /dev/dri unless permissions are unlocked or root runs.
# ==============================================================================
fix_device_permissions() {
    if [[ "$EUID" -eq 0 ]]; then
        if [[ -e /dev/kvm ]]; then
            chmod 666 /dev/kvm 2>/dev/null || true
        fi
        if [[ -d /dev/dri ]]; then
            chmod -R 666 /dev/dri 2>/dev/null || true
        fi
        # If user 'abc' exists (LinuxServer Selkies base image), grant group memberships
        if id "abc" >/dev/null 2>&1; then
            for grp in kvm render video; do
                if getent group "$grp" >/dev/null 2>&1; then
                    usermod -aG "$grp" abc 2>/dev/null || true
                fi
            done
        fi
    fi
}

# Run the relocatability fix and device permissions fix on load
fix_avd_portable_paths
fix_device_permissions

# ==============================================================================
# ANSI Color & Logger Formatting Helpers
# ==============================================================================
if [[ -t 1 ]]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_DIM="\033[2m"
    COLOR_RED="\033[1;31m"
    COLOR_GREEN="\033[1;32m"
    COLOR_YELLOW="\033[1;33m"
    COLOR_BLUE="\033[1;34m"
    COLOR_MAGENTA="\033[1;35m"
    COLOR_CYAN="\033[1;36m"
    COLOR_WHITE="\033[1;37m"
    COLOR_BG_BLUE="\033[44m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_WHITE=""
    COLOR_BG_BLUE=""
fi

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*"
}

log_err() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_step() {
    echo -e "\n${COLOR_CYAN}==>${COLOR_RESET} ${COLOR_BOLD}$*${COLOR_RESET}"
}
