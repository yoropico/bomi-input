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

# The five overrides below exist only so Scripts/test-enabled-list-selfheal.sh can
# drive this script against throwaway defaults domains and a temporary HOME,
# instead of the live input-source list and the real debug log. In normal launchd
# operation none of them are set and the defaults are what run.
SRC="${BOMI_DEBUG_LOG:-/tmp/bomi-debug.log}"
SWITCH="${BOMI_DEBUG_SWITCH:-/tmp/bomi-debug.on}"
TIS_DOMAIN="${BOMI_TIS_DOMAIN:-com.apple.HIToolbox}"
IS_DOMAIN="${BOMI_IS_DOMAIN:-com.apple.inputsources}"
IME_BUNDLE="${BOMI_IME_BUNDLE:-$HOME/Library/Input Methods/Bomi.app}"

DIR="$HOME/Library/Application Support/Bomi"
DURABLE="$DIR/bomi-debug.log"
OFFSET="$DIR/.offset"
REPORTS="$DIR/reports"
ANALYZER="$(cd "$(dirname "$0")" && pwd)/analyze-debug-log.py"
RUNTIME_COUNT="$(cd "$(dirname "$0")" && pwd)/tis-runtime-count.py"

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

# Watchdog for the input-source incident classes, so the next occurrence is
# datable to a 4h window instead of being reconstructed days later from nothing:
#
#   2026-07-28 -- Bomi vanished from the persisted enabled list entirely.
#   2026-08-03 -- duplicate "Sebeolsik Final" rows piled up in the input source
#                 list. Persisted state turned out clean (the duplication never
#                 exceeded one extra runtime entry), so the count below is what
#                 will show whether a real recurrence reaches persistence.
#   2026-08-11 -- root-caused the duplicates: macOS builds the runtime list by
#                 concatenating TWO persisted domains without dedup --
#                 com.apple.HIToolbox AppleEnabledInputSources and
#                 com.apple.inputsources AppleEnabledThirdPartyInputSources --
#                 and migrates third-party entries into the latter on its own
#                 schedule. A mode listed in BOTH is a duplicate menu row.
#
# "Enabled" is therefore the UNION of the two domains (see the self-heal
# comment below); healthy is each mode exactly once across the union.
enabled_list=$(defaults read "$TIS_DOMAIN" AppleEnabledInputSources 2>/dev/null)
is_list=$(defaults read "$IS_DOMAIN" AppleEnabledThirdPartyInputSources 2>/dev/null)
bomi_modes=$(printf '%s\n' "$enabled_list" | grep -c '"Input Mode" = "com.bomi.inputmethod.bomi\.')
tp_modes=$(printf '%s\n' "$is_list" | grep -c '"Input Mode" = "com.bomi.inputmethod.bomi\.')
union_modes=$((bomi_modes + tp_modes))
if [ "$union_modes" -gt 0 ]; then
    enabled_state="present"
else
    enabled_state="MISSING"
fi
echo "$(date '+%Y-%m-%d %H:%M') enabled-list: bomi $enabled_state (hitoolbox=$bomi_modes, third-party=$tp_modes, union expected 2)" >> "$DIR/maintenance.log"

# The persisted count above cannot see the duplicate class at all: on 2026-08-07 the
# runtime list carried the roman mode twice while AppleEnabledInputSources held each
# mode exactly once, so this watchdog logged a healthy "present (modes=2, expected 2)"
# with three Bomi rows sitting in the input menu. Only Carbon's TIS API sees that list,
# which is what tis-runtime-count.py reads.
#
# Detection only -- deliberately no repair. Removing a duplicate row is what rewrites
# the whole persisted array and took Bomi out of the enabled list for three days on
# 2026-08-03; the known safe reset is a logout, which is a human's call, not a
# background job's. Skipped for a test domain, where the live runtime list has nothing
# to do with the seeded one.
if [ "$TIS_DOMAIN" = com.apple.HIToolbox ] && [ -f "$RUNTIME_COUNT" ]; then
    runtime=$(python3 "$RUNTIME_COUNT" 2>/dev/null)
    if [ -z "$runtime" ]; then
        runtime_state="unreadable"
    elif [ "${runtime% rows=*}" = "korean=1 roman=1" ]; then
        runtime_state="healthy"
    else
        runtime_state="UNEXPECTED"
    fi
    echo "$(date '+%Y-%m-%d %H:%M') runtime-list: bomi $runtime_state ($runtime)" >> "$DIR/maintenance.log"
fi

