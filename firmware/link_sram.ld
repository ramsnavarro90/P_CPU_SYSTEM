/* link_sram.ld — Application image that runs from SRAM (loaded by bootloader)
 *
 * The whole image (.text/.rodata/.data) is loaded from flash to 0x8000_0000.
 * LMA == VMA, so crt0's .data copy is a harmless self-copy.
 * Image must fit in the 32 KB boot window; stack grows down from top of SRAM.
 */

MEMORY {
    SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS {
    .text : {
        *(.text.init)       /* crt0 _start must be first: bootloader jumps here */
        *(.text*)
        *(.rodata*)
        *(.srodata*)
    } > SRAM

    _data_lma = LOADADDR(.data);

    .data : {
        _data_start = .;
        *(.data*)
        *(.sdata*)
        _data_end   = .;
    } > SRAM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        _bss_end   = .;
    } > SRAM

    _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);

    ASSERT(_bss_end <= ORIGIN(SRAM) + 0x8000, "app image too large for the 32 KB boot window")
}