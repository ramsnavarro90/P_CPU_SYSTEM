// -----------------------------------------------------------------------------
// tb_soc_i2c.v — System testbench for apps/i2c_demo
// Implements the same I2C slave model as the unit test.
// Open-drain: bus = master_o & slave_o
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_soc_i2c;

    parameter integer CLK_FREQ  = 100_000;
    parameter integer BAUD_RATE = 10_000;
    parameter integer TIMEOUT   = 5_000_000;
    parameter         ROM_FILE  = "firmware.hex";
    parameter         SLAVE_ADDR = 7'h28;

    reg         clk, rst_n;
    wire        cpu_trap, timer_irq;
    wire        uart_tx;
    reg         uart_rx;
    wire [31:0] gpio_out, gpio_dir;
    reg  [31:0] gpio_in;
    wire        spi_sclk, spi_mosi, spi_cs_n;
    reg         spi_miso;
    wire        i2c_scl;
    wire        i2c_sda;
    reg         scl_slave;
    reg         sda_slave;
    reg         scl_bus, sda_bus;
    pullup      (i2c_scl);
    pullup      (i2c_sda);

    soc_top #(
        .ROM_FILE(ROM_FILE),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE))
    u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_trap(cpu_trap),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .gpio_out(gpio_out),
        .gpio_in(gpio_in),
        .gpio_dir(gpio_dir),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda),
        .timer_irq(timer_irq)
    );

    uart_monitor #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .PREFIX("UART-MON"))
    u_mon (
        .clk(clk),
        .uart_tx(uart_tx)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc_i2c.vcd");
        $dumpvars(0, tb_soc_i2c);
    end

    always @(posedge clk) if (cpu_trap) begin
        $display("FAIL: cpu_trap"); $finish;
    end

    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("FAIL: timeout at %0d cycles", TIMEOUT); $finish;
        end
    end

    // -------------------------------------------------------------------------
    // I2C slave model (same as unit test)
    // -------------------------------------------------------------------------
    reg [7:0] slave_mem [0:7];
    integer   si;

    task slave_ack_task;
        begin
            // SCL is already LOW when called — drive SDA low immediately
            sda_slave = 1'b0;
            @(posedge scl_bus);   // master raises SCL
            @(negedge scl_bus);   // master lowers SCL
            sda_slave = 1'b1;     // release SDA
        end
    endtask

    task slave_read_byte_task;
        output [7:0] data;
        integer i; reg b;
        begin
            data = 8'b0;
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge scl_bus); data[i] = sda_bus;
                @(negedge scl_bus);
            end
        end
    endtask

    task slave_send_byte_task;
        input [7:0] data;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                @(negedge scl_bus);
                sda_slave = data[i];
                @(posedge scl_bus);
                @(negedge scl_bus);
                sda_slave = 1'b1;
            end
        end
    endtask

    initial begin
        for (si = 0; si < 8; si = si + 1)
            slave_mem[si] = 8'h00;
        scl_slave = 1'b1;
        sda_slave = 1'b1;

        forever begin
            reg [7:0] addr_b, mem_addr_b, data_b;
            reg       rw;

            // Wait for START condition: SDA falls while SCL HIGH
            @(negedge sda_bus);
            if (scl_bus) begin    // SCL high → valid START

                slave_read_byte_task(addr_b);
                rw = addr_b[0];

                if (addr_b[7:1] == SLAVE_ADDR) begin
                    slave_ack_task();

                    if (!rw) begin
                        // WRITE: read memory address then data bytes
                        slave_read_byte_task(mem_addr_b);
                        slave_ack_task();

                        begin : wr_loop
                            integer wr_i;
                            for (wr_i = 0; wr_i < 4; wr_i = wr_i + 1) begin
                                slave_read_byte_task(data_b);
                                slave_mem[mem_addr_b + wr_i] = data_b;
                                slave_ack_task();
                            end
                        end

                    end else begin
                        // READ: send byte from memory
                        slave_send_byte_task(slave_mem[mem_addr_b]);
                        @(posedge scl_bus);
                        @(negedge scl_bus);
                    end

                end
                // Address mismatch → no ACK

            end
            // SCL was low → data transition, not START → loop back silently
        end

    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        uart_rx = 1;
        gpio_in = 0;
        spi_miso = 0;
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1;
        $display("INFO: reset released");

        @(posedge clk);
        while (gpio_out !== 32'h12C900D0) @(posedge clk);
        $display("PASS: sentinel 0x12C900D0 at cycle %0d — I2C OK",
                  cycle_count);
        $display("--- tb_soc_i2c: all checks passed ---");
        $finish;
    end

endmodule
`default_nettype wire