#!/bin/bash
set -e

# ==============================================================================
# CONFIGURATION
# Paste your DIRECT download link for filesystem.squashfs from GoFile below
# ==============================================================================
GOFILE_URL="PASTE_YOUR_DIRECT_GOFILE_LINK_HERE"

echo "=================================================="
echo "      PearOS 1 Installer (Netinstall)             "
echo "=================================================="

# Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root: sudo bash install-system-en.sh"
  exit 1
fi

# Check required utilities
echo "[1/6] Checking required packages..."
apt-get update -qq
apt-get install -y -qq wget squashfs-tools parted e2fsprogs dosfstools grub-efi-amd64

# Scan for drives >= 30 GB
echo ""
echo "[2/6] Scanning for available drives (minimum 30 GB)..."
echo "--------------------------------------------------"

DISKS=$(lsblk -d -n -b -o NAME,SIZE,MODEL | awk '$2 >= 32212254720 {print $1 " (" $2/1073741824 " GB) - " $3}')

if [ -z "$DISKS" ]; then
    echo "[!] No drives with at least 30 GB of storage were found!"
    exit 1
fi

echo "Available drives:"
echo "$DISKS"
echo "--------------------------------------------------"
read -p "Enter the device name to install on (e.g., sdb or nvme0n1): " TARGET_DEV

TARGET_DISK="/dev/$TARGET_DEV"

if [ ! -b "$TARGET_DISK" ]; then
    echo "[!] Target drive $TARGET_DISK does not exist!"
    exit 1
fi

echo ""
echo "WARNING: ALL DATA ON DRIVE $TARGET_DISK WILL BE WIPED!"
read -p "Are you sure you want to proceed? (type 'YES'): " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Installation aborted."
    exit 0
fi

# Partitioning drive (GPT: EFI + ROOT)
echo ""
echo "[3/6] Partitioning and formatting $TARGET_DISK..."
umount ${TARGET_DISK}* 2>/dev/null || true

parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

# Define partition naming scheme
if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
    EFI_PART="${TARGET_DISK}p1"
    ROOT_PART="${TARGET_DISK}p2"
else
    EFI_PART="${TARGET_DISK}1"
    ROOT_PART="${TARGET_DISK}2"
fi

# Format partitions
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F -L "PearOS" "$ROOT_PART"

# Mount target paths
MNT_DIR="/mnt/pearos_target"
mkdir -p "$MNT_DIR"
mount "$ROOT_PART" "$MNT_DIR"
mkdir -p "$MNT_DIR/boot/efi"
mount "$EFI_PART" "$MNT_DIR/boot/efi"

# Download system image
echo ""
echo "[4/6] Downloading system image from GoFile..."
TEMP_SQUASH="/tmp/filesystem.squashfs"
rm -f "$TEMP_SQUASH"
wget --show-progress -O "$TEMP_SQUASH" "$GOFILE_URL"

# Extract system files
echo ""
echo "[5/6] Unsquashing PearOS 1 onto ext4 partition..."
unsquashfs -f -d "$MNT_DIR" "$TEMP_SQUASH"
rm -f "$TEMP_SQUASH"

# GRUB & EFI Setup
echo ""
echo "[6/6] Installing GRUB bootloader..."
mount --bind /dev "$MNT_DIR/dev"
mount --bind /proc "$MNT_DIR/proc"
mount --bind /sys "$MNT_DIR/sys"

echo "LABEL=PearOS / ext4 defaults 0 1" > "$MNT_DIR/etc/fstab"

chroot "$MNT_DIR" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=PearOS --recheck
chroot "$MNT_DIR" update-grub

umount -R "$MNT_DIR"

echo "=================================================="
echo " PearOS 1 successfully installed on $TARGET_DISK! "
echo " Remove the installer media and reboot your PC.   "
echo "=================================================="