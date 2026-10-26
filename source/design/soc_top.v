// -----------------------------------------------------------------------------
// soc_top.v — Minimal PicoRV32 SoC
//
// Memory map:
//   0x0000_0000 – 0x0000_0FFF  Boot ROM  (4 KB, read-only)
//   0x8000_0000 – 0x8000_FFFF  Data SRAM (64 KB)
//   0x9000_0000 – 0x9000_00FF  GPIO      (DATA + DIR)
//   0xA000_0000 – 0xA000_00FF  UART TX   (DATA + STATUS)
//   0xB000_0000 – 0xB000_00FF  CFG       (SOC_ID, SOC_VER,
//                                         UART_CTRL, UART_BAUD,
//                                         GPIO_CTRL)
//
// Parameters:
//   ROM_FILE : hex image loaded by wb_rom via $readmemh
// -----------------------------------------------------------------------------

`default_nettype none

module soc_top #(
    parameter ROM_FILE = "firmware.hex",
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  wire        clk,
    input  wire        rst_n,
    // Status
    output wire        cpu_trap,
    // GPIO pads
    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_dir,
    // UART pads
    output wire        uart_tx,
    input  wire        uart_rx,
    // SPI pads
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        spi_cs_n,
    // I2C pads
    inout  wire        i2c_scl,
    inout  wire        i2c_sda,
    // Timer pads
    output wire        timer_irq
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
wire sel_rom   = (wbm_adr[31:12] == 20'h00000);
wire sel_sram  = (wbm_adr[31:16] == 16'h8000 );
wire sel_gpio  = (wbm_adr[31: 8] == 24'h900000);
wire sel_uart  = (wbm_adr[31:16] == 16'hA000);
wire sel_cfg   = (wbm_adr[31:16] == 16'hB000);
wire sel_timer = (wbm_adr[31:16] == 16'hC000);
wire sel_spi   = (wbm_adr[31:16] == 16'hD000);
wire sel_i2c  = (wbm_adr[31:16] == 16'hE000);

wire timer_stb = wbm_stb & sel_timer;
wire cfg_stb   = wbm_stb & sel_cfg;
wire spi_stb   = wbm_stb & sel_spi;
wire i2c_stb   = wbm_stb & sel_i2c;

wire rom_stb  = wbm_stb & sel_rom;
wire sram_stb = wbm_stb & sel_sram;
wire gpio_stb = wbm_stb & sel_gpio;
wire uart_stb = wbm_stb & sel_uart;

// SPI signals
wire [31:0] spi_dat_o;
wire        spi_ack;

// I2C signals
wire [31:0] i2c_dat_o;
wire        i2c_ack;
wire        i2c_irq;

// Timer signals
wire [31:0] timer_dat_o;
wire        timer_ack;

// Config signals
wire [31:0] cfg_dat_o;
wire        cfg_ack;

// UART signals
wire        uart_en;
wire [15:0] uart_baud_div;
wire        gpio_en;
wire [31:0] uart_dat_o;
wire        uart_ack;

// Wishbnone read mux
assign wbm_dat_s2m = sel_rom   ? rom_dat_o   :
                     sel_sram  ? sram_dat_o  :
                     sel_gpio  ? gpio_dat_o  :
                     sel_uart  ? uart_dat_o  :
                     sel_cfg   ? cfg_dat_o   :
                     sel_timer ? timer_dat_o :
                     sel_spi   ? spi_dat_o   :
                     sel_i2c   ? i2c_dat_o   :
                     32'hDEAD_BEEF;

assign wbm_ack = rom_ack | sram_ack | gpio_ack | uart_ack
               | cfg_ack | timer_ack | spi_ack | i2c_ack;

// -----------------------------------------------------------------------------
// CPU — PicoRV32 (Wishbone wrapper)
// -----------------------------------------------------------------------------
picorv32_wb #(
    .ENABLE_MUL          (1),   // <-- enables picorv32_pcpi_mul
    .ENABLE_DIV          (1),   // <-- enables picorv32_pcpi_div
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
    .irq       ({30'b0, 
                 i2c_irq,
                 timer_irq}
                 )
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
// Config
// -----------------------------------------------------------------------------
wb_cfg #(
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_cfg (
    .wb_clk_i    (clk),
    .wb_rst_i    (~rst_n),
    .wb_cyc_i    (wbm_cyc),
    .wb_stb_i    (cfg_stb),
    .wb_we_i     (wbm_we),
    .wb_sel_i    (wbm_sel),
    .wb_adr_i    (wbm_adr),
    .wb_dat_i    (wbm_dat_m2s),
    .wb_dat_o    (cfg_dat_o),
    .wb_ack_o    (cfg_ack),
    .uart_en     (uart_en),
    .uart_baud_div(uart_baud_div),
    .gpio_en     (gpio_en)
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
    .gpio_en(gpio_en),
    .gpio_out(gpio_out),
    .gpio_in (gpio_in),
    .gpio_dir(gpio_dir)
);

// -----------------------------------------------------------------------------
// UART
// -----------------------------------------------------------------------------
wb_uart u_uart (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(uart_stb),
    .wb_we_i (wbm_we),
    .wb_sel_i(wbm_sel),
    .wb_adr_i(wbm_adr),
    .wb_dat_i(wbm_dat_m2s),
    .wb_dat_o(uart_dat_o),
    .wb_ack_o(uart_ack),
    .baud_div(uart_baud_div),
    .uart_en (uart_en),
    .uart_rx (uart_rx),
    .uart_tx (uart_tx)
);

// -----------------------------------------------------------------------------
// Timer
// -----------------------------------------------------------------------------
wb_timer u_timer (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(timer_stb),
    .wb_we_i (wbm_we),
    .wb_sel_i(wbm_sel),
    .wb_adr_i(wbm_adr),
    .wb_dat_i(wbm_dat_m2s),
    .wb_dat_o(timer_dat_o),
    .wb_ack_o(timer_ack),
    .timer_irq(timer_irq)
);

// -----------------------------------------------------------------------------
// SPI
// -----------------------------------------------------------------------------
wb_spi u_spi (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(spi_stb),
    .wb_we_i (wbm_we),
    .wb_sel_i(wbm_sel),
    .wb_adr_i(wbm_adr),
    .wb_dat_i(wbm_dat_m2s),
    .wb_dat_o(spi_dat_o),
    .wb_ack_o(spi_ack),
    .sclk    (sclk),
    .mosi    (mosi),
    .miso    (miso),
    .spi_cs_n(spi_cs_n)
);

// -----------------------------------------------------------------------------
// I2C
// -----------------------------------------------------------------------------
wb_i2c u_i2c (
    .wb_clk_i(clk),
    .wb_rst_i(~rst_n),
    .wb_cyc_i(wbm_cyc),
    .wb_stb_i(i2c_stb),
    .wb_we_i (wbm_we),
    .wb_sel_i(wbm_sel),
    .wb_adr_i(wbm_adr),
    .wb_dat_i(wbm_dat_m2s),
    .wb_dat_o(i2c_dat_o),
    .wb_ack_o(i2c_ack),
    .scl     (i2c_scl),
    .sda     (i2c_sda),
    .i2c_irq (i2c_irq)
);

endmodule
`default_nettype wire