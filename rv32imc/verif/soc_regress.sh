#!/bin/bash
# usage: verif/soc_regress.sh   (project root; needs verif/third_party/fetch.sh done and build/cm/O2_rvc/coremark.hex for the CoreMark line)
# Builds rv_soc with plain / random-SRAM-wait-state / 2 register-slice SRAM paths and runs the test programs from boot ROM.
set -e
B() { bash verif/soc_build.sh build/$1 "${@:2}"; }
B soc_plain; B soc_stall -GSRAM_STALL=1; B soc_cut2 -GSRAM_CUTS=2; B soc_unified -GSPLIT_MEM=0
bash tests/soc/mkimg.sh
for cfg in soc_plain soc_stall soc_cut2 soc_unified; do
  for t in tests/directed tests/traps build/socimg/soc_faults build/cm/O2_rvc/coremark build/cm/O2_rvc_h/coremark; do
    [ -f $t.hex ] || continue
    r=$(build/$cfg/Vtb_soc +hex=$t.hex +rom=build/socimg/boot.hex +maxcyc=40000000 2>&1 | grep -o "TB: [A-Z]*.*" | head -1)
    echo "$cfg $(basename $t): $r"
  done
done
