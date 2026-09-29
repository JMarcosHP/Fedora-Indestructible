# Fedora Indestructible: Server + Headless Management

> *Maximum uptime, minimal fear—update your server with a safety net.*

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Disk Partitioning Scheme](#disk-partitioning-scheme)
- [Installation Steps](#installation-steps)
  - [Initial Setup](#initial-setup)
  - [Software and Network](#software-and-network)
  - [Disk Preparation](#disk-preparation)
  - [Partition Layout](#partition-layout)
  - [Subvolume Creation](#subvolume-creation)
  - [System Deployment](#system-deployment)
  - [Label the Btrfs Partition](#label-the-btrfs-partition)
  - [First Boot](#first-boot)
  - [System Tuning](#system-tuning)
  - [Snapper Setup](#snapper-setup)
  - [GRUB-Btrfs Setup](#grub-btrfs-setup)
  - [DNF5 Plugin Setup](#dnf5-plugin-setup)
- [Post-Installation](#post-installation)
- [Final Notes](#final-notes)

## Introduction

This guide sets up Fedora Server with Headless Management, static networking, and Cockpit, using the same flat BTRFS + Snapper + grub-btrfs stack as the desktop edition.


This configuration is ideal for:
- Homelab and production servers managed via Cockpit / SSH
- Systems where updates run via `dnf` or Cockpit's Software page
- Servers where `/srv` and `/var` data must survive rollbacks
- Anyone who wants openSUSE-style recovery on Fedora Server

## Prerequisites

- **Installation Media**: Fedora Server ISO, booted in UEFI mode
- **System Type**: UEFI firmware
- **Disk Space**: Minimum 30 GB (more for snapshots, and your specific server role)
- **RAM**: 4 GB minimum, 8 GB+ recommended
- **Internet Connection**: Required during installation


## Disk Partitioning Scheme

| Partition | Label | Type | Format | Size | Mount Point |
|-----------|-------|------|--------|------|-------------|
| **EFI System Partition** | `ESP` | EFI System Partition | FAT32 / vfat | 1 GiB | `/boot/efi` |
| **Swap** (optional) | `SWAP` | Swap | swap | As needed | - |
| **System Partition** | `SYSTEM` | Linux Filesystem | BTRFS | Remaining space | - |

**Subvolumes**:

| Subvolume | Mountpoint | Purpose |
|-----------|------------|---------|
| `root` | `/` | This is the main subvolume where the most important system directories will reside, like: `/boot`, `/etc`, `/lib`, `/lib64`, `/usr`, `/mnt`, `/media`, `/afs`, `/bin`, `/dev`, `/proc`, `/sys`, `/run`, `/sbin`, `/root`, `/tmp` |
| `home` | `/home` | Subvolume for user home directory, can be managed by snapper with different settings |
| `opt` | `/opt` | Third-party software, excluded from snapshots |
| `srv` | `/srv` | Server role data, excluded from snapshots |
| `usr_local` | `/usr/local` | Locally compiled software, scripts and source codes, excluded from snapshots |
| `var` | `/var` | Variable data like: logs, VMs, containers, DBs. This subvolume will be configured with COW disabled |

**Notes:**
- Labels `ESP` and `SYSTEM` are **mandatory**, post-install commands use `blkid -L ESP` / `blkid -L SYSTEM`.
- Unlike Debian or Arch, Fedora no longer needs `/var` split into multiple subvolumes. Since Fedora 36 the RPM database lives in `/usr/lib/sysimage/rpm` (with `/var/lib/rpm` as a symlink). Source: [RelocateRPMToUsr](https://fedoraproject.org/wiki/Changes/RelocateRPMToUsr). This allows boot-to-snapshot and transactional-style recovery.
- The downside: `snapper rollback` is deeply integrated with [SUSE's nested subvolume layout](https://rootco.de/2018-01-19-opensuse-btrfs-subvolumes/) and GRUB plugins. On Fedora it leaves bootloader entries inconsistent, but now we have better workarounds for snapper to have easy and flexible rollbacks, see [plugin explanation](../plugin-explanation.md).
- No dedicated subvolume for `/root` mountpoint (root's home), RHEL design enforces `/root` as a mandatory directory inside `/`. Sources: [Bug 710388](https://bugzilla.redhat.com/show_bug.cgi?id=710388), [wayback machine](https://web.archive.org/web/20260928213401/https://bugzilla.redhat.com/show_bug.cgi?id=710388), [anaconda.conf](https://github.com/rhinstaller/anaconda/blob/7ad05432f13483177d1ff16cb4dd0addc072d6b7/data/anaconda.conf#L271).

## Installation Steps

### Initial Setup

Boot the Fedora Server ISO.

#### 1. Set language and keyboard

![Server0](../screenshots/server/Server0.png)

### Software and Network

#### 2. Open Software Selection

On the Installation Summary, go to **Software Selection**.

![Server1](../screenshots/server/Server1.png)

#### 3. Enable Headless Management

Mark **Headless Management** and click Done.

![Server2](../screenshots/server/Server2.png)

#### 4. Configure network and hostname

Go to **Network & Hostname**, configure a static IP, DNS servers, and hostname as needed, then Apply and Done.

![Server3](../screenshots/server/Server3.png)

### Disk Preparation

#### 5. Open the storage editor

Go to **Installation Destination**, select the disk, choose **Advanced Custom (Blivet-GUI)**, click Done.

![Server4](../screenshots/server/Server4.png)

#### 6. Create a new GPT table

Delete old partitions if needed, then create a fresh GPT partition table, if you want a dual-boot setup, skip this step.

![Server5](../screenshots/server/Server5.png)

![Server6](../screenshots/server/Server6.png)

### Partition Layout

#### 7. Create the EFI partition

| Field | Value |
|-------|-------|
| Device type | Partition |
| Size | `1 GiB` |
| Filesystem | `EFI System Partition` |
| Label | `ESP` (important) |
| Mountpoint | `/boot/efi` |

![Server7](../screenshots/server/Server7.png)

> Optional: create a swap partition now if desired, otherwise skip.

#### 8. Create the system partition

| Field | Value |
|-------|-------|
| Device type | Partition |
| Size | Remaining disk space |
| Filesystem | `BTRFS` |
| Mountpoint | leave blank |

![Server8](../screenshots/server/Server8.png)

### Subvolume Creation

#### 9. Create subvolumes

Click the **Btrfs volume** folder and the **+** button.

![Server9](../screenshots/server/Server9.png)

![Server10](../screenshots/server/Server10.png)

Create the same six subvolumes as desktop (`root` → `/`, `home` → `/home`, `opt` → `/opt`, `srv` → `/srv`, `usr_local` → `/usr/local`, `var` → `/var`). Final layout should look like:

![Server11](../screenshots/server/Server11.png)

### System Deployment

#### 10. Confirm and set accounts

Click Done, accept the summary of changes.

![Server12](../screenshots/server/Server12.png)

Configure root and user accounts.

![Server13](../screenshots/server/Server13.png)

![Server14](../screenshots/server/Server14.png)

#### 11. Begin installation

![Server15](../screenshots/server/Server15.png)

![Server16](../screenshots/server/Server16.png)

![Server17](../screenshots/server/Server17.png)

After the installation completes, **do not reboot yet**.

### Label the Btrfs Partition

Because Blivet-GUI doesn't allow setting a Btrfs label, set it from a TTY:

#### 12. Switch to TTY and label

Press `Ctrl + Alt + F3`.

![Server18](../screenshots/server/Server18.png)

Find your OS device:

```bash
lsblk
```

![Server19](../screenshots/server/Server19.png)

Unmount and label:

```bash
cd /mnt
umount -l /mnt/sysroot
umount -l /mnt/sysimage
btrfs fi label /dev/sdX SYSTEM
```

Replace `/dev/sdX` with your Btrfs partition (e.g. `/dev/sda2`, `/dev/nvme0n1p2`).

And check with `blkid` to see if the label is set correctly:

![Server20](../screenshots/server/Server20.png)

Return to the installer (`Ctrl + Alt + F1` or F6 depending on ISO) and reboot.

### First Boot

#### 13. Log in

Boot the system and log into your user account (SSH, TTY or Cockpit).

### System Tuning

#### 14. Install utilities and clone the repo

```bash
sudo dnf install git snapper libdnf5-plugin-actions -y
```

```bash
sudo setenforce 0
cd ~/
git clone https://github.com/JMarcosHP/Fedora-Indestructible
```

> `scripts/first-boot-setup.sh` is provided as an automation entrypoint. Or you can run every command below manually.

#### 15. Remount the Btrfs top-level

```bash
SYSTEM="$(sudo blkid -L SYSTEM)"
ESP_UUID="$(sudo blkid -t LABEL=ESP -o value -s UUID)"
SYSTEM_UUID="$(sudo blkid -t LABEL=SYSTEM -o value -s UUID)"
sudo mkdir -p /mnt/fedora
sudo mount -o subvolid=5,noatime,nodiratime,space_cache=v2,compress=zstd:3 $SYSTEM /mnt/fedora
```

#### 16. Disable COW for `/var`

`/var` holds logs, crash dumps, VMs, containers, databases, and flatpaks. Random writes and fragmentation suffer under COW + compression:

```bash
cd /mnt/fedora
sudo mv var var-tmp
sudo btrfs su cre var
sudo chattr +C var
sudo cp -ar var-tmp/. var/
sudo btrfs su del var-tmp
VAR_ID="$(sudo btrfs subvolume show /mnt/fedora/var | awk '/Subvolume ID:/ {print $NF}')"
sudo umount -l /var && sudo mount -o subvolid=$VAR_ID,noatime,nodiratime,space_cache=v2 $SYSTEM /var
```

Verify with `lsattr -d /mnt/fedora/var` (should show `C`).

#### 17. Tune `fstab` with compression and space_cache

```bash
sudo bash -c '
ESP_UUID="'"$ESP_UUID"'"
SYSTEM_UUID="'"$SYSTEM_UUID"'"
( head -n 10 /mnt/fedora/root/etc/fstab; cat <<EOF
UUID=$ESP_UUID                             /boot/efi   vfat   noatime,nodiratime,errors=remount-ro,umask=0077,shortname=winnt     0 1
UUID=$SYSTEM_UUID  /           btrfs  subvol=root,noatime,nodiratime,space_cache=v2,compress=zstd:3       0 1
UUID=$SYSTEM_UUID  /home       btrfs  subvol=home,noatime,nodiratime,space_cache=v2,compress=zstd:3       0 1
UUID=$SYSTEM_UUID  /opt        btrfs  subvol=opt,noatime,nodiratime,space_cache=v2,compress=zstd:3        0 1
UUID=$SYSTEM_UUID  /srv        btrfs  subvol=srv,noatime,nodiratime,space_cache=v2,compress=zstd:3        0 1
UUID=$SYSTEM_UUID  /usr/local  btrfs  subvol=usr_local,noatime,nodiratime,space_cache=v2,compress=zstd:3  0 1
UUID=$SYSTEM_UUID  /var        btrfs  subvol=var,noatime,nodiratime,space_cache=v2                        0 1
EOF
) > /mnt/fedora/root/etc/fstab.tmp && mv -f /mnt/fedora/root/etc/fstab.tmp /mnt/fedora/root/etc/fstab
'
```

Then reload and verify:

```bash
sudo systemctl daemon-reload
sudo mount -av
```
Note: `/var` intentionally has **no** `compress=zstd:3`.

#### 18. Recompress with zstd

```bash
sudo btrfs filesystem defragment -r -v -czstd /mnt/fedora/{root,home,srv,opt,usr_local}
cd ~/
```

#### 19. Unhide the GRUB menu

Fedora hides GRUB on single-OS installs, you need it to boot snapshots:

```bash
sudo grub2-editenv list
sudo grub2-editenv - unset menu_auto_hide
```

#### 20. Tune `updatedb`

See `configuration/updatedb.conf`. Apply with:

```bash
sudo cp ~/Fedora-Indestructible/configuration/updatedb.conf /etc/updatedb.conf
```

This prunes `/.snapshots`, `/var/*` caches, and bind mounts so `locate` stays fast on Btrfs.

### Snapper Setup

#### 21. Create and tune the root config

```bash
sudo snapper -c root create-config /

SNAPPER_USER=$USER

sudo snapper -c root set-config \
  ALLOW_USERS=$SNAPPER_USER \
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

sudo systemctl disable snapper-boot.timer
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
```

### GRUB-Btrfs Setup

#### 22. Install grub-btrfs from COPR

```bash
sudo dnf copr enable jmarcoshp/grub-btrfs -y
sudo dnf check-update
sudo dnf install grub-btrfs -y
sudo systemctl enable --now grub-btrfsd.service

sudo sed -i \
  -e 's|^GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("@")|GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("root")|' \
  /etc/default/grub-btrfs/config

sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```
You can check the .spec source [here](https://github.com/JMarcosHP/fedora-builds-copr/tree/main/grub-btrfs)

### DNF5 Plugin Setup

#### 23. Install pre/post snapshot hooks and rollback utility

```bash
sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d/
sudo install -m 644 ~/Fedora-Indestructible/scripts/snapper-plugin-dnf5/snapper.actions /etc/dnf/libdnf5-plugins/actions.d/
sudo chmod +x /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
sudo install -m 755 ~/Fedora-Indestructible/scripts/snapper-plugin-dnf5/snapper-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/snapper-*.sh
sudo install -m 755 ~/Fedora-Indestructible/scripts/system-rollback /usr/local/bin/system-rollback
sudo chmod +x /usr/local/bin/system-rollback
```

#### 24. Unmount, restore SELinux, and reboot

```bash
sudo umount -R /mnt/fedora
sudo setenforce 1
sudo reboot
```

## Post-Installation

Verify after reboot:

```bash
snapper -c root ls
sudo systemctl is-active grub-btrfsd.service snapper-timeline.timer snapper-cleanup.timer
ls -l /usr/local/bin/snapper-*.sh /usr/local/bin/system-rollback
```

Ensure Cockpit is reachable at `https://<server-ip>:9090` for the rollback tests.

## Final Notes

You now have a headless Fedora Server with:
- A fully operational server with cockpit management
- Flat Btrfs layout with compression enabled
- Snapper + DNF5 pre/post snapshots
- Bootable GRUB snapshots
- `system-rollback` for safe full-system recovery

Next: test a rollback with Cockpit + CLI, see [Rollback Guide](../rollbacks.md#server-cockpit--system-rollback). Check the [troubleshooting section](../rollbacks.md#troubleshooting) if you find issues.

---

**Need help?** Check the [main documentation](../README.md) or open an [issue](https://github.com/JMarcosHP/Fedora-Indestructible/issues).
