#!/bin/bash
# usage: build_rt.sh <outdir> [bench...]   builds riscv-tests benchmarks -> <outdir>/<b>.{elf,imem.hex,dmem.hex}
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
RT="${RT_DIR:-/home/claude/src/riscv-tests}/benchmarks"; CROSS="${CROSS:-riscv64-unknown-elf-}"
OUT="$1"; shift; mkdir -p "$OUT"
BM="${*:-median qsort rsort towers vvadd memcpy multiply dhrystone spmv}"
CF="-march=rv32imc_zicsr -mabi=ilp32 -O2 -ffast-math -fno-common -fno-builtin-printf -fno-tree-loop-distribute-patterns -ffreestanding -nostdlib -DPREALLOCATE=1 -std=gnu99 -Wno-implicit-int -Wno-implicit-function-declaration -I$RT/common -I$HERE/inc"
$CROSS"gcc" $CF -c "$HERE/sys_rt.c" -o "$OUT/sys_rt.o"; $CROSS"gcc" $CF -c "$HERE/crt_rt.S" -o "$OUT/crt_rt.o"
for b in $BM; do
  $CROSS"gcc" $CF -I$RT/$b -T "$HERE/bench_sys.ld" -o "$OUT/$b.elf" "$OUT/crt_rt.o" $RT/$b/*.c "$OUT/sys_rt.o" -lgcc 2>&1 | grep -E "error|undefined" 
  [ -f "$OUT/$b.elf" ] || { echo "$b: BUILD FAIL"; continue; }
  $CROSS"objcopy" -O binary "$OUT/$b.elf" "$OUT/$b.bin"
  python3 "$ROOT/tests/bin2hex.py" "$OUT/$b.bin" "$OUT/$b.hex"
  echo "$b: $($CROSS"size" $OUT/$b.elf | tail -1)"
done
