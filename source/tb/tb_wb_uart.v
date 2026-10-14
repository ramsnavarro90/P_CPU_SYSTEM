// -----------------------------------------------------------------------------
// tb_wb_uart.v — UART TX+RX unit testbench
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_uart;

    localparam integer CLK_FREQ     = 100_000;
    localparam integer BAUD_RATE    = 10_000;
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam [15:0]  BAUD_DIV     = CLKS_PER_BIT;
    localparam integer CLK_PERIOD   = 10;

    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;
    wire        uart_tx;
    reg         uart_rx_tb;     // testbench drives RX line

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
        .uart_tx (uart_tx),
        .uart_rx (uart_rx_tb)
    );

    initial clk = 0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("tb_wb_uart.vcd");
        $dumpvars(0, tb_wb_uart);
    end

    // -------------------------------------------------------------------------
    // WB tasks
    // -------------------------------------------------------------------------
    task wb_write;
        input [31:0] addr, data;
        input  [3:0] byte_sel;
        begin
            @(negedge clk);
            cyc = 1; stb = 1; we = 1;
            adr = addr; dat_i = data; sel = byte_sel;
            @(posedge clk); while (!ack) @(posedge clk);
            @(negedge clk); cyc = 0; stb = 0; we = 0;
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
            @(negedge clk); cyc = 0; stb = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // TX monitor task (same as before)
    // -------------------------------------------------------------------------
    reg [7:0] rx_byte;
    integer   bit_i;

    task uart_receive;
        output [7:0] data;
        begin
            @(negedge uart_tx);
            repeat(CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                data[bit_i] = uart_tx;
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            if (!uart_tx) begin
                $display("FAIL: TX stop bit not HIGH"); $finish;
            end
            repeat(CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // RX driver task — drives uart_rx_tb with an 8N1 frame
    // -------------------------------------------------------------------------
    task uart_send;
        input [7:0] data;
        integer     sbit_i;
        begin
            // Start bit
            @(negedge clk); uart_rx_tb = 0;
            repeat(CLKS_PER_BIT) @(posedge clk);
            // 8 data bits (LSB first)
            for (sbit_i = 0; sbit_i < 8; sbit_i = sbit_i + 1) begin
                @(negedge clk); uart_rx_tb = data[sbit_i];
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            // Stop bit
            @(negedge clk); uart_rx_tb = 1;
            repeat(CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        {cyc, stb, we, sel, adr, dat_i} = 0;
        uart_rx_tb = 1;   // idle HIGH
        rst = 1;
        repeat(4) @(posedge clk);
        rst = 0;

        // === TX tests (same as before) =======================================
        if (!uart_tx) begin
            $display("FAIL T1: uart_tx not HIGH at idle"); $finish;
        end
        $display("PASS T1: uart_tx idles HIGH");

        wb_read(32'hA000_0004, rd);
        if (rd[0] !== 1'b0) begin
            $display("FAIL T2: tx_busy at idle"); $finish;
        end
        $display("PASS T2: tx_busy=0 at idle");

        fork
            wb_write(32'hA000_0000, 32'h55, 4'b0001);
            begin uart_receive(rx_byte);
                if (rx_byte !== 8'h55) begin
                    $display("FAIL T3: TX expected 0x55, got 0x%0h", rx_byte); $finish;
                end
                $display("PASS T3: TX 0x55 correct");
            end
        join

        fork
            wb_write(32'hA000_0000, 32'hA5, 4'b0001);
            begin uart_receive(rx_byte);
                if (rx_byte !== 8'hA5) begin
                    $display("FAIL T4: TX expected 0xA5, got 0x%0h", rx_byte); $finish;
                end
                $display("PASS T4: TX 0xA5 correct");
            end
        join

        // === RX tests =========================================================

        // T5: RX_STATUS idle — rx_ready must be 0
        wb_read(32'hA000_000C, rd);
        if (rd[0] !== 1'b0) begin
            $display("FAIL T5: rx_ready set at idle"); $finish;
        end
        $display("PASS T5: rx_ready=0 at idle");

        // T6: send 0xB7, verify RX_STATUS and RX_DATA
        uart_send(8'hB7);
        // Wait long enough for byte to complete (stop bit + margin)
        repeat(CLKS_PER_BIT * 2) @(posedge clk);
        wb_read(32'hA000_000C, rd);  // RX_STATUS
        if (rd[0] !== 1'b1) begin
            $display("FAIL T6: rx_ready not set after receive"); $finish;
        end
        $display("PASS T6: rx_ready=1 after receiving 0xB7");
        wb_read(32'hA000_0008, rd);  // RX_DATA (clears rx_ready)
        if (rd[7:0] !== 8'hB7) begin
            $display("FAIL T7: RX_DATA expected 0xB7, got 0x%0h", rd[7:0]); $finish;
        end
        $display("PASS T7: RX_DATA = 0xB7");

        // T8: rx_ready cleared after reading RX_DATA
        wb_read(32'hA000_000C, rd);
        if (rd[0] !== 1'b0) begin
            $display("FAIL T8: rx_ready not cleared after read"); $finish;
        end
        $display("PASS T8: rx_ready cleared after RX_DATA read");

        // T9: send 0xC3 and verify
        uart_send(8'hC3);
        repeat(CLKS_PER_BIT * 2) @(posedge clk);
        wb_read(32'hA000_0008, rd);
        if (rd[7:0] !== 8'hC3) begin
            $display("FAIL T9: RX_DATA expected 0xC3, got 0x%0h", rd[7:0]); $finish;
        end
        $display("PASS T9: RX_DATA = 0xC3");

        $display("--- wb_uart: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire