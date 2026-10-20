# Third-party sources used for verification (not modified except where stated)

| Source | Version | Used for |
|---|---|---|
| openhwfoundation/obi `OBI-v1.6.0.pdf` | main @ clone date | the protocol rules (R-xx numbers) |
| pulp-platform/obi | f29d4cc (2026-08-06) | `obi_xbar`, `obi_demux`, `obi_mux`, `obi_err_sbr`, `obi_sram_shim`, `obi_cut` |
| pulp-platform/common_cells | v1.38.0 (the version obi's Bender.yml asks for) | dependencies of the above |
| pulp-platform/common_verification | c5d97a1 | dependencies |

`obi_asserter_renamed.sv` = `obi/src/test/obi_asserter.sv` with ONLY the struct field names changed
(`a_req`->`req`, `a_gnt`->`gnt`, `r_valid`->`rvalid`, `r_ready`->`rready`). The upstream file does not compile
against the repository's own `OBI_TYPEDEF_*` structs (it uses the pre-rename field names), and upstream says it is
"!!!Not complete!!!" (R-2.1, R-2.2, R-3.1, R-4.1 only).

## Added for the independent checks
| Source | Version | Used for |
|---|---|---|
| riscv-software-src/riscv-isa-sim (Spike) | 5a76066 (2026-10-15) + `spike_platform.patch` (moves DEBUG_START and DEFAULT_RSTVEC so RAM can sit at address 0) | reference model for the random programs |
| riscv-software-src/riscv-tests | d7e86f7 (2026-10-14) | official ISA tests, run by `verif/riscv_tests/run.py` |
Fetch/build both with `verif/third_party/fetch_ref.sh`.
