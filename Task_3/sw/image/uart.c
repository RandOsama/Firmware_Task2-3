#include <stdint.h>

#define UART_BASE       0x80000000u
#define UART_CTRL_REG   0x10
#define UART_STATUS_REG 0x14
#define UART_TX_REG     0x1C
#define UART_TX_FULL    (1u << 0)
#define BAUD_RATE       921600
#define SYSCLK_FREQ     50000000

#define UART_WRITE(off, val) (*(volatile uint32_t *)(UART_BASE + (off)) = (val))
#define UART_READ(off)       (*(volatile uint32_t *)(UART_BASE + (off)))

void uart_init(void) {
    uint32_t nco = (uint32_t)(((uint64_t)BAUD_RATE << 20) / SYSCLK_FREQ);
    UART_WRITE(UART_CTRL_REG, (nco << 16) | 0x3u);
}

void uart_putc(char c) {
    while (UART_READ(UART_STATUS_REG) & UART_TX_FULL);
    UART_WRITE(UART_TX_REG, c);
}

void uart_print(const char *s) {
    while (*s) uart_putc(*s++);
}

int main(void) {
    uart_init();
    uart_print("This is a valid image\n");
    while (1);
    return 0;
}
