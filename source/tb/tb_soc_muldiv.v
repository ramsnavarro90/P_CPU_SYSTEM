// -----------------------------------------------------------------------------
// tb_soc_muldiv.v — System testbench for apps/muldiv
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_muldiv;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 50_000_000;
    parameter         ROM_FILE  = "firmware.hex";

    reg         clk, rst_n;
    wire        cpu_trap;
    wire        uart_tx;
    reg         uart_rx;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;
    reg  [31:0] gpio_in;
    wire sclk, mosi, spi_cs_n;
    reg  miso;
    wire        timer_irq;

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
        .uart_rx  (uart_rx),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .spi_cs_n(spi_cs_n)
        .timer_irq(timer_irq)
    );

    uart_monitor #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .PREFIX   ("UART-MON")
    ) u_uart_mon (
        .clk    (clk),
        .uart_tx(uart_tx)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

   initial begin
       $dumpfile("tb_soc_muldiv.vcd");
       $dumpvars(0, tb_soc_muldiv);
   end

    always @(posedge clk) begin
        if (cpu_trap) begin
            $display("FAIL: cpu_trap at time %0t", $time);
            $finish;
        end
    end

    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout after %0d cycles", TIMEOUT);
            $finish;
        end
    end

    initial begin
        uart_rx = 1;   // idle HIGH
        gpio_in = 32'b0;
        rst_n   = 1'b0;
        repeat(8) @(posedge clk);
        rst_n = 1'b1;
        $display("INFO: reset released — waiting for firmware...");

        @(posedge clk);
        while (gpio_out !== 32'hCA1CCA1C) @(posedge clk);
        $display("PASS: sentinel 0xCA1CCA1C seen at cycle %0d", cycle_count);
        $display("--- tb_soc_muldiv: all checks passed ---");
        $finish;
    end

    
    
    integer bench_start, bench_end;

    initial begin
        uart_rx = 1;   // idle HIGH
        miso = 1'b0;
        gpio_in = 32'b0;
        rst_n   = 1'b0;
        repeat(8) @(posedge clk);
        rst_n = 1'b1;

        // Wait for benchmark start marker
        @(posedge clk);
        while (gpio_out !== 32'hBEEF0000) @(posedge clk);
        bench_start = cycle_count;
        $display("INFO: benchmark started at cycle %0d", bench_start);

        // Wait for benchmark end marker
        while (gpio_out !== 32'hBEEF0001) @(posedge clk);
        bench_end = cycle_count;
        $display("INFO: benchmark ended   at cycle %0d", bench_end);
        $display("INFO: arithmetic cycles = %0d for 10000 iterations",
                  bench_end - bench_start);
        $display("INFO: cycles per iteration = %0d",
                  (bench_end - bench_start) / 10000);

        // Wait for completion sentinel
        while (gpio_out !== 32'hCA1CCA1C) @(posedge clk);
        $display("PASS: sentinel seen at cycle %0d", cycle_count);
        $display("--- tb_soc_muldiv: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire