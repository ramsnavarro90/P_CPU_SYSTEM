// muldiv/main.c — Multiplication and division via libgcc soft-routines
//
// PicoRV32 is RV32I only (no M extension).
// The compiler emits __mulsi3/__divsi3/__umodsi3 calls from libgcc,
// which implement these operations using only RV32I shift+add/sub.
//
// This demonstrates the cost of soft arithmetic vs hardware M extension.

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

// uart_print_uint usando restas (sin division) — como en arithmetic app
static void uart_print_uint(unsigned int val) {
    static const unsigned int pow10[] = {
        1000000000u, 100000000u, 10000000u, 1000000u,
        100000u,     10000u,     1000u,     100u,     10u, 1u
    };
    int i, digit, leading = 1;
    if (val == 0) { uart_putchar('0'); return; }
    for (i = 0; i < 10; i++) {
        digit = 0;
        while (val >= pow10[i]) { val -= pow10[i]; digit++; }
        if (digit > 0 || !leading) {
            uart_putchar('0' + digit);
            leading = 0;
        }
    }
}

static void print_op(const char *label,
                     unsigned int a, const char *op, unsigned int b,
                     unsigned int result) {
    uart_print("  ");
    uart_print_uint(a);
    uart_putchar(' ');
    uart_print(op);
    uart_putchar(' ');
    uart_print_uint(b);
    uart_print(" = ");
    uart_print_uint(result);
    uart_print("  [hex: ");
    uart_print_hex(result);
    uart_print("]  (");
    uart_print(label);
    uart_print(")\r\n");
}

// ---- Multiplication table ---------------------------------------------------
static void print_mul_table(unsigned int base, unsigned int rows) {
    unsigned int i;
    for (i = 1; i <= rows; i++) {
        uart_print("  ");
        uart_print_uint(base);
        uart_print(" x ");
        uart_print_uint(i);
        uart_print(" = ");
        uart_print_uint(base * i);   // __mulsi3 called here
        uart_print("\r\n");
    }
}

// ---- Division + remainder ---------------------------------------------------
static void print_divmod(unsigned int a, unsigned int b) {
    uart_print("  ");
    uart_print_uint(a);
    uart_print(" / ");
    uart_print_uint(b);
    uart_print(" = ");
    uart_print_uint(a / b);          // __udivsi3 called here
    uart_print("  remainder: ");
    uart_print_uint(a % b);          // __umodsi3 called here
    uart_print("\r\n");
}

// ---- Main -------------------------------------------------------------------
int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("=== RV32I Soft Mul/Div Demo ===\r\n");
    uart_print("(via libgcc __mulsi3/__udivsi3/__umodsi3)\r\n\r\n");

    // --- Basic operations
    uart_print("-- Basic Operations --\r\n");
    print_op("MUL",  12,  "*",   12,   12  *  12);
    print_op("MUL", 100,  "*", 1234,  100  * 1234);
    print_op("DIV", 1000, "/",    7, 1000  /    7);
    print_op("MOD", 1000, "%",    7, 1000  %    7);

    // --- Multiplication table of 7
    uart_print("\r\n-- Multiplication Table x7 --\r\n");
    print_mul_table(7, 10);

    // --- Division chain: successive halving
    uart_print("\r\n-- Successive Division by 2 --\r\n");
    unsigned int val = 65536;
    unsigned int i;
    for (i = 0; i < 8; i++) {
        uart_print("  ");
        uart_print_uint(val);
        uart_print(" / 2 = ");
        val = val / 2;               // __udivsi3 called here
        uart_print_uint(val);
        uart_print("\r\n");
    }

    // --- Power of 2 via multiplication
    uart_print("\r\n-- Powers of 2 via Multiplication --\r\n");
    unsigned int pw = 1;
    for (i = 0; i < 10; i++) {
        uart_print("  2^");
        uart_print_uint(i);
        uart_print(" = ");
        uart_print_uint(pw);
        uart_print("\r\n");
        pw = pw * 2;                 // __mulsi3 called here
    }

    // Agregar en main() dentro de -- Basic Operations --
    uart_print("\r\n-- Division + Remainder --\r\n");
    print_divmod(1000, 7);
    print_divmod(65535, 100);
    print_divmod(999999, 13);

    uart_print("\r\n=== Done ===\r\n");

    // Completion sentinel for testbench
    GPIO_DATA = 0xCA1CCA1C;   // "CALCCALC"
    while (1);
    return 0;
}