# Parent-allowlist watch. The parent "Keyboard Input Method" entry for bomi in
# com.apple.inputsources is what lets a third-party IME load at all: deleting it
# took Bomi off the runtime list within minutes on 2026-08-11, and that is the
# one loss this job cannot repair into visibility without a login anyway, so a
# MISSING here means "tell a human immediately". The mode counts are
# informational -- the runtime-list check above is the duplicate detector.
# Skipped for a test domain, same as the runtime check.
if [ "$TIS_DOMAIN" = com.apple.HIToolbox ]; then
    tp_entries=$(printf '%s\n' "$is_list" | grep -c '"Bundle ID" = "com.bomi.inputmethod.bomi"')
    if printf '%s\n' "$is_list" | grep -A2 '"Bundle ID" = "com.bomi.inputmethod.bomi"' | grep -q 'InputSourceKind = "Keyboard Input Method"'; then
        tp_state="present"
    else
        tp_state="MISSING"
    fi
    echo "$(date '+%Y-%m-%d %H:%M') third-party-list: bomi-parent $tp_state (entries=$tp_entries, modes=$tp_modes)" >> "$DIR/maintenance.log"
fi

# Self-heal the drop, because detecting it turned out not to be enough: the
# 2026-08-03 recurrence sat MISSING through 19 consecutive watchdog runs (three
# days) while every input-menu rebuild -- and every exit from a password field's
# secure-input mode, which is where it was finally noticed -- reverted the
# selection to ABC. Only the modes actually absent are added back, so a partial
# drop is repaired without disturbing whichever one survived.
#
# "Enabled" is the UNION of two persisted domains, and repairs target only the
# second one. Measured 2026-08-11: macOS builds the runtime list by
# concatenating the two domains WITHOUT dedup (HIToolbox 4 rows +
# com.apple.inputsources 1..3 rows = runtime 5..7 rows), and it migrates
# third-party entries into com.apple.inputsources on its own schedule (that day
# it moved both bomi modes out of AppleEnabledInputSources minutes after a
# login and re-listed them under AppleEnabledThirdPartyInputSources). A mode
# present in BOTH domains is a duplicate menu row -- and this script created
# exactly that (korean=2 roman=2) by re-adding modes to HIToolbox that macOS
# had already migrated out. So a mode present in EITHER domain counts as
# enabled, and missing modes are written to AppleEnabledThirdPartyInputSources.
#
# The parent "Keyboard Input Method" entry in com.apple.inputsources is the
# allowlist that lets a third-party IME load at all (deleting it took Bomi off
# the runtime list within minutes on 2026-08-11), so a repair ensures it first.
#
# Three guards, each for a failure this could otherwise cause:
#   - both domains unreadable: `defaults write -array-add` CREATES the key when
#     it is absent, so repairing off an unreadable world would fabricate a list
#     holding only Bomi and take ABC and the Apple layouts down with it.
#   - more than two modes in the union: duplicates are the OTHER incident
#     class, and adding entries can only make that worse. Leave it for a human.
#   - no bundle: once ~/Library/Input Methods/Bomi.app is removed (the
#     documented teardown), the entries SHOULD stay gone rather than being
#     resurrected every four hours.
repaired=""
if { [ -n "$enabled_list" ] || [ -n "$is_list" ]; } && [ "$union_modes" -lt 2 ] && [ -d "$IME_BUNDLE" ]; then
    if ! printf '%s\n' "$is_list" | grep -A2 '"Bundle ID" = "com.bomi.inputmethod.bomi"' | grep -q 'InputSourceKind = "Keyboard Input Method"'; then
        defaults write "$IS_DOMAIN" AppleEnabledThirdPartyInputSources -array-add \
            '{ "Bundle ID" = "com.bomi.inputmethod.bomi"; InputSourceKind = "Keyboard Input Method"; }'
        repaired=" parent-allowlist"
    fi
    for mode in korean roman; do
        printf '%s\n' "$enabled_list" "$is_list" | grep -q "com\.bomi\.inputmethod\.bomi\.$mode" && continue
        defaults write "$IS_DOMAIN" AppleEnabledThirdPartyInputSources -array-add \
            "{ \"Bundle ID\" = \"com.bomi.inputmethod.bomi\"; \"Input Mode\" = \"com.bomi.inputmethod.bomi.$mode\"; InputSourceKind = \"Input Mode\"; }"
        repaired="$repaired $mode"
    done
    if [ -n "$repaired" ]; then
        # The menu agent caches the list; without a restart the repair only shows
        # up at the next login. Skipped when running against a test domain.
        [ "$TIS_DOMAIN" = com.apple.HIToolbox ] && killall TextInputMenuAgent 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M') enabled-list: re-enabled$repaired (in $IS_DOMAIN)" >> "$DIR/maintenance.log"
    fi
fi

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
