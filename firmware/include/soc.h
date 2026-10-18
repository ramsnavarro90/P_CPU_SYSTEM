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

// SPI helpers
static inline unsigned char spi_transfer(unsigned char tx) {
    SPI_DATA = (unsigned int)tx;          // start transfer
    while (SPI_BUSY);                     // wait complete
    return (unsigned char)(SPI_DATA & 0xFF);  // read RX (clears rx_valid)
}

static inline void spi_cs_assert(void)   { SPI_CTRL &= ~SPI_CS_N; }
static inline void spi_cs_deassert(void) { SPI_CTRL |=  SPI_CS_N; }

#endif // SOC_H