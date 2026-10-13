#!/usr/bin/env bash
# ==============================================================================
# Shared Folder Manager
# Provides bidirectional file transfer between Linux Host and Android AVD.
# Supports live ADB auto-sync daemon, manual push/pull, and QEMU 9p VirtFS.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/env.sh"

SYNC_PID_FILE="$DATA_DIR/sync_daemon.pid"

get_adb() {
    echo "$SDK_DIR/platform-tools/adb"
}

is_device_ready() {
    local adb
    adb="$(get_adb)"
    if [[ ! -x "$adb" ]]; then
        return 1
    fi
    local state
    state="$("$adb" get-state 2>/dev/null || echo "offline")"
    [[ "$state" == "device" ]]
}

wait_for_device() {
    local adb
    adb="$(get_adb)"
    local timeout="${1:-60}"
    log_info "Waiting for Android device connection (timeout: ${timeout}s)..."

    local counter=0
    while (( counter < timeout )); do
        if is_device_ready; then
            # Verify boot completed
            local boot_completed
            boot_completed="$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
            if [[ "$boot_completed" == "1" ]]; then
                log_success "Android device is online and fully booted!"
                return 0
            fi
        fi
        sleep 2
        counter=$((counter + 2))
    done

    log_warn "Timeout waiting for device boot."
    return 1
}

init_device_share_dir() {
    local adb
    adb="$(get_adb)"
    if is_device_ready; then
        "$adb" shell "mkdir -p '${DEVICE_SHARE_DIR:-/sdcard/Download/Shared}'" 2>/dev/null || true
    fi
}

push_to_device() {
    local local_file="$1"
    local remote_dest="${2:-${DEVICE_SHARE_DIR:-/sdcard/Download/Shared}}"
    local adb
    adb="$(get_adb)"

    if [[ -z "$local_file" ]]; then
        log_err "Usage: push_to_device <local_file_path> [remote_dest]"
        return 1
    fi

    if [[ ! -e "$local_file" ]]; then
        log_err "Local file not found: $local_file"
        return 1
    fi

    if ! is_device_ready; then
        log_err "Android device is not connected or ready."
        return 1
    fi

    init_device_share_dir
    log_info "Pushing '$local_file' to '$remote_dest'..."
    if "$adb" push "$local_file" "$remote_dest"; then
        log_success "File successfully transferred to device!"
        # Trigger media scanner so files show in Android Downloads / Files app immediately
        local filename
        filename="$(basename "$local_file")"
        "$adb" shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://${remote_dest}/${filename}" >/dev/null 2>&1 || true
    else
        log_err "Failed to push file to device."
        return 1
    fi
}

pull_from_device() {
    local remote_src="${1:-${DEVICE_SHARE_DIR:-/sdcard/Download/Shared}}"
    local local_dest="${2:-$SHARED_FROM_DEVICE}"
    local adb
    adb="$(get_adb)"

    if ! is_device_ready; then
        log_err "Android device is not connected or ready."
        return 1
    fi

    mkdir -p "$local_dest"
    log_info "Pulling '$remote_src' to '$local_dest'..."
    if "$adb" pull "$remote_src" "$local_dest"; then
        log_success "Files successfully transferred to: $local_dest"
    else
        log_err "Failed to pull files from device."
        return 1
    fi
}

# Sync files bidirectionally once
sync_shared_folders() {
    local adb
    adb="$(get_adb)"

    if ! is_device_ready; then
        return 1
    fi

    init_device_share_dir

    # 1. Push files from shared/to_device to device
    if [[ -d "$SHARED_TO_DEVICE" ]]; then
        local count
        count="$(find "$SHARED_TO_DEVICE" -mindepth 1 -maxdepth 1 | wc -l)"
        if (( count > 0 )); then
            for item in "$SHARED_TO_DEVICE"/*; do
                [[ -e "$item" ]] || continue
                "$adb" push "$item" "${DEVICE_SHARE_DIR:-/sdcard/Download/Shared}/" >/dev/null 2>&1
            done
        fi
    fi

    # 2. Pull from Android to shared/from_device
    mkdir -p "$SHARED_FROM_DEVICE"
    "$adb" pull "${DEVICE_SHARE_DIR:-/sdcard/Download/Shared}/." "$SHARED_FROM_DEVICE/" >/dev/null 2>&1 || true
}

# Live background sync daemon
start_share_daemon() {
    if [[ -f "$SYNC_PID_FILE" ]] && kill -0 "$(cat "$SYNC_PID_FILE")" 2>/dev/null; then
        log_info "Shared folder sync daemon already running (PID: $(cat "$SYNC_PID_FILE"))."
        return 0
    fi

    log_info "Starting background folder synchronization daemon..."
    (
        while true; do
            if is_device_ready; then
                sync_shared_folders
            fi
            sleep 4
        done
    ) >/dev/null 2>&1 &

    local pid=$!
    echo "$pid" > "$SYNC_PID_FILE"
    log_success "Sync daemon started in background (PID: $pid)"
}

stop_share_daemon() {
    if [[ -f "$SYNC_PID_FILE" ]]; then
        local pid
        pid="$(cat "$SYNC_PID_FILE")"
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" >/dev/null 2>&1 || true
            log_info "Stopped shared folder sync daemon (PID: $pid)."
        fi
        rm -f "$SYNC_PID_FILE"
    fi
}

# Helper to mount QEMU VirtFS in guest if custom kernel has 9p
mount_qemu_virtfs_guest() {
    local adb
    adb="$(get_adb)"
    local tag="${VIRTFS_MOUNT_TAG:-hostshare}"
    local guest_mount="/data/local/tmp/hostshare"

    log_step "QEMU VirtFS (9p) Guest Mount Helper"
    echo "  Mount Tag:   $tag"
    echo "  Guest Path:  $guest_mount"
    echo ""
    echo "To mount inside Android guest (requires root / su in guest & 9p kernel driver):"
    echo "  adb shell"
    echo "  su"
    echo "  mkdir -p $guest_mount"
    echo "  mount -t 9p -o trans=virtio $tag $guest_mount"
    echo ""

    if is_device_ready; then
        read -r -p "Attempt to execute mount command via adb root/su now? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            "$adb" shell "su -c 'mkdir -p $guest_mount && mount -t 9p -o trans=virtio $tag $guest_mount'" 2>/dev/null || \
            "$adb" shell "mkdir -p $guest_mount && mount -t 9p -o trans=virtio $tag $guest_mount" 2>/dev/null || \
            log_warn "Mount command executed. If it failed, ensure guest kernel has CONFIG_9P_FS enabled and su has permission."
        fi
    fi
}
