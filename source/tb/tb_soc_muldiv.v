// -----------------------------------------------------------------------------
// tb_soc_muldiv.v — System testbench for apps/muldiv
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_muldiv;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 5_000_000;
    parameter         ROM_FILE  = "firmware.hex";

    reg        clk, rst_n;
    wire       cpu_trap;
    wire       uart_tx;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;
    reg  [31:0] gpio_in;

    soc_top #(
        .ROM_FILE (ROM_FILE),
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .cpu_trap(cpu_trap),
        .uart_tx (uart_tx),
        .gpio_out(gpio_out),
        .gpio_in (gpio_in),
        .gpio_dir(gpio_dir)
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

endmodule
`default_nettype wire