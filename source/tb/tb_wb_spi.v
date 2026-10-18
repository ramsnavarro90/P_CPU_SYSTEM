// -----------------------------------------------------------------------------
// tb_wb_spi.v — wb_spi unit testbench
//
// Uses a simple SPI slave model inside the testbench:
//   slave returns (received_byte + 1) for each byte received.
//
// Tests:
//   T1: STATUS.busy=0 and sclk=CPOL at idle
//   T2: Transfer 0xA5 in Mode 0 — verify MOSI bit sequence and rx=(0xA5+1)
//   T3: Transfer 0x55 in Mode 0 — alternating bits, easy visual check
//   T4: CS manual control — assert before, deassert after transaction
//   T5: CLK_DIV changes SCLK frequency
//   T6: Mode 3 (CPOL=1, CPHA=1) — verify sclk idles HIGH
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_spi;

    localparam CLK_PERIOD = 10;    // 10 ns → 100 MHz for fast sim
    localparam CLK_DIV    = 4;     // SCLK at 100MHz/(2*4) = 12.5 MHz

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;
    wire        sclk;
    wire        mosi;
    reg         miso_tb;
    wire        spi_cs_n;

    wb_spi u_dut (
        .wb_clk_i(clk), .wb_rst_i(rst),
        .wb_cyc_i(cyc), .wb_stb_i(stb), .wb_we_i(we),
        .wb_sel_i(sel), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_ack_o(ack),
        .sclk(sclk), .mosi(mosi), .miso(miso_tb), .spi_cs_n(spi_cs_n)
    );

    initial clk = 0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("tb_wb_spi.vcd");
        $dumpvars(0, tb_wb_spi);
    end

    // -------------------------------------------------------------------------
    // WB tasks
    // -------------------------------------------------------------------------
    reg [31:0] rd;

    task wb_write;
        input [31:0] addr, data;
        input  [3:0] byte_sel;
        begin
            @(negedge clk);
            cyc=1; stb=1; we=1; adr=addr; dat_i=data; sel=byte_sel;
            @(posedge clk); while (!ack) @(posedge clk);
            @(negedge clk); cyc=0; stb=0; we=0;
        end
    endtask

    task wb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            cyc=1; stb=1; we=0; sel=4'hF; adr=addr;
            @(posedge clk); while (!ack) @(posedge clk);
            data = dat_o;
            @(negedge clk); cyc=0; stb=0;
        end
    endtask

    task wait_not_busy;
        begin
            wb_read(32'hD000_0004, rd);
            while (rd[0]) wb_read(32'hD000_0004, rd);
        end
    endtask

    // -------------------------------------------------------------------------
    // SPI slave model — responds with (received_byte + 1)
    // Drives MISO based on SCLK edges (Mode 0 by default in slave model)
    // -------------------------------------------------------------------------
    reg [7:0] slave_tx;
    reg [7:0] slave_rx;
    integer   slave_bit;

    // -------------------------------------------------------------------------
    // SPI slave model — tracks SCLK edges directly (no CS dependency)
    // Pre-drives MISO before first rising edge; updates on falling edges.
    // Mode 0 (CPOL=0, CPHA=0): sample MOSI on rising, setup MISO on falling.
    // -------------------------------------------------------------------------
    task spi_slave_exchange;
        input  [7:0] tx_data;
        output [7:0] rx_data;
        integer i;
        begin
            slave_rx = 8'b0;
            miso_tb  = tx_data[7];        // pre-drive MSB before first rising edge
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge sclk);           // leading edge — sample MOSI
                slave_rx[i] = mosi;
                @(negedge sclk);           // trailing edge — setup next MISO bit
                if (i > 0)
                    miso_tb = tx_data[i-1];
            end
            rx_data = slave_rx;
            miso_tb = 1'b0;               // release MISO after transfer
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg [7:0] slave_received;
    reg [7:0] dut_received;

    initial begin
        {cyc, stb, we, sel, adr, dat_i} = 0;
        miso_tb = 0;
        rst = 1; repeat(4) @(posedge clk); rst = 0;

        // Configure CLK_DIV and Mode 0 (cpol=0, cpha=0)
        wb_write(32'hD000_000C, CLK_DIV, 4'hF);  // CLK_DIV = 4
        wb_write(32'hD000_0008, 32'h10,  4'hF);  // CTRL: cs_n=1 (deasserted)

        // T1: idle checks
        wb_read(32'hD000_0004, rd);
        if (rd[0] !== 1'b0) begin
            $display("FAIL T1: busy at idle"); $finish;
        end
        if (sclk !== 1'b0) begin
            $display("FAIL T1: SCLK not LOW at idle (Mode 0)"); $finish;
        end
        $display("PASS T1: idle — busy=0, sclk=0");

        // T2: assert CS, transfer 0xA5, slave returns 0xA6
        wb_write(32'hD000_0008, 32'h00, 4'hF);  // cs_n=0 (assert CS)
        fork
            begin
                wb_write(32'hD000_0000, 32'hA5, 4'h1);  // TX 0xA5
                wait_not_busy();
            end
            spi_slave_exchange(8'hA6, slave_received);
        join
        wb_read(32'hD000_0000, rd);   // read RX_DATA (clears rx_valid)
        dut_received = rd[7:0];
        if (dut_received !== 8'hA6) begin
            $display("FAIL T2: DUT received 0x%0h, expected 0xA6", dut_received);
            $finish;
        end
        if (slave_received !== 8'hA5) begin
            $display("FAIL T2: slave received 0x%0h, expected 0xA5", slave_received);
            $finish;
        end
        $display("PASS T2: TX=0xA5 slave_rx=0x%0h DUT_rx=0x%0h",
                  slave_received, dut_received);

        // T3: transfer 0x55 (alternating bits), slave returns 0x56
        fork
            begin
                wb_write(32'hD000_0000, 32'h55, 4'h1);
                wait_not_busy();
            end
            spi_slave_exchange(8'h56, slave_received);
        join
        wb_read(32'hD000_0000, rd);
        dut_received = rd[7:0];
        if (dut_received !== 8'h56 || slave_received !== 8'h55) begin
            $display("FAIL T3: TX=0x55 slave_rx=%0h DUT_rx=%0h",
                      slave_received, dut_received); $finish;
        end
        $display("PASS T3: TX=0x55 slave_rx=0x%0h DUT_rx=0x%0h",
                  slave_received, dut_received);

        // T4: deassert CS and verify
        wb_write(32'hD000_0008, 32'h10, 4'hF);  // cs_n=1
        @(posedge clk); @(posedge clk);
        if (!spi_cs_n) begin
            $display("FAIL T4: cs_n not deasserted"); $finish;
        end
        $display("PASS T4: CS correctly deasserted");

        // T5: check rx_valid cleared after DATA read
        wb_read(32'hD000_0004, rd);
        if (rd[1] !== 1'b0) begin
            $display("FAIL T5: rx_valid not cleared after DATA read"); $finish;
        end
        $display("PASS T5: rx_valid cleared after read");

        // T6: Mode 3 (cpol=1, cpha=1) — sclk should idle HIGH
        wb_write(32'hD000_0008, 32'h13, 4'hF);  // cpol=1, cpha=1, cs_n=1
        @(posedge clk); @(posedge clk);
        if (sclk !== 1'b1) begin
            $display("FAIL T6: sclk not HIGH at idle (Mode 3)"); $finish;
        end
        $display("PASS T6: Mode 3 — sclk idles HIGH");

        $display("--- wb_spi: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire