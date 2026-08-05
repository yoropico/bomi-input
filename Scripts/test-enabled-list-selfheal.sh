#!/bin/bash
# Self-check for the enabled-list repair in bomi-log-snapshot.sh.
#
# The repair writes to a macOS defaults domain, so this drives the real script
# against a throwaway domain and a temporary HOME. It never reads or writes
# com.apple.HIToolbox, and the script's killall of TextInputMenuAgent is skipped
# for any domain but the real one.
#
# Run:  ./Scripts/test-enabled-list-selfheal.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/bomi-log-snapshot.sh"
DOMAIN="com.bomi.test.selfheal.$$"
TMP="$(mktemp -d)"
BUNDLE="$TMP/Bomi.app"
fail=0

cleanup() {
    defaults delete "$DOMAIN" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$BUNDLE"

ABC='{ InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 252; "KeyboardLayout Name" = ABC; }'
KOREAN='{ "Bundle ID" = "com.bomi.inputmethod.bomi"; "Input Mode" = "com.bomi.inputmethod.bomi.korean"; InputSourceKind = "Input Mode"; }'
ROMAN='{ "Bundle ID" = "com.bomi.inputmethod.bomi"; "Input Mode" = "com.bomi.inputmethod.bomi.roman"; InputSourceKind = "Input Mode"; }'

seed() {
    defaults delete "$DOMAIN" 2>/dev/null
    for entry in "$@"; do
        defaults write "$DOMAIN" AppleEnabledInputSources -array-add "$entry"
    done
}

# BOMI_DEBUG_LOG points at a file that does not exist, so the script does its
# watchdog + repair work and then exits before touching any real log or report.
run() {
    HOME="$TMP" \
    BOMI_TIS_DOMAIN="$DOMAIN" \
    BOMI_IME_BUNDLE="$1" \
    BOMI_DEBUG_LOG="$TMP/absent.log" \
    BOMI_DEBUG_SWITCH="$TMP/switch.on" \
    bash "$SCRIPT" >/dev/null 2>&1
}

modes() { defaults read "$DOMAIN" AppleEnabledInputSources 2>/dev/null | grep -c 'com\.bomi\.inputmethod\.bomi\.[a-z]'; }
entries() { defaults read "$DOMAIN" AppleEnabledInputSources 2>/dev/null | grep -c 'InputSourceKind'; }

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1: expected $2, got $3"
        fail=1
    fi
}

# The 2026-08-03 incident itself: both Bomi modes gone, ABC still there.
seed "$ABC"
run "$BUNDLE"
check "both modes restored" 2 "$(modes)"
check "unrelated entry kept" 3 "$(entries)"

# A partial drop must not duplicate the mode that survived.
seed "$ABC" "$KOREAN"
run "$BUNDLE"
check "partial drop repaired" 2 "$(modes)"

seed "$ABC" "$KOREAN" "$ROMAN"
run "$BUNDLE"
check "healthy list untouched" 2 "$(modes)"

# Duplicates are the other incident class -- adding entries could only worsen it.
seed "$ABC" "$KOREAN" "$KOREAN" "$ROMAN"
run "$BUNDLE"
check "duplicates left alone" 3 "$(modes)"

# After the documented teardown removes the bundle, the entry must stay gone.
seed "$ABC"
run "$TMP/nonexistent.app"
check "no bundle, no repair" 0 "$(modes)"

# An unreadable list must not be "repaired" into an array holding only Bomi.
defaults delete "$DOMAIN" 2>/dev/null
run "$BUNDLE"
check "empty list not repaired" 0 "$(modes)"

exit $fail
