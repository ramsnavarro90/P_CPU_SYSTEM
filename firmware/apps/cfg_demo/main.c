// cfg_demo/main.c — Runtime SoC configuration via wb_cfg
//
// Demonstrates:
//   1. Reading SOC_ID and SOC_VER
//   2. Reading default UART baud divisor
//   3. Disabling GPIO — writes to DATA have no effect on gpio_out
//   4. Re-enabling GPIO — gpio_out recovers the last written value

// ---- CFG --------------------------------------------------------------------
#define CFG_BASE      0xB0000000UL
#define CFG_SOC_ID    (*(volatile unsigned int *)(CFG_BASE + 0x00))
#define CFG_SOC_VER   (*(volatile unsigned int *)(CFG_BASE + 0x04))
#define CFG_UART_CTRL (*(volatile unsigned int *)(CFG_BASE + 0x08))
#define CFG_UART_BAUD (*(volatile unsigned int *)(CFG_BASE + 0x0C))
#define CFG_GPIO_CTRL (*(volatile unsigned int *)(CFG_BASE + 0x10))

// ---- GPIO -------------------------------------------------------------------
#define GPIO_BASE  0x90000000UL
#define GPIO_DATA  (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR   (*(volatile unsigned int *)(GPIO_BASE + 0x04))

// ---- UART -------------------------------------------------------------------
#define UART_BASE   0xA0000000UL
#define UART_DATA   (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_STATUS (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_BUSY   (UART_STATUS & 0x1)

static void uart_putchar(char c) {
    while (UART_BUSY);
    UART_DATA = (unsigned int)c;
}
static void uart_print(const char *s) { while (*s) uart_putchar(*s++); }
static void uart_print_hex(unsigned int v) {
    static const char h[] = "0123456789ABCDEF";
    int i; uart_print("0x");
    for (i = 28; i >= 0; i -= 4) uart_putchar(h[(v >> i) & 0xF]);
}

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    // ---- 1. Print SoC identity ------------------------------------------
    uart_print("=== SoC CFG Demo ===\r\n\r\n");
    uart_print("SOC_ID  : "); uart_print_hex(CFG_SOC_ID);  uart_print("\r\n");
    uart_print("SOC_VER : "); uart_print_hex(CFG_SOC_VER); uart_print("\r\n");
    uart_print("UART_BAUD: "); uart_print_hex(CFG_UART_BAUD); uart_print("\r\n");
    uart_print("UART_CTRL: "); uart_print_hex(CFG_UART_CTRL); uart_print("\r\n");
    uart_print("GPIO_CTRL: "); uart_print_hex(CFG_GPIO_CTRL); uart_print("\r\n");

    // ---- 2. GPIO disable demo -------------------------------------------
    uart_print("\r\n-- GPIO Disable --\r\n");
    GPIO_DATA = 0x12345678;
    uart_print("GPIO_DATA written: 0x12345678\r\n");
    uart_print("Disabling GPIO (gpio_en = 0)...\r\n");

    // Sentinel: TB verifies gpio_out is still 0x12345678 before disable
    GPIO_DATA = 0xC0DE0001;   // checkpoint 1: about to disable
    CFG_GPIO_CTRL = 0x0;      // disable GPIO — gpio_out should go to 0

    // Write to DATA while disabled — should NOT appear on gpio_out
    GPIO_DATA = 0xDEADF00D;
    uart_print("GPIO_DATA written while disabled: 0xDEADF00D\r\n");
    uart_print("(gpio_out should remain 0x00000000)\r\n");

    // Sentinel: TB verifies gpio_out == 0 despite DATA write
    // (gpio_out is gated by gpio_en, so gpio_out = 0)

    // ---- 3. GPIO re-enable ----------------------------------------------
    uart_print("\r\n-- GPIO Re-enable --\r\n");
    CFG_GPIO_CTRL = 0x1;
    uart_print("GPIO re-enabled (gpio_en = 1)\r\n");
    uart_print("gpio_out should now show last DATA value: 0xDEADF00D\r\n");

    GPIO_DATA = 0xC0DE0002;   // checkpoint 2: gpio re-enabled
    uart_print("\r\n=== Done ===\r\n");

    // Completion sentinel
    GPIO_DATA = 0xCA1CC06F;   // "CALCCFG"
    while (1);
    return 0;
}