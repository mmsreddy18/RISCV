#!/usr/bin/env python3
"""CoreMark (-O2, RVC) versus memory behaviour: response latency, grant wait states, FIFO depth."""
import json, os, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(__file__))
from common import *

HEX = os.path.join(ROOT, "build", "cm", "O2_rvc", "coremark.hex")
ITER = 10

def one(job):
    key, vtb_path, args = job
    d, _ = run(vtb_path, HEX, *args, maxcyc=900_000_000)
    d["coremark_per_mhz"] = ITER * 1e6 / d["cycles"]
    d["cpi"] = d["cycles"] / d["issued"]
    return key, d

def main():
    sims = {}
    for f in (0, 1):
        for dep in (2, 4, 8):
            sims[(f, dep)] = build_sim(f, dep)
    jobs = []
    for f in (0, 1):
        v = sims[(f, 4)]
        for lat in range(1, 9):                       # response latency in cycles = 1 + extra
            jobs.append((("ilat", f, lat), v, [f"+ilat={lat-1}"]))
            jobs.append((("dlat", f, lat), v, [f"+dlat={lat-1}"]))
        for w in range(0, 4):                         # grant offered 1 cycle in (w+1)
            jobs.append((("igw", f, w), v, [f"+igw={w}"]))
            jobs.append((("dgw", f, w), v, [f"+dgw={w}"]))
        for dep in (2, 4, 8):
            for lat in (1, 2, 4):
                jobs.append((("depth", f, dep, lat), sims[(f, dep)], [f"+ilat={lat-1}"]))
    res = {}
    with ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as ex:
        for key, d in ex.map(one, jobs):
            res["|".join(map(str, key))] = d
            print(key, f"cycles={d['cycles']} CM/MHz={d['coremark_per_mhz']:.3f} CPI={d['cpi']:.3f}", flush=True)
    json.dump(res, open(os.path.join(ROOT, "tests/perf/results/mem_sweep.json"), "w"), indent=1)
main()
