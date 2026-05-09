#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART0_BASE_ADDR 0x80000000u

#define UART_CTRL_OFFSET       0x10u
#define UART_STATUS_OFFSET     0x14u
#define UART_WDATA_OFFSET      0x1Cu
#define UART_FIFO_CTRL_OFFSET  0x20u

// STATUS register
#define UART_STATUS_TXFULL  (1u << 0)   // bit 0: TX FIFO full

// CTRL register
#define UART_CTRL_TX_EN      (1u << 0)  // bit 0: enable TX
#define UART_CTRL_RX_EN      (1u << 1)  // bit 1: enable RX
#define UART_CTRL_NCO_SHIFT  16u        // bits [31:16] = NCO

// FIFO_CTRL register
#define UART_FIFO_CTRL_RXRST  (1u << 0)
#define UART_FIFO_CTRL_TXRST  (1u << 1)

// to get a pointer to a UART register as a volatile uint32_t pointer.
#define UART_REG(offset) \
    (*((volatile uint32_t *)(UART0_BASE_ADDR + (offset))))

static inline void uart_init(void)
{
    /*
        assuming a clock frequency of 24 MHz and a desired baud rate of 115200:

        NCO = (baud_rate * 2^20) / clk_hz
        NCO = (115200 * 1048576) / 24000000
        NCO = 5033
    */
    uint32_t nco = 0x4B7Fu;

    // Reset TX and RX FIFOs.
    // OpenTitan docs say writing 1 to TXRST/RXRST resets the FIFOs, and reads return 0.
    UART_REG(UART_FIFO_CTRL_OFFSET) =
        UART_FIFO_CTRL_RXRST |
        UART_FIFO_CTRL_TXRST;
 
    // Enable TX and RX and set NCO value in CTRL register.
    UART_REG(UART_CTRL_OFFSET) =
        UART_CTRL_TX_EN |
        UART_CTRL_RX_EN |
        (nco << UART_CTRL_NCO_SHIFT);
}

static inline void uart_send_byte(char c)
{
    
    // Poll until TX FIFO is not full.
    while ((UART_REG(UART_STATUS_OFFSET) & UART_STATUS_TXFULL)) {}

    // Write the byte to WDATA register to send it.
    UART_REG(UART_WDATA_OFFSET) = (uint32_t)c;
}

static inline void uart_send_string(const char *s)
{
    while (*s != '\0') {
        if (*s == '\n') {
            /*
                Convert newline to CRLF for UART terminals.
                CRLF: \r = carriage return with \n = line feed.
            */
            uart_send_byte('\r');
        }

        uart_send_byte(*s);
        s++;
    }
}

#endif