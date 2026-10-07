// -----------------------------------------------------------------------------
// soc_top.v — Minimal PicoRV32 SoC
//
// Memory map:
//   0x0000_0000 – 0x0000_0FFF  Boot ROM  (4 KB, read-only)
//   0x8000_0000 – 0x8000_FFFF  Data SRAM (64 KB)
//   0x9000_0000 – 0x9000_00FF  GPIO
//
// Parameters:
//   ROM_FILE : hex image loaded by wb_rom via $readmemh
// -----------------------------------------------------------------------------

`default_nettype none

module soc_top #(
    parameter ROM_FILE = "firmware.hex"
)(
    input  wire        clk,
    input  wire        rst_n,
    // Status
    output wire        cpu_trap,
    // GPIO pads
    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_dir
);

// -----------------------------------------------------------------------------
// Wishbone master bus (CPU drives)
// -----------------------------------------------------------------------------
wire [31:0] wbm_adr;
wire [31:0] wbm_dat_m2s;
wire [31:0] wbm_dat_s2m;
wire        wbm_we;
wire  [3:0] wbm_sel;
wire        wbm_stb;
wire        wbm_ack;
wire        wbm_cyc;

// -----------------------------------------------------------------------------
// Per-slave signals
// -----------------------------------------------------------------------------
wire [31:0] rom_dat_o,  sram_dat_o,  gpio_dat_o;
wire        rom_ack,    sram_ack,    gpio_ack;

// -----------------------------------------------------------------------------
// Address decoder
// -----------------------------------------------------------------------------
wire sel_rom  = (wbm_adr[31:12] == 20'h00000);
wire sel_sram = (wbm_adr[31:16] == 16'h8000 );
wire sel_gpio = (wbm_adr[31: 8] == 24'h900000);

wire rom_stb  = wbm_stb & sel_rom;
wire sram_stb = wbm_stb & sel_sram;
wire gpio_stb = wbm_stb & sel_gpio;

assign wbm_dat_s2m = sel_rom  ? rom_dat_o  :
                     sel_sram ? sram_dat_o :
                     sel_gpio ? gpio_dat_o :
                     32'hDEAD_BEEF;

assign wbm_ack = rom_ack | sram_ack | gpio_ack;

// -----------------------------------------------------------------------------
// CPU — PicoRV32 (Wishbone wrapper)
// -----------------------------------------------------------------------------
picorv32_wb #(
    .ENABLE_MUL          (0),
    .ENABLE_REGS_DUALPORT(1)
) u_cpu (
    .wb_clk_i  (clk),
    .wb_rst_i  (~rst_n),
    .wbm_adr_o (wbm_adr),
    .wbm_dat_o (wbm_dat_m2s),
    .wbm_dat_i (wbm_dat_s2m),
    .wbm_we_o  (wbm_we),
    .wbm_sel_o (wbm_sel),
    .wbm_stb_o (wbm_stb),
    .wbm_ack_i (wbm_ack),
    .wbm_cyc_o (wbm_cyc),
    .trap      (cpu_trap),
    .irq       (32'b0)
);

// -----------------------------------------------------------------------------
// Boot ROM
// -----------------------------------------------------------------------------
wb_rom #(
    .DEPTH   (1024),
    .MEM_FILE(ROM_FILE)
) u_rom (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(rom_stb),
    .wb_adr_i(wbm_adr),
    .wb_dat_o(rom_dat_o),
    .wb_ack_o(rom_ack)
);

// -----------------------------------------------------------------------------
// Data SRAM
// -----------------------------------------------------------------------------
wb_sram #(
    .DEPTH(16384)
) u_sram (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(sram_stb),
    .wb_we_i (wbm_we),
    .wb_sel_i(wbm_sel),
    .wb_adr_i(wbm_adr),
    .wb_dat_i(wbm_dat_m2s),
    .wb_dat_o(sram_dat_o),
    .wb_ack_o(sram_ack)
);

// -----------------------------------------------------------------------------
// GPIO
// -----------------------------------------------------------------------------
wb_gpio u_gpio (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(gpio_stb),
    .wb_we_i (wbm_we),
    .wb_sel_i(wbm_sel),
    .wb_adr_i(wbm_adr),
    .wb_dat_i(wbm_dat_m2s),
    .wb_dat_o(gpio_dat_o),
    .wb_ack_o(gpio_ack),
    .gpio_out(gpio_out),
    .gpio_in (gpio_in),
    .gpio_dir(gpio_dir)
);

endmodule
`default_nettype wire