// tb_soc_timer.v — System testbench for timer_demo app

`timescale 1ns/1ps
`default_nettype none

module tb_soc_timer;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 5_000_000;
    parameter         ROM_FILE  = "firmware.hex";

    reg         clk, rst_n;
    wire        cpu_trap, timer_irq;
    wire        uart_tx;
    reg         uart_rx;
    wire [31:0] gpio_out, gpio_dir;
    reg  [31:0] gpio_in;
    wire        sclk, mosi, spi_cs_n;
    reg         miso;

    soc_top #(
        .ROM_FILE(ROM_FILE),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_trap(cpu_trap),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .gpio_out(gpio_out),
        .gpio_in(gpio_in),
        .gpio_dir(gpio_dir),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .spi_cs_n(spi_cs_n)
        .timer_irq(timer_irq)
    );

    uart_monitor #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .PREFIX("UART-MON"))
    u_mon (.clk(clk), .uart_tx(uart_tx));

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc_timer.vcd");
        $dumpvars(0, tb_soc_timer);
    end

    always @(posedge clk) if (cpu_trap) begin
        $display("FAIL: cpu_trap"); $finish;
    end

    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout after %0d cycles", TIMEOUT); $finish;
        end
    end

    initial begin
        uart_rx = 1;   // idle HIGH
        miso = 1'b0;
        gpio_in = 0;
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1;
        $display("INFO: reset released");

        // Wait for completion sentinel
        @(posedge clk);
        while (gpio_out !== 32'hA10CA10C) @(posedge clk);
        $display("PASS: timer_demo sentinel at cycle %0d", cycle_count);
        $display("--- tb_soc_timer: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire