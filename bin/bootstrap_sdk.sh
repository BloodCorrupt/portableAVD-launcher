#!/usr/bin/env bash
# ==============================================================================
# Android SDK Bootstrapper
# Automatically downloads cmdline-tools, platform-tools, emulator, and accepts licenses.
# All components are strictly isolated inside the portable directory.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/env.sh"
# shellcheck source=bin/java_setup.sh
source "$SCRIPT_DIR/java_setup.sh"

# Official Google commandlinetools package for Linux (11076708 is cmdline-tools v13.0)
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

check_kvm() {
    log_step "Checking Hardware Virtualization (KVM)"
    if [[ ! -e /dev/kvm ]]; then
        log_warn "/dev/kvm device node not found!"
        log_warn "Hardware acceleration (KVM) might be disabled in BIOS/UEFI or kernel module not loaded."
        log_warn "Run: 'sudo modprobe kvm' and 'sudo modprobe kvm_intel' (or kvm_amd)"
        return 1
    elif [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        log_warn "Cannot read/write to /dev/kvm!"
        log_warn "Your user may not have permission to access KVM."
        log_warn "Fix this by adding your user to the kvm group:"
        log_warn "  sudo usermod -aG kvm \$USER"
        log_warn "  (Log out and log back in for changes to take effect)"
        return 1
    else
        log_success "KVM acceleration is available and accessible (/dev/kvm)!"
        return 0
    fi
}

install_cmdline_tools() {
    local sdkmanager_bin="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
    if [[ -x "$sdkmanager_bin" ]]; then
        log_info "Android command-line tools already installed."
        return 0
    fi

    log_step "Downloading Android Command-Line Tools..."

    # Ensure unzip is available
    if ! command -v unzip >/dev/null 2>&1; then
        log_err "'unzip' utility is required to extract Android SDK tools. Please install unzip."
        return 1
    fi

    local zip_file="$DATA_DIR/cmdline-tools.zip"
    mkdir -p "$DATA_DIR"

    if command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$zip_file" "$CMDLINE_TOOLS_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$zip_file" "$CMDLINE_TOOLS_URL"
    else
        log_err "Neither curl nor wget found. Cannot download command-line tools."
        return 1
    fi

    if [[ ! -s "$zip_file" ]]; then
        log_err "Downloaded file is empty or missing."
        rm -f "$zip_file"
        return 1
    fi

    log_info "Extracting command-line tools..."
    local temp_extract="$DATA_DIR/temp_cmdline"
    rm -rf "$temp_extract"
    mkdir -p "$temp_extract"
    unzip -q "$zip_file" -d "$temp_extract"
    rm -f "$zip_file"

    # Android SDK requires directory structure: $SDK_DIR/cmdline-tools/latest/
    mkdir -p "$SDK_DIR/cmdline-tools"
    rm -rf "$SDK_DIR/cmdline-tools/latest"
    if [[ -d "$temp_extract/cmdline-tools" ]]; then
        mv "$temp_extract/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
    else
        mv "$temp_extract" "$SDK_DIR/cmdline-tools/latest"
    fi
    rm -rf "$temp_extract"

    if [[ -x "$sdkmanager_bin" ]]; then
        log_success "Command-line tools installed at: $SDK_DIR/cmdline-tools/latest"
    else
        log_err "Failed to install cmdline-tools. File not found: $sdkmanager_bin"
        return 1
    fi
}

accept_licenses() {
    log_info "Accepting Android SDK licenses..."
    local sdkmanager_bin="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
    if [[ -x "$sdkmanager_bin" ]]; then
        yes 2>/dev/null | "$sdkmanager_bin" --licenses >/dev/null 2>&1 || true
        log_success "SDK licenses accepted."
    fi
}

install_core_packages() {
    local sdkmanager_bin="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
    local needs_install=false

    if [[ ! -x "$SDK_DIR/platform-tools/adb" ]]; then
        needs_install=true
    fi

    if [[ ! -x "$SDK_DIR/emulator/emulator" ]]; then
        needs_install=true
    fi

    if [[ "$needs_install" == true ]]; then
        log_step "Installing core SDK components: platform-tools & emulator..."
        "$sdkmanager_bin" --install "platform-tools" "emulator"
        accept_licenses
    else
        log_info "Core packages (platform-tools, emulator) are already installed."
    fi
}

bootstrap_all() {
    ensure_java || return 1
    install_cmdline_tools || return 1
    accept_licenses || return 1
    install_core_packages || return 1
    check_kvm || true
    log_success "SDK bootstrap completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bootstrap_all
fi
