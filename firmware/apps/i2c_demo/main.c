// i2c_demo/main.c — I2C master demo (alexforencich core, FIFO-based)
//
// Write: [S][ADDR+W][ptr=0][data x N][P]
// Read : [S][ADDR+W][ptr=0][Sr][ADDR+R][data x N (last one NACKed)][P]

#include "soc.h"

#define SLAVE_ADDR    0x28
#define N_BYTES       4
#define I2C_PRESCALE  2          // f_scl = f_clk / (4 * 2)

static const unsigned char write_data[N_BYTES] = {0xDE, 0xAD, 0xBE, 0xEF};

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("=== I2C Master Demo ===\r\n\r\n");

    I2C_PRE_LO = I2C_PRESCALE & 0xFF;
    I2C_PRE_HI = (I2C_PRESCALE >> 8) & 0xFF;
    i2c_clear_nack();

    unsigned int i, errors = 0;

    // ---- Write -------------------------------------------------------------
    uart_print("-- Write --\r\n");
    I2C_CMD_ADDR = SLAVE_ADDR;
    I2C_DATA     = 0x00;                              // pointer byte
    I2C_COMMAND  = I2C_CMD_START | I2C_CMD_WRITE;
    for (i = 0; i < N_BYTES; i++) {
        I2C_DATA    = write_data[i];
        I2C_COMMAND = I2C_CMD_WRITE | ((i == N_BYTES - 1) ? I2C_CMD_STOP : 0);
    }
    i2c_wait();

    if (i2c_nacked()) {
        uart_print("  NACK during write!\r\n");
        errors++;
        i2c_clear_nack();
    } else {
        for (i = 0; i < N_BYTES; i++) {
            uart_print("  Wrote ");
            uart_print_hex(write_data[i]);
            uart_print("\r\n");
        }
    }

    // ---- Read back ---------------------------------------------------------
    uart_print("\r\n-- Read --\r\n");
    I2C_DATA    = 0x00;                               // set read pointer
    I2C_COMMAND = I2C_CMD_START | I2C_CMD_WRITE;      // no STOP: hold the bus
    for (i = 0; i < N_BYTES; i++) {
        unsigned int cmd = I2C_CMD_READ;
        if (i == 0)           cmd |= I2C_CMD_START;   // repeated START + ADDR+R
        if (i == N_BYTES - 1) cmd |= I2C_CMD_STOP;    // NACK + STOP on last byte
        I2C_COMMAND = cmd;
    }
    i2c_wait();

    if (i2c_nacked()) {
        uart_print("  NACK during read!\r\n");
        errors++;
        i2c_clear_nack();
    }

    for (i = 0; i < N_BYTES; i++) {
        unsigned char rx = (unsigned char)(I2C_DATA & 0xFF);   // pops read FIFO
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