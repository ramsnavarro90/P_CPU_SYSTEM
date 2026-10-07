// -----------------------------------------------------------------------------
// tb_wb_rom.v — Directed testbench for wb_rom
//
// Tests:
//   1. Reset clears outputs
//   2. Four sequential word reads match known hex content
//   3. ACK is asserted for exactly one cycle per transaction
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_rom;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst;
    reg         cyc, stb;
    reg  [31:0] adr;
    wire [31:0] dat_o;
    wire        ack;

    // -------------------------------------------------------------------------
    // DUT instantiation — override MEM_FILE to point to test vectors
    // -------------------------------------------------------------------------
    wb_rom #(
        .DEPTH   (8),
        .MEM_FILE("test_rom.hex")
    ) u_dut (
        .wb_clk_i(clk),
        .wb_rst_i(rst),
        .wb_cyc_i(cyc),
        .wb_stb_i(stb),
        .wb_adr_i(adr),
        .wb_dat_o(dat_o),
        .wb_ack_o(ack)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_wb_rom.vcd");
        $dumpvars(0, tb_wb_rom);
    end

    // -------------------------------------------------------------------------
    // WB read task
    // -------------------------------------------------------------------------
    reg [31:0] read_data;
    integer    ack_count;

    task wb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            ack_count = 0;
            @(negedge clk);
            cyc = 1; stb = 1; adr = addr;
            // Wait for ACK, count how many cycles it stays high
            @(posedge clk);
            while (!ack) @(posedge clk);
            data = dat_o;
            // Verify ACK deasserts next cycle
            @(posedge clk);
            if (ack) begin
                $display("FAIL [addr=%0h]: ACK held high for >1 cycle", addr);
                $finish;
            end
            @(negedge clk);
            cyc = 0; stb = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Expected values — must match test_rom.hex
    // -------------------------------------------------------------------------
    reg [31:0] expected [0:7];
    initial begin
        expected[0] = 32'hDEADBEEF;
        expected[1] = 32'hCAFEBABE;
        expected[2] = 32'h12345678;
        expected[3] = 32'hABCD1234;
        expected[4] = 32'h00000001;
        expected[5] = 32'h00000002;
        expected[6] = 32'h00000004;
        expected[7] = 32'h00000008;
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    integer idx;

    initial begin
        cyc = 0; stb = 0; adr = 0;
        rst = 1;
        repeat(4) @(posedge clk);
        rst = 0;
        @(negedge clk);

        // --- Test 1: reset cleared outputs
        if (dat_o !== 32'b0)
            $display("WARN: dat_o not zero after reset (got %0h)", dat_o);

        // --- Test 2: sequential reads
        for (idx = 0; idx < 8; idx = idx + 1) begin
            wb_read(idx << 2, read_data);   // byte address = word_index * 4
            if (read_data !== expected[idx]) begin
                $display("FAIL [word %0d]: expected %0h, got %0h",
                         idx, expected[idx], read_data);
                $finish;
            end else begin
                $display("PASS [word %0d]: %0h", idx, read_data);
            end
        end

        $display("--- wb_rom: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire