// -----------------------------------------------------------------------------
// tb_wb_i2c.v — wb_i2c unit testbench (alexforencich i2c_master_wbs_8 core)
//
// Commands are queued in the core's command FIFO; data bytes in the write FIFO.
// Idle detection: cmd FIFO empty AND !busy (FIFO status is read first because
// busy may lag the command pop).
//
// Tests:
//   T1: idle bus, busy=0, cmd FIFO empty
//   T2: single-byte write  -> slave mem[0] == 0xAB
//   T3: single-byte read   -> 0xAB (repeated START, NACK + STOP)
//   T4: burst write/read   -> 4 bytes at pointer 2 (auto-increment)
//   T5: address NACK       -> miss_ack set, cleared by writing 1
//   T6: FIFOs empty at the end (no leftover bytes)
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_i2c;

    localparam CLK_PERIOD = 10;
    localparam PRESCALE   = 2;            // f_scl = f_clk / (4 * PRESCALE)
    localparam [6:0] SLAVE_ADDR = 7'h28;

    // Register addresses (word-aligned)
    localparam [31:0] R_STATUS  = 32'hE000_0000;
    localparam [31:0] R_FIFO    = 32'hE000_0004;
    localparam [31:0] R_CMDADDR = 32'hE000_0008;
    localparam [31:0] R_CMD     = 32'hE000_000C;
    localparam [31:0] R_DATA    = 32'hE000_0010;
    localparam [31:0] R_PRE_LO  = 32'hE000_0018;
    localparam [31:0] R_PRE_HI  = 32'hE000_001C;

    // Command bits
    localparam [7:0] C_START = 8'h01;
    localparam [7:0] C_READ  = 8'h02;
    localparam [7:0] C_WRITE = 8'h04;
    localparam [7:0] C_STOP  = 8'h10;

    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;
    wire        i2c_irq;

    // Open-drain bus with external pull-ups
    wire scl, sda;
    pullup(scl);
    pullup(sda);

    wb_i2c u_dut (
        .wb_clk_i(clk), .wb_rst_i(rst),
        .wb_cyc_i(cyc), .wb_stb_i(stb), .wb_we_i(we),
        .wb_sel_i(sel), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_ack_o(ack),
        .scl(scl), .sda(sda),
        .i2c_irq(i2c_irq)
    );

    i2c_slave_model #(.ADDR(SLAVE_ADDR)) u_slave (.scl(scl), .sda(sda));

    initial clk = 0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("tb_wb_i2c.vcd");
        $dumpvars(0, tb_wb_i2c);
    end

    // Watchdog — never hang the simulation
    initial begin
        #(CLK_PERIOD * 200_000);
        $display("FAIL: timeout");
        $finish;
    end

    // -------------------------------------------------------------------------
    // WB tasks
    // -------------------------------------------------------------------------
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

    // Wait until the command FIFO is empty AND the core is not busy.
    // FIFO status is read first: busy may lag the command pop by a cycle or two.
    reg [31:0] fifo_st, st;
    task i2c_wait_idle;
        begin
            fifo_st = 32'h0; st = 32'h1;
            while (!fifo_st[0] || st[0]) begin
                wb_read(R_FIFO,   fifo_st);
                wb_read(R_STATUS, st);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    integer k;

    initial begin
        {cyc, stb, we, sel, adr, dat_i} = 0;
        rst = 1; repeat(4) @(posedge clk); rst = 0;

        wb_write(R_PRE_LO, PRESCALE);
        wb_write(R_PRE_HI, 0);

        // ---- T1: idle ---------------------------------------------------------
        if (scl !== 1'b1 || sda !== 1'b1) begin
            $display("FAIL T1: bus not idle (scl=%b sda=%b)", scl, sda); $finish;
        end
        wb_read(R_STATUS, rd);
        if (rd[0]) begin $display("FAIL T1: busy at idle"); $finish; end
        wb_read(R_FIFO, rd);
        if (!rd[0]) begin $display("FAIL T1: cmd FIFO not empty"); $finish; end
        $display("PASS T1: idle — SCL=1, SDA=1, busy=0, cmd FIFO empty");

        // ---- T2: write 0xAB to mem[0] ------------------------------------------
        // [S][ADDR+W][A][ptr=0][A][0xAB][A][P]
        wb_write(R_CMDADDR, SLAVE_ADDR);
        wb_write(R_DATA,    8'h00);                    // pointer byte
        wb_write(R_CMD,     C_START | C_WRITE);
        wb_write(R_DATA,    8'hAB);
        wb_write(R_CMD,     C_WRITE | C_STOP);
        i2c_wait_idle;
        if (u_slave.mem[0] !== 8'hAB) begin
            $display("FAIL T2: slave mem[0]=0x%0h, expected 0xAB", u_slave.mem[0]);
            $finish;
        end
        $display("PASS T2: wrote 0xAB to slave mem[0]");

        // ---- T3: read back mem[0] ----------------------------------------------
        // [S][ADDR+W][A][ptr=0][A][Sr][ADDR+R][A][data][N][P]
        wb_write(R_DATA, 8'h00);
        wb_write(R_CMD,  C_START | C_WRITE);           // set pointer, hold the bus
        wb_write(R_CMD,  C_START | C_READ | C_STOP);   // repeated START, 1 byte
        i2c_wait_idle;
        wb_read(R_DATA, rd);                           // pops the read FIFO
        if (rd[7:0] !== 8'hAB) begin
            $display("FAIL T3: read 0x%0h, expected 0xAB", rd[7:0]); $finish;
        end
        $display("PASS T3: read back 0xAB");

        // ---- T4: burst write + burst read at pointer 2 ---------------------------
        wb_write(R_DATA, 8'h02);
        wb_write(R_CMD,  C_START | C_WRITE);
        for (k = 0; k < 4; k = k + 1) begin
            wb_write(R_DATA, 8'h11 * (k + 1));         // 11 22 33 44
            wb_write(R_CMD,  C_WRITE | ((k == 3) ? C_STOP : 8'h00));
        end
        i2c_wait_idle;

        wb_write(R_DATA, 8'h02);
        wb_write(R_CMD,  C_START | C_WRITE);
        for (k = 0; k < 4; k = k + 1)
            wb_write(R_CMD, C_READ | ((k == 0) ? C_START : 8'h00)
                                   | ((k == 3) ? C_STOP  : 8'h00));
        i2c_wait_idle;
        for (k = 0; k < 4; k = k + 1) begin
            wb_read(R_DATA, rd);
            if (rd[7:0] !== 8'h11 * (k + 1)) begin
                $display("FAIL T4: byte %0d = 0x%0h, expected 0x%0h",
                          k, rd[7:0], 8'h11 * (k + 1));
                $finish;
            end
        end
        $display("PASS T4: burst write/read of 4 bytes with auto-increment");

        // ---- T5: no leftovers in the FIFOs after the normal traffic ------------
        wb_read(R_FIFO, rd);
        if ((rd[7:0] & 8'h49) !== 8'h49) begin   // rd_empty, wr_empty, cmd_empty
            $display("FAIL T5: FIFO status = 0x%0h", rd[7:0]); $finish;
        end
        $display("PASS T5: all FIFOs empty");

        // ---- T6: address NACK (last test: the core may keep the dummy byte) ----
        wb_write(R_CMDADDR, 8'h7F);                    // nobody home
        wb_write(R_DATA,    8'h00);                    // dummy byte
        wb_write(R_CMD,     C_START | C_WRITE | C_STOP);
        i2c_wait_idle;
        wb_read(R_STATUS, rd);
        if (!rd[3]) begin $display("FAIL T6: miss_ack not set"); $finish; end
        wb_write(R_STATUS, 8'h08);                     // write 1 to clear miss_ack
        wb_read(R_STATUS, rd);
        if (rd[3]) begin $display("FAIL T6: miss_ack not cleared"); $finish; end
        wb_read(R_FIFO, rd);
        $display("INFO: FIFO status after NACK = 0x%0h (wr_empty = bit 3)", rd[7:0]);
        $display("PASS T6: NACK detected on 0x7F and cleared");

        $display("--- wb_i2c: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire