// Deyaa Al-khativ
// 18/2/2026

/*This is a bootloader code that deals with flash look at spiflash.v 
spiflash has commands that we can target to start the process of boot loading

The code is structured into 5 segments:

A: The "define" that has the SPI, UART, Flash, SRAM addresses and register offset
B: SPI handler
C: UART HANDLER
D: IMAGE INTEGRITY CHECKS
E: THE MAIN COPYING LOOP
*/

#include <stdint.h>

//For register offset check vendor/lowrisc_ip/ip/spi_host/rtl/spi_host_reg_pkg.sv
//For the actual bit structure of register check vendor/lowrisc_ip/ip/spi_host/data/spi_host.json

// SPI
#define SPI_HOST_CONFIGOPTS (0x18)
#define SPI_HOST_STATUS (0x14)
#define SPI_HOST_CONTROL (0x10)
#define SPI_HOST_TXDATA (0x28)
#define SPI_HOST_CSID (0x1C)
#define SPI_HOST_COMMAND (0x20)
#define SPI_HOST_RXDATA (0x24)
#define SPI_BASE 0x40300000u
#define SPI_REG(offset)   (SPI_BASE + (offset))
#define DEV_WRITE(off, val) (*(volatile uint32_t *)(SPI_BASE + (off)) = (val))
#define DEV_READ(off)       (*(volatile uint32_t *)(SPI_BASE + (off)))
#define CTRL_SPIEN (1u << 31)
#define CTRL_OUTEN (1u << 29)
#define CLKDIV ((50000000/(2*1000000) - 1))

// UART
#define UART_BASE       0x80000000u
#define UART_CTRL_REG   0x10
#define UART_STATUS_REG 0x14
#define UART_TX_REG     0x1C
#define UART_TX_FULL    (1u << 0)
#define BAUD_RATE       921600
#define SYSCLK_FREQ     50000000

#define UART_WRITE(off, val) (*(volatile uint32_t *)(UART_BASE + (off)) = (val))
#define UART_READ(off)       (*(volatile uint32_t *)(UART_BASE + (off)))

// Bootloader
#define BOOT_MAGIC   0xB007C0DE
#define APP_BASE     0x00110000u
#define MAX_IMG_SIZE 0x00010000u   // 64KB max
#define HEADER_SIZE  0x0000000Cu   // magic(4) + size(4) + crc32(4)




void spi_wait_ready(){
    /*
        While !status[31]: !Ready || Status[30]: SPI active processing previous commands
    */
    uint32_t status;
    do {
        status = DEV_READ(SPI_HOST_STATUS);
    } while (!(status&(1u<< 31)) || status&(1u<<30));
}

void spi_enable(){
    /*
         We enable spi by writing on CTRL_SPIEN and CTRL_OUT  of the Control register
    */
    DEV_WRITE(SPI_HOST_CONTROL, CTRL_SPIEN | CTRL_OUTEN);
    spi_wait_ready();
}


void spi_configure(){
    /*
        Wrting on CONFIGOPTS register, the formula for CLKDIV from the opentitan documentation, SPI theory of operations
    */
    uint32_t configopts = CLKDIV | (0xF << 16) | (0xF << 20) | (0xF << 24);
    DEV_WRITE(SPI_HOST_CONFIGOPTS, configopts);
    spi_wait_ready();
}

void spi_reset(){
    /*
        Reset the internal state of the SPI and reset and the TX,RX DATA buffers
    */
    DEV_WRITE(SPI_HOST_CONTROL, (0x1 << 30));
    DEV_WRITE(SPI_HOST_CONTROL, (0x0 << 30));
    spi_wait_ready();
}



void spi_init(){
    /*
        Initialize to start sending commands and recieving DATA
    */
    spi_reset();
    spi_configure();
    spi_enable();
}


void spi_transmit_byte(uint8_t byte){
    /*
        Making sure the TXDATA FIFO is not full before sending DATA
    */
    uint32_t status;
    do{
        status = DEV_READ(SPI_HOST_STATUS);
    }while((status & (1u << 29)));
    DEV_WRITE(SPI_HOST_TXDATA, byte);
}

void spi_transmit_word(uint32_t word){
    uint32_t status;
    do{
        status = DEV_READ(SPI_HOST_STATUS);
    } while(status & (1u << 29));
    DEV_WRITE(SPI_HOST_TXDATA, word);
}

void spi_send_command(uint16_t len, uint8_t segment, uint8_t speed, uint8_t direction){
    /*
        Sending Command Function supports the following:
            - Sending Segments i.e sending cmd and addresses that follows
            - Sending in std, dual, quad modes
            - Direction: TX, RX, Birdirectional, Dummy(QSPI), 
    */
    uint32_t command;
    if (segment) {
    command = (direction << 12) | (speed << 10) | (0x1 << 9) | ((len - 1)<< 0);
    }
    else{
    command = (direction << 12) | (speed << 10) | (0x0 << 9) | ((len -1)<< 0); 
    }
    //WRITE 1 TO CISD TO COMMUNICATE WITH FLASH
    DEV_WRITE(SPI_HOST_CSID, 0x0);
    DEV_WRITE(SPI_HOST_COMMAND, command);
    spi_wait_ready();
}

void spi_recieve_command(uint16_t len, uint8_t speed){
    /*
        Telling the hardware(RXDATA) how to receive
        in this function the commnad[12] is set to 1 which means I'm receiving certain speed i.e std, dual, quad
    */

    uint32_t command = (0x1 << 12) | (speed << 10) | (0x0 << 9) | ((len -1) << 0); 

    DEV_WRITE(SPI_HOST_CSID, 0x0);
    DEV_WRITE(SPI_HOST_COMMAND, command);
    spi_wait_ready();
}

uint32_t spi_read_rxdata(){
    /*
        READ FROM FIFO
    */
    uint32_t status;
    do{
        status = DEV_READ(SPI_HOST_STATUS);
    }while((1u >> 24) & status);
    uint32_t recieved = DEV_READ(SPI_HOST_RXDATA);
    return recieved;
}

uint32_t flash_read_word(uint32_t addr){
    spi_transmit_byte(0xEB);
    spi_send_command(1, 1, 0, 2); 
    uint32_t packed = ((addr >> 16) & 0xFF)        |
                      (((addr >> 8) & 0xFF) << 8)  |
                      ((addr & 0xFF) << 16)         |
                      (0x00 << 24);
    spi_transmit_word(packed);
    spi_send_command(4, 1, 2, 2);
    spi_send_command(8, 1, 2, 0);
    spi_recieve_command(4, 2);
    uint32_t recieved = spi_read_rxdata();
    return recieved; 
}

void powerup_flash(){
    spi_transmit_byte(0xab);
    spi_send_command(1, 0, 0, 2);
}

//UART Initalization
void uart_init(){
    uint32_t nco = (uint32_t)(((uint64_t)BAUD_RATE << 20) / SYSCLK_FREQ);
    UART_WRITE(UART_CTRL_REG, (nco << 16) | 0x3u);
}

void uart_putc(char c){
    while (UART_READ(UART_STATUS_REG) & UART_TX_FULL);
    UART_WRITE(UART_TX_REG, c);
}

void uart_print(const char *s){
    while (*s) uart_putc(*s++);
}

void print_hex32(uint32_t val){
    const char hex[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(val >> i) & 0xF]);
}


//CRC TABLE
static const uint32_t crc32_table[256] = {
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
    0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
    0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
    0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
    0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
    0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
    0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
    0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
    0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
    0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
    0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
    0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
    0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
    0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
    0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
    0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
    0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
    0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
    0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
    0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
    0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
    0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
};


// Compute CRC for image integrity 
uint32_t crc32_compute(const uint8_t *data, uint32_t len, const uint32_t *table) {
    uint32_t crc = 0xFFFFFFFF;
    for (uint32_t i = 0; i < len; i++) {
        uint32_t idx = (crc ^ data[i]) & 0xFF;
        crc = (crc >> 8) ^ table[idx];
    }
    return crc ^ 0xFFFFFFFF;
}


#ifdef DEBUG
volatile int _debug_wait = 1;
#endif

int main(){

#ifdef DEBUG
    while(_debug_wait) {}
#endif
    uart_init();
    spi_init();
    powerup_flash();

    //Read and validate magic which is a handshake between spi and flash
    uint32_t magic = flash_read_word(0x000000);
    uart_print("MAGIC=");
    print_hex32(magic);
    uart_putc('\n');
    if (magic != BOOT_MAGIC) {
        uart_print("ERR: BAD MAGIC\n");
        while(1);
    }
    uart_print("MAGIC OK\n");

    //Read and validate size to make sure its a multiple of 4 and that its not exceeding the allowed image size
    uint32_t size = flash_read_word(0x000004);
    uart_print("SIZE=");
    print_hex32(size);
    uart_putc('\n');
    if (size == 0 || size > MAX_IMG_SIZE || size % 4 != 0) {
        uart_print("ERR: BAD SIZE\n");
        while(1);
    }
    uart_print("SIZE OK\n");

    //Read stored CRC from flash
    uint32_t stored_crc = flash_read_word(0x000008);

    //Copy image from flash to SRAM
    volatile uint32_t *dst = (volatile uint32_t *) APP_BASE;
    for(int32_t i = 0; i < size/4 ; i++ ){
        dst[i] = flash_read_word(HEADER_SIZE + i*4);
    }

    //Verify CRC
    uint32_t computed_crc = crc32_compute((const uint8_t *)APP_BASE, size, crc32_table);
    uart_print("STORED=");
    print_hex32(stored_crc);
    uart_putc('\n');
    uart_print("COMPUTED=");
    print_hex32(computed_crc);
    uart_putc('\n');
    uart_print("CRC=");
    print_hex32(computed_crc);
    uart_putc('\n');
    if (computed_crc != stored_crc) {
        uart_print("ERR: BAD CRC\n");
        while(1);
    }
    uart_print("CRC OK\n");

    //Clean handoff — disable peripherals before jump
    DEV_WRITE(SPI_HOST_CONTROL, 0x0);

    //Jump to application
    void (*app_entry)(void) = (void (*)(void))APP_BASE;
    app_entry();

    return 0;
}