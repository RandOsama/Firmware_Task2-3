#include <stdint.h>


/*
    ============================================================
    UART SECTION
    ============================================================
*/

#define UART_BASE       0x80000000u

#define UART_CTRL_REG   0x10u
#define UART_STATUS_REG 0x14u
#define UART_TX_REG     0x1Cu

#define UART_TX_FULL    (1u << 0)

#define BAUD_RATE       921600u
#define SYSCLK_FREQ     50000000u

#define UART_WRITE(off, val) \
    (*(volatile uint32_t *)(UART_BASE + (off)) = (val))

#define UART_READ(off) \
    (*(volatile uint32_t *)(UART_BASE + (off)))


static inline void uart_init(void)
{
    /*
        NCO = (BAUD_RATE * 2^20) / SYSCLK_FREQ

        For 921600 baud and 50 MHz:

        NCO = (921600 * 1048576) / 50000000
            = 19327
            = 0x4B7F
    */
    uint32_t nco = 0x4B7Fu;
    // Set NCO value and enable TX and RX in CTRL register.
    UART_WRITE(UART_CTRL_REG, (nco << 16) | 0x3u);
}

static inline void uart_send_byte(char c)
{
    while (UART_READ(UART_STATUS_REG) & UART_TX_FULL) {}

    UART_WRITE(UART_TX_REG, (uint32_t)(uint8_t)c);
}

static inline void uart_send_string(const char *s)
{
    while (*s != '\0') {
        if (*s == '\n') {
            uart_send_byte('\r');
        }

        uart_send_byte(*s);
        s++;
    }
}

static inline void uart_send_hex32(uint32_t value)
{
    const char hex_digits[] = "0123456789ABCDEF";

    for (int i = 7; i >= 0; i--) {
        uint32_t nibble = (value >> (i * 4)) & 0xFu;
        uart_send_byte(hex_digits[nibble]);
    }
}

static inline void uart_send_label_hex32(const char *label, uint32_t value)
{
    uart_send_string(label);
    uart_send_hex32(value);
    uart_send_string("\n");
}


/*
    ============================================================
    SPI HOST SECTION
    ============================================================
*/

#define SPI0_BASE_ADDR 0x40300000u

#define SPI_CONTROL_OFFSET      0x10u
#define SPI_STATUS_OFFSET       0x14u
#define SPI_CONFIGOPTS_OFFSET   0x18u
#define SPI_CSID_OFFSET         0x1Cu
#define SPI_COMMAND_OFFSET      0x20u
#define SPI_RXDATA_OFFSET       0x24u
#define SPI_TXDATA_OFFSET       0x28u

#define SPI_CONTROL_SPIEN      (1u << 31)
#define SPI_CONTROL_SW_RST     (1u << 30)
#define SPI_CONTROL_OUTPUT_EN  (1u << 29)

#define SPI_STATUS_READY       (1u << 31)
#define SPI_STATUS_ACTIVE      (1u << 30)
#define SPI_STATUS_TXFULL      (1u << 29)
#define SPI_STATUS_RXEMPTY     (1u << 24)

#define SPI_COMMAND_DIRECTION_SHIFT 12u
#define SPI_COMMAND_SPEED_SHIFT     10u
#define SPI_COMMAND_CSAAT           (1u << 9)

#define SPI_DIR_DUMMY 0u
#define SPI_DIR_RX    1u
#define SPI_DIR_TX    2u
#define SPI_DIR_BIDIR 3u

#define SPI_SPEED_STANDARD 0u
#define SPI_SPEED_DUAL     1u
#define SPI_SPEED_QUAD     2u


#define SPI_REG(offset) \
    (*(volatile uint32_t *)(SPI0_BASE_ADDR + (offset)))

static inline uint32_t spi_make_command(uint32_t direction,
                                        uint32_t speed,
                                        uint32_t csaat,
                                        uint32_t length)
{
    return ((direction & 0x3u) << SPI_COMMAND_DIRECTION_SHIFT) |
           ((speed & 0x3u) << SPI_COMMAND_SPEED_SHIFT) |
           (csaat ? SPI_COMMAND_CSAAT : 0u) |
           ((length - 1u) & 0x1FFu);
}

static inline void spi_wait_ready(void)
{
    uint32_t status;

    do {
        status = SPI_REG(SPI_STATUS_OFFSET);
    } while (((status & SPI_STATUS_READY) == 0u) ||
             ((status & SPI_STATUS_ACTIVE) != 0u));
}


static inline void spi_init(void)
{
    // Reset SPI host internal state and FIFOs.
    SPI_REG(SPI_CONTROL_OFFSET) = SPI_CONTROL_SW_RST;
    SPI_REG(SPI_CONTROL_OFFSET) = 0u;
    spi_wait_ready();

    // Configure SPI host with default settings.
    SPI_REG(SPI_CONFIGOPTS_OFFSET) = 0u;
    spi_wait_ready();

    // Enable SPI host.
    SPI_REG(SPI_CONTROL_OFFSET) =
        SPI_CONTROL_SPIEN |
        SPI_CONTROL_OUTPUT_EN;
    spi_wait_ready();

    // Select chip select 0
    SPI_REG(SPI_CSID_OFFSET) = 0u;
}

static inline void spi_transmit_word(uint32_t word)
{
    while ((SPI_REG(SPI_STATUS_OFFSET) & SPI_STATUS_TXFULL) != 0u) {}
    SPI_REG(SPI_TXDATA_OFFSET) = word;
}

static inline void spi_transmit_byte(uint8_t byte)
{
    spi_transmit_word((uint32_t)byte);
}

static inline void spi_run_command(uint32_t direction,
                                   uint32_t speed,
                                   uint32_t csaat,
                                   uint32_t length)
{
    spi_wait_ready();

    SPI_REG(SPI_CSID_OFFSET) = 0u;

    SPI_REG(SPI_COMMAND_OFFSET) =
        spi_make_command(direction, speed, csaat, length);

    spi_wait_ready();
}

static inline uint32_t spi_receive_word(void)
{
    while ((SPI_REG(SPI_STATUS_OFFSET) & SPI_STATUS_RXEMPTY) != 0u) {}
    return SPI_REG(SPI_RXDATA_OFFSET);
}


/*
    ============================================================
    SPI FLASH SECTION
    ============================================================
*/

#define FLASH_CMD_POWER_UP       0xABu
#define FLASH_CMD_POWER_DOWN     0xB9u
#define FLASH_CMD_CLEAR_XIP      0xFFu
#define FLASH_CMD_READ_STANDARD  0x03u
#define FLASH_CMD_READ_DUAL      0xBBu
#define FLASH_CMD_READ_QUAD      0xEBu
#define FLASH_CMD_READ_QUAD_DDR  0xEDu

#define FLASH_MODE_BYTE          0x00u
#define FLASH_DUMMY_CYCLES       8u

static inline void flash_power_up(void)
{
    // Send 0xAB using standard SPI.
    spi_transmit_byte((uint8_t)FLASH_CMD_POWER_UP);

    spi_run_command(
        SPI_DIR_TX,
        SPI_SPEED_STANDARD,
        0u,
        1u
    );
}

static inline uint32_t flash_read_word(uint32_t addr)
{
    /*
        0xEB fast quad read transaction:

            1. Send opcode 0xEB using standard SPI
            2. Send address[23:16], address[15:8], address[7:0], mode byte
               using quad SPI
            3. Send 8 dummy cycles
            4. Receive 4 bytes using quad SPI
    */

    // Send opcode 0xEB & Keep CS active after this command.
    
    spi_transmit_byte((uint8_t)FLASH_CMD_READ_QUAD);

    spi_run_command(
        SPI_DIR_TX,
        SPI_SPEED_STANDARD,
        1u,
        1u
    );

    // Pack address and mode byte into a single 32-bit word for transmission.
    uint32_t packed =
        (((addr >> 16) & 0xFFu) << 0)  |
        (((addr >> 8)  & 0xFFu) << 8)  |
        (((addr >> 0)  & 0xFFu) << 16) |
        ((FLASH_MODE_BYTE & 0xFFu) << 24);

    spi_transmit_word(packed);

    spi_run_command(
        SPI_DIR_TX,
        SPI_SPEED_QUAD,
        1u,
        4u
    );

    // send 8 dummy cycles
    spi_run_command(
        SPI_DIR_DUMMY,
        SPI_SPEED_QUAD,
        1u,
        FLASH_DUMMY_CYCLES
    );

    // receive 4 bytes
    spi_run_command(
        SPI_DIR_RX,
        SPI_SPEED_QUAD,
        0u,
        4u
    );

    return spi_receive_word();
}


/*
    ============================================================
    CRC32 SECTION
    ============================================================
*/

static uint32_t crc32_table[256];
static int crc32_table_ready = 0;

static void crc32_init_table(void)
{
    for (uint32_t i = 0; i < 256u; i++) {
        uint32_t crc = i;

        for (int bit = 0; bit < 8; bit++) {
            if ((crc & 1u) != 0u) {
                crc = (crc >> 1) ^ 0xEDB88320u;
            } else {
                crc = crc >> 1;
            }
        }

        crc32_table[i] = crc;
    }

    crc32_table_ready = 1;
}

static uint32_t crc32_compute(const uint8_t *data, uint32_t len)
{
    if (!crc32_table_ready) {
        crc32_init_table();
    }

    uint32_t crc = 0xFFFFFFFFu;

    for (uint32_t i = 0; i < len; i++) {
        uint8_t index = (uint8_t)((crc ^ data[i]) & 0xFFu);
        crc = (crc >> 8) ^ crc32_table[index];
    }

    return crc ^ 0xFFFFFFFFu;
}


/*
    ============================================================
    BOOTLOADER SECTION
    ============================================================
*/

#define FLASH_MAGIC_OFFSET    0x00u
#define FLASH_SIZE_OFFSET     0x04u
#define FLASH_CRC_OFFSET      0x08u
#define FLASH_PAYLOAD_OFFSET  0x0Cu

#define EXPECTED_MAGIC        0xB007C0DEu
#define SRAM_LOAD_ADDR        0x00110000u
#define MAX_PAYLOAD_SIZE      0x00010000u

// print a panic message and halt the system when error is detected
static void bootloader_panic(const char *message)
{
    uart_send_string(message);
    uart_send_string("\n");

    while (1) {
    }
}

int main(void)
{
    // initialize UART 
    uart_init();
    
    // initialize SPI host
    spi_init();

    // wake up SPI flash
    flash_power_up();

    // read firmware header from flash
    uint32_t magic = flash_read_word(FLASH_MAGIC_OFFSET);
    uint32_t size = flash_read_word(FLASH_SIZE_OFFSET);
    uint32_t stored_crc = flash_read_word(FLASH_CRC_OFFSET);

    // verify magic
    uart_send_label_hex32("MAGIC=", magic);
    if (magic != EXPECTED_MAGIC) {
        bootloader_panic("MAGIC BAD");
    }
    uart_send_string("MAGIC OK\n");

    /// verify size
    uart_send_label_hex32("SIZE=", size);

    if ( size == 0u || size > MAX_PAYLOAD_SIZE  ) {
        bootloader_panic("SIZE BAD");
    }

    uart_send_string("SIZE OK\n");

    // copy payload into SRAM
    volatile uint32_t *payload_words = (volatile uint32_t *)SRAM_LOAD_ADDR;

    for (uint32_t i = 0; i < (size / 4u); i++) {
        payload_words[i] = flash_read_word(FLASH_PAYLOAD_OFFSET + (i * 4u));
    }

    // compute CRC32 and compare with stored CRC
    uint32_t computed_crc =
        crc32_compute((const uint8_t *)SRAM_LOAD_ADDR, size);

    uart_send_label_hex32("STORED=", stored_crc);
    uart_send_label_hex32("COMPUTED=", computed_crc);
    if (computed_crc != stored_crc) {
        bootloader_panic("CRC BAD");
    }
    uart_send_string("CRC OK\n");

    // Disable SPI host
    SPI_REG(SPI_CONTROL_OFFSET) = 0u;

    // Jump to loaded firmware.
    void (*firmware_entry)(void) = (void (*)(void))SRAM_LOAD_ADDR;
    firmware_entry();

    while (1) {
    }

    return 0;
}