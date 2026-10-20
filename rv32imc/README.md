# rv32imc — 4-stage RV32IMC core (CV32E40P-class), step 1

RV32IMC + Zicsr + machine-mode traps/interrupts (M-mode only). Zifencei not implemented.
SystemVerilog, lint-clean under `verilator -Wall`, simulated with Verilator 5.

```
rtl/rv_pkg.sv        types/opcodes
rtl/rv_c_decoder.sv  RV32C -> RV32 expander (all integer C instructions, illegal detection)
rtl/rv_fetch.sv      IF: prefetch FIFO + halfword aligner + expander, OBI-style instr port
rtl/rv_decoder.sv    RV32IM decoder
rtl/rv_alu.sv        ALU
rtl/rv_mul.sv        MUL 1 cycle; MULH/MULHSU/MULHU 4 cycles on one shared 17x17 multiplier
rtl/rv_div.sv        radix-2 restoring divider, 1+32+1 cycles, spec-correct x/0 and INT_MIN/-1
rtl/rv_regfile.sv    32x32, 2R1W
rtl/rv_csr.sv        M-mode CSR file, counters, trap/mret state, interrupt pending/priority
rtl/rv_core.sv       pipeline: IF/ID/EX/WB, hazards, data port
tb/tb_core.sv        memory model (+random gnt/latency), magic result address
tests/               directed.S, random generator, RV32IM Python ISS, differential runner
```

## Three ready-made variants (`rtl/rv32imc_variants.sv`)
| Module | Contents |
|---|---|
| `rv32imc_base`  | RV32IMC, no branch predictor, no CSRs/traps (`BP_ENABLE=0, ZICSR=0`) |
| `rv32imc_bp`    | base + BTB/BHT/RAS predictor (`BP_ENABLE=1, ZICSR=0`) |
| `rv32imc_zicsr` | bp + Zicsr + machine-mode traps/interrupts (`BP_ENABLE=1, ZICSR=1`) |
All three wrap `rv_core` with identical ports. `make regress-variants` tests all three.

## Run
```
make lint
make run T=tests/directed                 # PASS
make run T=tests/directed STALL=1 SEED=7  # random gnt / latency on both ports
make regress                              # directed + random-vs-ISS on 4 configs
python3 tests/run_random.py 1 200         # differential random test only
```
Needs `verilator` (>=5), `riscv64-unknown-elf-gcc` (binutils is enough), `python3`.

## Pipeline
| Stage | What happens |
|---|---|
| IF | Word fetch into a 4-entry FIFO; aligner delivers one 16/32-bit instruction per cycle (handles 32-bit instrs straddling words, branch to halfword targets); RVC expanded here; IF/ID register |
| ID | decode, regfile read, **forwarding**, branch/JAL/JALR compare + target, redirect IF |
| EX | ALU, MUL/DIV, load/store address, **data request issued here** (waits for `gnt`) |
| WB | waits for `data_rvalid` (loads *and* stores), aligns/sign-extends load data, writes regfile |

**Forwarding.** Operands are made final in ID: EX result (combinational, ALU/MUL/DIV) > WB result
(incl. load data from `data_rdata_i`) > regfile. EX therefore needs no forwarding muxes, and the
same forwarded value feeds the branch comparator.
**Hazards.** Load-use: 1 bubble. Taken branch/jump: IF/ID + FIFO flushed. Multi-cycle EX op or
EX waiting for `gnt`: ID/IF hold. WB waiting for `rvalid`: whole pipeline freezes. There is no
speculation, so no wrong-path memory access can occur.

Measured (Verilator, zero-wait memory):

| | default | `FAST_REDIRECT=1` |
|---|---|---|
| taken branch / jump penalty | 3 cycles | 2 cycles |
| load-use | +1 | +1 |
| MUL / MULH* / DIV,REM | 1 / 4 / 34 cycles | same |

`FAST_REDIRECT` issues the target fetch in the same cycle ID resolves the branch. It creates a
combinational path `data_gnt/rvalid -> issue -> instr_req/addr`; leave it off if your fabric can
make `data_gnt` depend on `instr_req` combinationally (loop risk).

## Ports
OBI-style: `*_req`, `*_gnt`, `*_addr`, (`*_we`, `*_be`, `*_wdata`), `*_rvalid`, `*_rdata`.
Up to 2 outstanding instruction requests, 1 data request. Responses must be in order.
Status pulses: `retire_o`, `ecall_o`, `ebreak_o`, `illegal_o`.

