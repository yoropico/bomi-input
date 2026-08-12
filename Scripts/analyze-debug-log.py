#!/usr/bin/env python3
"""Per-app health report for the Bomi IME debug log.

    touch /tmp/bomi-debug.on && killall Bomi     # start logging
    Scripts/analyze-debug-log.py                 # read /tmp/bomi-debug.log

Why this exists: the Han/Eng toggle wedge (fixed 2026-07-22, see
docs/superpowers/specs/2026-07-14-bomi-han-eng-mode-switching-design.md) was only
ever visible in this log, and the first verification of the fix reported TOTALS
only -- so "which apps did those 2814 toggles actually cover?" could not be
answered afterwards. Coverage is the point of this script: a green total across
one app is not evidence about the others.

The wedge, precisely: after a toggle fires, IMK stops delivering `flagsChanged`
to that controller instance while `keyDown` keeps arriving, so the next
Right-Cmd is silently lost until the app is refocused. That is what `wedges`
counts, per app.
"""

import re
import sys
from collections import defaultdict

LOG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/bomi-debug.log"

# "HH:MM:SS.mmm  c968  <rest>" -- the tag may be indented (FIRE / -> lines are).
LINE = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d{3})\s+(?:(c\d+)\s+)?(.*)$")
APP = re.compile(r"app=(\S+)")
LANDED = re.compile(r"landed in (\d+)ms")


def parse(path):
    """Yields (t_seconds, instance_or_None, rest). Rebuilds a monotonic clock:
    the log stamps HH:MM:SS only, so a day boundary looks like time going
    backwards ~24h."""
    day, prev = 0, None
    with open(path, errors="replace") as fh:
        for raw in fh:
            m = LINE.match(raw)
            if not m:
                continue
            h, mi, s, ms, inst, rest = m.groups()
            t = int(h) * 3600 + int(mi) * 60 + int(s) + int(ms) / 1000
            if prev is not None and t < prev - 3600:
                day += 1
            prev = t
            yield t + day * 86400, inst, rest.rstrip()


def clock(t):
    """Back to the log's own HH:MM:SS so a finding can be grepped for. `t` is the
    monotonic seconds from parse(), so strip the synthetic day offset first."""
    t = int(t) % 86400
    return f"{t // 3600:02d}:{t % 3600 // 60:02d}:{t % 60:02d}"


class AppStat:
    def __init__(self):
        self.fires = 0
        self.wedges = 0
        self.suppressed = 0
        self.keydowns = 0
        self.landings = []
        self.not_landed = 0
        self.fallbacks = 0
        self.dropped = 0
        self.wrong_mode = 0
        self.first_after_toggle = 0
        self.arrivals = []      # press->IME arrival ms, from keyDown lat= (2026-08-13+)
        self.instances = set()
        self.examples = []


