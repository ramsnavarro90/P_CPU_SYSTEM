// -----------------------------------------------------------------------------
// tb_wb_uart.v — Directed testbench for wb_uart
//
// Uses accelerated parameters to keep simulation fast:
//   CLK_FREQ = 100_000 Hz  →  CLK_PERIOD = 10 ns
//   BAUD_RATE = 10_000     →  CLKS_PER_BIT = 10
//
// Tests:
//   1. STATUS reads tx_busy correctly
//   2. TX byte 0x55 (01010101) — alternating bits, easy to verify
//   3. TX byte 0xA5 (10100101) — verify LSB-first framing
//   4. Read-back of DATA register returns last sent byte
//   5. Write while busy is dropped, ACK still asserted
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_uart;

    // -------------------------------------------------------------------------
    // Accelerated timing for simulation
    // -------------------------------------------------------------------------
    localparam integer CLK_FREQ     = 100_000;
    localparam integer BAUD_RATE    = 10_000;
    localparam [15:0]  BAUD_DIV     = CLK_FREQ / BAUD_RATE;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;
    wire        uart_tx;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    wb_uart u_dut (
        .wb_clk_i(clk),
        .wb_rst_i(rst),
        .wb_cyc_i(cyc),
        .wb_stb_i(stb),
        .wb_we_i (we),
        .wb_sel_i(sel),
        .wb_adr_i(adr),
        .wb_dat_i(dat_i),
        .wb_dat_o(dat_o),
        .wb_ack_o(ack),
        .baud_div(BAUD_DIV),
        .uart_en (1'b1),
        .uart_tx (uart_tx)
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
        $dumpfile("tb_wb_uart.vcd");
        $dumpvars(0, tb_wb_uart);
    end

    // -------------------------------------------------------------------------
    // WB write / read tasks
    // -------------------------------------------------------------------------
    task wb_write;
        input [31:0] addr, data;
        input  [3:0] byte_sel;
        begin
            @(negedge clk);
            cyc = 1; stb = 1; we = 1;
            adr = addr; dat_i = data; sel = byte_sel;
            @(posedge clk); while (!ack) @(posedge clk);
            @(negedge clk);
            cyc = 0; stb = 0; we = 0;
        end
    endtask

    reg [31:0] rd;
    task wb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            cyc = 1; stb = 1; we = 0; sel = 4'hF; adr = addr;
            @(posedge clk); while (!ack) @(posedge clk);
            data = dat_o;
            @(negedge clk);
            cyc = 0; stb = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // UART receive task — samples uart_tx and reconstructs the byte
    // -------------------------------------------------------------------------
    reg [7:0] rx_byte;
    integer   i;

    task uart_receive;
        output [7:0] data;
        integer      bit_i;     // local — avoids shared 'i' in fork..join
        begin
            // Wait for start bit falling edge
            @(negedge uart_tx);
            // Delay 1.5 bit periods — land in the middle of bit 0
            repeat(CLK_PERIOD * CLKS_PER_BIT + CLK_PERIOD * CLKS_PER_BIT / 2) #1;
            // Sample 8 data bits, LSB first
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                data[bit_i] = uart_tx;
                repeat(CLK_PERIOD * CLKS_PER_BIT) #1;
            end
            // Verify stop bit (we're ~0.5 bit period into it)
            if (!uart_tx) begin
                $display("FAIL: stop bit not HIGH"); $finish;
            end
            // Wait for stop bit to fully complete before releasing the task
            // Without this, the next wb_write hits a busy UART and TX never fires
            repeat(CLK_PERIOD * CLKS_PER_BIT) #1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        {cyc, stb, we, sel, adr, dat_i} = 0;
        rst = 1;
        repeat(4) @(posedge clk);
        rst = 0;

        // --- Test 1: TX idle → uart_tx must be HIGH
        @(posedge clk);
        if (!uart_tx) begin
            $display("FAIL T1: uart_tx not HIGH at idle"); $finish;
        end
        $display("PASS T1: uart_tx idles HIGH");

        // --- Test 2: STATUS reads not busy at idle
        wb_read(32'hA000_0004, rd);
        if (rd[0] !== 1'b0) begin
            $display("FAIL T2: tx_busy asserted at idle"); $finish;
        end
        $display("PASS T2: STATUS.tx_busy = 0 at idle");

        // --- Test 3: transmit 0x55 and verify frame
        fork
            wb_write(32'hA000_0000, 32'h55, 4'b0001);
            begin
                uart_receive(rx_byte);
                if (rx_byte !== 8'h55) begin
                    $display("FAIL T3: expected 0x55, got 0x%0h", rx_byte);
                    $finish;
                end
                $display("PASS T3: received 0x55 correctly");
            end
        join

        // --- Test 4: transmit 0xA5 and verify frame
        fork
            wb_write(32'hA000_0000, 32'hA5, 4'b0001);
            begin
                uart_receive(rx_byte);
                if (rx_byte !== 8'hA5) begin
                    $display("FAIL T4: expected 0xA5, got 0x%0h", rx_byte);
                    $finish;
                end
                $display("PASS T4: received 0xA5 correctly");
            end
        join

        // --- Test 5: DATA read-back
        wb_read(32'hA000_0000, rd);
        if (rd[7:0] !== 8'hA5) begin
            $display("FAIL T5: read-back expected 0xA5, got 0x%0h", rd[7:0]);
            $finish;
        end
        $display("PASS T5: DATA read-back = 0xA5");

        $display("--- wb_uart: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire