# 🚀 Firmware Development Environment: MySoC

Welcome to the team! This repository contains the **MySoC** hardware
environment. You will be writing C code that runs on a simulated RISC-V
processor.

Instead of using a physical FPGA or chip, we use a **Verilator
Simulation Model**. This is a high-performance binary that acts like the
real hardware, allowing you to test your firmware and see exactly what
the CPU is doing without needing physical hardware on your desk.

------------------------------------------------------------------------

## 📂 Project Structure

-   **`sw/`**: Your workspace. Contains `hello_world.c`, `boot.S`
    (startup code), `link.ld` (memory map), and `build.sh`.
-   **`build/`**: Contains the pre-compiled hardware model (the
    "Simulated SoC").
-   **`hello_world.elf`**: The compiled RISC-V binary (generated after
    building).

------------------------------------------------------------------------

## 🛠 Prerequisites

You need the RISC-V GCC toolchain to compile your code. You can install
it via your package manager:

``` bash
# Example for Ubuntu/Debian
sudo apt install gcc-riscv32-unknown-elf
```

------------------------------------------------------------------------

## ⚡ Quick Start: Running your first program

### 1. Build the Software

Navigate to the root directory and run the build script. This will
compile your C code and assembly boot code into a RISC-V ELF file.

``` bash
chmod +x sw/build.sh
./sw/build.sh
```

------------------------------------------------------------------------

### 2. Run the Simulation

Execute the hardware model and pass your compiled `.elf` file to it
using the following command. The `-t` flag enables tracing, and `-E`
specifies the ELF file to load.

``` bash
./build/marno_soc_main_0/sim-verilator/Vtop_verilator -t -E hello_world.elf
```

------------------------------------------------------------------------

## 🔍 Debugging & Logs

Once the simulation runs, it will generate several files in your current
directory. These are your primary debugging tools:

  -----------------------------------------------------------------------------------
  File                    Type       Purpose
  ----------------------- ---------- ------------------------------------------------
  `uart0.log`             Output     Your serial console. If your code prints "Hello
                                     World", it will appear here.

  `trace_core_00000000`   Trace      Instruction-level debugger showing every
                                     executed instruction and register changes.

  `sim.fst`               Waveform   Contains wire-level signals. Open with GTKWave
                                     for timing/hardware debugging.
  -----------------------------------------------------------------------------------

------------------------------------------------------------------------



