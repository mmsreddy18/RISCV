# Memory integration: what was checked, how, and what it does and does not show

Source of the rules: OpenHW/Silicon Labs **OBI v1.6.0** (`OBI-v1.6.0.pdf`, openhwgroup/obi), rule numbers R-x below.
Run everything with `verif/run_all.sh` (about 8 minutes). Last result: `verif/results/run_all.txt`.

## Port audit (our core as an OBI manager)
| Rule | Finding on the original core | Now |
|---|---|---|
| R-2.1 req low in reset | violated (instr port) | fixed |
| R-3.1.1 / R-3.1.2 address phase stable, req not retracted | violated: a redirect changed a pending fetch address (up to 46 hits per run with random stalls) | fixed: ungranted request held (`pend_q`/`pend_addr_q` in `rv_fetch`) |
| R-21.1 / R-24 req must not depend combinationally on gnt/rvalid (or another port's inputs) | data_req depended on data_rvalid; with FAST_REDIRECT=1 instr_req depends on data_gnt/rvalid | fixed for FAST_REDIRECT=0 (`OBI_STRICT_REQ`). **FAST_REDIRECT=1 still violates R-24: it is not an OBI-compliant option.** |
| R-5 / R-6 response ordering, R-7 / R-9 be + addr | no violations found | |
| err (access fault) | no err input existed | added on both ports; mcause 1 / 5 / 7 |
| Not implemented | rready (tied high, allowed by spec §3.7), aid/rid, atop, parity/checksum | |

## Evidence by method
| Method | Independent of us? | Result |
|---|---|---|
| Our OBI checker (`obi_checker.sv`) on both ports, all test programs, FAST 0/1, stall 0/1 | no (written by us from the spec) | no violations; it did flag the original core (`results/audit_before.txt`) |
| Yosys structural check of R-21.1/R-24 (`comb_deps.py`) | no | FAST_REDIRECT=0: no output depends on a link input. FAST_REDIRECT=1: instr_req/addr depend on data_gnt/rvalid/err/rdata |
| pulp-platform `obi_asserter` on every link of the SoC (4 crossbar outputs + 2 core ports) | **yes** (third party; upstream says it is "not complete": R-2.1, R-2.2, R-3.1, R-4.1 only) | no failures on directed, traps, soc_faults, CoreMark; fires when an address-hold bug is injected |
| SoC built from unmodified pulp-platform `obi_xbar`, `obi_sram_shim`, `obi_err_sbr`, `obi_cut` | **yes** | all programs PASS: plain, random SRAM wait states, 2 register slices, and the single shared-SRAM mode (20 program/config runs) |
| Official **riscv-tests** (rv32ui/um/uc/mi) | **yes** | 61 pass, 2 fail, 4 skipped (see below); same on core-only, SoC (3 memory configs), FAST 0/1, stall 0/1 |
| Random programs against **Spike** | **yes** (Spike built from riscv-isa-sim; only DEBUG_START and DEFAULT_RSTVEC moved, `third_party/spike_platform.patch`) | 300 programs x 2 stall modes: 0 mismatches; an injected SLT bug gives 70 mismatches |
| Bounded formal (Yosys SAT, `rv_obi_formal.sv`): stability, hold-until-gnt, be/addr, outstanding limits with a free OBI-legal environment | no | no violation within 30 cycles of reset (depth 20 in `run_all.sh`); finds an injected address-hold bug at depth 14 |
| Mutation checks (8 trap/CSR bugs, earlier turn) | no | all caught by `traps.S` |

## riscv-tests failures (both expected, not logic bugs)
* `rv32mi/breakpoint`: needs the optional debug-trigger CSRs (`tselect`/`tdata*`, Sdtrig). Trace: illegal-instruction trap at `csrw tselect`.
* `rv32ui/ma_data`: expects misaligned loads/stores to succeed. This core traps on them (cause 4/6), which the spec allows.
* Skipped: `fence_i` (no Zifencei), `pmpaddr` (no PMP), `zicntr`, `instret_overflow` (counter access control / overflow not modelled).

## What is NOT shown
* The formal result is a **bounded** proof from reset (30 cycles), not an unbounded proof. The Yosys/sby combination available here could not run sby's normal flow, so plain `sat` was used (see `formal/run_sat.sh`).
* Only the manager side of our own core is checked against the full rule set; the third-party asserter covers a subset of OBI.
* No RVFI/lock-step instruction-by-instruction comparison: Spike is compared at the end of each random program (registers + 1 KiB memory), not per retired instruction. Random programs contain no CSR/trap instructions; those are covered by `traps.S`, `soc_faults.S` and riscv-tests rv32mi.
* No FPGA/silicon run, no timing/area numbers for the SoC, no multi-outstanding or atomic transactions.

## Cost of compliance (CoreMark, 10 iterations, measured region, 3,133,341 instructions)
| Configuration | Cycles | CPI |
|---|---|---|
| Before the OBI fixes, testbench memory (no wait states) | 3,568,468 | 1.139 |
| After (R-21.1 strict requests), testbench memory | 3,749,683 | 1.197 (+5.1%) |
| SoC, one shared SRAM (`SPLIT_MEM=0`) | 4,081,538 | 1.303 |
| **SoC, separate ITCM + DTCM (default), Harvard-linked CoreMark** | **3,749,741** | **1.197** |
| Same, random wait states in both memories | 4,378,752 | 1.397 |
| Same, 2 register slices in front of each memory | 8,813,449 | 2.813 |
| (shared SRAM) + random wait states | 4,982,820 | 1.590 |
| (shared SRAM) + 2 register slices | 8,922,642 | 2.848 |
The +5.1% was measured by switching `OBI_STRICT_REQ` off (cycles return to 3,568,468). The extra 8.8% between the testbench memory and the plain SoC is contention for the single SRAM port: instruction fetch and data accesses share one SRAM, and the testbench memory has separate instruction and data memories. Measured in the CoreMark region: both ports see a 1-cycle response latency (same as the testbench), but the data port waits 335,984 cycles for grant and the instruction port 141,633, and every one of those wait cycles coincides with the other port being granted in the same cycle. Extra cycles vs the testbench: 331,855. Splitting code and data into two SRAMs removes it: the split SoC runs CoreMark in 3,749,741 cycles, within 58 cycles of the testbench figure (the CoreMark image must be linked with data in DTCM; the old single-region image on the split SoC takes 3,999,193 because its data still lands in ITCM). Wait states cost +16.8% instead of +22% for the shared SRAM.

## Found by Vivado synthesis (xczu5ev, Vivado 2025.2), fixed
`rv_fetch` reset `fetch_addr_q`, `pc_q`, `hw_off_q` asynchronously to the value of the input `boot_addr_i`. Vivado mapped them to FDCP
(async set AND clear) and raised ~60 critical warnings "cannot be timed accurately" (Netlist 29-358). Simulation and the formal check
could not show this. Fix: the register block of `rv_fetch` now uses a synchronous reset (reset must last at least one clock edge).
All checks were re-run afterwards with identical results (cycle counts unchanged).
