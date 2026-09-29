#!/usr/bin/env bash

# snapper-important.sh
# ---------------------
# Determines whether the package resolved in the transaction belongs to
# a critical subsystem (kernel, drivers, bootloader, systemd, etc.).
#
# Runs on the `goal_resolved` hook, BEFORE the transaction executes —
# evaluates each resolved package's name against a list of patterns and
# marks the whole transaction as "important" if at least one matches
# (a single match is enough to flag the entire transaction).
#
# The result accumulates in a state file keyed by PID, since
# goal_resolved fires once per package in the transaction.
# snapper-pre.sh reads that file when creating the PRE snapshot and
# uses it as userdata `important=yes|no`.
#

PID="$1"
PKG_NAME="$2"

STATE_DIR="/run/snapper-actions"
FLAG_FILE="$STATE_DIR/snapper_important_${PID}"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# If already flagged as important by an earlier package in this same
# transaction, there is nothing left to evaluate.
[[ -f "$FLAG_FILE" ]] && [[ "$(cat "$FLAG_FILE")" == "yes" ]] && exit 0

# --- Patterns for packages considered critical ---
# Each entry is a glob pattern evaluated against the package name.
IMPORTANT_PATTERNS=(
    # Kernel & initramfs
    "kernel*" "kernel-core*" "kernel-modules*" "kernel-headers*" "dracut*"
    # Base libraries & init
    "glibc*" "glib*" "systemd*" "udev*"
    # Bootloader / Secure Boot
    "grub2*" "grubby*" "shim*" "shim-unsigned*"
    # Firmware
    "fwupd*" "kernel-firmware*"
    # NVIDIA
    "nvidia-*" "akmod-nvidia*" "kmod-nvidia-*" "xorg-x11-drv-nvidia*"
    # AMD GPU
    "xorg-x11-drv-amdgpu*" "amdgpu*"
    # Mesa / Vulkan / OpenGL
    "mesa*" "vulkan*" "libva*"
    # ROCm / HIP / OpenCL
    "rocm-*" "roc*" "hip*" "opencl-amdgpu*" "rocm-opencl*" "opencl-headers*"
)

is_important="no"
for pattern in "${IMPORTANT_PATTERNS[@]}"; do
    # shellcheck disable=SC2053  # intentional glob match, unquoted
    if [[ "$PKG_NAME" == $pattern ]]; then
        is_important="yes"
        break
    fi
done

echo "$is_important" > "$FLAG_FILE"
