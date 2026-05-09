#include "uart.h"

int main(void){

    uart_init();

    uart_send_string("Hello World from UART!\n");
    // uart_send_byte('A');

    while (1) {
        // uart_send_string("AAAA UART TEST AAAA\n");
    }

    return 0;
}