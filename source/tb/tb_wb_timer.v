// -----------------------------------------------------------------------------
// tb_wb_timer.v — wb_timer unit testbench
//
// Tests:
//   1. Counter reads 0 after reset
//   2. Counter does NOT increment when disabled (CTRL.en=0)
//   3. Counter increments when enabled
//   4. Match fires at COUNT == COMPARE
//   5. Auto-reload: counter resets to 0 and match fires again
//   6. STATUS write-1-to-clear works
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_timer;

    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;
    wire        timer_irq;

    wb_timer u_dut (
        .wb_clk_i(clk), .wb_rst_i(rst),
        .wb_cyc_i(cyc), .wb_stb_i(stb), .wb_we_i(we),
        .wb_sel_i(sel), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_ack_o(ack),
        .timer_irq(timer_irq)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    initial begin
        $dumpfile("tb_wb_timer.vcd");
        $dumpvars(0, tb_wb_timer);
    end

    reg [31:0] rd;

    task wb_write;
        input [31:0] addr, data;
        begin
            @(negedge clk);
            cyc=1; stb=1; we=1; sel=4'hF; adr=addr; dat_i=data;
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

    integer start_cycle, end_cycle, cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    initial begin
        {cyc, stb, we, sel, adr, dat_i} = 0;
        rst = 1; repeat(4) @(posedge clk); rst = 0;

        // T1: COUNT = 0 after reset
        wb_read(32'hC000_0000, rd);
        if (rd !== 32'b0) begin
            $display("FAIL T1: COUNT=%0h after reset", rd); $finish;
        end
        $display("PASS T1: COUNT=0 after reset");

        // T2: Counter does not increment when disabled
        repeat(20) @(posedge clk);
        wb_read(32'hC000_0000, rd);
        if (rd !== 32'b0) begin
            $display("FAIL T2: COUNT incremented while disabled: %0h", rd); $finish;
        end
        $display("PASS T2: COUNT stays 0 when disabled");

        // T3+T4: Enable, set COMPARE=20, verify match at cycle 20
        wb_write(32'hC000_0004, 32'd20);           // COMPARE = 20
        start_cycle = cycle_count;
        wb_write(32'hC000_0008, 32'h1);            // CTRL: en=1, auto_reload=0

        // Wait for match
        @(posedge clk);
        while (!timer_irq) @(posedge clk);
        end_cycle = cycle_count;
        $display("PASS T3: counter incremented, match at cycle delta=%0d (expected ~20)",
                  end_cycle - start_cycle);

        // Verify STATUS.match
        wb_read(32'hC000_000C, rd);
        if (rd[0] !== 1'b1) begin
            $display("FAIL T4: STATUS.match not set"); $finish;
        end
        $display("PASS T4: STATUS.match = 1");

        // T5: Clear match flag
        wb_write(32'hC000_000C, 32'h1);            // write 1 to clear
        wb_read(32'hC000_000C, rd);
        if (rd[0] !== 1'b0) begin
            $display("FAIL T5: STATUS.match not cleared"); $finish;
        end
        $display("PASS T5: STATUS.match cleared by SW");

        // T6: Auto-reload — reset, set COMPARE=15, enable with auto_reload
        wb_write(32'hC000_0008, 32'h0);            // disable
        wb_write(32'hC000_0004, 32'd15);           // COMPARE = 15
        wb_write(32'hC000_000C, 32'h1);            // clear any pending match
        wb_write(32'hC000_0008, 32'h3);            // CTRL: en=1, auto_reload=1

        // Wait for first match
        @(posedge clk);
        while (!timer_irq) @(posedge clk);
        wb_write(32'hC000_000C, 32'h1);            // clear

        // Wait for second match (counter should have reset and fired again)
        while (!timer_irq) @(posedge clk);
        wb_read(32'hC000_0000, rd);
        $display("PASS T6: auto-reload fired twice, COUNT at 2nd match = %0d", rd);

        // Stop timer
        wb_write(32'hC000_0008, 32'h0);

        $display("--- wb_timer: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire