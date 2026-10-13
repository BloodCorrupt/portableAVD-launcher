#!/usr/bin/env bash
# ==============================================================================
# Portable AVD Launcher for Linux
# 100% Self-Contained Android Virtual Device Environment
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/bin/env.sh"
# shellcheck source=bin/bootstrap_sdk.sh
source "$BIN_DIR/bootstrap_sdk.sh"
# shellcheck source=bin/avd_creator.sh
source "$BIN_DIR/avd_creator.sh"
# shellcheck source=bin/avd_launcher.sh
source "$BIN_DIR/avd_launcher.sh"
# shellcheck source=bin/file_share.sh
source "$BIN_DIR/file_share.sh"
# shellcheck source=bin/java_setup.sh
source "$BIN_DIR/java_setup.sh"
# shellcheck source=bin/tui.sh
source "$BIN_DIR/tui.sh"

show_help() {
    cat << EOF
Portable AVD Launcher for Linux (100% Isolated & Portable)

Usage:
  ./launcher.sh                            Launch interactive menu (TUI)
  ./launcher.sh run <avd_name> [options]   Launch an AVD with specific options
  ./launcher.sh create [options]           Download and create a new AVD
  ./launcher.sh list                       List all configured AVDs
  ./launcher.sh reconfig <name> [options]  Update hardware (cores, RAM, disk)
  ./launcher.sh wipe <name>                Wipe user data of an AVD
  ./launcher.sh delete <name>              Delete an AVD
  ./launcher.sh share <command> [args]     File sharing commands (push/pull/sync)
  ./launcher.sh shell                      Open interactive adb shell
  ./launcher.sh adb <args...>              Execute isolated adb command
  ./launcher.sh bootstrap                  Download SDK tools and accept licenses
  ./launcher.sh kvm                        Check KVM virtualization status
  ./launcher.sh help                       Show this help message

Run Options:
  --gpu <mode>       Renderer: host (GPU), swiftshader_indirect (CPU), angle_indirect, auto, off
  --cores <N>        Granular CPU cores (e.g. 2, 4, 8)
  --ram <MB>         Granular RAM size in MB (e.g. 2048, 4096, 8192)
  --kernel <path>    Custom Linux kernel file (path to bzImage / Image.gz)
  --append <args>    Custom kernel command-line arguments (e.g. "console=ttyS0")
  --sync-share       Enable background file sharing daemon
  --no-sync-share    Disable background file sharing daemon
  --headless         Run without GUI window (-no-window)
  --no-audio         Disable audio emulation (recommended for containers/Selkies/VPS)
  --virtfs           Enable QEMU 9p VirtFS parameter (requires 9p QEMU support)
  --no-virtfs        Disable QEMU 9p VirtFS parameter (default)
  --wipe-data        Wipe user data before starting
  --cold-boot        Force cold boot (do not restore quick-boot snapshot)

Create Options:
  --name, -n <name>        Name of the virtual device (Required)
  --api, -a <level>        Android API level (e.g. 34 for Android 14, 35 for Android 15)
  --variant, -v <type>     System image variant:
                             playstore   (Google Play Store & official apps)
                             google_apis (Google APIs, rootable, lightweight)
                             aosp        (Clean open-source Android, no Google services)
  --arch <arch>            Architecture: x86_64 (default), x86, arm64-v8a
  --cores <N>              Granular CPU cores (default: 4)
  --ram <MB>               Granular RAM in MB (default: 4096)
  --disk <MB>              Granular storage/disk in MB (default: 8192)
  --heap <MB>              VM Heap size in MB (default: 512)
  --device <profile>       Device skin/hardware profile (default: pixel_6)

Share Commands:
  share push <file> [dest] Transfer file to device (/sdcard/Download/Shared)
  share pull [src] [dest]  Retrieve files from device to shared/from_device
  share sync               Sync shared folders bidirectionally once
  share start-daemon       Start live background sync daemon
  share stop-daemon        Stop live background sync daemon
  share virtfs             Show QEMU 9p VirtFS guest mount instructions

Examples:
  # Launch interactive interface
  ./launcher.sh

  # Create an Android 14 AVD with Google Play Store, 4 cores, 4GB RAM
  ./launcher.sh create --name Pixel14 --api 34 --variant playstore --cores 4 --ram 4096

  # Create a Pure AOSP AVD (no Google services) with 8 cores, 8GB RAM
  ./launcher.sh create --name AOSP_Dev --api 34 --variant aosp --cores 8 --ram 8192

  # Launch with Host GPU acceleration
  ./launcher.sh run Pixel14 --gpu host

  # Launch with SwiftShader (CPU software rendering) on a VPS/headless server
  ./launcher.sh run Pixel14 --gpu swiftshader_indirect --headless

  # Launch with a custom kernel and live file sharing
  ./launcher.sh run Pixel14 --kernel kernels/bzImage --sync-share

  # Push an APK or file to the running AVD
  ./launcher.sh share push my_app.apk
EOF
}

