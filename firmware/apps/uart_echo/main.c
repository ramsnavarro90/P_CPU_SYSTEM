// uart_echo/main.c — UART echo: receive a byte, send it back
// Testbench drives uart_rx with 8 bytes; firmware echoes each one via uart_tx.

#include "soc.h"

#define ECHO_COUNT 8

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("=== UART Echo Demo ===\r\n");
    uart_print("Echoing ");
    uart_print_uint(ECHO_COUNT);
    uart_print(" bytes...\r\n");

    // Signal testbench: banner done, ready to receive
    GPIO_DATA = 0xEC000000; 

    unsigned int i;
    for (i = 0; i < ECHO_COUNT; i++) {
        // Wait for a byte to arrive
        while (!UART_RX_READY);
        unsigned char c = (unsigned char)(UART_RX_DATA & 0xFF);

        // Echo back via TX
        uart_putchar(c);

        // Show progress on GPIO
        GPIO_DATA = 0xEC000000 | ((unsigned int)c << 8) | i;
    }

    uart_print("\r\nEcho done.\r\n");
    GPIO_DATA = 0xEC40EC40;   // ECHOECHO sentinel
    while (1);
    return 0;
}