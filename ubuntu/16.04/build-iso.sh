#!/bin/bash
set -e

# lookup specific binaries
: "${BIN_7Z:=$(type -P 7z)}"
: "${BIN_MKISOFS:=$(type -P mkisofs)}"

# get parameters
SSH_PUBLIC_KEY_FILE=${1:-"$HOME/.ssh/id_rsa.pub"}
TARGET_ISO=${2:-"`pwd`/ubuntu-16.04-netboot-amd64-unattended.iso"}

# check if ssh key exists
if [ ! -f "$SSH_PUBLIC_KEY_FILE" ];
then
    echo "Error: public SSH key $SSH_PUBLIC_KEY_FILE not found!"
    exit 1
fi

# get directories
CURRENT_DIR="`pwd`"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TMP_DOWNLOAD_DIR="`mktemp -d`"
TMP_DISC_DIR="`mktemp -d`"
TMP_INITRD_DIR="`mktemp -d`"

# download and extract netboot iso
SOURCE_ISO_URL="http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/mini.iso"
cd "$TMP_DOWNLOAD_DIR"
wget -4 "$SOURCE_ISO_URL" -O "./netboot.iso"
"$BIN_7Z" x "./netboot.iso" "-o$TMP_DISC_DIR"

# patch boot menu
cd "$TMP_DISC_DIR"
dos2unix "./isolinux.cfg"
patch -p1 -i "$SCRIPT_DIR/custom/boot-menu.patch"

# prepare assets
cd "$TMP_INITRD_DIR"
mkdir "./custom"
cp "$SCRIPT_DIR/custom/preseed.cfg" "./preseed.cfg"
cp "$SSH_PUBLIC_KEY_FILE" "./custom/userkey.pub"
cp "$SCRIPT_DIR/custom/ssh-host-keygen.service" "./custom/ssh-host-keygen.service"

# append assets to initrd image
cd "$TMP_INITRD_DIR"
cat "$TMP_DISC_DIR/initrd.gz" | gzip -d > "./initrd"
echo "./preseed.cfg" | fakeroot cpio -o -H newc -A -F "./initrd"
find "./custom" | fakeroot cpio -o -H newc -A -F "./initrd"
cat "./initrd" | gzip -9c > "$TMP_DISC_DIR/initrd.gz"

# build iso
cd "$TMP_DISC_DIR"
rm -r '[BOOT]'
"$BIN_MKISOFS" -r -V "Capture Agent Install" \
  -cache-inodes -J -l -b isolinux.bin -c boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "${TARGET_ISO}" ./
isohybrid "${TARGET_ISO}"


# go back to initial directory
cd "$CURRENT_DIR"

# delete all temporary directories
rm -r "$TMP_DOWNLOAD_DIR"
rm -r "$TMP_DISC_DIR"
rm -r "$TMP_INITRD_DIR"

# done
echo "Next steps: install system, login via root, adjust the authorized keys, set a root password (if you want to), deploy via ansible (if applicable), enjoy!"
