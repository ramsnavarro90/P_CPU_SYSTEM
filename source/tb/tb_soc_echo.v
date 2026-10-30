// tb_soc_echo.v — System testbench for uart_echo app
// Drives 8 known bytes on uart_rx; verifies each is echoed on uart_tx.

`timescale 1ns/1ps
`default_nettype none

module tb_soc_echo;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 2_000_000;
    parameter         ROM_FILE  = "firmware.hex";

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg        clk, rst_n;
    wire       cpu_trap, timer_irq;
    wire       uart_tx;
    reg        uart_rx;
    wire [31:0] gpio_out, gpio_dir;
    reg  [31:0] gpio_in;
    wire        sclk, mosi, spi_cs_n;
    reg         miso;
    wire        i2c_scl;
    wire        i2c_sda;
    pullup      (i2c_scl);
    pullup      (i2c_sda);

    soc_top #(.ROM_FILE(ROM_FILE), .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE))
    u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_trap(cpu_trap),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .gpio_out(gpio_out),
        .gpio_in(gpio_in),
        .gpio_dir(gpio_dir),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .spi_cs_n(spi_cs_n),
        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda),
        .timer_irq(timer_irq)
    );

    uart_monitor #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .PREFIX("UART-MON")
    ) u_mon (
        .clk(clk),
        .uart_tx(uart_tx)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc_echo.vcd");
        $dumpvars(0, tb_soc_echo);
    end

    always @(posedge clk) if (cpu_trap) begin
        $display("FAIL: cpu_trap"); $finish;
    end

    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout"); $finish;
        end
    end

    // ---- Tasks ----------------------------------------------------------
    reg [7:0] echo_byte;
    integer   bit_i;

    task send_byte;
        input [7:0] data;
        integer     sbit_i;
        begin
            // Start bit
            @(negedge clk); uart_rx = 0;
            repeat(CLKS_PER_BIT) @(posedge clk);
            // Data bits
            for (sbit_i = 0; sbit_i < 8; sbit_i = sbit_i + 1) begin
                @(negedge clk); uart_rx = data[sbit_i];
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            // Stop bit
            @(negedge clk); uart_rx = 1;
            repeat(CLKS_PER_BIT * 2) @(posedge clk); // extra margin
        end
    endtask

    task receive_byte;  // capture echo from uart_tx
        output [7:0] data;
        begin
            @(negedge uart_tx);
            repeat(CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                data[bit_i] = uart_tx;
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            repeat(CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // Test bytes to echo
    reg [7:0] test_bytes [0:7];
    integer   i;
    initial begin
        uart_rx = 1;   // idle HIGH
        miso = 1'b0;
        test_bytes[0] = 8'h41;  // 'A'
        test_bytes[1] = 8'h42;  // 'B'
        test_bytes[2] = 8'h43;  // 'C'
        test_bytes[3] = 8'h31;  // '1'
        test_bytes[4] = 8'h32;  // '2'
        test_bytes[5] = 8'hAA;
        test_bytes[6] = 8'h55;
        test_bytes[7] = 8'hFF;
    end

    initial begin
        uart_rx = 1; gpio_in = 0;
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1;
        $display("INFO: reset released");

        // Wait for banner to finish — firmware writes 0xEC000000 when ready
        @(posedge clk);
        while (gpio_out !== 32'hEC000000) @(posedge clk);
        $display("INFO: firmware ready for echo at cycle %0d", cycle_count);

        // Wait for last banner byte stop bit to fully complete
        repeat(CLKS_PER_BIT * 12) @(posedge clk);

        // Send and verify echo for each byte
        for (i = 0; i < 8; i = i + 1) begin
            fork
                send_byte(test_bytes[i]);
                receive_byte(echo_byte);
            join
            if (echo_byte !== test_bytes[i]) begin
                $display("FAIL: echo[%0d] expected 0x%0h got 0x%0h",
                          i, test_bytes[i], echo_byte);
                $finish;
            end
            $display("PASS: echo[%0d] = 0x%0h ('%c')",
                      i, echo_byte,
                      (echo_byte >= 32 && echo_byte < 127) ? echo_byte : 8'h3F);
        end

        // Wait for completion sentinel
        while (gpio_out !== 32'hEC40EC40) @(posedge clk);
        $display("PASS: sentinel 0xEC40EC40 at cycle %0d", cycle_count);
        $display("--- tb_soc_echo: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire