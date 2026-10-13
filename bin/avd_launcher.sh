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

    # 7. QEMU VirtFS shared folder parameter
    local qemu_args=()
    if [[ "$ENABLE_QEMU_VIRTFS" == true ]]; then
        mkdir -p "$SHARED_DIR"
        qemu_args+=("-virtfs" "local,path=${SHARED_DIR},mount_tag=${VIRTFS_MOUNT_TAG:-hostshare},security_model=passthrough,id=hostshare")
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
    echo "  - QEMU VirtFS:   $ENABLE_QEMU_VIRTFS (tag: ${VIRTFS_MOUNT_TAG:-hostshare})"
    echo "  - Headless:      $headless"
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
