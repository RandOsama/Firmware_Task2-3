OUTPUT_ARCH(riscv)


MEMORY
{
    /* 60 KiB should be enough for anybody... */
    ram         : ORIGIN = 0x00110000, LENGTH = 0xF000 /* 60 KiB */
    stack       : ORIGIN = 0x0011F000, LENGTH = 0x01000  /* 4 KiB */
}


_stack_start   = ORIGIN(stack) + LENGTH(stack);


  SECTIONS
  {
      .text : {
      _start = .;
      . = ALIGN(4);
      *(.text)
      *(.text.*)
      . = ALIGN(4);
      } > ram

      .rodata : {
        . = ALIGN(4);
        /* Small RO data before large RO data */
        *(.srodata)
        *(.srodata.*)
        *(.rodata);
        *(.rodata.*)
        . = ALIGN(4);
    } > ram


    .data : {
        . = ALIGN(4);
        /* Small data before large data */
        *(.sdata)
        *(.sdata.*)
        *(.data);
        *(.data.*)
        . = ALIGN(4);
    } > ram

    .bss :
    {
        . = ALIGN(4);
        _bss_start = .;
        /* Small BSS before large BSS */
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _bss_end = .;
        . = ALIGN(4);
    } > ram
  }

ENTRY(_start)
     