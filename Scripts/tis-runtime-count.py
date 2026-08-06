#!/usr/bin/env python3
"""Count Bomi's modes in the RUNTIME enabled input-source list.

Why this exists separately from `defaults read com.apple.HIToolbox`: the two
incidents this project keeps hitting live in two different stores.

  drop      -- the mode disappears from the persisted AppleEnabledInputSources.
               `defaults read` sees it, and bomi-log-snapshot.sh repairs it.
  duplicate -- the same mode is registered twice in HIToolbox's per-login runtime
               registry while the persisted list stays perfectly clean
               (2026-08-03 both modes, 2026-08-07 roman only). `defaults read`
               is blind to it, so the watchdog reported "present (modes=2,
               expected 2)" while three Bomi rows sat in the input menu.

Only Carbon's TIS API sees the runtime list, hence ctypes. pyobjc has no Carbon
bindings and compiling a Swift helper would put the Xcode toolchain on the
watchdog's critical path; this runs in ~0.1s with system python3 alone.

Output is one shell-parseable line, e.g. `korean=1 roman=2 rows=6`. Read-only:
nothing here enables, disables or selects an input source.
"""
import ctypes
import sys

CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
TIS = ctypes.CDLL("/System/Library/Frameworks/Carbon.framework/Carbon")

CF.CFArrayGetCount.restype = ctypes.c_long
CF.CFArrayGetCount.argtypes = [ctypes.c_void_p]
CF.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
CF.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
CF.CFStringGetCString.restype = ctypes.c_bool
CF.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
CF.CFRelease.argtypes = [ctypes.c_void_p]

# includeAllInstalled = false: only what is enabled, which is what the input menu draws.
TIS.TISCreateInputSourceList.restype = ctypes.c_void_p
TIS.TISCreateInputSourceList.argtypes = [ctypes.c_void_p, ctypes.c_bool]
TIS.TISGetInputSourceProperty.restype = ctypes.c_void_p
TIS.TISGetInputSourceProperty.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

kTISPropertyInputSourceID = ctypes.c_void_p.in_dll(TIS, "kTISPropertyInputSourceID")
kCFStringEncodingUTF8 = 0x08000100

MODES = ("korean", "roman")
PREFIX = "com.bomi.inputmethod.bomi."


def cfstring(ref):
    buf = ctypes.create_string_buffer(512)
    if not ref or not CF.CFStringGetCString(ref, buf, len(buf), kCFStringEncodingUTF8):
        return ""
    return buf.value.decode("utf-8", "replace")


def main():
    array = TIS.TISCreateInputSourceList(None, False)
    if not array:
        print("TIS returned no input-source list", file=sys.stderr)
        return 1
    try:
        rows = CF.CFArrayGetCount(array)
        ids = [
            cfstring(TIS.TISGetInputSourceProperty(CF.CFArrayGetValueAtIndex(array, i), kTISPropertyInputSourceID))
            for i in range(rows)
        ]
    finally:
        CF.CFRelease(array)

    # A Mac always has at least one enabled keyboard layout, so an empty list means the
    # ctypes plumbing broke (a renamed symbol, a changed signature) rather than a real
    # reading. Fail loudly instead of reporting a comforting korean=0 roman=0.
    if rows < 1:
        print("runtime enabled list came back empty -- ctypes plumbing is broken", file=sys.stderr)
        return 1

    counts = {mode: ids.count(PREFIX + mode) for mode in MODES}
    print(" ".join(f"{mode}={counts[mode]}" for mode in MODES), f"rows={rows}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
