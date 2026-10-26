// -----------------------------------------------------------------------------
// soc.h — P_CPU_SYSTEM SoC peripheral register definitions
// Include this in every firmware app instead of redefining per-app.
// -----------------------------------------------------------------------------

#ifndef SOC_H
#define SOC_H

// ---- GPIO   0x9000_0000 -----------------------------------------------------
#define GPIO_BASE    0x90000000UL
#define GPIO_DATA    (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR     (*(volatile unsigned int *)(GPIO_BASE + 0x04))

// ---- UART   0xA000_0000 -----------------------------------------------------
// TX
#define UART_BASE      0xA0000000UL
#define UART_TX_DATA   (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_TX_STATUS (*(volatile unsigned int *)(UART_BASE + 0x04))
// RX (new)
#define UART_RX_DATA   (*(volatile unsigned int *)(UART_BASE + 0x08))
#define UART_RX_STATUS (*(volatile unsigned int *)(UART_BASE + 0x0C))

#define UART_TX_BUSY   (UART_TX_STATUS & 0x1)
#define UART_RX_READY  (UART_RX_STATUS & 0x1)
#define UART_RX_OVF    (UART_RX_STATUS & 0x2)

// ---- CFG    0xB000_0000 -----------------------------------------------------
#define CFG_BASE       0xB0000000UL
#define CFG_SOC_ID     (*(volatile unsigned int *)(CFG_BASE + 0x00))
#define CFG_SOC_VER    (*(volatile unsigned int *)(CFG_BASE + 0x04))
#define CFG_UART_CTRL  (*(volatile unsigned int *)(CFG_BASE + 0x08))
#define CFG_UART_BAUD  (*(volatile unsigned int *)(CFG_BASE + 0x0C))
#define CFG_GPIO_CTRL  (*(volatile unsigned int *)(CFG_BASE + 0x10))

// ---- TIMER  0xC000_0000 -----------------------------------------------------
#define TIMER_BASE     0xC0000000UL
#define TIMER_COUNT    (*(volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIMER_COMPARE  (*(volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIMER_CTRL     (*(volatile unsigned int *)(TIMER_BASE + 0x08))
#define TIMER_STATUS   (*(volatile unsigned int *)(TIMER_BASE + 0x0C))

#define TIMER_EN          (1u << 0)
#define TIMER_AUTO_RELOAD (1u << 1)
#define TIMER_MATCH       (1u << 0)

// ---- SPI    0xD000_0000 -----------------------------------------------------
#define SPI_BASE      0xD0000000UL
#define SPI_DATA      (*(volatile unsigned int *)(SPI_BASE + 0x00))
#define SPI_STATUS    (*(volatile unsigned int *)(SPI_BASE + 0x04))
#define SPI_CTRL      (*(volatile unsigned int *)(SPI_BASE + 0x08))
#define SPI_CLK_DIV   (*(volatile unsigned int *)(SPI_BASE + 0x0C))

#define SPI_BUSY      (SPI_STATUS & 0x1)
#define SPI_RX_VALID  (SPI_STATUS & 0x2)

// CTRL bits
#define SPI_CPOL      (1u << 0)
#define SPI_CPHA      (1u << 1)
#define SPI_CS_N      (1u << 4)   // 1=deasserted, 0=asserted

// ---- I2C    0xE000_0000 -----------------------------------------------------
// Wraps alexforencich/verilog-i2c i2c_master_wbs_8
#define I2C_BASE        0xE0000000UL
#define I2C_STATUS      (*(volatile unsigned int *)(I2C_BASE + 0x00))  // R
#define I2C_FIFO_STAT   (*(volatile unsigned int *)(I2C_BASE + 0x04))  // R
#define I2C_CMD_ADDR    (*(volatile unsigned int *)(I2C_BASE + 0x08))  // W  [6:0]
#define I2C_COMMAND     (*(volatile unsigned int *)(I2C_BASE + 0x0C))  // W
#define I2C_DATA        (*(volatile unsigned int *)(I2C_BASE + 0x10))  // R/W
#define I2C_PRE_LO      (*(volatile unsigned int *)(I2C_BASE + 0x18))  // R/W
#define I2C_PRE_HI      (*(volatile unsigned int *)(I2C_BASE + 0x1C))  // R/W

// STATUS bits
#define I2C_BUSY        (1u << 0)
#define I2C_BUS_CTRL    (1u << 1)
#define I2C_BUS_ACT     (1u << 2)
#define I2C_MISS_ACK    (1u << 3)

// COMMAND bits
#define I2C_CMD_START   (1u << 0)   // generate START or repeated START
#define I2C_CMD_READ    (1u << 1)   // read byte
#define I2C_CMD_WRITE   (1u << 2)   // write byte
#define I2C_CMD_WR_MULT (1u << 3)   // write multiple
#define I2C_CMD_STOP    (1u << 4)   // generate STOP

// -----------------------------------------------------------------------------

// ---- UART helpers -----------------------------------------------------------
static inline void uart_putchar(char c) {
    while (UART_TX_BUSY);
    UART_TX_DATA = (unsigned int)c;
}

static inline void uart_print(const char *s) {
    while (*s) uart_putchar(*s++);
}

static inline void uart_print_hex(unsigned int v) {
    static const char h[] = "0123456789ABCDEF";
    int i;
    uart_print("0x");
    for (i = 28; i >= 0; i -= 4) uart_putchar(h[(v >> i) & 0xF]);
}

static inline void uart_print_uint(unsigned int val) {
    static const unsigned int pow10[] = {
        1000000000u, 100000000u, 10000000u, 1000000u, 100000u,
        10000u, 1000u, 100u, 10u, 1u
    };
    int i, digit, leading = 1;
    if (val == 0) { uart_putchar('0'); return; }
    for (i = 0; i < 10; i++) {
        digit = 0;
        while (val >= pow10[i]) { val -= pow10[i]; digit++; }
        if (digit > 0 || !leading) { uart_putchar('0' + digit); leading = 0; }
    }
}

// ---- SPI helpers ------------------------------------------------------------
static inline unsigned char spi_transfer(unsigned char tx) {
    SPI_DATA = (unsigned int)tx;          // start transfer
    while (SPI_BUSY);                     // wait complete
    return (unsigned char)(SPI_DATA & 0xFF);  // read RX (clears rx_valid)
}

static inline void spi_cs_assert(void)   { SPI_CTRL &= ~SPI_CS_N; }
static inline void spi_cs_deassert(void) { SPI_CTRL |=  SPI_CS_N; }


// ---- I2C helpers ------------------------------------------------------------
static inline void i2c_wait(void) {
    while (I2C_STATUS & I2C_BUSY);
}

static inline unsigned char i2c_nacked(void) {
    return (I2C_STATUS & I2C_MISS_ACK) ? 1 : 0;
}

static inline void i2c_write_byte(unsigned char data,
                                   unsigned char start,
                                   unsigned char stop) {
    unsigned int cmd = I2C_CMD_WRITE;
    if (start) cmd |= I2C_CMD_START;
    if (stop)  cmd |= I2C_CMD_STOP;
    I2C_DATA    = data;
    I2C_COMMAND = cmd;
    i2c_wait();
}

static inline unsigned char i2c_read_byte(unsigned char stop) {
    unsigned int cmd = I2C_CMD_READ;
    if (stop) cmd |= I2C_CMD_STOP;
    I2C_COMMAND = cmd;
    i2c_wait();
    return (unsigned char)(I2C_DATA & 0xFF);
}

#endif // SOC_H