#!/usr/bin/env bash
#
# first-boot-setup.sh - Finish the Fedora Indestructible setup.
# Covers guide steps 12-21: Btrfs tuning, Snapper, grub-btrfs, DNF5 plugin.
# Usage: sudo ./first-boot-setup.sh

set -euo pipefail

# Must run as superuser.
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root (sudo ./first-boot-setup.sh)." >&2
    exit 1
fi

# Paths relative to this script (repo/scripts/first-boot-setup.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SNAPPER_SRC="$REPO_ROOT/scripts/snapper-plugin-dnf5"
ROLLBACK_SRC="$REPO_ROOT/scripts/system-rollback"
UPDATEDB_SRC="$REPO_ROOT/configuration/updatedb.conf"

# Invoking user gets Snapper access (root when run without sudo).
SNAPPER_USER="${SUDO_USER:-root}"

# Required repo files must exist before changing anything.
for f in "$SNAPPER_SRC/snapper.actions" "$ROLLBACK_SRC" "$UPDATEDB_SRC"; do
    [[ -e "$f" ]] || { echo "ERROR: required file not found: $f" >&2; exit 1; }
done

# Print current step.
step() { echo "==> [Step $1/21] $2"; }

# SELinux permissive during filesystem relabeling work.
setenforce 0

# Step 12: mount Btrfs top-level (subvolid=5) for raw subvolume access.
step "12" "Remount Btrfs top-level"
SYSTEM="$(blkid -L SYSTEM)"
ESP_UUID="$(blkid -t LABEL=ESP -o value -s UUID)"
SYSTEM_UUID="$(blkid -t LABEL=SYSTEM -o value -s UUID)"
mkdir -p /mnt/fedora
mount -o subvolid=5,noatime,nodiratime,space_cache=v2,compress=zstd:3 "$SYSTEM" /mnt/fedora

# Step 13: recreate /var with COW disabled (databases, VMs, containers).
step "13" "Disable COW for /var"
cd /mnt/fedora
mv var var-tmp
btrfs subvolume create var
chattr +C var
cp -ar var-tmp/. var/
btrfs subvolume delete var-tmp
VAR_ID="$(btrfs subvolume show /mnt/fedora/var | awk '/Subvolume ID:/ {print $NF}')"
umount -l /var && mount -o "subvolid=$VAR_ID",noatime,nodiratime,space_cache=v2 "$SYSTEM" /var
# Expect the C flag below.
lsattr -d /mnt/fedora/var

# Step 14: rewrite fstab with zstd compression (none for /var by design).
# Any pre-existing swap entry is preserved as-is.
step "14" "Tune fstab"
FSTAB_FILE=/mnt/fedora/root/etc/fstab
SWAP_ENTRIES="$(awk '$1 !~ /^#/ && $3 == "swap"' "$FSTAB_FILE")"
(
    head -n 10 "$FSTAB_FILE" | awk '$1 ~ /^#/ || $3 != "swap"'
    cat <<EOF
UUID=$ESP_UUID                             /boot/efi   vfat   noatime,nodiratime,errors=remount-ro,umask=0077,shortname=winnt     0 1
UUID=$SYSTEM_UUID  /           btrfs  subvol=root,noatime,nodiratime,space_cache=v2,compress=zstd:3       0 1
UUID=$SYSTEM_UUID  /home       btrfs  subvol=home,noatime,nodiratime,space_cache=v2,compress=zstd:3       0 1
UUID=$SYSTEM_UUID  /opt        btrfs  subvol=opt,noatime,nodiratime,space_cache=v2,compress=zstd:3        0 1
UUID=$SYSTEM_UUID  /srv        btrfs  subvol=srv,noatime,nodiratime,space_cache=v2,compress=zstd:3        0 1
UUID=$SYSTEM_UUID  /usr/local  btrfs  subvol=usr_local,noatime,nodiratime,space_cache=v2,compress=zstd:3  0 1
UUID=$SYSTEM_UUID  /var        btrfs  subvol=var,noatime,nodiratime,space_cache=v2                        0 1
EOF
    if [[ -n "$SWAP_ENTRIES" ]]; then
        # Realign to the same columns as the injected entries above.
        awk '{ printf "%-41s  %-10s  %-5s  %-59s  %s %s\n", $1, $2, $3, $4, $5, $6 }' <<< "$SWAP_ENTRIES"
    fi
) > "$FSTAB_FILE.tmp" && mv -f "$FSTAB_FILE.tmp" "$FSTAB_FILE"
systemctl daemon-reload
mount -av

# Step 15: defragment existing data with zstd.
step "15" "Recompress with zstd"
btrfs filesystem defragment -r -v -czstd /mnt/fedora/{root,home,srv,opt,usr_local}
cd /

# Step 16: show GRUB menu (needed to boot snapshots).
step "16" "Unhide GRUB menu"
grub2-editenv list
grub2-editenv - unset menu_auto_hide

# Step 17: keep locate fast on Btrfs (skip snapshots and bind mounts).
step "17" "Tune updatedb"
cp "$UPDATEDB_SRC" /etc/updatedb.conf

# Step 18: create Snapper config for / with timeline retention.
step "18" "Configure Snapper"
snapper -c root create-config /
snapper -c root set-config \
    ALLOW_USERS="$SNAPPER_USER" \
    SYNC_ACL=yes \
    BACKGROUND_COMPARISON=yes \
    NUMBER_CLEANUP=yes \
    NUMBER_MIN_AGE=1800 \
    NUMBER_LIMIT=20 \
    NUMBER_LIMIT_IMPORTANT=20 \
    TIMELINE_CREATE=yes \
    TIMELINE_CLEANUP=yes \
    TIMELINE_MIN_AGE=1800 \
    TIMELINE_LIMIT_HOURLY=3 \
    TIMELINE_LIMIT_DAILY=2 \
    TIMELINE_LIMIT_WEEKLY=1 \
    TIMELINE_LIMIT_MONTHLY=0 \
    TIMELINE_LIMIT_YEARLY=0 \
    EMPTY_PRE_POST_CLEANUP=yes \
    EMPTY_PRE_POST_MIN_AGE=3600
systemctl disable snapper-boot.timer
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

# Step 19: bootable snapshots in GRUB via COPR package.
step "19" "Install grub-btrfs"
dnf copr enable jmarcoshp/grub-btrfs -y
dnf check-update || true
dnf install grub-btrfs -y
systemctl enable --now grub-btrfsd.service
sed -i \
    -e 's|^GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("@")|GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("root")|' \
    /etc/default/grub-btrfs/config
grub2-mkconfig -o /boot/grub2/grub.cfg

# Step 20: DNF5 pre/post snapshot hooks and rollback utility.
step "20" "Install DNF5 plugin and system-rollback"
mkdir -p /etc/dnf/libdnf5-plugins/actions.d/
install -m 644 "$SNAPPER_SRC/snapper.actions" /etc/dnf/libdnf5-plugins/actions.d/
chmod +x /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
install -m 755 "$SNAPPER_SRC"/snapper-*.sh /usr/local/bin/
chmod +x /usr/local/bin/snapper-*.sh
install -m 755 "$ROLLBACK_SRC" /usr/local/bin/system-rollback
chmod +x /usr/local/bin/system-rollback

# Step 21: cleanup, restore SELinux, reboot with countdown.
step "21" "Unmount and reboot"
umount -R /mnt/fedora
setenforce 1
echo "Setup complete. Rebooting in 5 seconds (Ctrl+C to cancel)..."
for i in 5 4 3 2 1; do
    echo "$i..."
    sleep 1
done
reboot