def main():
    try:
        events = list(parse(LOG))
    except FileNotFoundError:
        sys.exit(f"no log at {LOG} -- enable it: touch /tmp/bomi-debug.on && killall Bomi")
    if not events:
        sys.exit(f"{LOG} has no parsable lines yet (the IME relaunches on the next keystroke)")

    # An instance's app is only named on lines that carry app=; keyDown lines do
    # not. Carry the last-seen app forward per instance.
    inst_app = {}
    stats = defaultdict(AppStat)
    fires = []          # (index, instance, app)
    pending_target = None   # target mode of the most recent FIRE, for the next keyDown

    for i, (t, inst, rest) in enumerate(events):
        if inst:
            m = APP.search(rest)
            if m:
                inst_app[inst] = m.group(1)
            app = inst_app.get(inst, "(unknown)")
            st = stats[app]
            st.instances.add(inst)
        else:
            # ModeSwitcher lines: attribute to the app of the last FIRE.
            app = fires[-1][2] if fires else "(unknown)"
            st = stats[app]

        if rest.startswith("flagsChanged"):
            if "outcome=fire" in rest:
                st.fires += 1
                fires.append((i, inst, app))
            elif "outcome=suppressed" in rest:
                st.suppressed += 1
            if "DROPPED" in rest:
                st.dropped += 1
        elif rest.startswith("keyDown"):
            st.keydowns += 1
            m = re.search(r"lat=(-?\d+)ms", rest)
            if m:
                st.arrivals.append(int(m.group(1)))
            if pending_target:
                st.first_after_toggle += 1
                m = re.search(r"mode=(\S+)", rest)
                if m and m.group(1) != pending_target:
                    st.wrong_mode += 1
                    st.examples.append(f"first key after toggle in {m.group(1)}: {rest[:70]}")
                pending_target = None
        elif rest.startswith("FIRE"):
            m = re.search(r"target=(\S+)", rest)
            pending_target = m.group(1) if m else None
        elif "landed in" in rest:
            st.landings.append(int(LANDED.search(rest).group(1)))
        elif "did NOT land" in rest:
            st.not_landed += 1
        elif "TIS refused" in rest:
            st.fallbacks += 1
        elif rest.startswith(("activateServer", "deactivateServer")):
            pending_target = None   # an app switch is not a lost keystroke

    # Wedge: after a FIRE, does that instance ever see another flagsChanged while
    # keyDowns keep arriving? Bounded so a trailing FIRE at end-of-log, or one
    # followed by a real focus change, is not miscounted.
    for idx, inst, app in fires:
        t0 = events[idx][0]
        keydowns_after, saw_flags = 0, False
        for t, inst2, rest in events[idx + 1:]:
            if inst2 != inst:
                continue
            if rest.startswith("flagsChanged"):
                saw_flags = True
                break
            if rest.startswith(("deactivateServer", "activateServer")):
                break
            if rest.startswith("keyDown"):
                keydowns_after += 1
            if t - t0 > 120:
                break
        if not saw_flags and keydowns_after >= 2:
            stats[app].wedges += 1
            stats[app].examples.append(
                f"WEDGE at {clock(t0)}, instance {inst}, "
                f"{keydowns_after} keyDowns with no flagsChanged (grep the log at that time)"
            )

    span_h = (events[-1][0] - events[0][0]) / 3600
    print(f"{LOG}: {len(events)} events over {span_h:.1f}h\n")

    hdr = (f"{'app':<34}{'toggles':>8}{'WEDGES':>8}{'sup':>6}{'keys':>8}{'p50':>6}{'p95':>6}{'max':>6}{'fail':>6}"
           f"{'aP95':>6}{'aMax':>6}")
    print(hdr)
    print("-" * len(hdr))

    def row(name, st):
        L = sorted(st.landings)
        p50 = L[len(L) // 2] if L else 0
        p95 = L[int(len(L) * 0.95)] if L else 0
        mx = L[-1] if L else 0
        fail = st.not_landed + st.fallbacks + st.dropped
        A = sorted(st.arrivals)
        ap95 = A[int(len(A) * 0.95)] if A else 0
        amax = A[-1] if A else 0
        print(f"{name:<34}{st.fires:>8}{st.wedges:>8}{st.suppressed:>6}"
              f"{st.keydowns:>8}{p50:>6}{p95:>6}{mx:>6}{fail:>6}{ap95:>6}{amax:>6}")

    for name, st in sorted(stats.items(), key=lambda kv: -kv[1].fires):
        if st.fires or st.keydowns:
            row(name, st)

    total = AppStat()
    for st in stats.values():
        total.fires += st.fires
        total.wedges += st.wedges
        total.suppressed += st.suppressed
        total.keydowns += st.keydowns
        total.landings += st.landings
        total.not_landed += st.not_landed
        total.fallbacks += st.fallbacks
        total.dropped += st.dropped
        total.wrong_mode += st.wrong_mode
        total.first_after_toggle += st.first_after_toggle
        total.arrivals += st.arrivals
    print("-" * len(hdr))
    row("TOTAL", total)

    print(f"\nfirst keystroke after a toggle: {total.first_after_toggle} cases, "
          f"{total.wrong_mode} handled in the pre-toggle mode")
    print("columns: WEDGES = toggle died (the bug); sup = duplicate presses correctly "
          "suppressed; p50/p95/max = ms for the switch to land in TIS; "
          "fail = didn't land + TIS fallbacks + dropped events; "
          "aP95/aMax = ms from hardware press to IME arrival (upstream queue delay; "
          "0 on lines predating the lat= field)")

    zero = [n for n, st in stats.items() if st.fires == 0 and st.keydowns > 200]
    if zero:
        print(f"\nNOTE: typed in but never toggled (no toggle coverage): {', '.join(sorted(zero))}")

    bad = [e for st in stats.values() for e in st.examples]
    if bad:
        print(f"\n{len(bad)} anomal{'y' if len(bad) == 1 else 'ies'}:")
        for e in bad[:20]:
            print("   ", e)


if __name__ == "__main__":
    main()
