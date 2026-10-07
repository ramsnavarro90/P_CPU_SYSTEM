// crt0.S — C runtime startup for PicoRV32 SoC
// Responsibilities: init stack, copy .data ROM→SRAM, zero BSS, call main.

    .section .text.init
    .global  _start
    .type    _start, @function

_start:
    // ----------------------------------------------------------------
    // Stack pointer — _stack_top defined in link.ld (top of SRAM)
    // ----------------------------------------------------------------
    la      sp, _stack_top

    // ----------------------------------------------------------------
    // Copy .data section: ROM load address → SRAM run address
    // ----------------------------------------------------------------
    la      t0, _data_lma        // source: where linker placed it in ROM
    la      t1, _data_start      // destination: SRAM VMA
    la      t2, _data_end
copy_data:
    bge     t1, t2, clear_bss   // skip if section is empty
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       copy_data

    // ----------------------------------------------------------------
    // Zero BSS
    // ----------------------------------------------------------------
clear_bss:
    la      t0, _bss_start
    la      t1, _bss_end
1:
    bge     t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    // ----------------------------------------------------------------
    // Jump to C entry point
    // ----------------------------------------------------------------
    call    main

    // ----------------------------------------------------------------
    // main() returned — halt
    // ----------------------------------------------------------------
halt:
    ebreak
    j       halt