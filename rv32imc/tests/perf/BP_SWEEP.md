# Branch-predictor size sweep (CoreMark, 10 iterations, measured region 3,133,341 instructions, ZICSR=1, zero-wait memory)
Script: `python3 tests/perf/bp_sweep.py` (round 1) and `SWEEP=combo python3 tests/perf/bp_sweep.py` (round 2). Every run passes CoreMark.
Default predictor = BTB 16 (fully associative) / BHT 64 / RAS 8.  Speedup is relative to no predictor (4,761,656 cycles, CPI 1.520).

| Configuration | Cycles | CPI | Speedup |
|---|---|---|---|
| no predictor | 4,761,656 | 1.520 | 1.000 |
| default 16 / 64 / 8 | 3,749,683 | 1.197 | 1.270 |
| BTB 2 (BHT 64, RAS 8) | 4,070,953 | 1.299 | 1.170 |
| BTB 4 | 4,005,752 | 1.278 | 1.189 |
| BTB 8 | 3,850,659 | 1.229 | 1.237 |
| BTB 32 | 3,715,317 | 1.186 | 1.282 |
| BHT 4 (BTB 16, RAS 8) | 3,867,983 | 1.234 | 1.231 |
| BHT 16 | 3,773,623 | 1.204 | 1.262 |
| BHT 256 | 3,746,067 | 1.196 | 1.271 |
| RAS 2 (BTB 16, BHT 64) | 3,749,957 | 1.197 | 1.270 |
| RAS 4 / 8 / 16 | 3,749,683 | 1.197 | 1.270 |
| gshare BHT 64 | 3,887,260 | 1.241 | 1.225 |
| gshare BHT 256 | 3,822,237 | 1.220 | 1.246 |
| **C: 16 / 16 / 2** | 3,773,897 | 1.204 | 1.262 |
| **D: 8 / 16 / 2** | 3,865,406 | 1.234 | 1.232 |
| **E: 4 / 16 / 2** | 4,011,400 | 1.280 | 1.187 |
| 32 / 32 / 2 | 3,720,500 | 1.187 | 1.280 |

Limits: one benchmark. CoreMark has shallow call nesting, so the return stack looks unnecessary beyond 2 entries; deeper recursion would need more.
Area (Vivado, xczu5ev-sfve784-1LV-i, post-synthesis): no predictor `u_core` 2,487 LUT / 790 FF; default predictor 4,875 LUT / 2,355 FF (`u_npc` 2,381 LUT / 1,486 FF).
