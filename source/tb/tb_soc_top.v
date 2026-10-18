// -----------------------------------------------------------------------------
// tb_soc_top.v — System-level testbench for soc_top
//
// Boot sequence verified:
//   1. Reset released → CPU fetches from 0x0000_0000
//   2. crt0 executes (stack init, .data/.bss)
//   3. main() writes GPIO_DIR  = 0xFFFF_FFFF
//   4. main() writes GPIO_DATA = 0xDEAD_BEEF  ← sentinel check
//   5. Counter loop: gpio_out[31:24] == 0xA5, lower byte increments
//
// Failure conditions:
//   - cpu_trap asserted
//   - Sentinel not seen within TIMEOUT cycles
//   - Counter does not increment after sentinel
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_top;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter integer CLK_FREQ  = 100_000;   // CLKS_PER_BIT = 10
    parameter integer BAUD_RATE = 10_000;
    parameter TIMEOUT     = 500_000;        // max cycles before fail
    parameter CLK_PERIOD  = 10;            // ns

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst_n;
    wire        cpu_trap;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;
    reg  [31:0] gpio_in;
    wire        uart_tx;
    reg         uart_rx;
    wire sclk, mosi, spi_cs_n;
    reg  miso;
    wire        timer_irq;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    soc_top #(
        .ROM_FILE("firmware.hex"),
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
    // UART monitor — prints received lines to simulation console
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
    always  #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_soc_top.vcd");
        $dumpvars(0, tb_soc_top);
    end

    // -------------------------------------------------------------------------
    // Trap watchdog — fail immediately on cpu_trap
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
            $display("FAIL: timeout after %0d cycles — sentinel never seen",
                     TIMEOUT);
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus + checks
    // -------------------------------------------------------------------------
    integer i;
    reg [31:0] prev_gpio;

    initial begin
        uart_rx = 1;
        miso = 1'b0;
        gpio_in = 32'hCAFE_1234;   // arbitrary input value
        rst_n   = 1'b0;
        repeat(8) @(posedge clk);  // hold reset for 8 cycles
        rst_n   = 1'b1;
        $display("INFO: reset released at cycle %0d", cycle_count);

        // --- Check 1: wait for sentinel 0xDEAD_BEEF on gpio_out
        @(posedge clk);
        while (gpio_out !== 32'hDEAD_BEEF) begin
            @(posedge clk);
        end
        $display("PASS: sentinel 0xDEAD_BEEF seen on gpio_out at cycle %0d",
                  cycle_count);

        // --- Check 2: gpio_dir must be all-outputs
        if (gpio_dir !== 32'hFFFF_FFFF) begin
            $display("FAIL: gpio_dir = %0h, expected FFFFFFFF", gpio_dir);
            $finish;
        end
        $display("PASS: gpio_dir = 0xFFFFFFFF");

        // --- Check 3: counter increments with 0xA5 prefix
        // Wait for first counter write (lower byte moves away from EF)
        @(posedge clk);
        while (gpio_out[31:24] !== 8'hA5) @(posedge clk);
        $display("INFO: counter loop started at cycle %0d", cycle_count);

        prev_gpio = gpio_out;
        for (i = 0; i < 8; i = i + 1) begin
            // Wait for gpio_out to change
            @(posedge clk);
            while (gpio_out === prev_gpio) @(posedge clk);

            if (gpio_out[31:24] !== 8'hA5) begin
                $display("FAIL: counter prefix corrupted: %0h", gpio_out[31:24]);
                $finish;
            end
            if (gpio_out[7:0] !== ((prev_gpio[7:0] + 1) & 8'hFF)) begin
                $display("FAIL: counter not incrementing — prev=%0h cur=%0h",
                         prev_gpio, gpio_out);
                $finish;
            end
            $display("PASS: counter step %0d → gpio_out = 0x%0h", i, gpio_out);
            prev_gpio = gpio_out;
        end

        $display("--- tb_soc_top: all checks passed in %0d cycles ---",
                  cycle_count);
        $finish;
    end

endmodule
`default_nettype wire