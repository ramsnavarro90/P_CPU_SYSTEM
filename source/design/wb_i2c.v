// -----------------------------------------------------------------------------
// wb_i2c.v — I2C Master, 32-bit Wishbone B4 wrapper
//
// Wraps alexforencich/verilog-i2c i2c_master_wbs_8.
// SCL/SDA are true inout open-drain — OEN resolved internally.
//
// Register map (base: 0xE000_0000), each 8-bit reg at word offset:
//   +0x00  Status    (R)   bit[0]=busy, [1]=bus_ctrl, [2]=bus_act, [3]=miss_ack
//   +0x04  FIFO Stat (R)   FIFO fill/overflow flags
//   +0x08  Cmd Addr  (W)   bits[6:0] = 7-bit I2C target address
//   +0x0C  Command   (W)   bit[0]=start, [1]=read, [2]=write, [3]=wr_mult, [4]=stop
//   +0x10  Data      (R/W) read/write data byte
//   +0x18  Pre LO    (R/W) prescaler low byte
//   +0x1C  Pre HI    (R/W) prescaler high byte
//
// Open-drain model:
//   core_*_t = 1 → release (1'bz, pull-up takes line high)
//   core_*_t = 0 → drive low (1'b0)
// -----------------------------------------------------------------------------

`default_nettype none

module wb_i2c (
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire  [3:0] wb_sel_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack_o,
    // I2C open-drain bidirectional — pull-ups external
    inout  wire        scl,
    inout  wire        sda,
    // Interrupt
    output wire        i2c_irq
);

    // -------------------------------------------------------------------------
    // Tristate signals from core
    // -------------------------------------------------------------------------
    wire core_scl_t;   // 1=release, 0=drive_low
    wire core_sda_t;   // 1=release, 0=drive_low
    wire core_scl_o;
    wire core_sda_o;

    // Open-drain: drive 0 when active, else release (Z → pull-up → 1)
    assign scl = core_scl_t ? 1'bz : 1'b0;
    assign sda = core_sda_t ? 1'bz : 1'b0;

    // -------------------------------------------------------------------------
    // 32-bit → 8-bit WB adapter
    // adr[4:2] selects the 8-bit register (0..7)
    // -------------------------------------------------------------------------
    wire [7:0] wbs_dat_r;
    wire       wbs_ack;
    wire       wbs_stb = wb_cyc_i && wb_stb_i && !wb_ack_o;

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            wb_dat_o <= 32'b0;
        end else if (wbs_stb && wbs_ack) begin
            wb_ack_o <= 1'b1;
            wb_dat_o <= {24'b0, wbs_dat_r};
        end
    end

    // -------------------------------------------------------------------------
    // alexforencich i2c_master_wbs_8 instance
    // -------------------------------------------------------------------------
    i2c_master_wbs_8 u_i2c (
        .clk         (wb_clk_i),
        .rst         (wb_rst_i),
        // Wishbone 8-bit
        .wbs_adr_i   (wb_adr_i[4:2]),   // word addr → 8-bit reg index
        .wbs_dat_i   (wb_dat_i[7:0]),
        .wbs_dat_o   (wbs_dat_r),
        .wbs_we_i    (wb_we_i),
        //.wbs_sel_i   (wb_sel_i[0]),
        .wbs_stb_i   (wbs_stb),
        .wbs_ack_o   (wbs_ack),
        .wbs_cyc_i   (wb_cyc_i),
        // I2C physical
        .i2c_scl_i   (scl),
        .i2c_scl_o   (core_scl_o),
        .i2c_scl_t   (core_scl_t),
        .i2c_sda_i   (sda),
        .i2c_sda_o   (core_sda_o),
        .i2c_sda_t   (core_sda_t)
        // Interrupt
        //.interrupt   (i2c_irq)
    );

endmodule
`default_nettype wire