// -----------------------------------------------------------------------------
// wb_cfg.v — SoC Configuration Register Block, Wishbone B4 slave
//
// Provides runtime configuration for SoC peripherals.
// SOC_ID and SOC_VER are read-only. All other registers are R/W.
//
// Register map (base: 0xB000_0000):
//   +0x00  SOC_ID     [R]    0x50435359 ("PCSY")
//   +0x04  SOC_VER    [R]    0x00000001
//   +0x08  UART_CTRL  [R/W]  bit[0] = uart_tx_en   (default = 1)
//   +0x0C  UART_BAUD  [R/W]  baud divisor = CLK_FREQ/BAUD_RATE (default)
//   +0x10  GPIO_CTRL  [R/W]  bit[0] = gpio_en       (default = 1)
//
// Parameters:
//   CLK_FREQ  : system clock in Hz — computes default baud divisor
//   BAUD_RATE : default baud rate
// -----------------------------------------------------------------------------

`default_nettype none

module wb_cfg #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115_200
)(
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
    // Config outputs to peripherals
    output wire        uart_en,
    output wire [15:0] uart_baud_div,
    output wire        gpio_en
);

    localparam [31:0] SOC_ID          = 32'h50435359;  // "PCSY"
    localparam [31:0] SOC_VER         = 32'h00000001;
    localparam [15:0] DEFAULT_BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg [31:0] uart_ctrl_r;
    reg [15:0] uart_baud_r;
    reg [31:0] gpio_ctrl_r;

    assign uart_en       = uart_ctrl_r[0];
    assign uart_baud_div = uart_baud_r;
    assign gpio_en       = gpio_ctrl_r[0];

    wire access = wb_cyc_i && wb_stb_i && !wb_ack_o;

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            uart_ctrl_r <= 32'h1;
            uart_baud_r <= DEFAULT_BAUD_DIV;
            gpio_ctrl_r <= 32'h1;
            wb_dat_o    <= 32'b0;
        end else if (access) begin
            wb_ack_o <= 1'b1;
            if (wb_we_i) begin
                case (wb_adr_i[4:2])
                    // 3'h0, 3'h1 : SOC_ID / SOC_VER — writes ignored
                    3'h2: begin  // UART_CTRL
                        if (wb_sel_i[0]) uart_ctrl_r[ 7: 0] <= wb_dat_i[ 7: 0];
                        if (wb_sel_i[1]) uart_ctrl_r[15: 8] <= wb_dat_i[15: 8];
                    end
                    3'h3: begin  // UART_BAUD
                        if (wb_sel_i[0]) uart_baud_r[ 7: 0] <= wb_dat_i[ 7: 0];
                        if (wb_sel_i[1]) uart_baud_r[15: 8] <= wb_dat_i[15: 8];
                    end
                    3'h4: begin  // GPIO_CTRL
                        if (wb_sel_i[0]) gpio_ctrl_r[ 7: 0] <= wb_dat_i[ 7: 0];
                        if (wb_sel_i[1]) gpio_ctrl_r[15: 8] <= wb_dat_i[15: 8];
                    end
                    default: ;
                endcase
            end else begin
                case (wb_adr_i[4:2])
                    3'h0: wb_dat_o <= SOC_ID;
                    3'h1: wb_dat_o <= SOC_VER;
                    3'h2: wb_dat_o <= uart_ctrl_r;
                    3'h3: wb_dat_o <= {16'b0, uart_baud_r};
                    3'h4: wb_dat_o <= gpio_ctrl_r;
                    default: wb_dat_o <= 32'hDEAD_BEEF;
                endcase
            end
        end
    end

endmodule
`default_nettype wire