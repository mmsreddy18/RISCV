#!/usr/bin/env python3
"""Branch-predictor size sweep: CoreMark (-O2, RVC) and Dhrystone (-O2, word strings), FAST_REDIRECT=0.

Needs build/cm/O2_rvc/coremark.hex and build/dhry/O2_wordstr/dhry.hex (run coremark_run.py and
dhrystone_run.py once first). Results: tests/perf/results/bp_sweep.json
"""
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

KNOWN = ["0xe9f5", "0xe714", "0x1fd7", "0x8e3a", "0xfcaf"]
# (bp, gshare, log2 BTB entries, log2 BHT counters)
CONFIGS = [(0, 0, 5, 9),
           (1, 0, 1, 5), (1, 0, 2, 5), (1, 0, 3, 6), (1, 0, 3, 7), (1, 0, 4, 7), (1, 0, 4, 8), (1, 0, 5, 9), (1, 0, 6, 9),
           (1, 1, 3, 7), (1, 1, 5, 9)]

def sim(fast, bp, gs, bl, hl):
    suffix = "" if (bl, hl) == (4, 6) else f"_t{bl}_{hl}"
    subprocess.check_call(["make", "-s", "-C", ROOT, "sim", f"FAST={fast}", "DEPTH=4", f"BP={bp}", f"GSHARE={gs}",
                           f"BTBLOG={bl}", f"BHTLOG={hl}"], stdout=subprocess.DEVNULL)
    return os.path.join(ROOT, "build", f"f{fast}_d4_b{bp}_g{gs}{suffix}", "Vtb_core")

def main():
    cm = os.path.join(ROOT, "build/cm/O2_rvc/coremark.hex")
    dh = os.path.join(ROOT, "build/dhry/O2_wordstr/dhry.hex")
    res = []
    for bp, gs, bl, hl in CONFIGS:
        v = sim(0, bp, gs, bl, hl)
        d, o = run(v, cm, maxcyc=400_000_000)
        ok = "Correct operation validated" in o and all(k in o for k in KNOWN)
        e, _ = run(v, dh, maxcyc=50_000_000)
        r = dict(bp=bp, gshare=gs, btb=2 ** bl, bht=2 ** hl, cm_cycles=d["cycles"], cm_cpi=d["cycles"] / d["issued"],
                 coremark_per_mhz=10 * 1e6 / d["cycles"], valid=ok, dhry_cycles_per_run=e["cycles"] / 500,
                 dhry_cpi=e["cycles"] / e["issued"], cm_branch_bubbles=d["branch"])
        res.append(r)
        print(r, flush=True)
    json.dump(res, open(os.path.join(ROOT, "tests/perf/results/bp_sweep.json"), "w"), indent=1)
main()
