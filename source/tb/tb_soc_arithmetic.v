// -----------------------------------------------------------------------------
// tb_soc_arithmetic.v — System testbench for apps/arithmetic
//
// Verification is UART-only: the uart_monitor prints results to console.
// Pass condition: firmware reaches "=== Done ===" without cpu_trap.
// Fail conditions: cpu_trap asserted, or timeout before Done.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_arithmetic;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 2_000_000;
    parameter         ROM_FILE  = "firmware.hex";

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst_n;
    wire        cpu_trap;
    wire        uart_tx;
    reg         uart_rx;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;
    reg  [31:0] gpio_in;
    wire        sclk, mosi, spi_cs_n;
    reg         miso;
    wire        timer_irq;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    soc_top #(
        .ROM_FILE (ROM_FILE),
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .cpu_trap(cpu_trap),
        .gpio_out(gpio_out),
        .gpio_in (gpio_in),
        .gpio_dir(gpio_dir),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .spi_cs_n(spi_cs_n)
        .timer_irq(timer_irq)
    );

    // -------------------------------------------------------------------------
    // UART monitor
    // -------------------------------------------------------------------------
    uart_monitor #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .PREFIX   ("UART-MON")
    ) u_uart_mon (
        .clk    (clk),
        .uart_tx(uart_tx)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_soc_arithmetic.vcd");
        $dumpvars(0, tb_soc_arithmetic);
    end

    // -------------------------------------------------------------------------
    // Trap watchdog
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (cpu_trap) begin
            $display("FAIL: cpu_trap asserted at time %0t", $time);
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout after %0d cycles", TIMEOUT);
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus — just release reset and let UART monitor do the work
    // -------------------------------------------------------------------------
    initial begin
        uart_rx = 1;   // idle HIGH
        miso = 1'b0;
        gpio_in = 32'b0;
        rst_n   = 1'b0;
        repeat(8) @(posedge clk);
        rst_n = 1'b1;
        $display("INFO: reset released — waiting for firmware output...");

        // Wait for firmware completion sentinel on GPIO
        @(posedge clk);
        while (gpio_out !== 32'h900DD00E) @(posedge clk);
        $display("PASS: firmware completed — sentinel 0x900DD00E seen at cycle %0d",
                  cycle_count);
        $display("--- tb_soc_arithmetic: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire