// main.c — Firmware: UART print + GPIO toggle

// ---- GPIO -------------------------------------------------------------------
#define GPIO_BASE  0x90000000UL
#define GPIO_DATA  (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR   (*(volatile unsigned int *)(GPIO_BASE + 0x04))

// ---- UART -------------------------------------------------------------------
#define UART_BASE    0xA0000000UL
#define UART_DATA    (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_STATUS  (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_BUSY    (UART_STATUS & 0x1)

static void uart_putchar(char c) {
    while (UART_BUSY);
    UART_DATA = (unsigned int)c;
}

static void uart_print(const char *s) {
    while (*s) uart_putchar(*s++);
}

static void uart_print_hex(unsigned int val) {
    static const char hex[] = "0123456789ABCDEF";  // static → vive en ROM, no se copia
    int i;
    uart_print("0x");
    for (i = 28; i >= 0; i -= 4)
        uart_putchar(hex[(val >> i) & 0xF]);
}

// -----------------------------------------------------------------------------
int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("PicoRV32 SoC -- Hello World!\r\n");

    unsigned int count = 0;
    while (1) {
        GPIO_DATA = 0xA5000000 | (count & 0xFF);
        uart_print("count = ");
        uart_print_hex(count);
        uart_putchar('\r');
        uart_putchar('\n');
        count++;
    }

    return 0;
}