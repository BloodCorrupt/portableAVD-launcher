#!/usr/bin/env bash
# ==============================================================================
# AVD Creator & Downloader
# Handles downloading system images (with/without Play Store), API selection,
# and granular hardware configuration (Cores, RAM, Heap, Storage).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/env.sh
source "$SCRIPT_DIR/env.sh"
# shellcheck source=bin/bootstrap_sdk.sh
source "$SCRIPT_DIR/bootstrap_sdk.sh"

get_sdkmanager() {
    echo "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
}

get_avdmanager() {
    echo "$SDK_DIR/cmdline-tools/latest/bin/avdmanager"
}

# List currently installed system images
list_installed_system_images() {
    local sdkmanager
    sdkmanager="$(get_sdkmanager)"
    "$sdkmanager" --list_installed | grep "^  system-images;" | awk '{print $1}'
}

# List all created AVDs with details
list_avds() {
    log_step "Configured Portable AVDs"
    if [[ ! -d "$ANDROID_AVD_HOME" ]] || [[ -z "$(ls -A "$ANDROID_AVD_HOME"/*.ini 2>/dev/null)" ]]; then
        echo "  (No AVDs configured yet)"
        return 0
    fi

    printf "  %-20s %-8s %-12s %-8s %-10s %s\n" "NAME" "CORES" "RAM" "DISK" "PLAY STORE" "TARGET"
    printf "  %-20s %-8s %-12s %-8s %-10s %s\n" "----" "-----" "---" "----" "----------" "------"

    for ini_file in "$ANDROID_AVD_HOME"/*.ini; do
        [[ -e "$ini_file" ]] || continue
        local name
        name="$(basename "$ini_file" .ini)"
        local avd_dir="$ANDROID_AVD_HOME/${name}.avd"
        local config_file="$avd_dir/config.ini"

        local cores="N/A"
        local ram="N/A"
        local disk="N/A"
        local playstore="No"
        local target="Unknown"

        if [[ -f "$config_file" ]]; then
            cores="$(grep -E "^hw.cpu.ncore" "$config_file" | cut -d= -f2 | tr -d ' ' || echo "N/A")"
            ram="$(grep -E "^hw.ramSize" "$config_file" | cut -d= -f2 | tr -d ' ' || echo "N/A")"
            disk="$(grep -E "^disk.dataPartition.size" "$config_file" | cut -d= -f2 | tr -d ' ' || echo "N/A")"
            target="$(grep -E "^image.sysdir.1" "$config_file" | cut -d= -f2 | tr -d ' ' || echo "Unknown")"

            if [[ "$target" == *"playstore"* ]]; then
                playstore="Yes"
            fi
            [[ -n "$ram" && "$ram" != "N/A" ]] && ram="${ram} MB"
        fi

        printf "  %-20s %-8s %-12s %-8s %-10s %s\n" "$name" "$cores" "$ram" "$disk" "$playstore" "$target"
    done
    echo ""
}

# Granularly update config.ini for an AVD
update_avd_hardware() {
    local avd_name="$1"
    local cores="$2"
    local ram_mb="$3"
    local heap_mb="${4:-$DEFAULT_HEAP_MB}"
    local disk_mb="${5:-$DEFAULT_DISK_MB}"

    local config_file="$ANDROID_AVD_HOME/${avd_name}.avd/config.ini"
    if [[ ! -f "$config_file" ]]; then
        log_err "Configuration file not found: $config_file"
        return 1
    fi

    log_info "Applying granular hardware configuration to '$avd_name'..."

    # Helper function to set or replace key=value in config.ini
    set_config_param() {
        local key="$1"
        local val="$2"
        if grep -q "^${key}[[:space:]]*=" "$config_file"; then
            sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${val}|g" "$config_file"
        else
            echo "${key} = ${val}" >> "$config_file"
        fi
    }

    set_config_param "hw.cpu.ncore" "$cores"
    set_config_param "hw.ramSize" "$ram_mb"
    set_config_param "vm.heapSize" "${heap_mb}M"
    set_config_param "disk.dataPartition.size" "${disk_mb}M"
    set_config_param "hw.keyboard" "yes"
    set_config_param "hw.gpu.enabled" "yes"
    set_config_param "hw.gpu.mode" "auto"
    set_config_param "fastboot.forceColdBoot" "no"

    log_success "Hardware updated: Cores=$cores, RAM=${ram_mb}MB, Heap=${heap_mb}MB, Disk=${disk_mb}MB"
}

# Download system image and create AVD
create_avd() {
    local avd_name="$1"
    local api_level="$2"
    local variant="$3" # google_apis_playstore | google_apis | default
    local arch="${4:-$DEFAULT_ARCH}"
    local cores="${5:-$DEFAULT_CORES}"
    local ram_mb="${6:-$DEFAULT_RAM_MB}"
    local disk_mb="${7:-$DEFAULT_DISK_MB}"
    local heap_mb="${8:-$DEFAULT_HEAP_MB}"
    local device_profile="${9:-$DEFAULT_DEVICE}"

    if [[ -z "$avd_name" || -z "$api_level" || -z "$variant" ]]; then
        log_err "Usage: create_avd <name> <api_level> <variant: google_apis_playstore|google_apis|default> [arch] [cores] [ram_mb] [disk_mb] [heap_mb] [device]"
        return 1
    fi

    bootstrap_all || return 1

    local sdkmanager
    sdkmanager="$(get_sdkmanager)"
    local avdmanager
    avdmanager="$(get_avdmanager)"

    local image_package="system-images;android-${api_level};${variant};${arch}"
    local platform_package="platforms;android-${api_level}"

    log_step "Preparing AVD: '$avd_name'"
    echo "  - API Level:      $api_level"
    echo "  - Variant:        $variant"
    echo "  - Architecture:   $arch"
    echo "  - CPU Cores:      $cores"
    echo "  - RAM Size:       ${ram_mb} MB"
    echo "  - Disk Partition: ${disk_mb} MB"
    echo "  - VM Heap:        ${heap_mb} MB"
    echo "  - Device Profile: $device_profile"

    # Step 1: Install packages via sdkmanager
    log_info "Downloading / Verifying system image ($image_package)..."
    "$sdkmanager" --install "$image_package" "$platform_package"
    accept_licenses

    # Step 2: Create AVD using avdmanager
    log_info "Creating virtual device '$avd_name'..."
    # Sending 'no' to custom hardware profile question to accept defaults first
    echo "no" | "$avdmanager" create avd \
        -n "$avd_name" \
        -k "$image_package" \
        --device "$device_profile" \
        --force

    # Step 3: Ensure path in .ini is updated to current portable path
    fix_avd_portable_paths

    # Step 4: Apply granular hardware configuration
    update_avd_hardware "$avd_name" "$cores" "$ram_mb" "$heap_mb" "$disk_mb"

    log_success "AVD '$avd_name' successfully created and configured!"
}

delete_avd() {
    local avd_name="$1"
    if [[ -z "$avd_name" ]]; then
        log_err "Specify AVD name to delete."
        return 1
    fi

    local avdmanager
    avdmanager="$(get_avdmanager)"

    log_warn "Deleting AVD '$avd_name'..."
    if [[ -x "$avdmanager" ]]; then
        "$avdmanager" delete avd -n "$avd_name" || true
    fi

    rm -rf "$ANDROID_AVD_HOME/${avd_name}.avd"
    rm -f "$ANDROID_AVD_HOME/${avd_name}.ini"
    log_success "AVD '$avd_name' removed."
}

wipe_avd() {
    local avd_name="$1"
    local avd_dir="$ANDROID_AVD_HOME/${avd_name}.avd"
    if [[ ! -d "$avd_dir" ]]; then
        log_err "AVD '$avd_name' does not exist."
        return 1
    fi

    log_warn "Wiping user data for '$avd_name'..."
    rm -f "$avd_dir"/userdata*.img
    rm -f "$avd_dir"/cache.img*
    rm -rf "$avd_dir"/snapshots/*
    log_success "User data wiped for '$avd_name'."
}
