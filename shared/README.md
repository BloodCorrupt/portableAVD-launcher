# Bidirectional Shared Folder

This folder allows transferring files between your Linux host machine and the running Android Virtual Device (AVD).

## Directory Structure
- `shared/to_device/`: Place files here that you want transferred to the Android device.
- `shared/from_device/`: Files downloaded from Android's shared directory will appear here.

## How It Works

### Method 1: Live Auto-Sync Daemon (Default)
When you launch an AVD with live sync enabled (`./launcher.sh run <avd_name> --sync-share` or in the TUI), a background sync daemon automatically pushes files from `to_device/` to `/sdcard/Download/Shared/` on Android, and pulls any new files created on the device into `from_device/`.

### Method 2: Manual Push & Pull Commands
You can manually transfer files anytime via CLI:
```bash
# Push a file to Android
./launcher.sh share push myfile.txt

# Pull files from Android
./launcher.sh share pull

# Sync both folders right now
./launcher.sh share sync
```

### Method 3: QEMU VirtFS (9p Mount)
For custom kernels compiled with 9p VirtFS support:
The host's `shared/` folder is passed to QEMU with the mount tag `hostshare`.
Inside the Android terminal (with root/su):
```bash
mount -t 9p -o trans=virtio hostshare /data/local/tmp/hostshare
```
