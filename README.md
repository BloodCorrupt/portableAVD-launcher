# Portable AVD Launcher for Linux

A **100% self-contained, portable Android Virtual Device (AVD) manager and emulator launcher** written in Linux shell script (Bash).

Everything runs directly from the script folder without contaminating your host system (`~/.android`, `~/.config`, etc.). You can move this entire folder to another path, an external SSD, or a different Linux PC, and your AVDs, SDK tools, and configurations remain intact.

---

## 🌟 Key Features

- **100% Truly Portable & Relocatable**:
  - All Android SDK tools (`cmdline-tools`, `emulator`, `platform-tools`, `system-images`) and user data live in `./sdk` and `./data`.
  - Dynamic `.ini` path relocation auto-repairs absolute paths whenever the project folder is moved.
  - Zero required host setup: Automatically detects host Java 17+ or downloads a self-contained portable OpenJDK 17.
- **Granular AVD Choice & Download**:
  - Pick any Android API level (Android 15, 14, 13, 12, 11, 10, 9, or custom).
  - Choice of image variants:
    - **With Google Play Store** (`google_apis_playstore`): Official Google Play Store & Google Play Services.
    - **Google APIs** (`google_apis`): Google services included, rootable, no Play Store app.
    - **Pure AOSP** (`default`): Clean open-source Android without any Google services, lightweight and rootable.
  - Choice of architecture (`x86_64`, `x86`, `arm64-v8a`).
- **Granular Hardware Allocation**:
  - Configure precise CPU core counts (1, 2, 4, 6, 8, etc.).
  - Configure precise RAM allocation (1024, 2048, 4096, 8192 MB, etc.).
  - Configure disk partition size and VM heap size.
  - Override CPU cores and RAM per-launch without modifying permanent configuration.
- **Renderer of Choice**:
  - **GPU (`host`)**: Direct hardware acceleration via host GPU (OpenGL/Vulkan) for maximum framerate and smoothness.
  - **SwiftShader (`swiftshader_indirect`)**: CPU software rendering. Ideal for VPS, cloud instances, headless servers, or machines with unsupported GPU drivers.
  - **ANGLE (`angle_indirect`)**: Direct3D/Vulkan translation layer.
  - **Auto (`auto`)**: Lets the emulator pick the best available renderer.
- **Custom Kernel Boot**:
  - Seamlessly boot the AVD with your own compiled Linux kernel (`bzImage`, `vmlinux`, `Image.gz`, etc.).
  - Supports passing custom kernel command-line parameters (`-append "console=ttyS0 debug"`).
  - Place custom kernels in `./kernels/` for easy selection in the interactive menu.
- **Bidirectional File Sharing**:
  - **Live Auto-Sync Daemon**: Drop files into `./shared/to_device/` and they are automatically pushed to `/sdcard/Download/Shared/` on Android. Files created on Android are pulled to `./shared/from_device/`.
  - **Manual CLI Push / Pull**: `./launcher.sh share push <file>` and `./launcher.sh share pull`.
  - **QEMU VirtFS (9p Passthrough)**: Emulator is launched with `-virtfs` support for custom kernels compiled with 9p VirtFS.
- **Dual Mode (Interactive TUI + Scriptable CLI)**:
  - Run `./launcher.sh` without arguments for an interactive, ANSI-colored menu.
  - Run with CLI arguments for CI/CD, automation, or power-user terminal workflows.

---

## 📁 Directory Structure

```text
portableAVD-launcher/
├── launcher.sh            # Main executable entrypoint (Interactive TUI & CLI)
├── portable-avd.sh        # Alias / alternative entrypoint
├── config/
│   └── settings.conf      # Default configuration (renderer, cores, RAM, etc.)
├── bin/
│   ├── env.sh             # Portable environment loader & dynamic path relocator
│   ├── bootstrap_sdk.sh   # SDK, platform-tools & emulator installer
│   ├── java_setup.sh      # Java detector & portable OpenJDK 17 downloader
│   ├── avd_creator.sh     # System image downloader & granular AVD creator
│   ├── avd_launcher.sh    # Emulator runner (renderer, kernel, cores, RAM)
│   ├── file_share.sh      # File sharing daemon & transfer helpers
│   └── tui.sh             # Interactive terminal user interface
├── kernels/               # Drop custom compiled Linux kernels here
│   └── README.md
├── shared/                # Host-device file sharing bridge
│   ├── to_device/         # Files to push into Android
│   ├── from_device/       # Files pulled from Android
│   └── README.md
├── sdk/                   # Self-contained Android SDK (isolated from system)
├── data/                  # Self-contained user data & AVD storage
│   ├── .android/          # Isolated ADB keys and emulator configs
│   └── avd/               # Isolated virtual device disks and configs
└── logs/                  # Emulator session and debug logs
```

---

## 🚀 Quick Start

### 1. Prerequisites (Linux)
Ensure basic command-line tools are installed on your Linux distribution:
```bash
# Ubuntu / Debian
sudo apt-get update && sudo apt-get install -y curl unzip tar libgl1

# Arch Linux
sudo pacman -S curl unzip tar

# Fedora / RHEL
sudo dnf install -y curl unzip tar
```

