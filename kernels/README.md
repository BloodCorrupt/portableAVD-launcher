# Custom Android Emulator Kernels

Place your custom compiled Linux kernel binaries (e.g., `bzImage`, `vmlinux`, `Image.gz`, or `kernel-ranchu`) in this directory.

## Recommended Kernel Architectures
- **x86_64 AVDs**: Use x86_64 Linux kernel images (typically `bzImage` or `arch/x86/boot/bzImage`).
- **arm64 AVDs**: Use ARM64 kernel images (`Image` or `Image.gz`).

## How to Launch with a Custom Kernel
1. Copy your compiled kernel into this folder, for example: `kernels/bzImage_custom`
2. Launch using the launcher:
   ```bash
   ./launcher.sh run <avd_name> --kernel kernels/bzImage_custom
   ```
   Or via the interactive menu (`./launcher.sh` -> Launch AVD -> Select Custom Kernel).

## Kernel Arguments
You can pass custom kernel command-line arguments using `--append`:
```bash
./launcher.sh run <avd_name> --kernel kernels/bzImage_custom --append "console=ttyS0 debug androidboot.hardware=ranchu"
```

## Shared Folder Support via QEMU VirtFS (9p)
If your custom kernel is compiled with:
- `CONFIG_NET_9P=y`
- `CONFIG_NET_9P_VIRTIO=y`
- `CONFIG_9P_FS=y`
- `CONFIG_9P_FS_POSIX_ACL=y`

You can mount the host's `shared/` folder directly in Android:
```bash
adb shell
su
mkdir -p /data/local/tmp/hostshare
mount -t 9p -o trans=virtio hostshare /data/local/tmp/hostshare
```
