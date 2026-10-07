/* link.ld — Linker script for PicoRV32 minimal SoC
 *
 * Address map must match soc_top.v address decoder:
 *   ROM  : 0x0000_0000 – 0x0000_0FFF   4 KB  (boot, read-only)
 *   SRAM : 0x8000_0000 – 0x8000_FFFF  64 KB  (data + stack)
 */

MEMORY {
    ROM  (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS {
    /* ---- Code and read-only data → ROM -------------------------------- */
    .text : {
        *(.text.init)       /* crt0 _start must land at address 0x0 */
        *(.text*)
        *(.rodata*)
    } > ROM

    /* LMA of .data (sits right after .text in ROM flash image) */
    _data_lma = LOADADDR(.data);

    /* ---- Initialized data: loaded from ROM, runs in SRAM -------------- */
    .data : {
        _data_start = .;
        *(.data*)
        _data_end   = .;
    } > SRAM AT > ROM

    /* ---- Zero-initialized data (BSS) ---------------------------------- */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end   = .;
    } > SRAM

    /* ---- Stack top (stack grows downward from top of SRAM) ------------ */
    _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
}