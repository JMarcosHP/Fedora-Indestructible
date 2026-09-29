#!/usr/bin/env bash

# snapper-gui-pkg.sh
# ------------------
# Tracks the incoming (direction=in) packages of a GUI-based transaction
# to determine the transaction's actual intent and build an accurate
# summary description once it closes.
#
# This script:
# - Runs during the pre_transaction hook, filtered to direction=in only
#   (packages entering the system: install, upgrade, downgrade, reinstall)
# - Detects if the transaction originated from a GUI
# - Tallies each incoming package's action and records the first package
#   name per category
#
# Outgoing packages (direction=out — replaced/obsoleted versions, or
# genuine removals) are intentionally NOT tallied here: in a normal
# update, every upgraded package produces both an incoming (new version)
# and an outgoing (old version) entry, so counting both sides double-
# counts the same event and can make a bulk update look like a mass
# removal. Only the incoming side reflects what the user actually asked
# for, so pre_transaction:*:out entries should NOT call this script (see
# snapper.actions).
#
# At POST time, the dominant action across the tallied incoming packages
# decides the final wording:
#   - "U" (upgrade) actions dominate     -> "GUI update"
#   - otherwise, install-family (I/D/R)  -> "GUI install <first package>"
#
# This keeps descriptions meaningful for both a one-off install and a
# bulk update coming from Discover/PackageKit, without being skewed by
# the automatic removal of old package versions or leftover cleanup.
#

PID="$1"
ACTION="$2"
NAME="$3"

STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
TALLY_FILE="$STATE_DIR/snapper_gui_tally_${PID}"
FIRST_INSTALL_FILE="$STATE_DIR/snapper_gui_first_install_${PID}"

# Read previously stored description (set in PRE phase)
desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")

# Only proceed if this is a GUI transaction
[[ "$desc" != "GUI" ]] && exit 0

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# Classify the incoming action:
#   U           = upgrade -> counts toward "update"
#   I|D|R       = install/downgrade/reinstall -> counts toward "install"
case "$ACTION" in
    U)
        echo "update" >> "$TALLY_FILE"
        ;;
    I|D|R)
        echo "install" >> "$TALLY_FILE"
        [[ ! -f "$FIRST_INSTALL_FILE" ]] && echo "$NAME" > "$FIRST_INSTALL_FILE"
        ;;
esac
