// -----------------------------------------------------------------------------
// tb_wb_i2c.v — wb_i2c unit testbench
//
// Open-drain simulation:
//   pullup primitives simulate external pull-up resistors.
//   Slave drives SDA with assign: 1'bz = release, 1'b0 = drive_low.
//
// I2C slave model at address 0x28:
//   8 bytes of internal memory.
//   Write: [S][ADDR+W][A][MEM_ADDR][A][DATA...][A][P]
//   Read:  [S][ADDR+W][A][MEM_ADDR][A][RS][ADDR+R][A][DATA][N][P]
//
// Tests:
//   T1: bus idle — scl=1, sda=1, busy=0
//   T2: write 0xAB to mem[0]
//   T3: read back mem[0] — verify 0xAB
//   T4: NACK on wrong address
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_wb_i2c;

    localparam CLK_PERIOD = 10;
    localparam PRESCALE   = 2;       // SCL = clk / (4*(2+1)) ≈ fast for sim
    localparam SLAVE_ADDR = 7'h28;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst;
    reg         cyc, stb, we;
    reg  [3:0]  sel;
    reg  [31:0] adr, dat_i;
    wire [31:0] dat_o;
    wire        ack;
    wire        i2c_irq;

    // Open-drain bus — pull-ups simulate external resistors
    wire  scl;
    wire  sda;
    pullup(scl);
    pullup(sda);

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    wb_i2c u_dut (
        .wb_clk_i(clk), .wb_rst_i(rst),
        .wb_cyc_i(cyc), .wb_stb_i(stb), .wb_we_i(we),
        .wb_sel_i(sel), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_ack_o(ack),
        .scl(scl), .sda(sda),
        .i2c_irq(i2c_irq)
    );

    initial clk = 0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("tb_wb_i2c.vcd");
        $dumpvars(0, tb_wb_i2c);
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

    task wait_busy_clear;
        begin
            wb_read(32'hE000_0000, rd);  // Status
            while (rd[0]) wb_read(32'hE000_0000, rd);
        end
    endtask

    // -------------------------------------------------------------------------
    // I2C slave model (address 0x28)
    // Drives SDA open-drain: 1'bz = release, 1'b0 = drive_low
    // -------------------------------------------------------------------------
    reg [7:0] slave_mem [0:7];
    reg       slave_sda_r;

    assign sda = slave_sda_r ? 1'bz : 1'b0;

    integer si;
    initial begin
        for (si = 0; si < 8; si = si + 1)
            slave_mem[si] = 8'hC0 + si;
        slave_sda_r = 1'b1;   // release (idle)
    end

    // Slave bit tasks
    task slave_send_ack;
        begin
            @(negedge scl);
            slave_sda_r = 1'b0;   // drive SDA low = ACK
            @(posedge scl);       // master reads ACK
            @(negedge scl);
            slave_sda_r = 1'b1;   // release
        end
    endtask

    task slave_read_byte;
        output [7:0] data;
        integer i;
        begin
            data = 8'b0;
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge scl);
                data[i] = sda;   // sample after rising edge
                @(negedge scl);
            end
        end
    endtask

    task slave_send_byte;
        input [7:0] data;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                @(negedge scl);
                slave_sda_r = (data[i] == 1'b0) ? 1'b0 : 1'b1;
                @(posedge scl);
            end
            @(negedge scl);
            slave_sda_r = 1'b1;   // release for master ACK/NACK
        end
    endtask

    // -------------------------------------------------------------------------
    // Slave process — runs as background fork
    // -------------------------------------------------------------------------
    reg [7:0] s_addr_b, s_mem_addr, s_data;
    reg       s_rw;

    initial begin
        forever begin
            // Wait for START: SDA falls while SCL high
            @(negedge sda);
            if (scl) begin
                // Valid START condition
                slave_read_byte(s_addr_b);
                s_rw = s_addr_b[0];

                if (s_addr_b[7:1] == SLAVE_ADDR) begin
                    slave_send_ack();
                    if (!s_rw) begin
                        // WRITE: receive mem_addr then data
                        slave_read_byte(s_mem_addr);
                        slave_send_ack();
                        begin : wr_blk
                            integer wi;
                            for (wi = 0; wi < 4; wi = wi + 1) begin
                                slave_read_byte(s_data);
                                slave_mem[s_mem_addr + wi] = s_data;
                                slave_send_ack();
                            end
                        end
                    end else begin
                        // READ: send byte from memory
                        slave_send_byte(slave_mem[s_mem_addr]);
                        // Wait for master NACK (master releases SDA = 1)
                        @(posedge scl); @(negedge scl);
                    end
                end
                // else: address mismatch → no ACK
            end
            // else: data transition (not START) → loop back
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg nack;

    initial begin
        {cyc, stb, we, sel, adr, dat_i} = 0;
        rst = 1; repeat(4) @(posedge clk); rst = 0;

        // Configure prescaler
        wb_write(32'hE000_0018, PRESCALE, 4'h1);  // Pre LO
        wb_write(32'hE000_001C, 8'h00,    4'h1);  // Pre HI

        // T1: idle checks
        if (scl !== 1'b1) begin $display("FAIL T1: SCL not high"); $finish; end
        if (sda !== 1'b1) begin $display("FAIL T1: SDA not high"); $finish; end
        wb_read(32'hE000_0000, rd);
        if (rd[0]) begin $display("FAIL T1: busy at idle"); $finish; end
        $display("PASS T1: idle — SCL=1, SDA=1, busy=0");

        // T2: write 0xAB to slave mem[0]
        // [S][0x50][A][0x00][A][0xAB][A][P]
        wb_write(32'hE000_0008, SLAVE_ADDR, 4'h1); // Cmd Addr = 0x28
        wb_write(32'hE000_0010, 8'h00,      4'h1); // Data = mem_addr 0
        wb_write(32'hE000_000C, 8'h05,      4'h1); // CMD: start(1)+write(4)=0x05
        wait_busy_clear();

        wb_write(32'hE000_0010, 8'hAB, 4'h1);      // Data = 0xAB
        wb_write(32'hE000_000C, 8'h14, 4'h1);      // CMD: write(4)+stop(16)=0x14
        wait_busy_clear();

        // Check slave received 0xAB
        repeat(10) @(posedge clk);
        if (slave_mem[0] !== 8'hAB) begin
            $display("FAIL T2: slave_mem[0]=0x%0h, expected 0xAB", slave_mem[0]);
            $finish;
        end
        $display("PASS T2: wrote 0xAB to slave_mem[0]");

        // T3: read back mem[0]
        // [S][0x50][A][0x00][A][RS][0x51][A][data][N][P]
        wb_write(32'hE000_0008, SLAVE_ADDR,   4'h1); // Addr = 0x28
        wb_write(32'hE000_0010, 8'h00,        4'h1); // mem_addr
        wb_write(32'hE000_000C, 8'h05,        4'h1); // start+write
        wait_busy_clear();

        // Repeated start + read address
        wb_write(32'hE000_0008, SLAVE_ADDR,   4'h1); // Addr = 0x28
        wb_write(32'hE000_000C, 8'h03,        4'h1); // start(1)+read(2)=0x03
        wait_busy_clear();

        // Wait for data in FIFO
        wb_read(32'hE000_0010, rd);
        if (rd[7:0] !== 8'hAB) begin
            $display("FAIL T3: read 0x%0h, expected 0xAB", rd[7:0]);
            $finish;
        end
        $display("PASS T3: read back 0xAB");

        // T4: NACK on wrong address 0x7F
        wb_write(32'hE000_0008, 7'h7F,  4'h1);  // wrong addr
        wb_write(32'hE000_000C, 8'h55,  4'h1);  // start+write+stop = 0x55
        wait_busy_clear();
        wb_read(32'hE000_0000, rd);
        if (!rd[3]) begin  // miss_ack bit
            $display("FAIL T4: miss_ack not set for unknown address"); $finish;
        end
        $display("PASS T4: NACK detected for address 0x7F (miss_ack=1)");

        $display("--- wb_i2c: all tests passed ---");
        $finish;
    end

endmodule
`default_nettype wire