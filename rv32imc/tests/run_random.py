#!/usr/bin/env python3
"""Differential random test: ISS(rv32im build) vs RTL(rv32imc build)."""
import subprocess, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import gen_random, iss
if os.environ.get('REF') == 'spike':
    import spike_ref

ROOT = os.path.join(os.path.dirname(__file__), "..")
CROSS = "riscv64-unknown-elf-"
B = os.path.join(ROOT, "build", "rnd")
os.makedirs(B, exist_ok=True)

def build(src, march, tag):
    elf = f"{B}/{tag}.elf"
    subprocess.check_call([CROSS + "gcc", f"-march={march}", "-mabi=ilp32", "-nostdlib", "-nostartfiles",
                           "-T", f"{ROOT}/tests/link.ld", "-o", elf, src])
    subprocess.check_call([CROSS + "objcopy", "-O", "binary", elf, f"{B}/{tag}.bin"])
    return f"{B}/{tag}.bin"

def parse(path):
    d = {}
    for line in open(path):
        k, v = line.split()
        d[k] = int(v, 16)
    return d

def main():
    first, count = int(sys.argv[1]), int(sys.argv[2])
    stalls = [int(x) for x in os.environ.get("STALLS", "0,1").split(",")]
    bad = 0
    for seed in range(first, first + count):
        src = f"{B}/s{seed}.S"
        open(src, "w").write(gen_random.gen(seed))
        ref_bin = build(src, "rv32im", f"s{seed}_ref")
        dut_bin = build(src, "rv32imc", f"s{seed}_dut")
        # size of compressed image (just info)
        subprocess.check_call(["python3", f"{ROOT}/tests/bin2hex.py", dut_bin, f"{B}/s{seed}.hex"])
        x, mem = spike_ref.run(f"{B}/s{seed}_ref.elf") if os.environ.get('REF') == 'spike' else iss.run(ref_bin)
        ref = {f"x{i}": x[i] for i in range(1, 32)}
        for i in range(256):
            a = 0x4000 + 4 * i
            ref["m%08x" % a] = int.from_bytes(mem[a:a + 4], "little")
        for st in stalls:
            dump = f"{B}/s{seed}_st{st}.dump"
            p = subprocess.run([os.environ.get("VTB", f"{ROOT}/build/f0_d4_b1_g0/Vtb_core"), f"+hex={B}/s{seed}.hex", f"+stall={st}",
                                f"+seed={seed*7+st}", f"+dump={dump}", "+maxcyc=400000", *os.environ.get("VTB_ARGS", "").split()],
                               capture_output=True, text=True)
            if "PASS" not in p.stdout:
                print(f"seed {seed} stall={st}: DUT did not finish: {p.stdout.strip()[-120:]}")
                bad += 1
                continue
            got = parse(dump)
            diffs = [k for k in ref if ref[k] != got.get(k)]
            if diffs:
                bad += 1
                print(f"seed {seed} stall={st}: MISMATCH in {diffs[:6]}")
                for k in diffs[:4]:
                    print(f"    {k}: ref={ref[k]:08x} dut={got.get(k):08x}")
    print(f"done: {count} programs x {len(stalls)} configs, failures={bad}")
    sys.exit(1 if bad else 0)

main()
