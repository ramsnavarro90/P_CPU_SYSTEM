// i2c_demo/main.c — I2C master demo using alexforencich core

#include "soc.h"

#define SLAVE_ADDR  0x28
#define N_BYTES     4
#define I2C_PRESCALE 2   // SCL = CLK_FREQ / (4*(2+1)) — fast for sim

static const unsigned char write_data[N_BYTES] = {0xDE, 0xAD, 0xBE, 0xEF};

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("=== I2C Master Demo ===\r\n\r\n");

    // Configure prescaler
    I2C_PRE_LO = I2C_PRESCALE & 0xFF;
    I2C_PRE_HI = (I2C_PRESCALE >> 8) & 0xFF;

    unsigned int i, errors = 0;
    unsigned char rx;

    // ---- Write N bytes starting at mem[0] -----------------------------------
    uart_print("-- Write --\r\n");
    I2C_CMD_ADDR = SLAVE_ADDR;

    // Send mem address (0x00) with START
    i2c_write_byte(0x00, 1, 0);
    if (i2c_nacked()) { uart_print("  NACK on addr!\r\n"); errors++; }

    // Send data bytes
    for (i = 0; i < N_BYTES; i++) {
        unsigned char stop = (i == N_BYTES - 1) ? 1 : 0;
        i2c_write_byte(write_data[i], 0, stop);
        uart_print("  Wrote ");
        uart_print_hex(write_data[i]);
        uart_print("\r\n");
    }

    // ---- Read back N bytes --------------------------------------------------
    uart_print("\r\n-- Read --\r\n");

    // Set read pointer: START + write mem_addr
    I2C_CMD_ADDR = SLAVE_ADDR;
    i2c_write_byte(0x00, 1, 0);

    // Repeated START + read address
    I2C_CMD_ADDR = SLAVE_ADDR;
    I2C_COMMAND  = I2C_CMD_START | I2C_CMD_READ;
    i2c_wait();
    if (i2c_nacked()) { uart_print("  NACK on read addr!\r\n"); errors++; }

    for (i = 0; i < N_BYTES; i++) {
        unsigned char stop = (i == N_BYTES - 1) ? 1 : 0;
        rx = i2c_read_byte(stop);
        uart_print("  RX[");
        uart_print_uint(i);
        uart_print("] = ");
        uart_print_hex(rx);
        if (rx != write_data[i]) { uart_print(" MISMATCH!\r\n"); errors++; }
        else                       uart_print(" OK\r\n");
    }

    uart_print("\r\nErrors: ");
    uart_print_uint(errors);
    uart_print("\r\n=== Done ===\r\n");

    GPIO_DATA = errors ? 0xBAD12CBA : 0x12C900D0;
    while (1);
    return 0;
}