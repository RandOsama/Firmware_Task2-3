set(MY_TARGET_NAME uart)

add_executable(${MY_TARGET_NAME})

target_sources(${MY_TARGET_NAME} PRIVATE
    boot.S
    uart.c
)

target_compile_options(${MY_TARGET_NAME} PRIVATE $<$<CONFIG:Debug>:-g -O0 -DDEBUG>)
target_compile_options(${MY_TARGET_NAME} PRIVATE -march=rv32imc -mabi=ilp32 -static -mcmodel=medany -Wall -fvisibility=hidden -ffreestanding)
target_link_options(${MY_TARGET_NAME} PRIVATE -T${CMAKE_CURRENT_SOURCE_DIR}/link.ld -nostdlib -nostartfiles)

# post build command to convert the firmware to binary format using objcopy
add_custom_command(TARGET ${MY_TARGET_NAME} POST_BUILD
    COMMAND ${MY_RISCV_OBJCOPY}
    -O binary
    $<TARGET_FILE:${MY_TARGET_NAME}>
    $<TARGET_FILE_DIR:${MY_TARGET_NAME}>/${MY_TARGET_NAME}.bin
)

add_custom_command(TARGET ${MY_TARGET_NAME} POST_BUILD
    COMMAND python3 
    ${CMAKE_CURRENT_SOURCE_DIR}/mkflash.py
    $<TARGET_FILE_DIR:${MY_TARGET_NAME}>/${MY_TARGET_NAME}.bin
    $<TARGET_FILE_DIR:${MY_TARGET_NAME}>/firmware.hex
)