## Verification done
* `directed.S`: ~100 self-checking cases (ALU, forwarding distances, all load/store sizes with
  sign-extension, load-use incl. into store data / address / branch / jalr, all branch types,
  jal/jalr/link/bit0, MUL/DIV edge cases incl. x/0 and INT_MIN/-1, every C.* form, 32-bit
  instructions on halfword boundaries). Passes with and without random stalls (20 seeds).
* Differential random test: generator -> same source built `rv32im` (run on the Python ISS)
  and `rv32imc` (assembler compresses it, run on the RTL); all x1..x31 and 1 KiB of memory must
  match. 1000+ programs x {no stall, random stall}, over 4 configs (FAST_REDIRECT 0/1, FIFO depth 2/4/8). 0 failures.
* Mutation check: 6 injected RTL bugs (no WB forwarding, no load-use stall, no stale-response
  drop, MULH signedness, divider remainder sign, aligner straddle) are all caught.

Not done: riscv-arch-test / riscv-tests, formal, synthesis/timing. The ISS is my own, so a shared
misreading of the spec is possible (the hand-computed directed values are independent of it).

## Memory system (`rtl/soc/`, microcontroller style: on-chip SRAM, no caches)
`rv_soc` = `rv_core` + unmodified pulp-platform `obi_xbar` + memories. Code and data are separate SRAMs (`SPLIT_MEM=1`, default), so a fetch and a data access in the same cycle never share a port; `SPLIT_MEM=0` gives the old single 256 KiB SRAM for comparison. Link software with code at 0x0 and data/stack at 0x20000 (`tests/perf/coremark/bench_harvard.ld`; `CM_LD=bench_harvard.ld build_coremark.sh ...`). Rebuild the boot/fault images with `tests/soc/mkimg.sh`.
| Region | Address | Notes |
|---|---|---|
| ITCM (instruction memory) | 0x0000_0000 - 0x0001_FFFF (128 KiB, `ITCM_WORDS`) | read/write/execute; the data port may also reach it (tables, loaders) |
| DTCM (data memory) | 0x0002_0000 - 0x0003_FFFF (128 KiB, `DTCM_WORDS`) | read/write, **not executable** (fetch -> err -> access fault); separate SRAM from ITCM |
| Boot ROM | 0x0004_0000 - 0x0004_0FFF (reset vector) | read/execute, write = access fault |
| MMIO | 0x1000_0000 - 0x1000_0FFF | tohost, putchar, ROI markers, mtime/mtimecmp timer, sw/ext irq lines; not executable |
| anything else | | `obi_err_sbr` answers err=1 -> access fault (mcause 1 fetch / 5 load / 7 store) |
The core ports follow OBI 1.6 (no rready/aid/atop) with an added `*_err_i`. Audit, evidence and limits: `verif/VERIFICATION.md`.
Run: `bash verif/third_party/fetch.sh` (pulp sources), `verif/third_party/fetch_ref.sh` (Spike, riscv-tests), then `verif/run_all.sh`.
`FAST_REDIRECT=1` is faster but **not OBI-compliant** (its instruction request depends combinationally on data-port inputs).

## Zicsr + machine-mode traps
* CSRs: mstatus(MIE/MPIE, MPP=11), misa, mie, mip, mtvec (direct/vectored), mscratch, mepc, mcause, mtval,
  mcountinhibit, mcycle/minstret (+h), cycle/instret shadows, mvendorid/marchid/mimpid/mhartid.
  Unknown CSR or write to a read-only CSR = illegal-instruction trap.
* csrrw/rs/rc[i] execute in EX (old value = result, write when leaving EX); rs/rc with x0/uimm=0 do not write.
* Exceptions: illegal instruction, ecall, ebreak (taken in ID), misaligned load/store (detected in EX from the address,
  no bus request). Interrupts: software, timer, external (priority MEI > MSI > MTI), taken before the instruction in ID.
  `mret` is resolved in ID. `wfi` is a NOP.
* Precise: the trapping instruction becomes a bubble, older instructions complete. A trap-capable instruction in ID
  waits one cycle while a CSR instruction is in EX.
* Cost: CoreMark cycle counts identical to before (3,568,468 / 3,502,814); area +3.8k um2 (+8.7%) on the 16/64 core.
* Test: `tests/traps.S` (~150 checks, run by `make regress`).

## Known limitations
* No Zifencei (`fence.i` is illegal); `fence` is a NOP. No bus access-fault exceptions (ports have no error signal).
* Instruction-address-misaligned cannot occur with C; mtval for illegal instructions is the instruction bits.
* On redirect a not-yet-granted instruction request may be retracted / change address (documented in `rv_fetch.sv`).
* Reset is async active-low on control state; datapath registers are not reset.
* The random differential test (Python ISS) covers RV32IMC only; CSR/trap behaviour is covered by the directed `traps.S`.
