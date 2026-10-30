// bootloader/main.c — Stage-0 bootloader (lives in ROM)
//
// Reads an application image from SPI flash (standard READ 0x03), copies it to
// SRAM, verifies the checksum and jumps to it.
//
// Flash layout (little-endian):
//   +0x00 magic 0xB007F1A5 | +0x04 length | +0x08 byte-sum | +0x0C payload
//
// GPIO progress codes (observed by the testbench):
//   0xB0070000  bootloader alive
//   0xB007600D  image verified, about to jump
//   0xB007BAD0  bad/missing magic    0xB007BAD1  bad length
//   0xB007BAD2  checksum mismatch

#include "soc.h"

#define FLASH_CMD_READ    0x03
#define FLASH_IMG_OFFSET  0x000000u
#define IMG_MAGIC         0xB007F1A5u
#define APP_BASE          0x80000000u
#define APP_MAX_SIZE      0x8000u          // 32 KB boot window
#define BOOT_SPI_DIV      4                // SCLK = f_clk / (2 * div); raise for slow flash

static void flash_read_begin(unsigned int addr) {
    spi_cs_assert();
    spi_transfer(FLASH_CMD_READ);
    spi_transfer((addr >> 16) & 0xFF);
    spi_transfer((addr >>  8) & 0xFF);
    spi_transfer( addr        & 0xFF);
}

static void flash_read_end(void) {
    spi_cs_deassert();
}

static unsigned char flash_read_byte(void) {
    return spi_transfer(0x00);
}

static unsigned int flash_read_word(void) {
    unsigned int w = 0, i;
    for (i = 0; i < 4; i++)
        w |= (unsigned int)flash_read_byte() << (8 * i);
    return w;
}

static void boot_fail(const char *msg, unsigned int code) {
    flash_read_end();
    uart_print("BOOT: ");
    uart_print(msg);
    uart_print("\r\n");
    GPIO_DATA = code;
    while (1);
}

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xB0070000;

    uart_print("BOOT: reading flash...\r\n");

    SPI_CLK_DIV = BOOT_SPI_DIV;
    SPI_CTRL    = SPI_CS_N;                // mode 0, CS deasserted

    flash_read_begin(FLASH_IMG_OFFSET);

    unsigned int magic = flash_read_word();
    unsigned int len   = flash_read_word();
    unsigned int sum   = flash_read_word();

    if (magic != IMG_MAGIC)
        boot_fail("no valid image (bad magic)", 0xB007BAD0);
    if (len == 0 || len > APP_MAX_SIZE || (len & 3))
        boot_fail("bad image length", 0xB007BAD1);

    volatile unsigned int *dst = (volatile unsigned int *)APP_BASE;
    unsigned int calc = 0;
    unsigned int i, j;

    for (i = 0; i < len / 4; i++) {
        unsigned int w = 0;
        for (j = 0; j < 4; j++) {
            unsigned char b = flash_read_byte();
            w    |= (unsigned int)b << (8 * j);
            calc += b;
        }
        dst[i] = w;
    }
    flash_read_end();

    if (calc != sum)
        boot_fail("checksum mismatch", 0xB007BAD2);

    uart_print("BOOT: image ");
    uart_print_uint(len);
    uart_print(" bytes, checksum OK\r\n");
    uart_print("BOOT: jumping to ");
    uart_print_hex(APP_BASE);
    uart_print("\r\n");

    GPIO_DATA = 0xB007600D;
    while (UART_TX_BUSY);                  // let the last character finish

    ((void (*)(void))APP_BASE)();

    while (1);
    return 0;
}