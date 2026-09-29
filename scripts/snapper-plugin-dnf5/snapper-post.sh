#!/usr/bin/env bash

# snapper-post.sh
# ----------------
# Creates the POST snapshot after a DNF5 transaction completes.
#
# This script:
# - Retrieves the stored PRE snapshot, description, and "important" flag
# - For GUI transactions, builds an accurate description from the
#   tally of INCOMING package actions recorded by snapper-gui-pkg.sh:
#     - "update" actions dominate  -> "GUI update"
#     - otherwise                  -> "GUI install <first package>"
#   Only incoming (direction=in) packages are tallied, so the automatic
#   removal of old package versions during a normal update never skews
#   the result toward "remove" (see snapper.actions and
#   snapper-gui-pkg.sh for the full rationale).
# - Applies the SQLite WAL checkpoint fix for libdnf5
# - Creates the POST snapshot linked to the PRE snapshot, with the
#   same "important" userdata
# - Cleans up temporary state files
#
# The WAL checkpoint is necessary on Fedora 44+ to reduce
# inconsistencies between filesystem state and the RPM database.
#

PID="$1"
STATE_DIR="/run/snapper-actions"

DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PRE_FILE="$STATE_DIR/snapper_pre_${PID}"
TALLY_FILE="$STATE_DIR/snapper_gui_tally_${PID}"
FIRST_INSTALL_FILE="$STATE_DIR/snapper_gui_first_install_${PID}"
IMPORTANT_FILE="$STATE_DIR/snapper_important_${PID}"

# Load stored state (if available)
desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
pre=$(cat "$PRE_FILE" 2>/dev/null || echo "")
important=$(cat "$IMPORTANT_FILE" 2>/dev/null || echo "no")

# If no PRE snapshot exists, there is nothing to do
[[ -z "$pre" ]] && exit 0

# Build a richer description from the tallied incoming GUI package actions
if [[ -f "$TALLY_FILE" ]]; then
    # grep -c already prints 0 (with a non-zero exit status) when there
    # are no matches, so no "|| echo 0" fallback is needed here — adding
    # one would append a second "0" to the captured output and break
    # the arithmetic comparison below.
    update_count=$(grep -c '^update$' "$TALLY_FILE")
    install_count=$(grep -c '^install$' "$TALLY_FILE")

    if (( update_count >= install_count && update_count > 0 )); then
        desc="GUI update"
    elif (( install_count > 0 )); then
        first_install=$(cat "$FIRST_INSTALL_FILE" 2>/dev/null || echo "")
        desc="GUI install ${first_install}"
    fi
    snapper -c root modify -d "$desc" "$pre" || true
fi

# Apply the WAL checkpoint (best-effort; do not fail the transaction if it doesn't succeed)
/usr/local/bin/snapper-wal-checkpoint.sh || true

# Create the POST snapshot linked to the PRE snapshot, with the same important flag
snapper -c root create -c number -t post \
    --pre-number "$pre" -u "important=${important}" -d "$desc"

# Clean up temporary state files
rm -f "$DESC_FILE" "$PRE_FILE" "$IMPORTANT_FILE" \
      "$TALLY_FILE" "$FIRST_INSTALL_FILE"