# CLI Argument Parser
main() {
    local cmd="${1:-}"

    if [[ -z "$cmd" ]]; then
        tui_main_menu
        exit 0
    fi

    shift || true

    case "$cmd" in
        run)
            local avd_name="${1:-}"
            [[ -n "$avd_name" ]] && shift || true

            local renderer="$DEFAULT_RENDERER"
            local cores="$DEFAULT_CORES"
            local ram="$DEFAULT_RAM_MB"
            local kernel="$DEFAULT_KERNEL"
            local append="$DEFAULT_KERNEL_APPEND"
            local sync="$AUTO_SYNC_SHARE"
            local headless="$HEADLESS"
            local wipe="$WIPE_DATA"
            local cold="$COLD_BOOT"
            local no_audio="${NO_AUDIO:-false}"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --gpu|-g) renderer="$2"; shift 2 ;;
                    --cores|-c) cores="$2"; shift 2 ;;
                    --ram|-m) ram="$2"; shift 2 ;;
                    --kernel|-k) kernel="$2"; shift 2 ;;
                    --append) append="$2"; shift 2 ;;
                    --sync-share) sync=true; shift ;;
                    --no-sync-share) sync=false; shift ;;
                    --headless|-n) headless=true; shift ;;
                    --no-audio) no_audio=true; shift ;;
                    --virtfs) ENABLE_QEMU_VIRTFS=true; shift ;;
                    --no-virtfs) ENABLE_QEMU_VIRTFS=false; shift ;;
                    --wipe-data) wipe=true; shift ;;
                    --cold-boot) cold=true; shift ;;
                    *) log_err "Unknown run option: $1"; exit 1 ;;
                esac
            done

            run_avd "$avd_name" "$renderer" "$cores" "$ram" "$kernel" "$append" "$sync" "$headless" "$wipe" "$cold" "$no_audio"
            ;;

        create)
            local name=""
            local api="34"
            local variant="google_apis_playstore"
            local arch="$DEFAULT_ARCH"
            local cores="$DEFAULT_CORES"
            local ram="$DEFAULT_RAM_MB"
            local disk="$DEFAULT_DISK_MB"
            local heap="$DEFAULT_HEAP_MB"
            local device="$DEFAULT_DEVICE"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name|-n) name="$2"; shift 2 ;;
                    --api|-a) api="$2"; shift 2 ;;
                    --variant|-v)
                        case "$2" in
                            playstore|google_apis_playstore) variant="google_apis_playstore" ;;
                            google_apis) variant="google_apis" ;;
                            aosp|default) variant="default" ;;
                            *) variant="$2" ;;
                        esac
                        shift 2
                        ;;
                    --arch) arch="$2"; shift 2 ;;
                    --cores|-c) cores="$2"; shift 2 ;;
                    --ram|-m) ram="$2"; shift 2 ;;
                    --disk|-d) disk="$2"; shift 2 ;;
                    --heap) heap="$2"; shift 2 ;;
                    --device) device="$2"; shift 2 ;;
                    *) log_err "Unknown create option: $1"; exit 1 ;;
                esac
            done

            if [[ -z "$name" ]]; then
                log_err "Device name is required. Specify with --name <avd_name>"
                exit 1
            fi

            create_avd "$name" "$api" "$variant" "$arch" "$cores" "$ram" "$disk" "$heap" "$device"
            ;;

        list)
            list_avds
            ;;

        reconfig)
            local name="${1:-}"
            [[ -n "$name" ]] && shift || true

            if [[ -z "$name" ]]; then
                log_err "Specify AVD name: ./launcher.sh reconfig <name>"
                exit 1
            fi

            local cores="$DEFAULT_CORES"
            local ram="$DEFAULT_RAM_MB"
            local heap="$DEFAULT_HEAP_MB"
            local disk="$DEFAULT_DISK_MB"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --cores|-c) cores="$2"; shift 2 ;;
                    --ram|-m) ram="$2"; shift 2 ;;
                    --heap) heap="$2"; shift 2 ;;
                    --disk|-d) disk="$2"; shift 2 ;;
                    *) log_err "Unknown reconfig option: $1"; exit 1 ;;
                esac
            done

            update_avd_hardware "$name" "$cores" "$ram" "$heap" "$disk"
            ;;

        wipe)
            wipe_avd "$1"
            ;;

        delete)
            delete_avd "$1"
            ;;

        share)
            local subcmd="${1:-}"
            shift || true
            case "$subcmd" in
                push) push_to_device "$@" ;;
                pull) pull_from_device "$@" ;;
                sync) sync_shared_folders ;;
                start-daemon) start_share_daemon ;;
                stop-daemon) stop_share_daemon ;;
                virtfs) mount_qemu_virtfs_guest ;;
                *)
                    log_err "Unknown share command: $subcmd"
                    echo "Available: push, pull, sync, start-daemon, stop-daemon, virtfs"
                    exit 1
                    ;;
            esac
            ;;

        shell)
            local adb
            adb="$(get_adb)"
            if [[ ! -x "$adb" ]]; then
                log_err "adb not found. Run ./launcher.sh bootstrap first."
                exit 1
            fi
            "$adb" shell "$@"
            ;;

        adb)
            local adb
            adb="$(get_adb)"
            if [[ ! -x "$adb" ]]; then
                log_err "adb not found. Run ./launcher.sh bootstrap first."
                exit 1
            fi
            "$adb" "$@"
            ;;

        bootstrap)
            bootstrap_all
            ;;

        kvm)
            check_kvm
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            log_err "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
