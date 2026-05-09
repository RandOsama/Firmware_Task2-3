set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR riscv32)


if (EXISTS "/opt/riscv/bin/riscv32-unknown-elf-gcc")
set(RISCV_TOOLCHAIN_PATH "/opt/riscv" CACHE PATH "Path to the RISC-V toolchain")
elseif (EXISTS "/usr/bin/riscv32-unknown-elf-gcc")
set(RISCV_TOOLCHAIN_PATH "/usr" CACHE PATH "Path to the RISC-V toolchain")
endif()

# Check environment variable first
if(NOT EXISTS "${RISCV_TOOLCHAIN_PATH}/bin/riscv32-unknown-elf-gcc")
    #bail out
    message(
    FATAL_ERROR "RISC-V toolchain not found. Please pass the cmake variable RISCV_TOOLCHAIN_PATH  as path of your RISC-V toolchain.\
     Example: cmake -B build -S sw -DRISCV_TOOLCHAIN_PATH=/path/to/riscv/toolchain"
    )
endif()

set(CMAKE_C_COMPILER ${RISCV_TOOLCHAIN_PATH}/bin/riscv32-unknown-elf-gcc)
set(CMAKE_CXX_COMPILER ${RISCV_TOOLCHAIN_PATH}/bin/riscv32-unknown-elf-g++)

#OBJCOPY
find_program(MY_RISCV_OBJCOPY 
    NAMES riscv32-unknown-elf-objcopy
    HINTS ${RISCV_TOOLCHAIN_PATH}/bin
    DOC "objcopy for RISC-V"
    CACHE FILEPATH "objcopy location"
)

if(NOT MY_RISCV_OBJCOPY)
    message(WARNING "OBJCOPY not found.")
endif()

# GDB debugger
find_program(MY_RISCV_GDB 
    NAMES riscv32-unknown-elf-gdb gdb
    HINTS ${RISCV_TOOLCHAIN_PATH}/bin
    DOC "GDB debugger for RISC-V"
    CACHE FILEPATH "GDB debugger location"
)

if(NOT MY_RISCV_GDB)
    message(WARNING "GDB not found. Debug target will not be available.")
endif()