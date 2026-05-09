cmake_minimum_required(VERSION 3.28)
project(vtx_bootloader)
enable_language(ASM)

set(CMAKE_EXECUTABLE_SUFFIX ".elf")
set(CYCLES "${2\:-10000000}")

# Set the build type to Debug by default
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

add_executable(bootloader)
target_sources(bootloader PRIVATE
    bootloader.c
    boot.S
)
 target_compile_options(bootloader PRIVATE
      $<$<CONFIG:Debug>:-g -O0 -DDEBUG>
      -march=rv32imc
      -mabi=ilp32
      -static
      -mcmodel=medany
      -Wall
      -fvisibility=hidden
      -ffreestanding
  )
target_link_options(bootloader PRIVATE -T${CMAKE_CURRENT_SOURCE_DIR}/link.ld -mcmodel=medany -nostdlib -nostartfiles)

# GDB debugging target
if(MY_RISCV_GDB)
    add_custom_target(gdb_bootloader
        COMMAND ${MY_RISCV_GDB} $<TARGET_FILE:bootloader> -ex "target extended-remote :3333" 
        DEPENDS bootloader
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        COMMENT "Starting GDB debugger with bootloader.elf"
    )
else()
    message(STATUS "GDB not found - debug target unavailable")
endif()

add_subdirectory(image)