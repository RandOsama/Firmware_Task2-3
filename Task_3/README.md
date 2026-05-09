# Ibex RISC-V SoC Simulation Environment

A complete System-on-Chip (SoC) built around the lowRISC Ibex RISC-V processor with UART and SPI peripherals, designed for Verilator simulation and firmware development.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [SoC Architecture](#soc-architecture)
- [SoC Module Implementation (soc_mod.sv)](#soc-module-implementation-soc_modsv)
- [Firmware Development](#firmware-development)
- [Building and Simulation](#building-and-simulation)
- [Address Map](#address-map)
- [Documentation](#documentation)
- [Bootloader](#bootloader)
- [Run](#run)

---

## Overview

This project provides a minimal but complete SoC platform for embedded software development and hardware verification. The design integrates:

- **Ibex RISC-V Core** (RV32IMC) - lowRISC's production-quality 32-bit RISC-V processor
- **TileLink-UL Interconnect** - Industry-standard on-chip bus with automatic generation via OpenTitan xbar tool
- **UART Peripheral** - OpenTitan UART for serial communication (921600 baud)
- **SPI Host Controller** - OpenTitan SPI master supporting Standard/Dual/Quad modes
- **Dual-Port SRAM** - 128 KiB internal memory with separate instruction and data ports
- **Verilator Testbench** - Fast cycle-accurate simulation with waveform tracing (FST format)
- **Flash Simulation** - Behavioral SPI NOR flash model for boot and storage testing

**Key Features:**
- Complete toolchain integration (FuseSoC build system)
- Firmware examples in C with custom linker scripts
- Comprehensive documentation of implementation details
- Performance counter integration for profiling
- DPI-based UART logging to `uart0.log`

---

## Repository Structure

```
firmware/
├── rtl/                          # RTL source files
│   ├── soc_mod.sv               # Top-level SoC module (Ibex + peripherals + interconnect)
│   └── autogen/                 # Auto-generated crossbar files
│       ├── tl_main_pkg.sv       # Address map package
│       ├── xbar_main.sv         # TileLink crossbar RTL
│       └── xbar_main.core       # FuseSoC core definition
│
├── dv/                          # Design verification / testbench
│   ├── top_verilator.sv         # Verilator testbench top-level
│   ├── top_verilator.cc         # C++ testbench driver
│   └── spiflash.v               # Behavioral SPI flash model
│
├── sw/                          # Firmware and software
│   ├── boot.S                   # Assembly boot code (reset handler, BSS init)
│   ├── link.ld                  # Linker script (memory layout)
│   ├── spi_test.c               # SPI controller test firmware
│   ├── simulate_flash.c         # Flash simulation test
│   ├── build.sh                 # Firmware build script
│   └── device/                  # OpenTitan device library (optional, vendored)
│
├── util/                        # Utility scripts
│   ├── xbar_main.hjson          # Crossbar configuration (human-editable)
│   └── vendor.py                # Dependency vendoring script
│
├── vendor/                      # Third-party IP (lowRISC Ibex, OpenTitan IP)
│   ├── lowrisc_ibex/            # Ibex CPU core + tracer
│   │   └── rtl/                 # Ibex RTL source
│   └── lowrisc_ip/              # OpenTitan IP library
│       ├── ip/uart/             # UART peripheral
│       ├── ip/spi_host/         # SPI host controller
│       └── ip/xbar/             # Crossbar generator
│
├── docs/                        # Documentation
│   ├── implementation/          # Implementation guides
│   │   └── flash_simulation_walkthrough.md
│   ├── audit/                   # Design reviews
│   └── errors/                  # Error analysis
│
├── build/                       # Build artifacts (generated)
│   └── marno_soc_main_0/
│       └── sim-verilator/       # Verilator build output
│
├── soc.core                     # FuseSoC core file (build configuration)
├── python-requirements.txt      # Python dependencies for build tools
└── README.md                    # This file
```

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `rtl/` | All SystemVerilog RTL, including SoC top and auto-generated interconnect |
| `dv/` | Simulation testbench and behavioral models |
| `sw/` | Firmware source code, linker scripts, build scripts |
| `vendor/` | Third-party IP cores (Ibex CPU, OpenTitan peripherals) |
| `util/` | Build scripts and configuration generators |
| `docs/` | Design documentation and implementation walkthroughs |
| `build/` | Generated build artifacts (not tracked in git) |

---

## SoC Architecture

### Block Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                         soc_mod.sv                                 │
│                                                                    │
│  ┌──────────────────┐                                             │
│  │  ibex_top_tracing│                                             │
│  │   (RV32IMC)      │                                             │
│  │                  │                                             │
│  │  - 10 HPM counters                                             │
│  │  - Fast multiplier                                             │
│  │  - Boot: 0x00100000                                            │
│  └────┬─────────┬───┘                                             │
│       │(instr)  │(data)                                           │
│       │         │                                                 │
│   (direct)   ┌──▼─────────────────────┐                           │
│       │      │  tlul_adapter_host     │  Convert Ibex bus         │
│       │      │                        │  to TileLink-UL           │
│       │      └──┬─────────────────────┘                           │
│       │         │                                                 │
│       │         │ TileLink-UL                                     │
│       │         │                                                 │
│       │    ┌────▼──────────────────────────────────────────┐      │
│       │    │         xbar_main (TileLink Crossbar)         │      │
│       │    │                                               │      │
│       │    │  Address Decode & Route:                      │      │
│       │    │  • 0x00100000 → SRAM (128 KiB)               │      │
│       │    │  • 0x40300000 → SPI Host (4 KiB)             │      │
│       │    │  • 0x80000000 → UART (4 KiB)                 │      │
│       │    └──┬─────────┬──────────┬─────────────────────┘      │
│       │       │         │          │                            │
│       │   ┌───▼──┐  ┌───▼──┐  ┌────▼───┐                       │
│       │   │UART  │  │SPI   │  │tlul_   │                       │
│       │   │      │  │Host  │  │adapter_│                       │
│       │   │      │  │      │  │sram    │                       │
│       │   └───┬──┘  └──┬───┘  └────┬───┘                       │
│       │       │        │           │                            │
│       │    uart_tx  spi_sck    ┌───▼─────────────────┐          │
│       │    uart_rx  spi_csb    │  prim_ram_2p        │          │
│       │             spi_sd[3:0]│  (Dual-port SRAM)   │          │
│       │                        │  - Port A: Data     │          │
│       └────────────────────────┤  - Port B: Instr    │          │
│                                │  - 128 KiB          │          │
│                                └─────────────────────┘          │
└────────────────────────────────────────────────────────────────────┘
              │          │              │
              │          │              │
         ┌────▼───┐  ┌───▼──────────┐   │
         │uartdpi │  │  spiflash.v  │   │
         │(DPI)   │  │              │   │
         └────┬───┘  └──────────────┘   │
              │                         │
         uart0.log                 (waveforms)
```

### Component Summary

| Component | Type | Description | Source |
|-----------|------|-------------|--------|
| **ibex_top_tracing** | CPU | 32-bit RISC-V core (RV32IMC), 2-stage pipeline, fast multiplier | vendor/lowrisc_ibex/ |
| **xbar_main** | Interconnect | TileLink-UL crossbar, auto-generated from xbar_main.hjson | rtl/autogen/ |
| **tlul_adapter_host** | Bus Adapter | Converts Ibex data interface to TileLink-UL | vendor/lowrisc_ip/ip/tlul/ |
| **tlul_adapter_sram** | Bus Adapter | Converts TileLink-UL to SRAM interface | vendor/lowrisc_ip/ip/tlul/ |
| **prim_ram_2p** | Memory | Dual-port synchronous RAM (128 KiB) | vendor/lowrisc_ip/ip/prim/ |
| **uart** | Peripheral | OpenTitan UART with TX/RX FIFOs | vendor/lowrisc_ip/ip/uart/ |
| **spi_host** | Peripheral | OpenTitan SPI master (Standard/Dual/Quad modes) | vendor/lowrisc_ip/ip/spi_host/ |
| **uartdpi** | Testbench | DPI model for UART terminal logging | vendor/lowrisc_ibex/dv/ |
| **spiflash** | Testbench | Behavioral SPI NOR flash model (Verilog) | dv/spiflash.v |

---

## SoC Module Implementation (soc_mod.sv)

The [`soc_mod.sv`](rtl/soc_mod.sv) file is the top-level RTL module that integrates all SoC components. This section details its implementation.

### Module Interface

```systemverilog
module soc_mod #(
  parameter SramInitFile = ""
) (
  // Clock and reset
  input  logic clk_i,
  input  logic rst_ni,

  // UART interface
  input  logic uart_rx_i,
  output logic uart_tx_o,

  // SPI interface (Quad SPI signals)
  output logic       spi_sck_o,      // SPI clock
  output logic       spi_sck_en_o,   // SPI clock output enable
  output logic       spi_csb_o,      // Chip select (active low)
  output logic       spi_csb_en_o,   // Chip select output enable
  output logic [3:0] spi_sd_o,       // SPI data output [SD0-SD3]
  output logic [3:0] spi_sd_en_o,    // SPI data output enables
  input  logic [3:0] spi_sd_i        // SPI data input [SD0-SD3]
);
```

**Parameters:**
- `SramInitFile`: Path to memory initialization file (`.vmem` format) for pre-loading firmware

**Ports:**
- **Clock/Reset**: Standard synchronous design (active-low reset)
- **UART**: Simple RX/TX signals (DPI wrapper handles baud timing)
- **SPI**: Full quad-SPI support with per-signal output enables for tristate control

### Implementation Details

#### 1. Memory Configuration

```systemverilog
localparam int unsigned MemSize       = 128 * 1024; // 128 KiB
localparam int unsigned DataWidth     = 32;
localparam int unsigned AddrOffset    = $clog2(DataWidth / 8);  // = 2
localparam int unsigned SramAddrWidth = $clog2(MemSize) - AddrOffset;
```

- **Memory Size**: 128 KiB (configurable, but matches linker script)
- **Data Width**: 32-bit (matches Ibex and TileLink-UL data width)
- **Address Offset**: 2 bits (word-aligned addresses, byte offset bits excluded from SRAM)
- **SRAM Address Width**: `log2(128K) - 2 = 15 bits` (word addresses)

#### 2. Ibex CPU Instantiation

```systemverilog
ibex_top_tracing #(
  .MHPMCounterNum  ( 10                  ),  // 10 performance counters
  .RV32M           ( ibex_pkg::RV32MFast ),  // Fast multiplier
  .RV32B           ( ibex_pkg::RV32BNone ),  // No bit-manipulation
  .DbgTriggerEn    ( 1'b0                ),  // No debug triggers
  .DbgHwBreakNum   ( 0                   )   // No hardware breakpoints
) u_ibex_top_tracing (
  .clk_i,
  .rst_ni,
  .boot_addr_i (32'h00100000),  // Boot from SRAM base
  // ... instruction and data bus connections ...
);
```

**Key Configuration:**
- **Performance Counters**: 10 HPM counters enabled for profiling
- **Boot Address**: `0x00100000` (SRAM base, actual reset vector at +0x80)
- **Multiplier**: Fast single-cycle multiply (RV32MFast)
- **No Debug**: Debug features disabled for simplicity

**Bus Connections:**
- **Instruction Bus**: Direct connection to SRAM port B (read-only)
- **Data Bus**: Goes through TileLink adapter → crossbar → devices

#### 3. TileLink Crossbar (xbar_main)

```systemverilog
xbar_main xbar (
  .clk_i,
  .rst_ni,
  
  // Host (master) interface
  .tl_ibex_lsu_i (tl_ibex_lsu_h2d),
  .tl_ibex_lsu_o (tl_ibex_lsu_d2h),

  // Device (slave) interfaces
  .tl_sram_o      (tl_sram_h2d),
  .tl_sram_i      (tl_sram_d2h),
  .tl_uart_o      (tl_uart_h2d),
  .tl_uart_i      (tl_uart_d2h),
  .tl_spi_host_o  (tl_spi_host_h2d),
  .tl_spi_host_i  (tl_spi_host_d2h),
  
  .scanmode_i (prim_mubi_pkg::MuBi4False)
);
```

The crossbar is **auto-generated** from [`util/xbar_main.hjson`](util/xbar_main.hjson) using the OpenTitan tlgen tool. It performs:
- **Address Decoding**: Routes transactions based on address ranges
- **Protocol Conversion**: None (TileLink-UL throughout)
- **Error Handling**: Returns bus error for unmapped addresses

#### 4. TileLink Adapters

**Host Adapter (Ibex Data Bus → TileLink-UL):**
```systemverilog
tlul_adapter_host #(
  .EnableCmdIntgGen  (1),  // Generate command integrity bits
  .EnableDataIntgGen (1)   // Generate data integrity bits
) ibex_lsu_host_adapter (
  .req_i        (ibex_req),
  .addr_i       (ibex_addr),
  .we_i         (ibex_we),
  .wdata_i      (ibex_wdata),
  .be_i         (ibex_be),
  .tl_o         (tl_ibex_lsu_h2d),
  .tl_i         (tl_ibex_lsu_d2h),
  // ...
);
```

**Device Adapter (TileLink-UL → SRAM Interface):**
```systemverilog
tlul_adapter_sram #(
  .SramAw           ( SramAddrWidth - AddrOffset ),
  .EnableRspIntgGen ( 0 )
) sram_a_device_adapter (
  .tl_i        (tl_sram_h2d),
  .tl_o        (tl_sram_d2h),
  .req_o       (sram_data_req),
  .we_o        (sram_data_we),
  .addr_o      (sram_data_addr),
  // ...
);
```

#### 5. Dual-Port SRAM

```systemverilog
prim_ram_2p #(
  .Width           ( 32 ),
  .DataBitsPerMask ( 8 ),
  .Depth           ( 2 ** (SramAddrWidth - AddrOffset) ),
  .MemInitFile     ( SramInitFile )
) u_ram (
  .clk_a_i (clk_i),
  .clk_b_i (clk_i),
  
  // Port A: Data bus (read/write)
  .a_req_i   (sram_data_req),
  .a_write_i (sram_data_we),
  .a_addr_i  (sram_data_addr),
  .a_wdata_i (sram_data_wdata),
  .a_wmask_i (sram_data_wmask),
  .a_rdata_o (sram_data_rdata),

  // Port B: Instruction bus (read-only)
  .b_req_i   (sram_instr_req),
  .b_write_i (1'b0),
  .b_addr_i  (sram_instr_addr[SramAddrWidth-1+AddrOffset:AddrOffset]),
  .b_rdata_o (sram_instr_rdata),
  // ...
);
```

**Features:**
- **Byte-addressable**: 4 bytes per word, byte-write enable via `wmask`
- **Single-cycle latency**: `rvalid` asserted 1 cycle after `req`
- **Initialization**: Supports pre-loading via `.vmem` file

#### 6. UART Peripheral

```systemverilog
uart u_uart (
  .clk_i,
  .rst_ni,
  
  .cio_rx_i    (uart_rx_i),
  .cio_tx_o    (uart_tx_o),
  
  .tl_i (tl_uart_h2d),   // TileLink slave interface
  .tl_o (tl_uart_d2h),
  
  // Interrupts (unused, tied off)
  .intr_tx_watermark_o  ( ),
  .intr_rx_overflow_o   ( ),
  // ... 7 more interrupt outputs ...
);
```

**Configuration:**
- **Baud Rate**: Configurable via CTRL register (firmware sets 921600 baud)
- **FIFOs**: 32-byte TX/RX FIFOs (watermark interrupts available)
- **Register Interface**: TileLink-UL mapped at `0x80000000`

#### 7. SPI Host Peripheral

```systemverilog
spi_host spi_host(
  .clk_i,
  .rst_ni,
  
  .tl_i (tl_spi_host_h2d),
  .tl_o (tl_spi_host_d2h),
  
  // SPI physical interface
  .cio_sck_o    (spi_sck_o),
  .cio_sck_en_o (spi_sck_en_o),
  .cio_csb_o    (spi_csb_o),
  .cio_csb_en_o (spi_csb_en_o),
  .cio_sd_o     (spi_sd_o),      // SD[3:0] outputs
  .cio_sd_en_o  (spi_sd_en_o),   // SD[3:0] output enables
  .cio_sd_i     (spi_sd_i),      // SD[3:0] inputs
  
  // Alerts and passthrough (unused)
  .alert_rx_i (prim_alert_pkg::ALERT_RX_DEFAULT),
  .intr_error_o     ( ),
  .intr_spi_event_o ( ),
  // ...
);
```

**Features:**
- **Modes**: Standard SPI, Dual SPI, Quad SPI
- **Clock Divider**: Programmable SPI clock (derived from system clock)
- **CS Timing**: Configurable setup/hold/idle times
- **FIFOs**: Separate TX/RX FIFOs with watermark control
- **Command-based**: Each SPI transaction initiated via COMMAND register

**SPI Signal Mapping (Quad Mode):**
- `SD0` = MOSI (Master Out Slave In) in standard mode
- `SD1` = MISO (Master In Slave Out) in standard mode
- `SD[3:0]` = 4-bit bus in quad mode (bidirectional)

### Design Rationale

1. **Dual-Port SRAM**: Instruction and data buses are separated for simultaneous access, improving performance and simplifying the Ibex integration.

2. **TileLink-UL**: Industry-standard on-chip bus protocol with strong typing, automatic response generation, and error handling.

3. **Auto-Generated Crossbar**: Using the OpenTitan xbar generator ensures correct address decoding and reduces manual RTL errors. Changes to the address map only require editing the `.hjson` file.

4. **Integrity Checking**: TileLink adapters generate/check integrity bits for fault detection (though not strictly necessary in simulation).

5. **Output Enables**: SPI signals have separate output enables to support bidirectional I/O without Verilog `inout` (Verilator compatibility).

### Key Modifications

All modifications to vendored IP are marked with comments:
```systemverilog
// Added by Deyaa Al-khatib 17th of Feb 11PM
output logic [3:0] spi_sd_o,
output logic [3:0] spi_sd_en_o,
input  logic [3:0] spi_sd_i
// End of the addition
```

**Major additions:**
- SPI host peripheral integration (TileLink connection, physical I/O)
- Quad SPI signal routing (4-bit data bus instead of 2-wire)
- Crossbar update for SPI host address range (`0x40300000`)

---

## Firmware Development

### Overview

Firmware is written in C with a minimal runtime (no OS, bare-metal). The build process uses the RISC-V GCC toolchain to produce ELF binaries, which are converted to `.vmem` format for simulation.

### Firmware Structure

| File | Purpose |
|------|---------|
| [`sw/boot.S`](sw/boot.S) | Assembly startup code: reset vector, register init, BSS clearing |
| [`sw/link.ld`](sw/link.ld) | Linker script: defines memory layout and section placement |
| [`sw/spi_test.c`](sw/spi_test.c) | SPI controller test (basic read/write) |
| [`sw/simulate_flash.c`](sw/simulate_flash.c) | Flash simulation test (power-up sequence) |
| [`sw/CMakeLists.txt`](sw/CMakeLists.txt) | CMake File: compile → link → objcopy → elf2vmem |

### Memory Map (Linker Perspective)

From [`sw/link.ld`](sw/link.ld):

```ld
MEMORY
{
  ram (rwx) : ORIGIN = 0x00100000, LENGTH = 128K
}

SECTIONS
{
  . = 0x00100000;
  
  .vectors : { . = 0x80; KEEP(*(.vectors)); } > ram
  .text    : { *(.text*) } > ram
  .rodata  : { *(.rodata*) } > ram
  .data    : { *(.data*) } > ram
  .bss     : { *(.bss*) } > ram
  
  _stack_start = ORIGIN(ram) + LENGTH(ram);  /* 0x00120000 */
}
```

**Key Points:**
- All sections in SRAM (no flash/ROM in this design)
- Reset vector at `0x00100080` (`.vectors` section)
- Stack grows downward from top of SRAM
- No `.init` or `.fini` sections (minimal runtime)

### Boot Sequence

1. **Hardware Reset**: Ibex fetches from `0x00100080` (hardcoded in `soc_mod.sv`)
2. **Reset Handler** ([`boot.S`](sw/boot.S)):
   - Initialize all registers to zero
   - Set stack pointer to `_stack_start`
   - Clear `.bss` section (zero-initialized data)
   - Call `main()`
3. **Application Code**: `simulate_flash.c` or other firmware


### Register Access Macros

```c
#define DEV_WRITE(addr, val) (*((volatile uint32_t *)(addr)) = val)
#define DEV_READ(addr)       (*((volatile uint32_t *)(addr)))

// Usage:
DEV_WRITE(UART_BASE + UART_TX_REG, 'A');
uint32_t status = DEV_READ(SPI_HOST_BASE + SPI_HOST_STATUS);
```

### Debugging Tips

- **UART Output**: Check `build/marno_soc_main_0/sim-verilator/uart0.log`
- **Waveforms**: Open `sim.fst` in GTKWave
- **Objdump**: `riscv32-unknown-elf-objdump -d hello_world.elf` for disassembly
- **Memory Dump**: Check `.vmem` file for instruction encoding
- **PC Tracing**: Enable Ibex tracer for instruction-by-instruction log

---

## Building and Simulation

### Prerequisites

**System Packages:**
- Verilator 4.2+ (simulation engine)
- Python 3.7+ with `hjson`, `mako`, `pyyaml`
- RISC-V GCC toolchain
- CMake

**Python Packages:**
```bash
pip3 install -r python-requirements.txt
```



### Build Process


1. **Build Firmware**:
   ```CMake
   cd sw/
   cmake -S . --toolchain toolchain.cmake -B build -DRISCV_TOOLCHAIN_PATH=/opt/riscv -DCMAKE_BUILD_TYPE=Release
   cmake --build build
   ```

2. **Build Simulation**:
   ```bash
   fusesoc --cores-root=. run --target=sim --setup --build marno:soc:main
   ```
   This generates Verilator C++ from RTL and compiles the executable.

3. **Run Simulation**:
   ```bash
   ./build/marno_soc_main_0/sim-verilator/Vtop_verilator -E your_elf.elf -c 10000000(optional)
   
   ```

**Command-line Options:**
- `--meminit=ram,<file>`: Pre-load SRAM with firmware image
- `--trace-fst`: Enable FST waveform tracing
- `--trace-start <cycle>`: Start tracing at specific cycle (0 = from beginning)

### Output Files

- **Waveform**: `sim.fst` (open with GTKWave)
- **UART Log**: `build/marno_soc_main_0/sim-verilator/uart0.log`
- **Performance**: `performance_counters.csv` (if enabled in firmware)
- **Console**: Simulation termination message and cycle count

### Example Simulation Run

```bash
$ ./build/marno_soc_main_0/sim-verilator/Vtop_verilator \
    --meminit=ram,sw/simulate_spi.vmem --trace-fst

Hello from SPI flash firmware!
Initializing UART...
UART initialized at 921600 baud
Initializing SPI host...
SPI host initialized
Powering up SPI flash...
Flash powered up
Reading 4 bytes from flash address 0x00000000...
Read: 0xDEADBEEF
Simulation finished at cycle 125834
```

### Waveform Analysis

Open `sim.fst` in GTKWave:
```bash
gtkwave sim.fst
```

**Useful Signal Groups:**
- `top_verilator.u_soc.u_ibex_top_tracing`: CPU state (PC, registers, pipeline)
- `top_verilator.u_soc.xbar`: TileLink transactions
- `top_verilator.u_soc.u_uart`: UART TX/RX
- `top_verilator.u_soc.spi_host`: SPI bus signals
- `top_verilator.flash`: SPI flash model internals

---

## Address Map

The SoC address map is defined in [`util/xbar_main.hjson`](util/xbar_main.hjson) and auto-generated into [`rtl/autogen/tl_main_pkg.sv`](rtl/autogen/tl_main_pkg.sv).

### Memory-Mapped Regions

| Peripheral | Base Address | Size | Address Range | Description |
|------------|--------------|------|---------------|-------------|
| **SRAM** | `0x00100000` | 128 KiB | `0x00100000` - `0x0011FFFF` | Dual-port RAM (instruction + data) |
| **SPI Host** | `0x40300000` | 4 KiB | `0x40300000` - `0x40300FFF` | SPI master controller registers |
| **UART** | `0x80000000` | 4 KiB | `0x80000000` - `0x80000FFF` | UART registers |

### SRAM Layout (Firmware Perspective)

| Section | Address Range | Size | Purpose |
|---------|---------------|------|---------|
| Reset Vector | `0x00100080` | 4 bytes | Jump to `reset_handler` |
| `.text` | `0x00100084+` | Variable | Program code |
| `.rodata` | After `.text` | Variable | Const data (e.g., strings) |
| `.data` | After `.rodata` | Variable | Initialized global variables |
| `.bss` | After `.data` | Variable | Zero-initialized globals |
| Stack | `0x0011FFFF` ↓ | Variable | Grows downward from top of SRAM |

### Peripheral Address Offsets

**UART Registers** (base `0x80000000`):
| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | INTR_STATE | RW1C | Interrupt status |
| `0x04` | INTR_ENABLE | RW | Interrupt enable |
| `0x10` | CTRL | RW | Control (enable, baud config) |
| `0x14` | STATUS | RO | Status (TXFULL, RXEMPTY, etc.) |
| `0x18` | RDATA | RO | RX data (read pops FIFO) |
| `0x1C` | WDATA | WO | TX data (write pushes FIFO) |

**SPI Host Registers** (base `0x40300000`):
| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x10` | CONTROL | RW | Enable, reset, FIFO watermarks |
| `0x14` | STATUS | RO | Ready, active, FIFO status |
| `0x18` | CONFIGOPTS[0] | RW | Clock divider, CS timing, mode |
| `0x1C` | CSID | RW | Chip select ID (0 for single device) |
| `0x20` | COMMAND | WO | Issue transaction (direction, length) |
| `0x24` | RXDATA | RO | RX FIFO read |
| `0x28` | TXDATA | WO | TX FIFO write |

See vendor IP documentation for full register definitions:
- UART: `vendor/lowrisc_ip/ip/uart/doc/`
- SPI Host: `vendor/lowrisc_ip/ip/spi_host/doc/`

---

## Documentation

### Implementation Guides
- ***Run Documentation***
```
pip install -r python-requirements.txt
mkdocs serve
```

### Design Files

- **[xbar_main.hjson](util/xbar_main.hjson)**: Crossbar configuration (human-editable)
- **[soc.core](soc.core)**: FuseSoC build configuration
- **[link.ld](sw/link.ld)**: Firmware linker script

### Useful Resources

**lowRISC Ibex:**
- [Ibex User Manual](https://ibex-core.readthedocs.io/)
- [Ibex GitHub](https://github.com/lowRISC/ibex)

**OpenTitan Peripherals:**
- [OpenTitan Documentation](https://opentitan.org/book/)
- [UART Spec](https://opentitan.org/book/hw/ip/uart/)
- [SPI Host Spec](https://opentitan.org/book/hw/ip/spi_host/)
- [TileLink-UL Spec](https://opentitan.org/book/hw/ip/tlul/)

**Tools:**
- [Verilator Manual](https://verilator.org/guide/latest/)
- [FuseSoC Documentation](https://fusesoc.readthedocs.io/)
- [GTKWave User Guide](http://gtkwave.sourceforge.net/)

---

## Bootloader

The bootloader is implemented in [`sw/simulate_flash.c`](sw/simulate_flash.c). It runs entirely from SRAM, reads application firmware from the external SPI flash, validates it, copies it to a dedicated SRAM region, and jumps to it.

### Quick Start

```bash
cd sw
cmake -S . --toolchain toolchain.cmake -B build -DRISCV_TOOLCHAIN_PATH=/opt/riscv -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cd ..
./build/marno_soc_main_0/sim-verilator/Vtop_verilator -E sw/build/simulate_flash.elf -c 50000 +firmware=sw/build/image/firmware.hex
cat uart0.log
```

Expected output:
```
MAGIC=B007C0DE
MAGIC OK
SIZE=00000004
SIZE OK
CRC=E5AE7AEE
CRC OK
```

---

### Boot Flow

```
Power on
  └─ boot.S: zero registers, set stack, clear BSS, call main()
       └─ uart_init()          — configure UART at 921600 baud
       └─ spi_init()           — reset → configure → enable SPI host
       └─ powerup_flash()      — send 0xAB release-from-powerdown to flash
       └─ flash_read_word(0x00000000) — read magic
       └─ validate magic == 0xB007C0DE
       └─ flash_read_word(0x00000004) — read size
       └─ validate size: non-zero, ≤64KB, multiple of 4
       └─ flash_read_word(0x00000008) — read stored CRC32
       └─ copy loop: flash[0x0C .. 0x0C+size] → SRAM[APP_BASE]
       └─ compute CRC32 over SRAM copy
       └─ compare computed CRC == stored CRC
       └─ disable SPI host
       └─ jump to APP_BASE (0x00110000)
```

---

### Flash Image Format

The flash image must follow this exact header layout:

```
Offset 0x00: [magic   4 bytes] — 0xB007C0DE ("BOOTCODE"), little-endian
Offset 0x04: [size    4 bytes] — byte count of application, little-endian
Offset 0x08: [crc32   4 bytes] — CRC32 of application bytes only, little-endian
Offset 0x0C: [app bytes...]   — raw application binary
```

The `firmware.hex` file is loaded by `spiflash.v` via `$readmemh`. Each line is one byte in hex. Example for a 4-byte application (`0xCAFEBABE`):

```
DE        ← magic byte 0
C0        ← magic byte 1
07        ← magic byte 2
B0        ← magic byte 3
04        ← size byte 0  (4 bytes, little-endian)
00        ← size byte 1
00        ← size byte 2
00        ← size byte 3
EE        ← CRC32 byte 0 (0xE5AE7AEE, little-endian)
7A        ← CRC32 byte 1
AE        ← CRC32 byte 2
E5        ← CRC32 byte 3
BE        ← app byte 0  (0xCAFEBABE, little-endian)
BA        ← app byte 1
FE        ← app byte 2
CA        ← app byte 3
```

---

### Features

#### 1. Magic Number Validation

The first 4 bytes of flash must equal `0xB007C0DE` ("BOOTCODE"). This is a handshake constant agreed upon between the flash programmer and the bootloader. Any other value halts with `ERR: BAD MAGIC`. This prevents the CPU from jumping to random data after a blank or partially-programmed flash.

#### 2. Size Validation

The size field is validated against three conditions:
- Non-zero (empty image)
- Does not exceed `MAX_IMG_SIZE` (64 KB)
- Is a multiple of 4 (the copy loop reads 32-bit words; an unaligned size would silently miss the final bytes)

#### 3. CRC32 Image Integrity

After copying the application to SRAM, the bootloader recomputes CRC32 (IEEE 802.3 polynomial `0xEDB88320`) over the copied bytes and compares it against the value stored in the flash header. A mismatch means the flash data was corrupted either during programming or in storage, and halts with `ERR: BAD CRC`.

The CRC32 lookup table is precomputed at compile time as a `static const uint32_t crc32_table[256]` array — zero runtime cost at boot. The algorithm:

```
crc = 0xFFFFFFFF
for each byte:
    idx = (crc XOR byte) & 0xFF
    crc = (crc >> 8) XOR table[idx]
return crc XOR 0xFFFFFFFF
```

The `0xFFFFFFFF` initialization catches leading-zero corruption. The final XOR catches trailing-zero corruption.

#### 4. SRAM Copy

The application is copied word-by-word from flash to `APP_BASE` (`0x00110000`):

```c
volatile uint32_t *dst = (volatile uint32_t *)APP_BASE;
for (int32_t i = 0; i < size/4; i++)
    dst[i] = flash_read_word(HEADER_SIZE + i*4);
```

`APP_BASE` is placed 64 KB above the bootloader code base (`0x00100000`), safely above the bootloader's own code, stack, and BSS. The bootloader itself occupies only ~1.2 KB of SRAM.

#### 5. Clean Handoff

Before jumping, the SPI host is disabled by writing 0 to the CONTROL register. This ensures the application starts with known peripheral state rather than inheriting a partially-configured SPI transaction.

#### 6. Jump to Application

The jump is a C function pointer call:

```c
void (*app_entry)(void) = (void (*)(void))APP_BASE;
app_entry();
```

The CPU transfers control to `APP_BASE`. The application is responsible for reinitializing any peripherals it needs.

---

### Flash Model (`dv/spiflash.v`)

The behavioral SPI flash model simulates a Quad SPI NOR flash device in Verilog. It is instantiated in the Verilator testbench (`dv/top_verilator.sv`) and connected to the SoC's SPI signals.

**Key behaviors:**

| Feature | Detail |
|---|---|
| Storage | `$readmemh` loads `firmware.hex` at simulation start |
| Protocol | Standard SPI for command/address, Quad SPI for data |
| Commands | `0xAB` power-up, `0xEB` fast-read quad I/O |
| Addressing | 24-bit (3-byte) address, MSB first |
| Dummy cycles | 8 dummy cycles after address in `0xEB` mode |
| CS behavior | Deasserting CS resets byte counter and bit counter |
| Byte order | First received byte → RXDATA bits [7:0] (ByteOrder=1 in SPI Host) |
| Data width | 4 bits per clock cycle in QSPI read mode |

**`0xEB` Fast-Read Quad I/O transaction sequence:**

```
CS low
  → 1 byte:  opcode 0xEB         (standard SPI, TX)
  → 3 bytes: address MSB first   (quad SPI, TX)
  → 1 byte:  mode byte 0x00      (quad SPI, TX)
  → 8 cycles: dummy              (quad SPI, no data)
  → 4 bytes: data from flash     (quad SPI, RX)
CS high
```

**TXFIFO packing rule (critical):** The SPI Host reads **one 32-bit word** per TX segment regardless of segment length in bytes. For a 4-byte segment, one word is consumed with bytes packed as `[byte0=bits7:0, byte1=bits15:8, byte2=bits23:16, byte3=bits31:24]`. Writing 4 separate `spi_transmit_byte()` calls for a 4-byte segment leaves 3 orphaned words in the TXFIFO that corrupt the next transaction. The address must be packed into one word via a single `DEV_WRITE(SPI_HOST_TXDATA, packed)`.

---

### Future Plan: XIP (Execute In Place)

**What XIP means:** Instead of copying firmware to SRAM first, the CPU would fetch instructions directly from the SPI flash over the SPI bus — executing from flash in place without a staging copy.

**Why XIP is not supported in this design:**

The fundamental constraint is how the Ibex instruction bus is wired in `soc_mod.sv`:

```
Ibex instruction bus → directly → SRAM port B
```

The instruction bus has no path to the SPI host. It is hardwired to the SRAM. The SPI host is a **memory-mapped peripheral** — it responds to *data bus* transactions (register reads and writes). It is not a memory bus master and cannot participate in instruction fetches.

True XIP requires a dedicated **SPI flash memory controller** that:
1. Sits between the CPU instruction bus and the SPI flash
2. Translates instruction fetch addresses to SPI `0xEB` transactions automatically
3. Exposes the flash as a flat read-only address window (e.g., `0x20000000` - `0x2FFFFFFF`)
4. Handles caching/prefetch to hide SPI latency (SPI at 1 MHz is ~8× slower than a 50 MHz SRAM)

In OpenTitan this is handled by the **SPI Device** peripheral in passthrough/flash mode, not the SPI Host. Adding XIP to this SoC would require:
- A new SPI flash controller RTL module connected to the Ibex instruction bus
- A second chip select path to the flash
- An address decoder update to route the XIP region through the controller
- Potential cache or line buffer to make instruction fetch latency acceptable

This is planned as a future phase once the bare-metal driver layer and FPGA port are complete.

---

## run

```
pip -m .venv/bin/activate
pip install -r python-requirements.txt
pip install "setuptools<81"
fusesoc --cores-root=. run --target=sim --tool=verilator --setup --build marno:soc:main
chmod +x build.sh
sw/build
./build/marno_soc_main_0/sim-verilator/Vtop_verilator -E hello_world.elf -c 2000000
cat uart0.log
```

