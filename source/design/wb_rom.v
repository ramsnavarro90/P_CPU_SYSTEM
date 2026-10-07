// -----------------------------------------------------------------------------
// wb_rom.v — Boot ROM, Wishbone B4 slave (read-only)
//
// - Single-cycle registered ACK
// - Content loaded from hex file via $readmemh
// - Word-addressed internally; CPU byte address → word index via [N+1:2]
//
// Parameters:
//   DEPTH    : memory depth in 32-bit words  (default 1024 = 4 KB)
//   MEM_FILE : path to .hex file
// -----------------------------------------------------------------------------

`default_nettype none

module wb_rom #(
    parameter integer DEPTH    = 1024,
    parameter         MEM_FILE = "firmware.hex"
)(
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire [31:0] wb_adr_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack_o
);

    reg [31:0] mem [0:DEPTH-1];

    initial $readmemh(MEM_FILE, mem);

    // Byte address [1:0] ignored; mask to array depth
    wire [$clog2(DEPTH)-1:0] word_addr = wb_adr_i[$clog2(DEPTH)+1:2];

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            wb_dat_o <= 32'b0;
        end else if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
            wb_dat_o <= mem[word_addr];
            wb_ack_o <= 1'b1;
        end
    end

endmodule
`default_nettype wire