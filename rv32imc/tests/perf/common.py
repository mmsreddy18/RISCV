"""Shared helpers for the performance scripts."""
import os, re, subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CROSS = "riscv64-unknown-elf-"

# Branch predictor selection for all perf scripts: PERF_BP=0/1, PERF_GSHARE=0/1
BP = int(os.environ.get("PERF_BP", "1"))
GSHARE = int(os.environ.get("PERF_GSHARE", "0"))

def vtb(fast, depth=4, bp=None, gshare=None):
    bp = BP if bp is None else bp
    gshare = GSHARE if gshare is None else gshare
    return os.path.join(ROOT, "build", f"f{fast}_d{depth}_b{bp}_g{gshare}", "Vtb_core")

def build_sim(fast, depth=4, bp=None, gshare=None):
    bp = BP if bp is None else bp
    gshare = GSHARE if gshare is None else gshare
    subprocess.check_call(["make", "-s", "-C", ROOT, "sim", f"FAST={fast}", f"DEPTH={depth}",
                           f"BP={bp}", f"GSHARE={gshare}"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return vtb(fast, depth, bp, gshare)

def assemble(src, workdir, tag, march="rv32imc", ld=None, extra=()):
    os.makedirs(workdir, exist_ok=True)
    ld = ld or os.path.join(ROOT, "tests", "link.ld")
    elf = os.path.join(workdir, tag + ".elf")
    subprocess.check_call([CROSS + "gcc", f"-march={march}", "-mabi=ilp32", "-nostdlib",
                           "-nostartfiles", "-T", ld, "-o", elf, src, *extra])
    binf = os.path.join(workdir, tag + ".bin")
    subprocess.check_call([CROSS + "objcopy", "-O", "binary", elf, binf])
    hexf = os.path.join(workdir, tag + ".hex")
    subprocess.check_call(["python3", os.path.join(ROOT, "tests", "bin2hex.py"), binf, hexf])
    return elf, hexf

def run(vtb_path, hexf, *args, maxcyc=50_000_000, use_roi=True):
    p = subprocess.run([vtb_path, f"+hex={hexf}", "+perf=1", f"+maxcyc={maxcyc}", *args],
                       capture_output=True, text=True)
    out = p.stdout
    if "TB: PASS" not in out:
        raise RuntimeError("run failed: " + out[-300:])
    def grab(tag):
        m = re.search(r"^" + tag + r" (.*)$", out, re.M)
        if not m:
            return None
        d = {k: int(v) for k, v in (kv.split("=") for kv in m.group(1).split())}
        assert d["check"] == 1, "CPI stack does not sum to cycles"
        return d
    whole = grab("PERF")
    roi = grab("PERFROI")
    return (roi if (roi and use_roi) else whole), out
