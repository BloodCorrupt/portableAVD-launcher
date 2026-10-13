#!/usr/bin/env bash
# ==============================================================================
# Interactive Terminal User Interface (TUI)
# Clean, colorized interactive menu for managing and launching portable AVDs.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/env.sh"
# shellcheck source=bin/bootstrap_sdk.sh
source "$SCRIPT_DIR/bootstrap_sdk.sh"
# shellcheck source=bin/avd_creator.sh
source "$SCRIPT_DIR/avd_creator.sh"
# shellcheck source=bin/avd_launcher.sh
source "$SCRIPT_DIR/avd_launcher.sh"
# shellcheck source=bin/file_share.sh
source "$SCRIPT_DIR/file_share.sh"
# shellcheck source=bin/java_setup.sh
source "$SCRIPT_DIR/java_setup.sh"

press_enter() {
    echo ""
    read -r -p "Press [Enter] to return to menu..."
}

print_header() {
    clear 2>/dev/null || true
    echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_WHITE}           PORTABLE ANDROID VIRTUAL DEVICE (AVD) LAUNCHER             ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
    echo -e " ${COLOR_DIM}Path:${COLOR_RESET} $BASE_DIR"

    # Status indicators
    local kvm_status="${COLOR_RED}Unavailable${COLOR_RESET}"
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
        kvm_status="${COLOR_GREEN}Ready (/dev/kvm)${COLOR_RESET}"
    fi

    local sdk_status="${COLOR_RED}Not Initialized${COLOR_RESET}"
    if [[ -x "$SDK_DIR/emulator/emulator" && -x "$SDK_DIR/platform-tools/adb" ]]; then
        sdk_status="${COLOR_GREEN}Ready${COLOR_RESET}"
    fi

    local sync_status="${COLOR_DIM}Stopped${COLOR_RESET}"
    if [[ -f "$DATA_DIR/sync_daemon.pid" ]] && kill -0 "$(cat "$DATA_DIR/sync_daemon.pid")" 2>/dev/null; then
        sync_status="${COLOR_GREEN}Running (PID $(cat "$DATA_DIR/sync_daemon.pid"))${COLOR_RESET}"
    fi

    echo -e " ${COLOR_DIM}KVM:${COLOR_RESET} $kvm_status | ${COLOR_DIM}SDK:${COLOR_RESET} $sdk_status | ${COLOR_DIM}Live Sync:${COLOR_RESET} $sync_status"
    echo -e "${COLOR_CYAN}----------------------------------------------------------------------${COLOR_RESET}"
}

