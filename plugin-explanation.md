# Snapper DNF5 Plugin + system-rollback

## Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [How It Works](#how-it-works)
  - [1. Transaction Detection](#1-transaction-detection)
  - [2. Important-Flag Gathering](#2-important-flag-gathering)
  - [3. Description Building](#3-description-building)
  - [4. PRE Snapshot](#4-pre-snapshot)
  - [5. POST Snapshot + WAL Fix](#5-post-snapshot--wal-fix)
  - [6. Bootable Snapshots](#6-bootable-snapshots)
  - [7. Safe Rollback](#7-safe-rollback)
- [Installation](#installation)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)
  - [Check Snapshot Creation and grub-btrfs submenu state](#check-snapshot-creation-and-grub-btrfs-submenu-state)
  - [Verify Rollback Safety with Dry-Run](#verify-rollback-safety-with-dry-run)
- [Technical Details](#technical-details)
  - [Plugin Location](#plugin-location)
  - [Execution Environment](#execution-environment)
- [Credits](#credits)
- [See Also](#see-also)

## Overview

The Snapper [DNF5 plugin](https://github.com/JMarcosHP/Fedora-Indestructible/tree/main/scripts/snapper-plugin-dnf5) and the [system-rollback](https://github.com/JMarcosHP/Fedora-Indestructible/blob/main/scripts/system-rollback) utility are the critical components that bridge the gap between snapshot creation and bootable system recovery. Unlike openSUSE, which has native integration between Snapper, Zypper, and the bootloader, Fedora requires additional configuration to ensure DNF5 transactions are snapshotted and rollbacks keep GRUB consistent.

## The Problem

Two gaps exist on vanilla Fedora:

1. **No automatic snapshots**: stock DNF5 never creates Snapper pre/post pairs, so a broken `dnf update` or Discover upgrade has no restore point. This issue parallels [openSUSE Snapper Issue #722](https://github.com/openSUSE/snapper/issues/722), bootloader and snapshot state drift apart without integration.

2. **Unsafe rollback primitive**: `snapper rollback` changes the default subvolume and assumes [SUSE's nested subvolume layout](https://rootco.de/2018-01-19-opensuse-btrfs-subvolumes/). On Fedora's flat layout (and any other distro) it leaves bootloader entries and the Btrfs layout inconsistent, producing unreliable restores.

## The Solution

This repository ships two cooperating pieces:

- A `libdnf5-plugin-actions` hook set (`snapper.actions` + `snapper-*.sh`) that snapshots every transaction with accurate descriptions and an `important=yes|no` flag.
- A `system-rollback` script that restores by hand. Renames the target subvolume, creates a writable copy from a RO snapper snapshot and migrates child subvolumes, without ever touching the default subvolume (in this case btrfs top-level ID 5) similar to btrfs-assistant. Allowing to keep GRUB entries consistent.

## How It Works

### 1. Transaction Detection

Every DNF5 transaction (CLI `dnf`, Discover/PackageKit via `dnf5daemon`, Cockpit) triggers `libdnf5-plugin-actions` hooks defined in `scripts/snapper-plugin-dnf5/snapper.actions`:

- `goal_resolved:*:in/out` → `snapper-important.sh ${pid} ${pkg.name}`
- `pre_transaction` → `snapper-pre.sh ${pid}` + `snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}` (incoming only)
- `post_transaction` → `snapper-post.sh ${pid}`

### 2. Important-Flag Gathering

`snapper-important.sh` evaluates each resolved package against critical-subsystem patterns (kernel, dracut, glibc, systemd, grub2, shim, firmware, NVIDIA/AMD, Mesa/Vulkan, ROCm) and accumulates `important=yes|no` per PID in `/run/snapper-actions/`. A single match flags the whole transaction — used for Snapper retention (`NUMBER_LIMIT_IMPORTANT`).

### 3. Description Building

`snapper-desc.sh` inspects the originating process:
- GUI (`dnf5daemon` / `packagekitd`) → `GUI`
- CLI → normalized command (`upgrade`→`update`, `erase`→`remove`)

`snapper-gui-pkg.sh` tallies only **incoming** (`direction=in`) package actions. Outgoing entries are ignored by design — every upgrade produces both an incoming new version and an outgoing old version, so counting both double-counts and makes bulk updates look like mass removals. At POST time, upgrades dominating → `GUI update`, otherwise → `GUI install <first package>`.

### 4. PRE Snapshot

`snapper-pre.sh` creates the PRE snapshot (`snapper -c root create -c number -t pre`) with description and `important=` userdata, stores its number by PID, and ensures `/usr/lib/sysimage/libdnf5` exists (missing dir on fresh installs leaves orphaned PRE snapshots).

### 5. POST Snapshot + WAL Fix

`snapper-post.sh` refines the GUI description from the tally, updates the PRE description, applies the SQLite WAL checkpoint (`snapper-wal-checkpoint.sh`, needed on Fedora 44+ for libdnf5 consistency, best-effort), creates the linked POST snapshot, and cleans `/run/snapper-actions/` state.

### 6. Bootable Snapshots

`grub-btrfsd` watches `/.snapshots` and regenerates the GRUB snapshot submenu. `GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("root")` hides the duplicate top-level entry.

### 7. Safe Rollback

`system-rollback <ID>` (see `scripts/system-rollback` header for full usage) uses snapper and btrfs as backend:

1. Mounts Btrfs top-level (`subvolid=5`) temporarily
2. Locates `<target>/.snapshots/<ID>/snapshot`, derives target from the path (even when booted from a read-only snapshot)
3. Records direct child subvolumes (e.g. `.snapshots`)
4. Renames target → `<target>_backup_<timestamp>`
5. Creates a new **writable** snapshot in place of the target
6. Migrates children into the new target, verifies that the rollback is complete and consistent
7. Leaves a backup of the original target

On failure it auto-undoes (moves children back, deletes incomplete snapshot, renames backup back) so a failed run needs no manual recovery, but leaves the backup in case you want to undo the rollback or you selected a wrong snapshot number.

## Installation

The plugin and utility are installed during first-boot setup:

```bash
sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d/
sudo install -m 644 ~/Fedora-Indestructible/scripts/snapper-plugin-dnf5/snapper.actions /etc/dnf/libdnf5-plugins/actions.d/
sudo chmod +x /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
sudo install -m 755 ~/Fedora-Indestructible/scripts/snapper-plugin-dnf5/snapper-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/snapper-*.sh
sudo install -m 755 ~/Fedora-Indestructible/scripts/system-rollback /usr/local/bin/system-rollback
sudo chmod +x /usr/local/bin/system-rollback
```

## Compatibility

`system-rollback` and snapper dnf plugins are

**Compatible with:**
- Distros that ship DNF5 by default (only for snapper plugin, rollback script is independent)
- Distros using snapper snapshots
- Systems with a flat BTRFS subvolume layout

**Requirements:**
- GRUB2 as the bootloader
- `grub-btrfs` installed and configured for snapshot menu
- Snapper with a configuration for `/` (the name can be anyone, but `system-rollback` expects `root` by default, this behavior can be changed with `-c <config>` option or `CONFIG` variable inside the script)
- BTRFS filesystem with snapshot-capable subvolumes
- `libdnf5-plugin-actions` installed

## Troubleshooting

### Check Snapshot Creation and grub-btrfs submenu state

```bash
sudo snapper -c root ls
sudo systemctl status grub-btrfsd
```

### Verify Rollback Safety with Dry-Run

```bash
sudo btrfs subvolume get-default /
sudo system-rollback -n <snapper snapshot number ID> # -n = dry-run, no changes made
```

Default must stay ID `5`. The script warns if it differs.


## Technical Details

### Plugin Location

```
# Hooks
/etc/dnf/libdnf5-plugins/actions.d/snapper.actions
# Helpers
/usr/local/bin/snapper-{pre,post,desc,gui-pkg,important,wal-checkpoint}.sh
# Rollback
/usr/local/bin/system-rollback
# State
/run/snapper-actions/snapper_*_${PID}
```

### Execution Environment

Hooks run with root privileges inside the DNF5 transaction context, keyed by PID so parallel transactions never mix state.

## Credits

DNF5 Snapper plugin original code by [Sysguides](https://github.com/SysGuides/sysguides-snapper-fedora). Enhanced Snapshot description logic is original from this repository.

Special thanks to [btrfs-assistant](https://gitlab.com/btrfs-assistant/btrfs-assistant) developers for their original code logic idea for btrfs rollbacks.

## See Also

- [Installation variants](https://github.com/JMarcosHP/Fedora-Indestructible#installation-variants)
- [Rollback Guide](https://github.com/JMarcosHP/Fedora-Indestructible/blob/main/rollbacks.md)
- [openSUSE Snapper Issue #722](https://github.com/openSUSE/snapper/issues/722)
- [Fedora Wiki - Relocate RPM to /usr](https://fedoraproject.org/wiki/Changes/RelocateRPMToUsr)
