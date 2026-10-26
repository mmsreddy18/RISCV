#!/bin/bash
# usage: verif/sys_regress.sh   (project root).  Builds tb_sys for BP 0/1 x memory wait states 0/1 and runs directed, traps, CoreMark
# (needs build/sys/*.hex from tests/split_hex.py) and the official riscv-tests (build/riscv_tests/*.hex from verif/riscv_tests/run.py).
for bp in 0 1; do for st in 0 1; do bash verif/sys_build.sh build/sys_bp${bp}_st${st} -GBP_ENABLE=$bp -GMEM_STALL=$st || exit 1; done; done
for bp in 0 1; do for st in 0 1; do
  b=build/sys_bp${bp}_st${st}
  for n in directed traps cm; do
    r=$($b/Vtb_sys +imem=build/sys/$n.imem.hex +dmem=build/sys/$n.dmem.hex +maxcyc=60000000 2>&1 | grep -E "TB: (PASS|FAIL|TIMEOUT)|VIOLATION" | tr '\n' ' ')
    echo "BP=$bp STALL=$st $n: $r"
  done
  p=0; f=0; s=0; failed=""
  for h in build/riscv_tests/*.hex; do
    t=$(basename $h .hex); python3 tests/split_hex.py $h build/sys/rt.imem.hex build/sys/rt.dmem.hex >/dev/null 2>&1 || { s=$((s+1)); continue; }
    r=$($b/Vtb_sys +imem=build/sys/rt.imem.hex +dmem=build/sys/rt.dmem.hex +maxcyc=400000 2>&1 | grep -E "TB: (PASS|FAIL|TIMEOUT)" | head -1)
    case "$r" in *PASS*) p=$((p+1));; *) f=$((f+1)); failed="$failed $t";; esac
  done
  echo "BP=$bp STALL=$st riscv-tests: pass=$p fail=$f skipped/unsplit=$s ${failed:+(failed:$failed)}"
done; done
