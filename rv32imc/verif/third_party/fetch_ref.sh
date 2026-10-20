#!/bin/bash
# Fetch + build the independent references used by verif/: Spike (patched, see spike_platform.patch) and riscv-tests.
# usage: verif/third_party/fetch_ref.sh [dir]   -> dir/spike/install/bin/spike, dir/riscv-tests   (default ~/src)
# Needs: git, g++, make, device-tree-compiler, libboost-regex-dev, libboost-system-dev   (about 15 min on 2 cores)
set -e
D=${1:-$HOME/src}; P=$(cd "$(dirname "$0")" && pwd); mkdir -p $D/spike $D/riscv-tests
[ -d $D/spike/src/.git ] || git clone -q --depth 1 https://github.com/riscv-software-src/riscv-isa-sim.git $D/spike/src
(cd $D/spike/src && git apply --check $P/spike_platform.patch 2>/dev/null && git apply $P/spike_platform.patch || true)
mkdir -p $D/spike/build && cd $D/spike/build
../src/configure --prefix=$D/spike/install >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null
[ -d $D/riscv-tests/.git ] || git clone -q --depth 1 --recursive --shallow-submodules https://github.com/riscv-software-src/riscv-tests.git $D/riscv-tests
