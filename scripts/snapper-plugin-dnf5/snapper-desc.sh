#!/usr/bin/env bash

# snapper-desc.sh
# ----------------
# Determines a human-readable description for the transaction.
#
# This script inspects the process that triggered the DNF5 transaction.
#
# Behavior:
# - If the transaction originates from GUI tools (PackageKit / dnf5daemon),
#   it returns "GUI"
# - Otherwise, it returns the actual command with the operation word
#   normalized to a single canonical label, so "dnf upgrade ..." and
#   "dnf update ..." both read as "dnf update ...", and "dnf erase ..."
#   reads as "dnf remove ...". This keeps CLI descriptions consistent
#   with the GUI-side wording ("GUI update", "GUI install", "GUI remove").
#
# This description is later used by Snapper for snapshot naming.
#

PID="$1"

# Get the full command of the originating process
cmd=$(ps -o command --no-headers -p "$PID" 2>/dev/null || echo "Unknown Task")

case "$cmd" in
    */dnf5daemon* | */packagekitd*)
        # GUI-based transaction
        echo "GUI"
        ;;
    *)
        # CLI transaction: normalize dnf's synonym operation words to a
        # single canonical label per category, so descriptions read
        # consistently regardless of which synonym the user typed.
        echo "$cmd" | sed -E \
            -e 's/\bupgrade\b/update/' \
            -e 's/\berase\b/remove/'
        ;;
esac
