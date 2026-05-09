.section .text
.global _start
_start:
    la sp, _stack_start
    jal ra, main
    j .
