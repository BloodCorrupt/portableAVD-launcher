#!/usr/bin/env bash
# ==============================================================================
# AVD Launcher & Execution Engine
# Launches Android Virtual Devices with custom renderer (GPU / SwiftShader),
# custom kernel, granular cores & RAM, and shared folder integration.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/env.sh"
# shellcheck source=bin/bootstrap_sdk.sh
source "$SCRIPT_DIR/bootstrap_sdk.sh"
# shellcheck source=bin/file_share.sh
source "$SCRIPT_DIR/file_share.sh"
# shellcheck source=bin/avd_creator.sh
source "$SCRIPT_DIR/avd_creator.sh"

get_emulator_bin() {
    echo "$SDK_DIR/emulator/emulator"
}

# Auto-configure PulseAudio routing (especially on Selkies/Docker desktop or when run as root)
setup_audio() {
    local no_audio="$1"
    if [[ "$no_audio" == true ]]; then
        return
    fi

    # Check if PulseAudio is already responsive
    if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
        log_info "PulseAudio server detected and responsive."
        return 0
    fi

    # Probe for active PulseAudio UNIX sockets in Selkies / container desktop
    local pulse_sock=""
    for s in /run/user/*/pulse/native /tmp/pulse-*/native /var/run/pulse/native; do
        if [[ -S "$s" ]]; then
            pulse_sock="$s"
            break
        fi
    done

    if [[ -z "$pulse_sock" ]]; then
        pulse_sock="$(find /run/user /tmp /var/run -name "native" -type s 2>/dev/null | head -n 1)"
    fi

    if [[ -n "$pulse_sock" && -S "$pulse_sock" ]]; then
        log_info "Found active PulseAudio socket: $pulse_sock"
        export PULSE_SERVER="unix:$pulse_sock"

        # Search for pulse authorization cookie
        local cookie_file=""
        for c in "/config/.config/pulse/cookie" "$HOME/.config/pulse/cookie" "/home/abc/.config/pulse/cookie" /run/user/*/pulse/cookie; do
            if [[ -f "$c" ]]; then
                cookie_file="$c"
                break
            fi
        done

        if [[ -n "$cookie_file" ]]; then
            # If running as root, make sure cookie has read permission
            if [[ "$EUID" -eq 0 ]]; then
                chmod 644 "$cookie_file" 2>/dev/null || true
            fi
            export PULSE_COOKIE="$cookie_file"
            log_info "Configured PULSE_COOKIE: $cookie_file"
        fi

        if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
            log_success "PulseAudio audio successfully bridged!"
            return 0
        fi
    fi

    log_warn "PulseAudio connection could not be verified automatically."
    log_info "On Selkies desktop, you can also run launcher directly as the 'abc' user for native audio access."
}

run_avd() {
    local avd_name="$1"
    local renderer="${2:-$DEFAULT_RENDERER}"
    local cores="${3:-$DEFAULT_CORES}"
    local ram_mb="${4:-$DEFAULT_RAM_MB}"
    local custom_kernel="${5:-$DEFAULT_KERNEL}"
    local kernel_append="${6:-$DEFAULT_KERNEL_APPEND}"
    local auto_sync="${7:-$AUTO_SYNC_SHARE}"
    local headless="${8:-$HEADLESS}"
    local wipe_data="${9:-$WIPE_DATA}"
    local cold_boot="${10:-$COLD_BOOT}"
    local no_audio="${11:-${NO_AUDIO:-false}}"

    if [[ -z "$avd_name" ]]; then
        log_err "No AVD name specified."
        return 1
    fi

    local avd_ini="$ANDROID_AVD_HOME/${avd_name}.ini"
    if [[ ! -f "$avd_ini" ]]; then
        log_err "AVD '$avd_name' does not exist in $ANDROID_AVD_HOME"
        log_info "Available AVDs:"
        list_avds
        return 1
    fi

    # Fix any relocated paths
    fix_avd_portable_paths

    local emulator_bin
    emulator_bin="$(get_emulator_bin)"
    if [[ ! -x "$emulator_bin" ]]; then
        log_err "Emulator binary not found: $emulator_bin"
        bootstrap_all || return 1
    fi

    # Check /dev/kvm availability
    check_kvm || true

    # Prepare command-line arguments for emulator
    local emu_args=("-avd" "$avd_name")

    # 1. Renderer configuration
    # Valid values: host, swiftshader_indirect, angle_indirect, guest, auto, off
    case "$renderer" in
        host|swiftshader_indirect|angle_indirect|guest|auto|off)
            emu_args+=("-gpu" "$renderer")
            ;;
        swiftshader)
            emu_args+=("-gpu" "swiftshader_indirect")
            ;;
        gpu)
            emu_args+=("-gpu" "host")
            ;;
        *)
            log_warn "Unknown renderer '$renderer'. Defaulting to host."
            emu_args+=("-gpu" "host")
            ;;
    esac

    # 2. Granular CPU Cores & RAM
    if [[ -n "$cores" && "$cores" -gt 0 ]]; then
        emu_args+=("-cores" "$cores")
    fi

    if [[ -n "$ram_mb" && "$ram_mb" -gt 0 ]]; then
        emu_args+=("-memory" "$ram_mb")
    fi

    # 3. Custom Kernel configuration
    if [[ -n "$custom_kernel" ]]; then
        # Resolve path: check if relative to project or in kernels/
        local kernel_path="$custom_kernel"
        if [[ ! -f "$kernel_path" && -f "$KERNELS_DIR/$custom_kernel" ]]; then
            kernel_path="$KERNELS_DIR/$custom_kernel"
        elif [[ ! -f "$kernel_path" && -f "$BASE_DIR/$custom_kernel" ]]; then
            kernel_path="$BASE_DIR/$custom_kernel"
        fi

        if [[ -f "$kernel_path" ]]; then
            kernel_path="$(readlink -f "$kernel_path" 2>/dev/null || realpath "$kernel_path" 2>/dev/null || echo "$kernel_path")"
            log_info "Using Custom Kernel: $kernel_path"
            emu_args+=("-kernel" "$kernel_path")

            if [[ -n "$kernel_append" ]]; then
                log_info "Custom Kernel Append: $kernel_append"
                emu_args+=("-append" "$kernel_append")
            fi
        else
            log_err "Custom kernel file not found: $custom_kernel"
            return 1
        fi
    fi

    # 4. Headless mode
    if [[ "$headless" == true ]]; then
        emu_args+=("-no-window")
    fi

    # 5. Wipe data
    if [[ "$wipe_data" == true ]]; then
        emu_args+=("-wipe-data")
    fi

    # 6. Cold boot
    if [[ "$cold_boot" == true ]]; then
        emu_args+=("-no-snapshot-load")
    fi

    # 7. Audio handling & PulseAudio bridging
    if [[ "$no_audio" == true ]]; then
        emu_args+=("-no-audio")
    else
        setup_audio "$no_audio"
    fi

    # 8. Suppress crash consent dialogs in container / headless
    emu_args+=("-no-metrics")

    # 8. QEMU VirtFS shared folder parameter
    local qemu_args=()
    if [[ "$ENABLE_QEMU_VIRTFS" == true ]]; then
        # Google's official Android Emulator QEMU binary does NOT compile in virtio-9p-pci.
        # Only pass -virtfs if QEMU explicitly supports virtio-9p to prevent fatal exit:
        # "qemu-system-x86_64: 'virtio-9p-pci' is not a valid device model name"
        local qemu_bin="$SDK_DIR/emulator/qemu/linux-x86_64/qemu-system-x86_64"
        local supports_9p=false
        if [[ -x "$qemu_bin" ]] && "$qemu_bin" -device help 2>&1 | grep -q "virtio-9p"; then
            supports_9p=true
        fi

        if [[ "$supports_9p" == true ]]; then
            mkdir -p "$SHARED_DIR"
            qemu_args+=("-virtfs" "local,path=${SHARED_DIR},mount_tag=${VIRTFS_MOUNT_TAG:-hostshare},security_model=passthrough,id=hostshare")
        else
            log_warn "QEMU VirtFS (9p) requested, but this emulator's QEMU binary does not support 'virtio-9p-pci'."
            log_warn "Safely omitting -virtfs to prevent crash. Use ADB shared folder sync instead (fully supported)!"
        fi
    fi

    # Append QEMU arguments if any exist
    if (( ${#qemu_args[@]} > 0 )); then
        emu_args+=("-qemu" "${qemu_args[@]}")
    fi

    # Log file for emulator output
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local log_file="$LOGS_DIR/emulator_${avd_name}_${timestamp}.log"

    log_step "Launching AVD: '$avd_name'"
    echo "  - Renderer:      $renderer"
    echo "  - CPU Cores:     $cores"
    echo "  - RAM Size:      ${ram_mb} MB"
    echo "  - Custom Kernel: ${custom_kernel:-None (System Image Kernel)}"
    echo "  - Shared Folder: $SHARED_DIR"
    echo "  - Headless:      $headless"
    echo "  - Audio:         $([[ "$no_audio" == true ]] && echo "Disabled" || echo "Enabled")"
    echo "  - Log File:      $log_file"
    echo ""

    # Start live background sync daemon if requested
    if [[ "$auto_sync" == true ]]; then
        (
            wait_for_device 120 >/dev/null 2>&1
            start_share_daemon >/dev/null 2>&1
        ) &
    fi

    # Ensure cleanup of daemon when emulator terminates
    cleanup_launcher() {
        if [[ "$auto_sync" == true ]]; then
            stop_share_daemon >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_launcher EXIT INT TERM

    # Execute emulator
    log_info "Starting emulator process..."
    "$emulator_bin" "${emu_args[@]}" 2>&1 | tee "$log_file"

    local exit_code=$?
    cleanup_launcher

    if (( exit_code == 0 )); then
        log_success "Emulator session finished cleanly."
    else
        log_warn "Emulator exited with code: $exit_code. Check log at: $log_file"
    fi
    return $exit_code
}
