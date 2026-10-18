// spi_demo/main.c — SPI master loopback demo
//
// MOSI is looped back to MISO externally in the testbench.
// Every byte sent should be received back unchanged.
// Also demonstrates multi-byte transactions with CS held across bytes.

#include "soc.h"

#define N_BYTES  8

static const unsigned char tx_data[N_BYTES] = {
    0xA5, 0x5A, 0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34
};

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("=== SPI Loopback Demo ===\r\n\r\n");

    // Configure SPI: Mode 0 (cpol=0, cpha=0), CLK_DIV=4, CS deasserted
    SPI_CLK_DIV = 4;
    SPI_CTRL    = SPI_CS_N;   // cpol=0, cpha=0, cs_n=1

    uart_print("Config: Mode 0, CLK_DIV=4\r\n\r\n");

    // --- Single byte transfers -----------------------------------------------
    uart_print("-- Single byte transfers --\r\n");
    unsigned int i;
    unsigned char rx;
    unsigned int errors = 0;

    for (i = 0; i < N_BYTES; i++) {
        spi_cs_assert();
        rx = spi_transfer(tx_data[i]);
        spi_cs_deassert();

        uart_print("  TX=");
        uart_print_hex(tx_data[i]);
        uart_print("  RX=");
        uart_print_hex(rx);

        if (rx == tx_data[i]) {
            uart_print("  OK\r\n");
        } else {
            uart_print("  MISMATCH!\r\n");
            errors++;
        }
    }

    // --- Multi-byte transaction (CS held across all bytes) -------------------
    uart_print("\r\n-- Multi-byte transaction (CS held) --\r\n");
    spi_cs_assert();
    for (i = 0; i < N_BYTES; i++) {
        rx = spi_transfer(tx_data[i]);
        uart_print("  [");
        uart_print_uint(i);
        uart_print("] TX=");
        uart_print_hex(tx_data[i]);
        uart_print(" RX=");
        uart_print_hex(rx);
        if (rx != tx_data[i]) { uart_print(" MISMATCH!"); errors++; }
        uart_print("\r\n");
    }
    spi_cs_deassert();

    // --- Summary -------------------------------------------------------------
    uart_print("\r\nErrors: ");
    uart_print_uint(errors);
    uart_print("\r\n=== Done ===\r\n");

    GPIO_DATA = errors ? 0xBAD00BAD : 0x5E100D00;
    while (1);
    return 0;
}