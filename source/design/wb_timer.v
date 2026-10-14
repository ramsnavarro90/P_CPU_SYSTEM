// -----------------------------------------------------------------------------
// wb_timer.v — 32-bit compare timer, Wishbone B4 slave
//
// Register map (base: 0xC000_0000):
//   +0x00  COUNT    (R)   free-running 32-bit counter
//   +0x04  COMPARE  (R/W) match target value
//   +0x08  CTRL     (R/W) bit[0]=en  bit[1]=auto_reload
//   +0x0C  STATUS   (R/W) bit[0]=match  (write 1 to clear)
//
// Match condition: COUNT == COMPARE while enabled
// Match flag is sticky — stays set until SW clears it via STATUS write.
// Auto-reload: counter resets to 0 on match; period = COMPARE+1 cycles.
// timer_irq reflects match flag (connect to CPU irq when ENABLE_IRQ=1).
// -----------------------------------------------------------------------------

`default_nettype none

module wb_timer (
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
    // IRQ output (connect to CPU irq[0] when ENABLE_IRQ=1)
    output wire        timer_irq
);

    reg [31:0] count_r;
    reg [31:0] compare_r;
    reg [1:0]  ctrl_r;
    reg        match_r;

    wire timer_en    = ctrl_r[0];
    wire auto_reload = ctrl_r[1];

    assign timer_irq = match_r;

    // -------------------------------------------------------------------------
    // Counter + match logic
    // -------------------------------------------------------------------------
    wire count_match = timer_en && (count_r == compare_r);

    // Detect rising edge of enable — resets counter on each fresh start
    reg timer_en_prev;

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            count_r       <= 32'b0;
            match_r       <= 1'b0;
            timer_en_prev <= 1'b0;
        end else begin
            timer_en_prev <= timer_en;

            if (timer_en && !timer_en_prev) begin
                // Timer just enabled — always start from 0
                count_r <= 32'b0;
            end else if (count_match) begin
                match_r <= 1'b1;
                count_r <= auto_reload ? 32'b0 : count_r + 1;
            end else if (timer_en) begin
                count_r <= count_r + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Wishbone register access
    // -------------------------------------------------------------------------
    wire access = wb_cyc_i && wb_stb_i && !wb_ack_o;

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            compare_r <= 32'hFFFF_FFFF;
            ctrl_r    <= 2'b0;
            wb_dat_o  <= 32'b0;
        end else if (access) begin
            wb_ack_o <= 1'b1;
            if (wb_we_i) begin
                case (wb_adr_i[3:2])
                    2'b00: ;                 // COUNT — read-only
                    2'b01: begin             // COMPARE
                        if (wb_sel_i[0]) compare_r[ 7: 0] <= wb_dat_i[ 7: 0];
                        if (wb_sel_i[1]) compare_r[15: 8] <= wb_dat_i[15: 8];
                        if (wb_sel_i[2]) compare_r[23:16] <= wb_dat_i[23:16];
                        if (wb_sel_i[3]) compare_r[31:24] <= wb_dat_i[31:24];
                    end
                    2'b10: begin             // CTRL
                        if (wb_sel_i[0]) ctrl_r <= wb_dat_i[1:0];
                    end
                    2'b11: begin             // STATUS — write 1 to clear match
                        if (wb_sel_i[0] && wb_dat_i[0]) match_r <= 1'b0;
                    end
                    default: ;
                endcase
            end else begin
                case (wb_adr_i[3:2])
                    2'b00: wb_dat_o <= count_r;
                    2'b01: wb_dat_o <= compare_r;
                    2'b10: wb_dat_o <= {30'b0, ctrl_r};
                    2'b11: wb_dat_o <= {31'b0, match_r};
                    default: wb_dat_o <= 32'hDEAD_BEEF;
                endcase
            end
        end
    end

endmodule
`default_nettype wire