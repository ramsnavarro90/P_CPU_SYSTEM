// main.c — Minimal firmware: toggle GPIO output
//
// GPIO register map (matches soc_top.v, wb_gpio):
//   0x9000_0000  →  output data register
//   0x9000_0004  →  direction register  (1 = output, 0 = input)

#define GPIO_BASE   0x90000000UL
#define GPIO_DATA   (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR    (*(volatile unsigned int *)(GPIO_BASE + 0x04))

int main(void) {
    // Set all pins as output
    GPIO_DIR  = 0xFFFFFFFF;

    // Write a recognizable sentinel — easy to spot in waveform
    GPIO_DATA = 0xDEADBEEF;

    // Count up on the lower 8 bits
    // In simulation this generates visible toggling activity on gpio_out
    unsigned int count = 0;
    while (1) {
        GPIO_DATA = 0xA5000000 | (count & 0xFF);
        count++;
    }

    return 0;   // unreachable
}