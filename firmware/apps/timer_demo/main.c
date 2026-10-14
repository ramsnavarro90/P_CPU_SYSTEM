// timer_demo/main.c — 32-bit hardware timer polling demo

#include "soc.h"

#define TICKS       5
#define PERIOD      4999   // period = COMPARE+1 = 5000 cycles

int main(void) {
    GPIO_DIR  = 0xFFFFFFFF;
    GPIO_DATA = 0xDEADBEEF;

    uart_print("=== Timer Demo ===\r\n");
    uart_print("Period: ");
    uart_print_uint(PERIOD + 1);
    uart_print(" cycles\r\n\r\n");

    // Configure: compare value, then enable with auto-reload
    TIMER_COMPARE = PERIOD;
    TIMER_STATUS  = TIMER_MATCH;             // clear any stale flag
    TIMER_CTRL    = TIMER_EN | TIMER_AUTO_RELOAD;

    unsigned int tick;
    for (tick = 0; tick < TICKS; tick++) {
        // Poll for match
        while (!(TIMER_STATUS & TIMER_MATCH));
        TIMER_STATUS = TIMER_MATCH;          // clear flag

        uart_print("tick ");
        uart_print_uint(tick + 1);
        uart_print(" / ");
        uart_print_uint(TICKS);
        uart_print("\r\n");

        GPIO_DATA = 0xA0000000 | (tick + 1);
    }

    TIMER_CTRL = 0;                          // stop timer

    uart_print("\r\nTimer stopped.\r\n");
    uart_print("=== Done ===\r\n");

    GPIO_DATA = 0xA10CA10C;   // "ALOCALOC" sentinel
    while (1);
    return 0;
}