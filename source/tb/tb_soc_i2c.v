// -----------------------------------------------------------------------------
// tb_soc_i2c.v — System testbench for apps/i2c_demo
//
// I2C slave is the shared behavioral model (i2c_slave_model.v).
// Pass: sentinel 0x12C900D0 on GPIO, and slave memory holds DE AD BE EF.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_i2c;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 2_000_000;
    parameter         ROM_FILE  = "firmware.hex";

    reg         clk, rst_n;
    wire        cpu_trap, timer_irq;
    wire        uart_tx;
    reg         uart_rx;
    wire [31:0] gpio_out, gpio_dir;
    reg  [31:0] gpio_in;
    wire        spi_sclk, spi_mosi, spi_cs_n;
    reg         spi_miso;

    // I2C open-drain bus with external pull-ups
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

    i2c_slave_model #(.ADDR(7'h28)) u_i2c_slave (.scl(i2c_scl), .sda(i2c_sda));

    uart_monitor #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .PREFIX("UART-MON"))
    u_mon (.clk(clk), .uart_tx(uart_tx));

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc_i2c.vcd");
        $dumpvars(0, tb_soc_i2c);
    end

    always @(posedge clk) if (cpu_trap) begin
        $display("FAIL: cpu_trap at %0t", $time); $finish;
    end

    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout at %0d cycles", TIMEOUT); $finish;
        end
    end

    initial begin
        uart_rx = 1; gpio_in = 0; spi_miso = 0;
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1;
        $display("INFO: reset released");

        @(posedge clk);
        while (gpio_out !== 32'h12C900D0) @(posedge clk);

        if (u_i2c_slave.mem[0] !== 8'hDE || u_i2c_slave.mem[1] !== 8'hAD ||
            u_i2c_slave.mem[2] !== 8'hBE || u_i2c_slave.mem[3] !== 8'hEF) begin
            $display("FAIL: slave memory = %0h %0h %0h %0h",
                      u_i2c_slave.mem[0], u_i2c_slave.mem[1],
                      u_i2c_slave.mem[2], u_i2c_slave.mem[3]);
            $finish;
        end
        $display("PASS: sentinel 0x12C900D0 and slave memory OK at cycle %0d",
                  cycle_count);
        $display("--- tb_soc_i2c: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire