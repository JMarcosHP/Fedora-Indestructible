#!/usr/bin/env bash
set -e

# snapper-pre.sh
# ----------------
# Creates the PRE snapshot before a DNF5 transaction starts.
#
# This script:
# - Generates a description using snapper-desc.sh
# - Reads the "important" flag accumulated by snapper-important.sh
# - Stores the description, flag, and snapshot number in /run so
#   snapper-post.sh can use them when closing the transaction
#

PID="$1"
STATE_DIR="/run/snapper-actions"

# Ensure the state directory exists with secure permissions
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# On a fresh install, DNF5 may fail with
# "filesystem error: cannot copy: packages.toml" if this directory
# is missing, leaving an orphaned PRE snapshot with no matching POST.
if [[ ! -d /usr/lib/sysimage/libdnf5 ]]; then
    mkdir -p /usr/lib/sysimage/libdnf5
    restorecon -q /usr/lib/sysimage/libdnf5 2>/dev/null || true
fi

# Transaction description (GUI or CLI command)
desc=$(/usr/local/bin/snapper-desc.sh "$PID")
echo "$desc" > "$STATE_DIR/snapper_desc_${PID}"

# "important" flag accumulated during goal_resolved (defaults to "no"
# if no package triggered snapper-important.sh, e.g. empty transactions)
important=$(cat "$STATE_DIR/snapper_important_${PID}" 2>/dev/null || echo "no")

# Create the PRE snapshot and store its number to link it with the POST
pre=$(snapper -c root create -c number -t pre -p \
    -u "important=${important}" -d "$desc") || exit 1

echo "$pre" > "$STATE_DIR/snapper_pre_${PID}"
