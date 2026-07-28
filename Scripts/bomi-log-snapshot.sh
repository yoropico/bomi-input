#!/bin/bash
# Preserve the Bomi IME debug log past a reboot, and write a per-app report.
#
# Why this exists: the log lives in /tmp, which macOS clears on reboot -- and the
# enable switch (/tmp/bomi-debug.on) is cleared with it, so after a reboot the IME
# comes back with logging OFF and the evidence gone. That already cost one full
# round of verification data. This job runs every few hours via launchd
# (~/Library/LaunchAgents/com.bomi.logsnapshot.plist).
#
# It appends only the bytes it has not seen yet, so the durable copy accumulates
# across reboots instead of being overwritten by a fresh, shorter log.
#
# Remove with:  launchctl unload ~/Library/LaunchAgents/com.bomi.logsnapshot.plist

set -uo pipefail

SRC=/tmp/bomi-debug.log
SWITCH=/tmp/bomi-debug.on
DIR="$HOME/Library/Application Support/Bomi"
DURABLE="$DIR/bomi-debug.log"
OFFSET="$DIR/.offset"
REPORTS="$DIR/reports"
ANALYZER="$(cd "$(dirname "$0")" && pwd)/analyze-debug-log.py"

mkdir -p "$REPORTS"

# A reboot (or the periodic /tmp reaper) clears the switch; restore it. DebugLog
# re-checks the file every ~5s, so touching it is enough.
#
# NEVER `killall Bomi` here. Killing a live, selected input method leaves macOS
# with a selected-but-dead IME until the next keystroke relaunches it; that
# window is how Bomi got dropped from AppleEnabledInputSources on 2026-07-28
# (6 minutes dead at 06:10, enabled-list entry gone, IME then intermittently
# reverting to the default source). Older builds (pre re-check) cache the switch
# at startup and will simply stay silent until their next natural relaunch --
# acceptable; a dead IME is not.
[ -f "$SWITCH" ] || touch "$SWITCH"

# Watchdog for the 2026-07-28 incident class: record whether Bomi is still in
# the persisted enabled list, so the next drop is datable to a 4h window
# instead of being reconstructed days later from nothing.
if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null \
        | grep -q 'com.bomi.inputmethod.bomi'; then
    enabled_state="present"
else
    enabled_state="MISSING"
fi
echo "$(date '+%Y-%m-%d %H:%M') enabled-list: bomi $enabled_state" >> "$DIR/maintenance.log"

# Append only what is new. A current size smaller than the recorded offset means
# the log was cleared or recreated -- start from the beginning of the new one.
if [ -f "$SRC" ]; then
    cur=$(stat -f%z "$SRC")
    off=$(cat "$OFFSET" 2>/dev/null || echo 0)
    case "$off" in ''|*[!0-9]*) off=0 ;; esac
    [ "$cur" -lt "$off" ] && off=0
    if [ "$cur" -gt "$off" ]; then
        tail -c "+$((off + 1))" "$SRC" >> "$DURABLE"
    fi
    echo "$cur" > "$OFFSET"
fi

[ -f "$DURABLE" ] || exit 0

# The report is regenerated from the whole durable log each time, so `latest.txt`
# is always the full picture rather than one window of it.
python3 "$ANALYZER" "$DURABLE" > "$REPORTS/latest.txt" 2>&1
cp "$REPORTS/latest.txt" "$REPORTS/$(date +%Y-%m-%d).txt"

# Keep the durable log from growing without bound (it ran ~7MB/day in daily use).
# 200MB is months of headroom; past that, drop the oldest half rather than lose
# the recent evidence.
size=$(stat -f%z "$DURABLE")
if [ "$size" -gt 209715200 ]; then
    tail -c 104857600 "$DURABLE" > "$DURABLE.trim" && mv "$DURABLE.trim" "$DURABLE"
    echo "$(date '+%Y-%m-%d %H:%M') trimmed durable log to 100MB" >> "$DIR/maintenance.log"
fi
