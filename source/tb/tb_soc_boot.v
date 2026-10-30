// -----------------------------------------------------------------------------
// tb_soc_boot.v — Boot-from-flash system test
//
// ROM holds the bootloader; flash holds apps/arithmetic linked to run from SRAM.
// Checks:
//   1. Bootloader reports "image verified" (GPIO 0xB007600D), never BAD codes
//   2. SRAM holds exactly the flash payload (word by word)
//   3. The application runs from SRAM and reaches its sentinel 0x900DD00E
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_boot;

    parameter integer CLK_FREQ   = 100_000;
    parameter integer BAUD_RATE  = 10_000;
    parameter integer TIMEOUT    = 4_000_000;
    parameter         ROM_FILE   = "firmware.hex";
    parameter         FLASH_FILE = "flash.hex";

    reg         clk, rst_n;
    wire        cpu_trap, timer_irq;
    wire        uart_tx;
    reg         uart_rx;
    wire [31:0] gpio_out, gpio_dir;
    reg  [31:0] gpio_in;
    wire        spi_sclk, spi_mosi, spi_miso, spi_cs_n;

    wire i2c_scl, i2c_sda;
    pullup(i2c_scl);
    pullup(i2c_sda);

    soc_top #(.ROM_FILE(ROM_FILE), .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE))
    u_dut (
        .clk(clk), .rst_n(rst_n), .cpu_trap(cpu_trap),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .gpio_out(gpio_out), .gpio_in(gpio_in), .gpio_dir(gpio_dir),
        .timer_irq(timer_irq),
        .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso), .spi_cs_n(spi_cs_n),
        .i2c_scl(i2c_scl), .i2c_sda(i2c_sda)
    );

    spi_flash_model #(.FILE(FLASH_FILE)) u_flash (
        .sclk(spi_sclk), .cs_n(spi_cs_n), .mosi(spi_mosi), .miso(spi_miso)
    );

    uart_monitor #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .PREFIX("UART-MON"))
    u_mon (.clk(clk), .uart_tx(uart_tx));

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc_boot.vcd");
        $dumpvars(0, tb_soc_boot);
    end

    always @(posedge clk) if (cpu_trap) begin
        $display("FAIL: cpu_trap at %0t", $time); $finish;
    end

    // Bootloader failure codes: 0xB007BAD0..2
    always @(posedge clk)
        if (gpio_out[31:4] === 28'hB007BAD) begin
            $display("FAIL: bootloader reported error 0x%08h", gpio_out); $finish;
        end

    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout at %0d cycles", TIMEOUT); $finish;
        end
    end

    integer     w, nwords;
    reg  [31:0] exp_word;

    initial begin
        uart_rx = 1; gpio_in = 0;
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1;
        $display("INFO: reset released");

        // ---- 1. bootloader verified the image ---------------------------------
        @(posedge clk);
        while (gpio_out !== 32'hB007600D) @(posedge clk);
        $display("PASS: bootloader verified flash image at cycle %0d", cycle_count);

        // ---- 2. SRAM == flash payload (header is 12 bytes) -----------------------
        nwords = {u_flash.mem[7], u_flash.mem[6], u_flash.mem[5], u_flash.mem[4]} / 4;
        for (w = 0; w < nwords; w = w + 1) begin
            exp_word = {u_flash.mem[12 + 4*w + 3], u_flash.mem[12 + 4*w + 2],
                        u_flash.mem[12 + 4*w + 1], u_flash.mem[12 + 4*w]};
            if (u_dut.u_sram.mem[w] !== exp_word) begin
                $display("FAIL: SRAM[%0d] = 0x%08h, flash payload = 0x%08h",
                          w, u_dut.u_sram.mem[w], exp_word);
                $finish;
            end
        end
        $display("PASS: SRAM holds %0d words identical to the flash payload", nwords);

        // ---- 3. application runs from SRAM ---------------------------------------
        while (gpio_out !== 32'h900DD00E) @(posedge clk);
        $display("PASS: app sentinel 0x900DD00E at cycle %0d — running from SRAM",
                  cycle_count);
        $display("--- tb_soc_boot: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire