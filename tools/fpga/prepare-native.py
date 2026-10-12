from pathlib import Path
import shutil
import os

root = Path(__file__).resolve().parents[2]
project = root / "build/fpga/native/fpga"
sources = project / "core/native"
sources.mkdir(parents=True, exist_ok=True)
for path in (*sorted((root / "rtl").glob("*.sv")),
             *sorted((root / "rtl/pocket").glob("*.sv")),
             *sorted((root / "third_party/pocket").glob("*.v")),
             *sorted((root / "third_party/pocket").glob("*.sv"))):
    shutil.copy2(path, sources / path.name)
shutil.copy2(root / "rtl/pocket/core_constraints.sdc", project / "core/core_constraints.sdc")
shutil.copy2(root / "tools/fpga/validate-timing.tcl", project / "validate-timing.tcl")
shutil.copy2(root / "tools/fpga/validate-mapping.tcl", project / "validate-mapping.tcl")
qsf = project / "ap_core.qsf"
lines = [line for line in qsf.read_text().splitlines()
         if line.strip() not in (
             "set_global_assignment -name VERILOG_FILE core/core_top.v",
             "set_global_assignment -name QIP_FILE core/mf_pllbase.qip",
             "set_global_assignment -name SDC_FILE core/core_constraints.sdc")
         and "core/native/" not in line]
for path in sorted(sources.iterdir()):
    language = "SYSTEMVERILOG_FILE" if path.suffix == ".sv" else "VERILOG_FILE"
    lines.append(f"set_global_assignment -name {language} core/native/{path.name}")
lines.extend((
    "set_global_assignment -name MUX_RESTRUCTURE AUTO",
    "set_global_assignment -name FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS",
    'set_global_assignment -name FITTER_EFFORT "Standard Fit"',
    "set_global_assignment -name NUM_PARALLEL_PROCESSORS " +
    ("2" if os.environ.get("PDC_QUARTUS_EMULATOR") == "qemu" else "4"),
    "set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[*]",
    "set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_*",
    "set_instance_assignment -name FAST_INPUT_REGISTER ON -to cram0_dq[*]",
    "set_instance_assignment -name FAST_INPUT_REGISTER ON -to cram1_dq[*]",
    "set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to cram0_*",
    "set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to cram1_*",
    "set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to cram0_dq[*]",
    "set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to cram1_dq[*]",
    "set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to bridge_1wire",
    "set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to bridge_1wire",
))
qsf.write_text("\n".join(lines) + "\n")