Ensure your user has access to KVM hardware virtualization:
```bash
sudo usermod -aG kvm $USER
# (Log out and back in for group changes to take effect)
```

### 2. Launch the Interactive Menu
Simply run:
```bash
chmod +x launcher.sh
./launcher.sh
```
Follow the interactive prompts:
1. Select **[5]** to bootstrap the SDK and verify dependencies.
2. Select **[2]** to download and create an AVD (choose Android version, Google Play or Pure AOSP, cores, and RAM).
3. Select **[1]** to launch your AVD with your preferred renderer (GPU or SwiftShader) and optional custom kernel!

---

## 💻 CLI Usage & Automation

You can perform all actions directly from the command line:

### Create an AVD
```bash
# Android 14 with Google Play Store, 4 cores, 4GB RAM
./launcher.sh create --name Pixel14 --api 34 --variant playstore --cores 4 --ram 4096

# Pure AOSP (Clean Android, no Google services) with 8 cores, 8GB RAM
./launcher.sh create --name AOSP_Test --api 34 --variant aosp --cores 8 --ram 8192

# Android 13 with Google APIs (rootable, lightweight)
./launcher.sh create --name Dev13 --api 33 --variant google_apis --cores 4 --ram 4096
```

### Launch an AVD
```bash
# Launch with Host GPU acceleration (Best performance)
./launcher.sh run Pixel14 --gpu host

# Launch with SwiftShader (CPU software rendering - great for VPS/headless/Selkies)
./launcher.sh run Pixel14 --gpu swiftshader_indirect

# Launch in container / Selkies desktop with no audio issues
./launcher.sh run Pixel14 --gpu swiftshader_indirect --no-audio

# Launch with granular hardware overrides (override default cores & RAM)
./launcher.sh run Pixel14 --cores 6 --ram 8192

# Launch with a custom kernel
./launcher.sh run Pixel14 --kernel kernels/bzImage_custom

# Launch with custom kernel and kernel cmdline arguments
./launcher.sh run Pixel14 --kernel kernels/bzImage_custom --append "console=ttyS0 debug"

# Launch in headless mode (no GUI window)
./launcher.sh run Pixel14 --headless

# Launch with live shared folder auto-sync
./launcher.sh run Pixel14 --sync-share
```

### Manage AVDs
```bash
# List all configured AVDs with hardware specs
./launcher.sh list

# Reconfigure CPU cores and RAM for an existing AVD
./launcher.sh reconfig Pixel14 --cores 8 --ram 8192

# Wipe user data (factory reset)
./launcher.sh wipe Pixel14

# Delete an AVD
./launcher.sh delete Pixel14
```

### File Transfer & Shared Folders
```bash
# Push a file or folder from Linux host to Android (/sdcard/Download/Shared)
./launcher.sh share push my_app.apk

# Pull files from Android to ./shared/from_device/
./launcher.sh share pull

# Perform a bidirectional sync right now
./launcher.sh share sync

# Start / stop the background auto-sync daemon
./launcher.sh share start-daemon
./launcher.sh share stop-daemon

# View QEMU 9p VirtFS guest mount instructions
./launcher.sh share virtfs
```

### Shell & ADB Helpers
```bash
# Open interactive shell in Android
./launcher.sh shell

# Execute isolated adb command
./launcher.sh adb devices
./launcher.sh adb logcat
```

---

## 🛠️ Configuration (`config/settings.conf`)

You can modify default parameters in `config/settings.conf`:
```bash
DEFAULT_RENDERER="host"            # host, swiftshader_indirect, angle_indirect, auto
DEFAULT_CORES=4                    # Default CPU cores
DEFAULT_RAM_MB=4096                # Default RAM in MB
DEFAULT_DISK_MB=8192               # Default storage partition in MB
DEFAULT_HEAP_MB=512                # VM heap size
AUTO_SYNC_SHARE=true               # Start live file sync daemon automatically on boot
DEVICE_SHARE_DIR="/sdcard/Download/Shared"
ENABLE_QEMU_VIRTFS=true            # Enable QEMU -virtfs parameter for custom kernels
```

---

## 🐧 Custom Kernel Development

The launcher includes native support for booting custom Linux kernels:
1. Copy your compiled kernel binary (e.g. `bzImage`) into `./kernels/`.
2. Launch using:
   ```bash
   ./launcher.sh run <avd_name> --kernel kernels/bzImage
   ```
3. To mount the host's `./shared` folder inside Android with a 9p-enabled custom kernel:
   ```bash
   adb shell
   su
   mkdir -p /data/local/tmp/hostshare
   mount -t 9p -o trans=virtio hostshare /data/local/tmp/hostshare
   ```

---

## 🔒 100% Portability Guarantee

- **No Root or Global Install Required**: The launcher runs entirely from user space.
- **No System Pollution**: All Android SDK configurations, adb keys, cache, and system images are confined to `$PROJECT_DIR/sdk` and `$PROJECT_DIR/data`.
- **Relocatable**: If you move or rename the folder, `bin/env.sh` dynamically repairs all AVD `.ini` file paths on the fly.
