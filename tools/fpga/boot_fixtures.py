"""Convert existing CPU trace evidence into bounded, strict replay fixtures."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
for name in ("pink", "pdc100"):
    source = ROOT / "build/rea-pdc" / f"{name}.jsonl"
    if not source.exists():
        prefix = ROOT / "build/rtl/traces" / name
        prefix.parent.mkdir(parents=True, exist_ok=True)
        source = prefix.with_suffix(".jsonl")
        if not source.exists():
            subprocess.run(["make", "trace"], cwd=ROOT, check=True)
            rom = "pdc_pink.u2" if name == "pink" else "pdc100.bin"
            subprocess.run([str(ROOT / "build/pdc-trace"), rom, "1", str(prefix)], cwd=ROOT, check=True)
    target = ROOT / "build/rtl" / f"{name}-boot.txt"
    target.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with source.open() as stream, target.open("w") as output:
        for line in stream:
            item = json.loads(line)
            if count == 4096:
                break
            if item["step"] != count:
                raise ValueError("Boot trace is not contiguous")
            before, after = item["before"], item["after"]
            def modes(state):
                return sum(state[key] << bit for bit, key in enumerate(
                    ("irq", "fiq", "irq_enable", "fiq_enable", "fir_move")))
            values = [item["opcode"], item["cycles"], item["kind"] == "interrupt",
                      before["irq_signals"], before["fiq_signal"], *before["regs"],
                      *before["shift"], modes(before), *after["regs"], *after["shift"],
                      modes(after), len(item["bus"])]
            for kind, bank, address, value in item["bus"]:
                values.extend((kind == "w", address & 0x3fffff, value))
            output.write(" ".join(str(int(value)) for value in values) + "\n")
            count += 1
    if count != 4096:
        raise ValueError("Insufficient boot trace")
