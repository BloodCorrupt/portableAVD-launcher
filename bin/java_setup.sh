#!/usr/bin/env bash
# ==============================================================================
# Java Runtime Detector & Portable OpenJDK Bootstrapper
# Ensures a valid Java 17+ environment is available for Android cmdline-tools.
# ==============================================================================

# Source environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/env.sh"

# Default OpenJDK 17 download URL for Linux x86_64 (Eclipse Temurin)
TEMURIN_JDK17_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12%2B7/OpenJDK17U-jdk_x64_linux_hotspot_17.0.12_7.tar.gz"

get_java_major_version() {
    local java_bin="$1"
    if [[ ! -x "$java_bin" ]]; then
        echo "0"
        return
    fi
    local ver_string
    ver_string="$("$java_bin" -version 2>&1 | awk -F '"' '/version/ {print $2}')"
    local major_ver
    major_ver="$(echo "$ver_string" | awk -F. '{if ($1 == "1") print $2; else print $1}')"
    echo "${major_ver:-0}"
}

ensure_java() {
    # 1. Check if portable JDK already exists in $JDK_DIR
    if [[ -x "$JDK_DIR/bin/java" ]]; then
        local p_ver
        p_ver="$(get_java_major_version "$JDK_DIR/bin/java")"
        if (( p_ver >= 17 )); then
            export JAVA_HOME="$JDK_DIR"
            export PATH="$JAVA_HOME/bin:$PATH"
            return 0
        fi
    fi

    # 2. Check if system java exists and is >= 17
    if command -v java >/dev/null 2>&1; then
        local sys_java
        sys_java="$(command -v java)"
        local sys_ver
        sys_ver="$(get_java_major_version "$sys_java")"
        if (( sys_ver >= 17 )); then
            log_info "Detected compatible system Java ($sys_ver): $sys_java"
            return 0
        else
            log_warn "System Java is version $sys_ver. Android SDK tools require Java 17+."
        fi
    else
        log_warn "No system Java found. Android SDK tools require Java 17+."
    fi

    # 3. Prompt or auto-download portable OpenJDK
    install_portable_jdk
}

install_portable_jdk() {
    log_step "Installing Portable OpenJDK 17 to: $JDK_DIR"

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_err "Neither curl nor wget is available to download portable Java."
        return 1
    fi

    if ! command -v tar >/dev/null 2>&1; then
        log_err "tar command is required to extract portable Java."
        return 1
    fi

    local temp_tar="$BASE_DIR/data/openjdk17.tar.gz"
    mkdir -p "$BASE_DIR/data" "$JDK_DIR"

    log_info "Downloading OpenJDK 17 binary..."
    if command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$temp_tar" "$TEMURIN_JDK17_URL"
    else
        wget -q --show-progress -O "$temp_tar" "$TEMURIN_JDK17_URL"
    fi

    if [[ ! -s "$temp_tar" ]]; then
        log_err "Failed to download OpenJDK tarball."
        rm -f "$temp_tar"
        return 1
    fi

    log_info "Extracting portable OpenJDK into $JDK_DIR..."
    rm -rf "${JDK_DIR:?}"/*
    tar -xzf "$temp_tar" -C "$JDK_DIR" --strip-components=1
    rm -f "$temp_tar"

    if [[ -x "$JDK_DIR/bin/java" ]]; then
        export JAVA_HOME="$JDK_DIR"
        export PATH="$JAVA_HOME/bin:$PATH"
        log_success "Portable OpenJDK 17 installed successfully!"
        return 0
    else
        log_err "Extraction failed: $JDK_DIR/bin/java not found."
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ensure_java
fi
