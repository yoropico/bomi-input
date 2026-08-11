#!/bin/bash
# Self-check for the enabled-list repair in bomi-log-snapshot.sh.
#
# The repair writes to macOS defaults domains, so this drives the real script
# against throwaway domains and a temporary HOME. It never reads or writes
# com.apple.HIToolbox / com.apple.inputsources, and the script's killall of
# TextInputMenuAgent is skipped for any domain but the real one.
#
# "Enabled" is the union of two domains -- TIS (AppleEnabledInputSources) and
# IS (AppleEnabledThirdPartyInputSources) -- because macOS concatenates both
# into the runtime list without dedup, so a mode repaired into TIS while it
# already lives in IS becomes a duplicate menu row (2026-08-11).
#
# Run:  ./Scripts/test-enabled-list-selfheal.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/bomi-log-snapshot.sh"
DOMAIN="com.bomi.test.selfheal.$$"
ISDOMAIN="$DOMAIN.is"
TMP="$(mktemp -d)"
BUNDLE="$TMP/Bomi.app"
fail=0

cleanup() {
    defaults delete "$DOMAIN" 2>/dev/null
    defaults delete "$ISDOMAIN" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$BUNDLE"

ABC='{ InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 252; "KeyboardLayout Name" = ABC; }'
PARENT='{ "Bundle ID" = "com.bomi.inputmethod.bomi"; InputSourceKind = "Keyboard Input Method"; }'
KOREAN='{ "Bundle ID" = "com.bomi.inputmethod.bomi"; "Input Mode" = "com.bomi.inputmethod.bomi.korean"; InputSourceKind = "Input Mode"; }'
ROMAN='{ "Bundle ID" = "com.bomi.inputmethod.bomi"; "Input Mode" = "com.bomi.inputmethod.bomi.roman"; InputSourceKind = "Input Mode"; }'

seed() {
    defaults delete "$DOMAIN" 2>/dev/null
    defaults delete "$ISDOMAIN" 2>/dev/null
    for entry in "$@"; do
        defaults write "$DOMAIN" AppleEnabledInputSources -array-add "$entry"
    done
}

seed_is() {
    for entry in "$@"; do
        defaults write "$ISDOMAIN" AppleEnabledThirdPartyInputSources -array-add "$entry"
    done
}

# BOMI_DEBUG_LOG points at a file that does not exist, so the script does its
# watchdog + repair work and then exits before touching any real log or report.
run() {
    HOME="$TMP" \
    BOMI_TIS_DOMAIN="$DOMAIN" \
    BOMI_IS_DOMAIN="$ISDOMAIN" \
    BOMI_IME_BUNDLE="$1" \
    BOMI_DEBUG_LOG="$TMP/absent.log" \
    BOMI_DEBUG_SWITCH="$TMP/switch.on" \
    bash "$SCRIPT" >/dev/null 2>&1
}

modes() { { defaults read "$DOMAIN" AppleEnabledInputSources 2>/dev/null; defaults read "$ISDOMAIN" AppleEnabledThirdPartyInputSources 2>/dev/null; } | grep -c 'com\.bomi\.inputmethod\.bomi\.[a-z]'; }
entries() { { defaults read "$DOMAIN" AppleEnabledInputSources 2>/dev/null; defaults read "$ISDOMAIN" AppleEnabledThirdPartyInputSources 2>/dev/null; } | grep -c 'InputSourceKind'; }
hi_bomi() { defaults read "$DOMAIN" AppleEnabledInputSources 2>/dev/null | grep -c 'com\.bomi\.inputmethod\.bomi\.'; }

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1: expected $2, got $3"
        fail=1
    fi
}

# The 2026-08-03 incident itself: both Bomi modes gone, ABC still there.
# The repair lands in the IS domain (parent allowlist + both modes).
seed "$ABC"
run "$BUNDLE"
check "both modes restored" 2 "$(modes)"
check "unrelated entry kept" 4 "$(entries)"

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

# 2026-08-11 regression: modes already living in com.apple.inputsources count as
# enabled. Re-adding them to the TIS domain too is what manufactured the
# duplicate-menu-row class (the runtime list concatenates both domains).
seed "$ABC"
seed_is "$PARENT" "$KOREAN" "$ROMAN"
run "$BUNDLE"
check "third-party modes count as enabled" 2 "$(modes)"
check "no dual write into the TIS domain" 0 "$(hi_bomi)"

# A repair must restore the parent allowlist entry as well: without it the
# third-party IME cannot load at all.
seed "$ABC"
run "$BUNDLE"
check "parent allowlist restored" 1 "$(defaults read "$ISDOMAIN" AppleEnabledThirdPartyInputSources 2>/dev/null | grep -c 'InputSourceKind = "Keyboard Input Method"')"

# After the documented teardown removes the bundle, the entry must stay gone.
seed "$ABC"
run "$TMP/nonexistent.app"
check "no bundle, no repair" 0 "$(modes)"

# An unreadable world must not be "repaired" into one holding only Bomi.
defaults delete "$DOMAIN" 2>/dev/null
defaults delete "$ISDOMAIN" 2>/dev/null
run "$BUNDLE"
check "empty list not repaired" 0 "$(modes)"

exit $fail
