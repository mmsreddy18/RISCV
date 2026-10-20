# Branch prediction (BTB + BHT + RAS), adapted from biRISC-V

New module `rtl/rv_npc.sv`; changed modules `rtl/rv_fetch.sv` and `rtl/rv_core.sv`
(everything else is untouched). `BP_ENABLE=0` gives back the old core cycle for cycle
(checked: CoreMark 4,580,201 cycles both before and after the change).

## What was taken from biRISC-V (`biriscv_npc.v`)
* fully associative BTB with LFSR replacement
* 2-bit BHT counters reset to "strongly taken", bimodal by default, optional gshare (`GSHARE=1`)
* return-address stack with a speculative index and a real index; a mispredict restores the
  speculative index from the real one
* call/return classification: link register x1; `jalr x0,0(x1)` style = return
* predictor is trained on every resolved branch/jump
* biRISC-V defaults are 32 BTB entries, 512 BHT counters, 8 RAS entries; **this core defaults to 16 BTB entries and 64 counters** (area-efficient, see below), 8 RAS entries

## What had to differ in this core
| Topic | biRISC-V | here |
|---|---|---|
| Fetch | 64-bit bundles, 2 instructions | 32-bit words + halfword aligner (RVC) |
| BTB key | PC of the branch | address of the branch's **last halfword**, so the lookup for a word request finds every branch that ends in that word, including a 32-bit one straddling two words |
| Lookup point | fetch request address | same: one lookup per word request, so a predicted-taken branch causes no bubble in the request stream |
| Prediction travels | tagged on the fetch bundle | tag `{taken, halfword, target, call, ret}` follows the word through the in-flight queue and the prefetch FIFO; the aligner uses it when it delivers the branch |
| Verification | exec stage | ID stage (branches already resolve in ID). Direction, target and call/ret type are compared; a mismatch redirects fetch |
| BTB allocation | every branch | taken branches/jumps only |
| Empty BTB entry | pc == 0 | valid bit |
| RAS repair | on every resolved branch | on a redirect only; a call that had to redirect is pushed at that point |
| Speculative RAS | pops only when the RAS entry is valid | pops on any predicted return, so speculative and real indexes cannot drift |

## Parameters (`rv_core`, `rv_fetch`)
`BP_ENABLE`, `BTB_N`/`BTB_W`, `BHT_N`/`BHT_W`, `RAS_N`/`RAS_W`, `GSHARE`.
Makefile: `make run T=... BP=1 GSHARE=0 BTBLOG=5 BHTLOG=9`.

## Known limits
* The BTB assumes a fixed instruction layout. Code that changes in memory (self-modifying
  code, `fence.i`) would need the BTB invalidated; Zifencei is not implemented yet.
* Indirect jumps other than returns are predicted with the last target seen.
* Area: the 16-entry / 64-counter default adds 18.7k um2 (+76%) for +28% CoreMark. The biRISC-V size
  (32 / 512) adds 46.7k um2 (+190%) for +30%, so it was not kept as the default. The sweep in
  `tests/perf/bp_sweep.py` has the data. Dhrystone, whose hot code is larger than 16 branches, gains
  +7% at 16 entries against +19% at 32.
