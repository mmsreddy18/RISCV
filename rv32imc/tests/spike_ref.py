"""Reference run on Spike (independent RISC-V ISA simulator) for the random-program test.
Runs the rv32im ELF until the final `sw` (the store to the result address), then reads x1..x31 and 1 KiB of data.
Spike here is built from riscv-software-src/riscv-isa-sim with only DEBUG_START / DEFAULT_RSTVEC moved
(see verif/third_party/README.md) so that RAM can sit at address 0 like in our test layout."""
import os, re, subprocess, tempfile
SPIKE = os.environ.get("SPIKE", "/home/claude/src/spike/install/bin/spike")
ABI = "zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6".split()

def run(elf, data_base=0x4000, data_words=256):
    dis = subprocess.check_output(["riscv64-unknown-elf-objdump", "-d", elf], text=True)
    insns = re.findall(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(\S+)", dis, re.M)
    last = int(insns[-1][0], 16)                      # the final `j .`
    stop = last - 4                                   # the `sw` before it
    cmds = f"until pc 0 {stop:x}\nreg 0\n" + "".join(f"mem {data_base + 4 * i:x}\n" for i in range(data_words)) + "q\n"
    with tempfile.NamedTemporaryFile("w", suffix=".cmd", delete=False) as f:
        f.write(cmds); cf = f.name
    try:
        out = subprocess.run([SPIKE, "-d", f"--debug-cmd={cf}", "--isa=rv32im", "-m0x0:0x10000", "--pc=0", elf],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120).stdout
    finally:
        os.unlink(cf)
    regs = dict(re.findall(r"(\w+):\s+0x([0-9a-f]{8})", out))
    x = [int(regs[n], 16) for n in ABI]
    words = re.findall(r"^0x([0-9a-f]{8})$", out, re.M)
    assert len(words) == data_words and len(x) == 32, "unexpected Spike output:\n" + out[:400]
    mem = bytearray(0x10000)
    for i, w in enumerate(words):
        mem[data_base + 4 * i:data_base + 4 * i + 4] = int(w, 16).to_bytes(4, "little")
    return x, mem
