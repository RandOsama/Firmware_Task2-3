riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -static -mcmodel=medany -Wall -g -fvisibility=hidden -ffreestanding -c sw/hello_world.c
riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -static -mcmodel=medany -Wall -g -fvisibility=hidden -ffreestanding -c sw/boot.S
riscv32-unknown-elf-ld --nostdlib -Tsw/link.ld hello_world.o boot.o -o hello_world.elf
