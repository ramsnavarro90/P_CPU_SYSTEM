// -----------------------------------------------------------------------------
// wb_gpio.v — GPIO peripheral, Wishbone B4 slave
//
// Register map (word-aligned offsets from base address):
//   +0x00  DATA  — output data register (R/W)
//   +0x04  DIR   — direction register   (R/W)  1 = output, 0 = input
//
// gpio_out[i] reflects DATA[i] when DIR[i] = 1
// gpio_in[i]  is readable via DATA[i]  when DIR[i] = 0
// -----------------------------------------------------------------------------

`default_nettype none

module wb_gpio (
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
    // Physical pads
    input  wire        gpio_en,
    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_dir
);

    reg [31:0] data_reg;
    reg [31:0] dir_reg;

    assign gpio_out = gpio_en ? data_reg : 32'b0;
    assign gpio_dir = gpio_en ? dir_reg  : 32'b0;

    wire access = wb_cyc_i && wb_stb_i && !wb_ack_o;

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            data_reg <= 32'b0;
            dir_reg  <= 32'b0;
            wb_dat_o <= 32'b0;
        end else if (access) begin
            wb_ack_o <= 1'b1;
            if (wb_we_i) begin
                case (wb_adr_i[3:2])
                    2'b00: begin  // DATA
                        if (wb_sel_i[0]) data_reg[ 7: 0] <= wb_dat_i[ 7: 0];
                        if (wb_sel_i[1]) data_reg[15: 8] <= wb_dat_i[15: 8];
                        if (wb_sel_i[2]) data_reg[23:16] <= wb_dat_i[23:16];
                        if (wb_sel_i[3]) data_reg[31:24] <= wb_dat_i[31:24];
                    end
                    2'b01: begin  // DIR
                        if (wb_sel_i[0]) dir_reg[ 7: 0] <= wb_dat_i[ 7: 0];
                        if (wb_sel_i[1]) dir_reg[15: 8] <= wb_dat_i[15: 8];
                        if (wb_sel_i[2]) dir_reg[23:16] <= wb_dat_i[23:16];
                        if (wb_sel_i[3]) dir_reg[31:24] <= wb_dat_i[31:24];
                    end
                    default: ;
                endcase
            end else begin
                case (wb_adr_i[3:2])
                    2'b00: wb_dat_o <= (data_reg &  dir_reg)
                                     | (gpio_in  & ~dir_reg);
                    2'b01: wb_dat_o <= dir_reg;
                    default: wb_dat_o <= 32'hDEAD_BEEF;
                endcase
            end
        end
    end

endmodule
`default_nettype wire