# Sub-menu: Launch AVD
tui_launch_avd() {
    print_header
    echo -e "${COLOR_BOLD}=== Launch Virtual Device ===${COLOR_RESET}\n"

    # Check available AVDs
    local avd_list=()
    if [[ -d "$ANDROID_AVD_HOME" ]]; then
        for ini in "$ANDROID_AVD_HOME"/*.ini; do
            [[ -e "$ini" ]] || continue
            avd_list+=("$(basename "$ini" .ini)")
        done
    fi

    if (( ${#avd_list[@]} == 0 )); then
        log_warn "No AVDs found! Please create an AVD first."
        press_enter
        return
    fi

    echo "Available AVDs:"
    local i=1
    for avd in "${avd_list[@]}"; do
        echo "  [$i] $avd"
        ((i++))
    done
    echo "  [0] Back to main menu"
    echo ""
    read -r -p "Select AVD to launch [1-${#avd_list[@]}]: " avd_choice

    if [[ "$avd_choice" == "0" || -z "$avd_choice" ]]; then
        return
    fi

    if ! [[ "$avd_choice" =~ ^[0-9]+$ ]] || (( avd_choice < 1 || avd_choice > ${#avd_list[@]} )); then
        log_err "Invalid selection."
        press_enter
        return
    fi

    local selected_avd="${avd_list[$((avd_choice - 1))]}"

    # Choose Renderer
    echo -e "\n${COLOR_BOLD}Select Graphics Renderer:${COLOR_RESET}"
    echo "  [1] GPU (Host Hardware Acceleration - Recommended for performance)"
    echo "  [2] SwiftShader (CPU Software Rendering - Ideal for headless/VMs/buggy GPU)"
    echo "  [3] ANGLE (Host OpenGL/Direct3D translation)"
    echo "  [4] Auto (Let emulator decide)"
    read -r -p "Choice [Default: 1 (GPU)]: " rend_choice
    local chosen_renderer="host"
    case "$rend_choice" in
        2) chosen_renderer="swiftshader_indirect" ;;
        3) chosen_renderer="angle_indirect" ;;
        4) chosen_renderer="auto" ;;
        *) chosen_renderer="host" ;;
    esac

    # Granular Hardware Settings
    echo -e "\n${COLOR_BOLD}Granular Hardware Settings:${COLOR_RESET}"
    read -r -p "CPU Cores [Default: $DEFAULT_CORES]: " input_cores
    local launch_cores="${input_cores:-$DEFAULT_CORES}"

    read -r -p "RAM in MB [Default: $DEFAULT_RAM_MB]: " input_ram
    local launch_ram="${input_ram:-$DEFAULT_RAM_MB}"

    # Custom Kernel Option
    echo -e "\n${COLOR_BOLD}Custom Kernel Options:${COLOR_RESET}"
    echo "  [1] Standard Kernel (bundled with system image)"

    local kernel_files=()
    if [[ -d "$KERNELS_DIR" ]]; then
        for k in "$KERNELS_DIR"/*; do
            [[ -f "$k" ]] || continue
            kernel_files+=("$(basename "$k")")
        done
    fi

    local k_idx=2
    for kf in "${kernel_files[@]}"; do
        echo "  [$k_idx] $kf (from kernels/)"
        ((k_idx++))
    done
    echo "  [c] Specify custom path..."
    read -r -p "Select kernel [Default: 1]: " kernel_choice

    local chosen_kernel=""
    local kernel_append=""
    if [[ "$kernel_choice" =~ ^[0-9]+$ ]] && (( kernel_choice >= 2 && kernel_choice < k_idx )); then
        chosen_kernel="$KERNELS_DIR/${kernel_files[$((kernel_choice - 2))]}"
    elif [[ "$kernel_choice" == "c" || "$kernel_choice" == "C" ]]; then
        read -r -p "Enter path to kernel file: " user_k_path
        chosen_kernel="$user_k_path"
    fi

    if [[ -n "$chosen_kernel" ]]; then
        read -r -p "Custom kernel append parameters (optional, e.g. console=ttyS0): " kernel_append
    fi

    # Shared Folder Options
    read -r -p "Enable live shared folder sync? (Y/n): " sync_choice
    local run_sync=true
    if [[ "$sync_choice" =~ ^[Nn]$ ]]; then
        run_sync=false
    fi

    # Headless Option
    read -r -p "Run in headless mode (no GUI window)? (y/N): " head_choice
    local run_headless=false
    if [[ "$head_choice" =~ ^[Yy]$ ]]; then
        run_headless=true
    fi

    # Audio Option (Enabled by default, supported with Selkies PulseAudio)
    read -r -p "Enable audio (PulseAudio streaming)? (Y/n) [Default: Y]: " audio_choice
    local run_no_audio=false
    if [[ "$audio_choice" =~ ^[Nn]$ ]]; then
        run_no_audio=true
    fi

    echo ""
    log_info "Launching AVD '$selected_avd'..."
    run_avd "$selected_avd" "$chosen_renderer" "$launch_cores" "$launch_ram" "$chosen_kernel" "$kernel_append" "$run_sync" "$run_headless" false false "$run_no_audio"
    press_enter
}

# Sub-menu: Create New AVD
tui_create_avd() {
    print_header
    echo -e "${COLOR_BOLD}=== Download & Create AVD ===${COLOR_RESET}\n"

    read -r -p "Enter name for new AVD (e.g. Pixel_Android14): " avd_name
    if [[ -z "$avd_name" ]]; then
        log_err "Name cannot be empty."
        press_enter
        return
    fi

    echo -e "\n${COLOR_BOLD}Select Android Version (API Level):${COLOR_RESET}"
    echo "  [1] Android 15 (API 35)"
    echo "  [2] Android 14 (API 34) - Recommended"
    echo "  [3] Android 13 (API 33)"
    echo "  [4] Android 12L (API 32)"
    echo "  [5] Android 12 (API 31)"
    echo "  [6] Android 11 (API 30)"
    echo "  [7] Android 10 (API 29)"
    echo "  [8] Android 9.0 (API 28)"
    echo "  [c] Custom API Level..."
    read -r -p "Choice [Default: 2]: " api_choice

    local selected_api=34
    case "$api_choice" in
        1) selected_api=35 ;;
        2|"") selected_api=34 ;;
        3) selected_api=33 ;;
        4) selected_api=32 ;;
        5) selected_api=31 ;;
        6) selected_api=30 ;;
        7) selected_api=29 ;;
        8) selected_api=28 ;;
        c|C)
            read -r -p "Enter API level integer (e.g. 34): " custom_api
            selected_api="${custom_api:-34}"
            ;;
        *) selected_api=34 ;;
    esac

    echo -e "\n${COLOR_BOLD}Select Image Variant (Google Play choice):${COLOR_RESET}"
    echo "  [1] With Google Play Store (Official store & Google apps)"
    echo "  [2] Google APIs (Google services included, rootable, no Store app)"
    echo "  [3] Pure AOSP (Clean open-source Android, no Google services, lightweight & rootable)"
    read -r -p "Choice [Default: 1]: " var_choice

    local selected_var="google_apis_playstore"
    case "$var_choice" in
        1|"") selected_var="google_apis_playstore" ;;
        2) selected_var="google_apis" ;;
        3) selected_var="default" ;;
        *) selected_var="google_apis_playstore" ;;
    esac

    echo -e "\n${COLOR_BOLD}Select Architecture:${COLOR_RESET}"
    echo "  [1] x86_64 (Fastest, recommended for 64-bit Linux PC)"
    echo "  [2] x86 (32-bit)"
    echo "  [3] arm64-v8a (ARM emulation)"
    read -r -p "Choice [Default: 1]: " arch_choice
    local selected_arch="x86_64"
    case "$arch_choice" in
        2) selected_arch="x86" ;;
        3) selected_arch="arm64-v8a" ;;
        *) selected_arch="x86_64" ;;
    esac

    echo -e "\n${COLOR_BOLD}Granular Hardware Allocation:${COLOR_RESET}"
    read -r -p "CPU Cores [Default: $DEFAULT_CORES]: " input_cores
    local sel_cores="${input_cores:-$DEFAULT_CORES}"

    read -r -p "RAM in MB [Default: $DEFAULT_RAM_MB]: " input_ram
    local sel_ram="${input_ram:-$DEFAULT_RAM_MB}"

    read -r -p "Storage / Disk in MB [Default: $DEFAULT_DISK_MB]: " input_disk
    local sel_disk="${input_disk:-$DEFAULT_DISK_MB}"

    read -r -p "VM Heap in MB [Default: $DEFAULT_HEAP_MB]: " input_heap
    local sel_heap="${input_heap:-$DEFAULT_HEAP_MB}"

    read -r -p "Device Skin/Profile [Default: $DEFAULT_DEVICE]: " input_device
    local sel_device="${input_device:-$DEFAULT_DEVICE}"

    create_avd "$avd_name" "$selected_api" "$selected_var" "$selected_arch" "$sel_cores" "$sel_ram" "$sel_disk" "$sel_heap" "$sel_device"
    press_enter
}

# Sub-menu: Manage Existing AVDs
tui_manage_avds() {
    print_header
    echo -e "${COLOR_BOLD}=== Manage Existing AVDs ===${COLOR_RESET}\n"
    list_avds

    echo "Actions:"
    echo "  [1] Reconfigure CPU Cores & RAM for an AVD"
    echo "  [2] Wipe User Data (Factory Reset)"
    echo "  [3] Delete an AVD"
    echo "  [0] Back"
    read -r -p "Choice: " act_choice

    case "$act_choice" in
        1)
            read -r -p "Enter name of AVD to reconfigure: " t_name
            if [[ -f "$ANDROID_AVD_HOME/${t_name}.ini" ]]; then
                read -r -p "New CPU Cores [e.g. 4]: " n_cores
                read -r -p "New RAM in MB [e.g. 4096]: " n_ram
                read -r -p "New VM Heap in MB [e.g. 512]: " n_heap
                read -r -p "New Disk in MB [e.g. 8192]: " n_disk
                update_avd_hardware "$t_name" "${n_cores:-$DEFAULT_CORES}" "${n_ram:-$DEFAULT_RAM_MB}" "${n_heap:-$DEFAULT_HEAP_MB}" "${n_disk:-$DEFAULT_DISK_MB}"
            else
                log_err "AVD not found."
            fi
            ;;
        2)
            read -r -p "Enter name of AVD to wipe: " t_name
            read -r -p "Are you sure you want to wipe user data for '$t_name'? (y/N): " conf
            if [[ "$conf" =~ ^[Yy]$ ]]; then
                wipe_avd "$t_name"
            fi
            ;;
        3)
            read -r -p "Enter name of AVD to delete: " t_name
            read -r -p "Are you sure you want to permanently delete '$t_name'? (y/N): " conf
            if [[ "$conf" =~ ^[Yy]$ ]]; then
                delete_avd "$t_name"
            fi
            ;;
        *)
            return
            ;;
    esac
    press_enter
}

# Sub-menu: File Share Center
tui_share_center() {
    print_header
    echo -e "${COLOR_BOLD}=== Shared Folder & File Transfers ===${COLOR_RESET}\n"
    echo "Shared Directories on Host:"
    echo "  - Outbox (to Android):   $SHARED_TO_DEVICE"
    echo "  - Inbox (from Android):  $SHARED_FROM_DEVICE"
    echo "  - Destination on Device: ${DEVICE_SHARE_DIR:-/sdcard/Download/Shared}"
    echo ""

    if is_device_ready; then
        echo -e "Device Status: ${COLOR_GREEN}Online & Connected${COLOR_RESET}"
    else
        echo -e "Device Status: ${COLOR_YELLOW}Offline / Not Detected${COLOR_RESET}"
    fi

    echo ""
    echo "Options:"
    echo "  [1] Push file/folder from host to Android"
    echo "  [2] Pull files from Android to host"
    echo "  [3] Synchronize shared folder now"
    echo "  [4] Start live background auto-sync daemon"
    echo "  [5] Stop live background auto-sync daemon"
    echo "  [6] QEMU VirtFS (9p) mount instructions"
    echo "  [0] Back"
    read -r -p "Choice: " s_choice

    case "$s_choice" in
        1)
            read -r -p "Enter path of file to push to Android: " p_file
            push_to_device "$p_file"
            ;;
        2)
            pull_from_device
            ;;
        3)
            log_info "Synchronizing shared folders..."
            sync_shared_folders
            log_success "Sync completed."
            ;;
        4)
            start_share_daemon
            ;;
        5)
            stop_share_daemon
            ;;
        6)
            mount_qemu_virtfs_guest
            ;;
        *)
            return
            ;;
    esac
    press_enter
}

# Sub-menu: SDK & Diagnostics
tui_sdk_tools() {
    print_header
    echo -e "${COLOR_BOLD}=== SDK & System Diagnostics ===${COLOR_RESET}\n"

    echo "Components Check:"
    if [[ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then
        echo -e "  - cmdline-tools:  ${COLOR_GREEN}Installed${COLOR_RESET} ($SDK_DIR/cmdline-tools/latest)"
    else
        echo -e "  - cmdline-tools:  ${COLOR_RED}Missing${COLOR_RESET}"
    fi

    if [[ -x "$SDK_DIR/platform-tools/adb" ]]; then
        echo -e "  - platform-tools: ${COLOR_GREEN}Installed${COLOR_RESET} ($SDK_DIR/platform-tools)"
    else
        echo -e "  - platform-tools: ${COLOR_RED}Missing${COLOR_RESET}"
    fi

    if [[ -x "$SDK_DIR/emulator/emulator" ]]; then
        echo -e "  - emulator:       ${COLOR_GREEN}Installed${COLOR_RESET} ($SDK_DIR/emulator)"
    else
        echo -e "  - emulator:       ${COLOR_RED}Missing${COLOR_RESET}"
    fi

    if [[ -x "$JDK_DIR/bin/java" ]]; then
        echo -e "  - Java:           ${COLOR_GREEN}Portable OpenJDK Installed${COLOR_RESET} ($JDK_DIR)"
    elif command -v java >/dev/null 2>&1; then
        echo -e "  - Java:           ${COLOR_GREEN}Host Java Available${COLOR_RESET} ($(command -v java))"
    else
        echo -e "  - Java:           ${COLOR_RED}Missing (Required for SDK tools)${COLOR_RESET}"
    fi

    echo ""
    check_kvm || true

    echo ""
    echo "Actions:"
    echo "  [1] Bootstrap / Update SDK components & licenses"
    echo "  [2] Download Portable OpenJDK 17"
    echo "  [3] Accept SDK licenses"
    echo "  [0] Back"
    read -r -p "Choice: " act

    case "$act" in
        1) bootstrap_all ;;
        2) install_portable_jdk ;;
        3) accept_licenses ;;
        *) return ;;
    esac
    press_enter
}

# Main Interactive Loop
tui_main_menu() {
    while true; do
        print_header
        echo -e "${COLOR_BOLD}Main Menu:${COLOR_RESET}"
        echo "  [1] 🚀 Launch AVD"
        echo "  [2] 📦 Download & Create New AVD (Choice of API, Play Store, Cores, RAM)"
        echo "  [3] ⚙️  Manage Existing AVDs (Hardware reconfiguration, Wipe, Delete)"
        echo "  [4] 📂 Shared Folder & File Transfers (Live sync, Push, Pull, VirtFS)"
        echo "  [5] 🛠️  SDK & System Diagnostics (Bootstrap, Portable Java, KVM)"
        echo "  [0] 🚪 Exit"
        echo ""
        read -r -p "Select option [0-5]: " main_choice

        case "$main_choice" in
            1) tui_launch_avd ;;
            2) tui_create_avd ;;
            3) tui_manage_avds ;;
            4) tui_share_center ;;
            5) tui_sdk_tools ;;
            0|q|Q|exit)
                echo -e "\nGoodbye!"
                exit 0
                ;;
            *)
                log_warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}
