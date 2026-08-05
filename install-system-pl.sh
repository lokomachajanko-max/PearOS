#!/bin/bash
set -e

# ==============================================================================
# KONFIGURACJA
# Wklej tutaj BEZPOŚREDNI link pobierania pliku filesystem.squashfs z GoFile
# ==============================================================================
GOFILE_URL="TUTAJ_WKLEJ_BEZPOSREDNI_LINK_GOFILE"

echo "=================================================="
echo "      Instalator PearOS 1 (Netinstall)            "
echo "=================================================="

# Sprawdzenie uprawnień root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Uruchom skrypt z prawami roota: sudo bash install-system-pl.sh"
  exit 1
fi

# Sprawdzenie wymaganych narzędzi
echo "[1/6] Sprawdzanie narzędzi..."
apt-get update -qq
apt-get install -y -qq wget squashfs-tools parted e2fsprogs dosfstools grub-efi-amd64

# Wyszukiwanie dysków >= 30 GB
echo ""
echo "[2/6] Wyszukiwanie dysków (minimum 30 GB)..."
echo "--------------------------------------------------"

DISKS=$(lsblk -d -n -b -o NAME,SIZE,MODEL | awk '$2 >= 32212254720 {print $1 " (" $2/1073741824 " GB) - " $3}')

if [ -z "$DISKS" ]; then
    echo "[!] Nie znaleziono żadnego dysku o rozmiarze co najmniej 30 GB!"
    exit 1
fi

echo "Dostępne dyski:"
echo "$DISKS"
echo "--------------------------------------------------"
read -p "Podaj nazwę dysku do instalacji (np. sdb lub nvme0n1): " TARGET_DEV

TARGET_DISK="/dev/$TARGET_DEV"

if [ ! -b "$TARGET_DISK" ]; then
    echo "[!] Wybrany dysk $TARGET_DISK nie istnieje!"
    exit 1
fi

echo ""
echo "UWAGA: WSZYSTKIE DANE NA DYSKU $TARGET_DISK ZOSTANĄ USUNIĘTE!"
read -p "Czy na pewno chcesz kontynuować? (wpisz 'TAK'): " CONFIRM

if [ "$CONFIRM" != "TAK" ]; then
    echo "Instalacja przerwana."
    exit 0
fi

# Partycjonowanie dysku (GPT: EFI + ROOT)
echo ""
echo "[3/6] Partycjonowanie i formatowanie dysku $TARGET_DISK..."
umount ${TARGET_DISK}* 2>/dev/null || true

parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

# Określenie nazw partycji
if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
    EFI_PART="${TARGET_DISK}p1"
    ROOT_PART="${TARGET_DISK}p2"
else
    EFI_PART="${TARGET_DISK}1"
    ROOT_PART="${TARGET_DISK}2"
fi

# Formatowanie partycji
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F -L "PearOS" "$ROOT_PART"

# Montowanie partycji
MNT_DIR="/mnt/pearos_target"
mkdir -p "$MNT_DIR"
mount "$ROOT_PART" "$MNT_DIR"
mkdir -p "$MNT_DIR/boot/efi"
mount "$EFI_PART" "$MNT_DIR/boot/efi"

# Pobieranie obrazu systemu
echo ""
echo "[4/6] Pobieranie obrazu systemu z GoFile..."
TEMP_SQUASH="/tmp/filesystem.squashfs"
rm -f "$TEMP_SQUASH"
wget --show-progress -O "$TEMP_SQUASH" "$GOFILE_URL"

# Rozpakowywanie systemu na dysk
echo ""
echo "[5/6] Rozpakowywanie PearOS 1 na partycję ext4..."
unsquashfs -f -d "$MNT_DIR" "$TEMP_SQUASH"
rm -f "$TEMP_SQUASH"

# Konfiguracja rozruchu EFI / GRUB
echo ""
echo "[6/6] Instalowanie bootloadera GRUB..."
mount --bind /dev "$MNT_DIR/dev"
mount --bind /proc "$MNT_DIR/proc"
mount --bind /sys "$MNT_DIR/sys"

echo "LABEL=PearOS / ext4 defaults 0 1" > "$MNT_DIR/etc/fstab"

chroot "$MNT_DIR" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=PearOS --recheck
chroot "$MNT_DIR" update-grub

umount -R "$MNT_DIR"

echo "=================================================="
echo " PearOS 1 został zainstalowany na $TARGET_DISK! "
echo " Wyjmij instalator i zrestartuj komputer.        "
echo "=================================================="