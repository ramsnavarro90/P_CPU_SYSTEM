// -----------------------------------------------------------------------------
// tb_wb_sram.v — Directed testbench for wb_sram
//
// Tests:
//   1. Full 32-bit write → read-back
//   2. Byte-lane enables (write individual bytes, verify others unchanged)
//   3. Address independence (two different locations, no aliasing)
//   4. ACK width = 1 cycle
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_sram;

    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;

    wb_sram #(.DEPTH(256)) u_dut (
        .wb_clk_i(clk),
        .wb_rst_i(rst),
        .wb_cyc_i(cyc),
        .wb_stb_i(stb),
        .wb_we_i (we),
        .wb_sel_i(sel),
        .wb_adr_i(adr),
        .wb_dat_i(dat_i),
        .wb_dat_o(dat_o),
        .wb_ack_o(ack)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_wb_sram.vcd");
        $dumpvars(0, tb_wb_sram);
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
            @(posedge clk);
            while (!ack) @(posedge clk);
            @(negedge clk);
            cyc = 0; stb = 0; we = 0; sel = 4'b0;
        end
    endtask

    reg [31:0] rd;

    task wb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            cyc = 1; stb = 1; we = 0; sel = 4'b1111; adr = addr;
            @(posedge clk);
            while (!ack) @(posedge clk);
            data = dat_o;
            // Verify ACK = 1 cycle
            @(posedge clk);
            if (ack) begin
                $display("FAIL: ACK held high >1 cycle on read addr=%0h", addr);
                $finish;
            end
            @(negedge clk);
            cyc = 0; stb = 0;
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

        // --- Test 1: full word write / read-back
        wb_write(32'h8000_0000, 32'hDEAD_BEEF, 4'b1111);
        wb_read (32'h8000_0000, rd);
        if (rd !== 32'hDEAD_BEEF) begin
            $display("FAIL T1: expected DEADBEEF, got %0h", rd); $finish;
        end else $display("PASS T1: full word write/read");

        // --- Test 2: byte-lane enables
        // Write 0x00FF00FF with all lanes, then overwrite only byte 1 (0xAA)
        wb_write(32'h8000_0004, 32'h00FF00FF, 4'b1111);
        wb_write(32'h8000_0004, 32'hXXXXAAXX, 4'b0010); // only byte 1
        wb_read (32'h8000_0004, rd);
        if (rd !== 32'h00FFAAFF) begin
            $display("FAIL T2: expected 00FFAAFF, got %0h", rd); $finish;
        end else $display("PASS T2: byte-lane enable");

        // --- Test 3: address independence
        wb_write(32'h8000_0008, 32'h1111_1111, 4'b1111);
        wb_write(32'h8000_000C, 32'h2222_2222, 4'b1111);
        wb_read (32'h8000_0008, rd);
        if (rd !== 32'h1111_1111) begin
            $display("FAIL T3a: aliasing on addr 8"); $finish;
        end
        wb_read (32'h8000_000C, rd);
        if (rd !== 32'h2222_2222) begin
            $display("FAIL T3b: aliasing on addr C"); $finish;
        end
        $display("PASS T3: address independence");

        $display("--- wb_sram: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire