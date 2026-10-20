#!/bin/bash
# Usage: build_coremark.sh <outdir> <march> <opt-flags...>   -> <outdir>/coremark.{elf,bin,hex}
# CoreMark sources are fetched on first use (Apache-2.0, https://github.com/eembc/coremark).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CM="${COREMARK_DIR:-$ROOT/build/dl/coremark}"
OUT="$1"; MARCH="$2"; shift 2
CROSS="${CROSS:-riscv64-unknown-elf-}"
if [ ! -f "$CM/core_main.c" ]; then
  mkdir -p "$CM" && git clone --depth 1 https://github.com/eembc/coremark "$CM"
fi
mkdir -p "$OUT"
ITER="${ITERATIONS:-10}"
FLAGS="$*"
COMMON="-march=$MARCH -mabi=ilp32 -ffreestanding -nostdlib -I$HERE -I$CM"
DEFS="-DITERATIONS=$ITER -DTOTAL_DATA_SIZE=2000 -DPERFORMANCE_RUN=1 -DFLAGS_STR=\"\\\"$FLAGS\\\"\""
eval $CROSS"gcc" $COMMON $FLAGS $DEFS -c "$CM/core_main.c" "$CM/core_list_join.c" "$CM/core_matrix.c" \
    "$CM/core_state.c" "$CM/core_util.c" "$HERE/core_portme.c" 2>&1 | grep -v "^$" || true
mv core_*.o "$OUT"/ 2>/dev/null || true
$CROSS"gcc" $COMMON -O2 -fno-tree-loop-distribute-patterns -c "$HERE/libc_min.c" -o "$OUT/libc_min.o"
$CROSS"gcc" $COMMON -c "$HERE/crt0.S" -o "$OUT/crt0.o"
$CROSS"gcc" $COMMON -T "$HERE/${CM_LD:-bench.ld}" -o "$OUT/coremark.elf" "$OUT"/crt0.o "$OUT"/core_*.o "$OUT"/libc_min.o -lgcc
$CROSS"objcopy" -O binary "$OUT/coremark.elf" "$OUT/coremark.bin"
python3 "$ROOT/tests/bin2hex.py" "$OUT/coremark.bin" "$OUT/coremark.hex"
$CROSS"size" "$OUT/coremark.elf"
