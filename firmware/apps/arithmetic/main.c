// arithmetic/main.c — RV32I arithmetic demo
//
// Demonstrates native RV32I operations (no M extension required):
//   addition, subtraction, bitwise ops, shifts
//
// Also computes Fibonacci sequence using only addition.
// Results are printed via UART.

// ---- UART -------------------------------------------------------------------
#define UART_BASE   0xA0000000UL
#define UART_DATA   (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_STATUS (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_BUSY   (UART_STATUS & 0x1)

// ---- GPIO -------------------------------------------------------------------
#define GPIO_BASE  0x90000000UL
#define GPIO_DATA  (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR   (*(volatile unsigned int *)(GPIO_BASE + 0x04))

static void uart_putchar(char c) {
    while (UART_BUSY);
    UART_DATA = (unsigned int)c;
}

static void uart_print(const char *s) {
    while (*s) uart_putchar(*s++);
}

static void uart_print_hex(unsigned int val) {
    static const char hex[] = "0123456789ABCDEF";
    int i;
    uart_print("0x");
    for (i = 28; i >= 0; i -= 4)
        uart_putchar(hex[(val >> i) & 0xF]);
}

// static void uart_print_uint(unsigned int val) {
//     static char buf[11];
//     int i = 10;
//     buf[i] = '\0';
//     if (val == 0) { uart_putchar('0'); return; }
//     while (val > 0 && i > 0) {
//         buf[--i] = '0' + (val % 10);
//         val /= 10;
//     }
//     uart_print(&buf[i]);
// }

static void uart_print_uint(unsigned int val) {
    // Powers of 10 for RV32I — subtraction-based, no division needed
    static const unsigned int pow10[] = {
        1000000000u, 100000000u, 10000000u, 1000000u,
        100000u,     10000u,     1000u,     100u,     10u, 1u
    };
    int i, digit;
    int leading = 1;

    if (val == 0) { uart_putchar('0'); return; }

    for (i = 0; i < 10; i++) {
        digit = 0;
        while (val >= pow10[i]) {
            val  -= pow10[i];
            digit++;
        }
        if (digit > 0 || !leading) {
            uart_putchar('0' + digit);
            leading = 0;
        }
    }
}

// ---- Helpers ----------------------------------------------------------------
static void print_result(const char *label, unsigned int a,
                         const char *op,   unsigned int b,
                         unsigned int result) {
    uart_print("  ");
    uart_print_hex(a);
    uart_putchar(' ');
    uart_print(op);
    uart_putchar(' ');
    uart_print_hex(b);
    uart_print(" = ");
    uart_print_hex(result);
    uart_print("  (");
    uart_print(label);
    uart_print(")\r\n");
}

// ---- Fibonacci (addition only) ----------------------------------------------
#define FIB_COUNT 12

static unsigned int fib[FIB_COUNT];

static void compute_fibonacci(void) {
    int i;
    fib[0] = 0;
    fib[1] = 1;
    for (i = 2; i < FIB_COUNT; i++)
        fib[i] = fib[i-1] + fib[i-2];
}

// ---- Main -------------------------------------------------------------------
int main(void) {
    unsigned int a = 0xA5000000;
    unsigned int b = 0x00C0FFEE;
    unsigned int i;

    uart_print("=== RV32I Arithmetic Demo ===\r\n\r\n");

    // --- Addition
    uart_print("-- Addition & Subtraction --\r\n");
    print_result("ADD", a, "+",  b, a + b);
    print_result("SUB", a, "-",  b, a - b);

    // --- Bitwise operations
    uart_print("\r\n-- Bitwise Operations --\r\n");
    print_result("AND", a, "&",  b, a & b);
    print_result("OR",  a, "|",  b, a | b);
    print_result("XOR", a, "^",  b, a ^ b);
    print_result("NOT", a, "~",  0, ~a    );

    // --- Shifts (equivalent to multiply/divide by powers of 2)
    uart_print("\r\n-- Bit Shifts --\r\n");
    for (i = 1; i <= 4; i++) {
        uart_print("  0x00000001 << ");
        uart_print_uint(i);
        uart_print(" = ");
        uart_print_hex(1u << i);
        uart_print("\r\n");
    }

    // --- Fibonacci (addition only)
    uart_print("\r\n-- Fibonacci Sequence (first 12) --\r\n");
    compute_fibonacci();
    for (i = 0; i < FIB_COUNT; i++) {
        uart_print("  fib[");
        uart_print_uint(i);
        uart_print("] = ");
        uart_print_uint(fib[i]);
        uart_print("\r\n");
    }

    uart_print("\r\n=== Done ===\r\n");

    // Signal testbench: firmware completed successfully
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0x900DD00E;  // GOODDONE sentinel

    // Halt
    while (1);
}