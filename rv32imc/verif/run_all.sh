#!/bin/bash
# One command that re-runs every check and prints a one-line verdict per method.  usage: verif/run_all.sh   (project root)
# Needs: verilator, riscv64-unknown-elf-gcc, yosys, sv2v (SV2V=...), verif/third_party/fetch.sh and fetch_ref.sh done,
#        build/cm/O2_rvc/coremark.hex and build/cm/O2_rvc_h/coremark.hex (tests/perf/coremark/build_coremark.sh; the _h one with CM_LD=bench_harvard.ld).
SPIKE=${SPIKE:-$HOME/src/spike/install/bin/spike}; RT=${RT:-$HOME/src/riscv-tests}; export SPIKE
q() { grep -v "Warning\|^ *[0-9]* |\|\^~\|Location\|^ *\.\.\."; }
echo "1 variants regression (base/bp/zicsr; directed+traps+access_faults+300 random vs own ISS):"
make -s regress-variants 2>&1 | q | grep -c "PASS" | xargs echo "   PASS lines:"; make -s regress-variants 2>&1 | q | grep "failures=" | sort | uniq -c
echo "2 OBI dynamic checker audit (instr+data ports, FAST 0/1):"; bash verif/audit.sh run_all >/dev/null 2>&1; grep -vc "violations: none" verif/results/audit_run_all.txt | xargs echo "   rows with violations:"
echo "3 R-21.1 / R-24 structural (Yosys):"
sv2v rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv > build/cd_core.v 2>/dev/null
for f in 0 1; do echo "   FAST_REDIRECT=$f:"; python3 verif/comb_deps.py build/cd_core.v FAST_REDIRECT=$f 2>&1 | grep "<-" | sed 's/^/     /'; done
echo "4 SoC with pulp-platform interconnect (plain / SRAM wait states / 2 slices):"; bash verif/soc_regress.sh 2>&1 | q | grep -c "PASS" | xargs echo "   PASS lines (of 20):"
echo "5 SoC with third-party obi_asserter on every link:"
bash verif/soc_build.sh build/soc_asrt -DOBI_ASSERT --assert -GSRAM_STALL=1 -f verif/soc_asrt.f >/dev/null 2>&1
for t in tests/directed tests/traps build/socimg/soc_faults build/cm/O2_rvc/coremark build/cm/O2_rvc_h/coremark; do echo -n "   $(basename $t): "; build/soc_asrt/Vtb_soc +hex=$t.hex +rom=build/socimg/boot.hex +maxcyc=40000000 2>&1 | grep -o "TB: [A-Z]*\|Assertion failed" | head -1; done
echo "6 official riscv-tests (rv32ui/um/uc/mi):"
for c in "build/f0_d4_b1_g0/Vtb_core 0" "build/f0_d4_b1_g0/Vtb_core 1" "build/f1_d4_b1_g0/Vtb_core 0"; do set -- $c; echo -n "   $1 stall=$2: "; python3 verif/riscv_tests/run.py $RT $1 $2 2>&1 | grep TOTAL; done
echo "7 random programs vs Spike (300 x 2 stall modes):"; REF=spike python3 tests/run_random.py 100 300 2>&1 | tail -1 | sed 's/^/   /'
echo "8 bounded formal (Yosys SAT, OBI manager rules, 20 cycles from reset):"; bash verif/formal/run_sat.sh final 20 FAST_REDIRECT=0 2>&1 | tail -1 | sed 's/^/   /'
