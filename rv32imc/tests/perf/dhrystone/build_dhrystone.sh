#!/bin/bash
# Usage: build_dhrystone.sh <outdir> <march> <opt-flags...>  -> <outdir>/dhry.{elf,bin,hex}
# Sources come from riscv-software-src/riscv-tests (benchmarks/dhrystone), fetched on first use.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
DL="${DHRY_DIR:-$ROOT/build/dl/riscv-tests}"
OUT="$1"; MARCH="$2"; shift 2
CROSS="${CROSS:-riscv64-unknown-elf-}"
if [ ! -f "$DL/benchmarks/dhrystone/dhrystone_main.c" ]; then
  mkdir -p "$DL"
  git clone --depth 1 --filter=blob:none --sparse https://github.com/riscv-software-src/riscv-tests "$DL"
  (cd "$DL" && git sparse-checkout set benchmarks/dhrystone)
fi
D="$DL/benchmarks/dhrystone"
mkdir -p "$OUT"
COMMON="-march=$MARCH -mabi=ilp32 -ffreestanding -nostdlib -I$HERE/include -I$D"
$CROSS"gcc" $COMMON "$@" -fno-common -fno-builtin-printf -w -c "$D/dhrystone_main.c" -o "$OUT/dhry_main.o"
$CROSS"gcc" $COMMON "$@" -fno-common -fno-builtin-printf -w -Ddebug_printf=dhry_stub_debug_printf -c "$D/dhrystone.c" -o "$OUT/dhry.o"
$CROSS"gcc" $COMMON -O2 -fno-tree-loop-distribute-patterns -fno-builtin ${FAST_STR:+-DFAST_STR} -c "$HERE/port.c" -o "$OUT/port.o"
$CROSS"gcc" $COMMON -c "$ROOT/tests/perf/coremark/crt0.S" -o "$OUT/crt0.o"
$CROSS"gcc" $COMMON -T "$ROOT/tests/perf/coremark/bench.ld" -o "$OUT/dhry.elf" "$OUT"/crt0.o "$OUT"/dhry_main.o "$OUT"/dhry.o "$OUT"/port.o -lgcc
$CROSS"objcopy" -O binary "$OUT/dhry.elf" "$OUT/dhry.bin"
python3 "$ROOT/tests/bin2hex.py" "$OUT/dhry.bin" "$OUT/dhry.hex"
$CROSS"size" "$OUT/dhry.elf"
