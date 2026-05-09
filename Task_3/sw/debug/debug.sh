#!/bin/bash

set -e

# Detect path to Ibex-simulation-env root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IBEX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"


# Verify the existence directory
if [[ ! -d "$IBEX_ROOT/sw" ]]; then
    echo "Error: Could not find Ibex-simulation-env root directory"
    exit 1
fi

ELF=$1
if [[ -z "$ELF" ]]; then
    echo "Usage: $0 <ELF_FILE> [CYCLES]"
    exit 1
fi
if [[ ! -f "$ELF" ]]; then
    echo "Error: ELF file '$ELF' not found"
    exit 1
fi

SIM="$IBEX_ROOT/build/marno_soc_main_0/sim-verilator/Vtop_verilator"
CYCLES=${2:-10000000}
ELF_FILENAME=$(basename "$ELF")
ELF_BASENAME="${ELF_FILENAME%.elf}"
ELF_DIR=$(dirname "$ELF")

pkill -f Vtop_verilator 2>/dev/null || true
pkill -f openocd 2>/dev/null || true
pkill -f tmux 2>/dev/null || true
sleep 0.3

echo "[1/4] Building the ELF.."
cmake --build $IBEX_ROOT/sw/build --target $ELF_BASENAME
echo "[2/4] Starting simulation..."
$SIM -E $ELF -c $CYCLES +firmware=$ELF_DIR/image/firmware.hex --trace=$IBEX_ROOT/sim.fst > sim.log 2>&1 &
echo "[3/4] Waiting for JTAG socket..."
sleep 3
echo "[4/4] Starting OpenOCD..."
openocd -f $IBEX_ROOT/openocd.cfg > openocd.log 2>&1 &
sleep 3
echo "ready!"

tmux new-session -d -s debug \; \
    send-keys "tail -f sim.log" Enter \; \
    split-window -v \; \
    send-keys "tail -f openocd.log" Enter \; \
    split-window -h \; \
    send-keys "riscv32-unknown-elf-gdb $ELF -ex 'target extended-remote :3333'" Enter \; \
    attach-session -t debug