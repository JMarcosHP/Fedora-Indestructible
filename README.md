# Fedora Indestructible 🛡️

> *Because your system should survive anything—even your own mistakes.*

## Table of Contents

- [Overview](#overview)
- [What Makes It "Indestructible"?](#what-makes-it-indestructible)
- [Installation variants](#installation-variants)
- [Prerequisites](#prerequisites)
- [Installation Guides](#installation-guides)
- [Key Features Explained](#key-features-explained)
- [Post-Installation automated script](#post-installation-automated-script)
- [Rolling Back Your System](#rolling-back-your-system)
- [Contributing](#contributing)
- [Support the Project](#support-the-project)
- [License](#license)
- [Acknowledgments](#acknowledgments)
- [Resources that complemented every guide in this repository](#resources-that-complemented-every-guide-in-this-repository)

## Overview

**Fedora Indestructible** is a comprehensive guide for building a resilient, snapshot-capable Fedora system using BTRFS and Snapper. This setup combines Fedora's cutting-edge software with the advanced features of BTRFS snapshots, allowing you to roll back system changes effortlessly and recover from catastrophic failures.

Whether you're experimenting with new software, performing risky upgrades, or simply want peace of mind, this guide will help you create a system that's virtually indestructible.

## What Makes It "Indestructible"?

- **Atomic Snapshots**: Take instant snapshots of your entire system before any major change
- **Effortless Rollbacks**: Boot directly into previous snapshots from GRUB if something breaks
- **Fine-Grained Control**: Exclude specific directories (like `/home`, `/srv`, `/var`, etc) from snapshots
- **Automatic Snapshots**: DNF5 transactions and timeline-based snapshots capture your system state throughout the day
- **Desktop & Server Ready**: Includes configurations for Workstation, KDE Plasma, and Fedora Server with Cockpit
- **Safe Manual Rollback**: Custom `system-rollback` utility that never touches the default subvolume, keeping GRUB consistent

## Installation variants

This repository provides two installation variants:

### Desktop Systems (x86_64, UEFI)
- **Workstation + KDE Plasma**: Anaconda Web graphical install with manual partitioning

### Server Systems (x86_64, UEFI)
- **Fedora Server + Headless Management**: Anaconda GTK graphical install with static IP, Cockpit, and Blivet-GUI manual partitioning

All configurations use:
- BTRFS with Snapper for snapshot management
- Flat subvolume layout inspired by openSUSE, adapted for Fedora / RHEL
- GRUB2 with grub-btrfs integration (via `jmarcoshp/grub-btrfs` COPR)
- Anaconda installer with custom partitioning
- Custom DNF5 `libdnf5-plugin-actions` integration for pre/post snapshots
- Rollback utilities for different variants (CLI/GUI) btrfs-assistant and `system-rollback` script

## Prerequisites

### Recommended Installation Media

Download the official Fedora ISO for your edition:

- **[Fedora Workstation](https://getfedora.org/workstation/download/)** - GNOME desktop experience
- **[Fedora KDE Plasma](https://getfedora.org/spins/kde/download/)** - KDE Plasma desktop experience
- **[Fedora Server](https://getfedora.org/server/download/)** - Headless / Cockpit-managed server

Write the ISO to USB with [Fedora Media Writer](https://getfedora.org/mediawriter/) and boot in UEFI mode.

### Minimum Requirements

- 64-bit x86_64 processor (UEFI firmware)
- 4 GB RAM minimum (8 GB+ recommended)
- 30 GB disk space (more for `/home`, application data and snapshots)
- Internet connection during installation and post-reboot setup

*All installation guides erase target disk as an example, but can be used for dual-boot setups*


## Installation Guides

### Fedora Systems x86_64 UEFI

| Guide | Edition | Desktop / Management |
|-------|---------|----------------------|
| [Desktop (Workstation + KDE)](guides/DESKTOP.md) | Workstation / KDE Plasma Spin | GNOME / KDE Plasma + Discover | 
| [Server + Headless Management](guides/SERVER.md) | Fedora Server | Cockpit + SSH |

## Key Features Explained

### BTRFS Subvolume Layout

The installation creates a carefully designed flat subvolume structure that:

- Keeps the RPM database consistent across snapshots (`/usr/lib/sysimage/rpm` since Fedora 36, no need to split `/var` like Debian)
- Excludes user data, server data, and caches from automatic snapshots
- Prevents data loss when rolling back system changes
- Optimizes disk space usage with `zstd:3` compression and `space_cache`

Flat layout under subvolid 5:

| Subvolume | Mountpoint | Purpose |
|-----------|------------|---------|
| `root` | `/` | Main system (`/boot`, `/etc`, `/usr`, `/root`, …) |
| `home` | `/home` | User home directory, manageable with its own Snapper config |
| `opt` | `/opt` | Third-party software, excluded from rollbacks |
| `srv` | `/srv` | Server roles data, excluded from rollbacks |
| `usr_local` | `/usr/local` | Locally compiled software, scripts and source codes, excluded from rollbacks |
| `var` | `/var` | Logs, VMs, containers, DBs. COW disabled (`chattr +C`), no compression |

> For `/root`: no dedicated subvolume is created. RHEL design (following FHS) enforces `/root` as a mandatory directory inside `/`. See [Bug 710388](https://bugzilla.redhat.com/show_bug.cgi?id=710388) and [anaconda.conf](https://github.com/rhinstaller/anaconda/blob/7ad05432f13483177d1ff16cb4dd0addc072d6b7/data/anaconda.conf#L271).

### Snapper Integration

Automatic snapshot management with:

- Pre/post snapshots around every DNF5 / Discover / Cockpit transaction
- `important=yes` flag for kernel, bootloader, driver, and systemd updates
- Hourly, daily, and weekly timeline snapshots
- Configurable retention policies
- Bootable snapshots accessible from GRUB

This [plugin](https://github.com/JMarcosHP/Fedora-Indestructible/tree/main/scripts/snapper-plugin-dnf5) bridges the gap between Fedora and openSUSE's native snapshot integration, making rollbacks truly seamless.
For a detailed explanation about this plugin please [see](plugin-explanation.md).

### System-Rollback Utility

A custom rollback script that:

- Swaps the `root` subvolume by hand instead of using `snapper rollback`
- Never touches the default subvolume (stays `subvolid=5`), so GRUB entries remain consistent
- Migrates child subvolumes (`.snapshots`) into the restored system
- Keeps a timestamped `root_backup_*` so every rollback is reversible
- Logs operations and supports dry-run, list, and clean modes

Unlike `snapper rollback`, which is deeply integrated with [SUSE's nested subvolume layout](https://rootco.de/2018-01-19-opensuse-btrfs-subvolumes/) and leaves Fedora bootloader entries inconsistent, this approach keeps the flat layout intact.

## Post-Installation automated script

After completing your installation, a script is provided to finish the setup from the guide (Fstab, snapper config, grub-btrfs, DNF5 plugin, updatedb tuning):

```bash
cd ~/Fedora-Indestructible/scripts
chmod +x first-boot-setup.sh
sudo ./first-boot-setup.sh
```

You can check the full command list in [Desktop](guides/DESKTOP.md#system-tuning) and [Server](guides/SERVER.md#system-tuning) guides.


## Rolling Back Your System

Learn how to perform system rollbacks and manage snapshots in the [Rollback Guide](rollbacks.md).

## Contributing

Contributions are welcome! If you find issues, have suggestions, or want to add support for new configurations, please open an issue or submit a pull request.

## Support the Project

If this guide helped you to build a more resilient system, consider supporting further development:

**Available Methods:**
- [PayPal](https://paypal.me/JMarcosHP)
- [Github Sponsors](https://github.com/sponsors/JMarcosHP)

Testing and research takes a lot of time, every contribution helps maintain and improve these guides. Thank you! 💙

## License

This project is licensed under the GNU GPL v3.0 License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Special thanks to:

- The [openSUSE](https://www.opensuse.org/) team for pioneering BTRFS snapshot integration
- [GRUB-BTRFS developers](https://github.com/Antynea/grub-btrfs) for snapshots menu integration
- [Btrfs Assistant developers](https://gitlab.com/btrfs-assistant/btrfs-assistant) for the GUI management tool
- The Fedora and Linux communities for extensive documentation

## Resources that complemented every guide in this repository

- [BTRFS Documentation](https://btrfs.readthedocs.io/)
- [Snapper Documentation](http://snapper.io/)
- [Arch Wiki - Snapper](https://wiki.archlinux.org/title/Snapper)
- [openSUSE BTRFS layout](https://en.opensuse.org/SDB:BTRFS)
- [rootco.de - openSUSE BTRFS Subvolumes](https://rootco.de/2018-01-19-opensuse-btrfs-subvolumes/)
- [Fedora Wiki - Relocate RPM to /usr](https://fedoraproject.org/wiki/Changes/RelocateRPMToUsr)
- [RHEL Bug 710388 - /root must be inside /](https://bugzilla.redhat.com/show_bug.cgi?id=710388)
- [Anaconda configuration reference](https://github.com/rhinstaller/anaconda/blob/7ad05432f13483177d1ff16cb4dd0addc072d6b7/data/anaconda.conf#L271)
- [openSUSE Rollback guide](https://es.opensuse.org/Snapper_Rollback)

---

**Made with ❤️ for the Fedora community**
