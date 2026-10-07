// -----------------------------------------------------------------------------
// wb_sram.v — Data SRAM, Wishbone B4 slave (read/write)
//
// - Single-cycle registered ACK
// - Byte-lane write enable via wb_sel_i[3:0]
// - Initialized to zero at simulation start
//
// Parameters:
//   DEPTH : memory depth in 32-bit words (default 16384 = 64 KB)
// -----------------------------------------------------------------------------

`default_nettype none

module wb_sram #(
    parameter integer DEPTH = 16384
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
    output reg         wb_ack_o
);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
    end

    wire [$clog2(DEPTH)-1:0] word_addr = wb_adr_i[$clog2(DEPTH)+1:2];

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            wb_dat_o <= 32'b0;
        end else if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
            if (wb_we_i) begin
                if (wb_sel_i[0]) mem[word_addr][ 7: 0] <= wb_dat_i[ 7: 0];
                if (wb_sel_i[1]) mem[word_addr][15: 8] <= wb_dat_i[15: 8];
                if (wb_sel_i[2]) mem[word_addr][23:16] <= wb_dat_i[23:16];
                if (wb_sel_i[3]) mem[word_addr][31:24] <= wb_dat_i[31:24];
            end else begin
                wb_dat_o <= mem[word_addr];
            end
            wb_ack_o <= 1'b1;
        end
    end

endmodule
`default_nettype wire