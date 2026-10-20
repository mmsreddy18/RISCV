#!/usr/bin/env python3
"""Run the official riscv-tests (rv32ui, rv32um, rv32uc, rv32mi, p-environment) on rv_core in tb_core.
usage: run.py <riscv-tests dir> <Vtb_core> [stall] ; result table on stdout.  Pass = tohost written with 1."""
import os, subprocess, sys, glob
rt, vtb = sys.argv[1], sys.argv[2]; stall = sys.argv[3] if len(sys.argv) > 3 else "0"
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, "..", ".."))
out = os.path.join(root, "build", "riscv_tests"); os.makedirs(out, exist_ok=True)
SKIP = {"rv32ui/fence_i": "Zifencei not implemented", "rv32mi/pmpaddr": "no PMP", "rv32mi/zicntr": "needs U/S-mode counters access control",
        "rv32mi/instret_overflow": "hpm/instret overflow behaviour not modelled"}
res = []
for suite, march in (("rv32ui", "rv32im"), ("rv32um", "rv32im"), ("rv32uc", "rv32imc"), ("rv32mi", "rv32imc")):
    for src in sorted(glob.glob(f"{rt}/isa/{suite}/*.S")):
        name = f"{suite}/{os.path.basename(src)[:-2]}"
        if name in SKIP: res.append((name, "SKIP", SKIP[name])); continue
        tag = name.replace("/", "-"); elf = f"{out}/{tag}.elf"
        cc = subprocess.run(["riscv64-unknown-elf-gcc", f"-march={march}_zicsr", "-mabi=ilp32", "-static", "-mcmodel=medany",
                             "-fvisibility=hidden", "-nostdlib", "-nostartfiles", f"-I{rt}/env/p", f"-I{rt}/isa/macros/scalar",
                             "-T", f"{here}/link.ld", "-o", elf, src], capture_output=True, text=True)
        if cc.returncode: res.append((name, "BUILD-FAIL", cc.stderr.strip().splitlines()[-1][:80])); continue
        subprocess.check_call(["riscv64-unknown-elf-objcopy", "-O", "binary", elf, f"{out}/{tag}.bin"])
        subprocess.check_call(["python3", f"{root}/tests/bin2hex.py", f"{out}/{tag}.bin", f"{out}/{tag}.hex"])
        r = subprocess.run([vtb, f"+hex={out}/{tag}.hex", f"+stall={stall}", "+seed=5", "+maxcyc=400000", *os.environ.get("RT_EXTRA", "").split()], capture_output=True, text=True)
        line = next((l for l in r.stdout.splitlines() if l.startswith("TB:")), "no result")
        res.append((name, "PASS" if "PASS" in line else "FAIL", line[:70]))
for n, s, d in res: print(f"{s:10s} {n:28s} {d if s != 'PASS' else ''}")
c = {k: sum(1 for r in res if r[1] == k) for k in ("PASS", "FAIL", "BUILD-FAIL", "SKIP")}
print("TOTAL", c)
