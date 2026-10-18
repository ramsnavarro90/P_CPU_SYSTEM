// -----------------------------------------------------------------------------
// wb_spi.v — SPI Master controller, Wishbone B4 slave
//
// Full-duplex, MSB-first, 8-bit transfers.
// Supports all 4 SPI modes via CPOL/CPHA configuration.
//
// Register map (base: 0xD000_0000):
//   +0x00  DATA    (W) write byte to transmit and start transfer
//                  (R) last received byte — reading clears rx_valid
//   +0x04  STATUS  (R) bit[0]=busy  bit[1]=rx_valid
//   +0x08  CTRL    (R/W) bit[0]=cpol  bit[1]=cpha  bit[4]=cs_n
//   +0x0C  CLK_DIV (R/W) SCLK half-period in system clocks (min 2)
//
// Timing (Mode 0, CLK_DIV=4, clk=50 MHz):
//   SCLK = 50 MHz / (2*4) = 6.25 MHz
//
// CS is manually controlled by firmware via CTRL.cs_n:
//   Write 0 to CTRL.cs_n → assert CS (active low)
//   Write 1 to CTRL.cs_n → deassert CS
// This allows multi-byte transactions with CS held across bytes.
// -----------------------------------------------------------------------------

`default_nettype none

module wb_spi (
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
    // SPI interface
    output reg         sclk,
    output wire        mosi,
    input  wire        miso,
    output reg         spi_cs_n
);

    // -------------------------------------------------------------------------
    // Registered config (latched at transfer start — stable during transfer)
    // -------------------------------------------------------------------------
    reg        cpol_r;
    reg        cpha_r;
    reg [15:0] clk_div_r;

    // Runtime control registers
    reg        cpol_cfg;
    reg        cpha_cfg;
    reg        cs_n_cfg;
    reg [15:0] clk_div_cfg;

    // -------------------------------------------------------------------------
    // Transfer state
    // -------------------------------------------------------------------------
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;
    reg [7:0]  rx_data_r;
    reg        spi_busy;
    reg        rx_valid;
    reg [3:0]  hp_cnt;       // half-period counter 0..15 (16 per byte)
    reg [15:0] div_cnt;      // divider countdown

    assign mosi = tx_shift[7];  // MSB first, always driven from shift register

    // -------------------------------------------------------------------------
    // Wishbone register access
    // -------------------------------------------------------------------------
    wire access    = wb_cyc_i && wb_stb_i && !wb_ack_o;
    wire tx_start  = access && wb_we_i && (wb_adr_i[3:2] == 2'b00)
                     && wb_sel_i[0] && !spi_busy;
    wire rx_read   = access && !wb_we_i && (wb_adr_i[3:2] == 2'b00);

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            cpol_cfg    <= 1'b0;
            cpha_cfg    <= 1'b0;
            cs_n_cfg    <= 1'b1;     // deasserted by default
            clk_div_cfg <= 16'd4;
            wb_dat_o    <= 32'b0;
        end else if (access) begin
            wb_ack_o <= 1'b1;
            if (wb_we_i) begin
                case (wb_adr_i[3:2])
                    2'b00: ;  // DATA write — handled by transfer state machine
                    2'b01: ;  // STATUS — read-only
                    2'b10: begin  // CTRL
                        if (wb_sel_i[0]) begin
                            cpol_cfg <= wb_dat_i[0];
                            cpha_cfg <= wb_dat_i[1];
                            cs_n_cfg <= wb_dat_i[4];
                        end
                    end
                    2'b11: begin  // CLK_DIV
                        if (wb_sel_i[0]) clk_div_cfg[ 7:0] <= wb_dat_i[ 7:0];
                        if (wb_sel_i[1]) clk_div_cfg[15:8] <= wb_dat_i[15:8];
                    end
                endcase
            end else begin
                case (wb_adr_i[3:2])
                    2'b00: begin
                        wb_dat_o <= {24'b0, rx_data_r};
                        // rx_valid cleared by rx_read — handled below
                    end
                    2'b01: wb_dat_o <= {30'b0, rx_valid, spi_busy};
                    2'b10: wb_dat_o <= {27'b0, cs_n_cfg, 2'b0, cpha_cfg, cpol_cfg};
                    2'b11: wb_dat_o <= {16'b0, clk_div_cfg};
                    default: wb_dat_o <= 32'hDEAD_BEEF;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // CS pad — follows cs_n_cfg immediately
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i)
        if (wb_rst_i) spi_cs_n <= 1'b1;
        else          spi_cs_n <= cs_n_cfg;

    // // -------------------------------------------------------------------------
    // // RX valid clear on read
    // // -------------------------------------------------------------------------
    // always @(posedge wb_clk_i)
    //     if (wb_rst_i)  rx_valid <= 1'b0;
    //     else if (rx_read && !wb_we_i) rx_valid <= 1'b0;
    //     else if (!spi_busy && spi_busy) rx_valid <= 1'b1;  // set by state machine

    // -------------------------------------------------------------------------
    // rx_valid — single driver, detects transfer completion via busy falling edge
    // -------------------------------------------------------------------------
    reg spi_busy_prev;

    always @(posedge wb_clk_i)
        if (wb_rst_i) spi_busy_prev <= 1'b0;
        else          spi_busy_prev <= spi_busy;

    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            rx_valid <= 1'b0;
        else if (rx_read)
            rx_valid <= 1'b0;                    // cleared on DATA read
        else if (spi_busy_prev && !spi_busy)
            rx_valid <= 1'b1;                    // set when transfer completes
    end

    // -------------------------------------------------------------------------
    // SPI transfer state machine
    //
    // Each byte = 16 half-periods (hp_cnt 0..15)
    // hp_cnt even → leading edge transition (sclk goes to ~cpol)
    // hp_cnt odd  → trailing edge transition (sclk returns to cpol)
    //
    // CPHA=0: sample MISO on leading edges, shift MOSI on trailing edges
    // CPHA=1: sample MISO on trailing edges, shift MOSI on trailing edges
    //         (first MOSI bit already in tx_shift[7] before first edge)
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            spi_busy  <= 1'b0;
            sclk      <= 1'b0;
            tx_shift  <= 8'b0;
            rx_shift  <= 8'b0;
            rx_data_r <= 8'b0;
            hp_cnt    <= 4'b0;
            div_cnt   <= 16'b0;
        end else if (!spi_busy) begin
            // Idle — SCLK holds at CPOL level
            sclk <= cpol_cfg;
            if (tx_start) begin
                // Latch config at transfer start
                tx_shift  <= wb_dat_i[7:0];
                cpol_r    <= cpol_cfg;
                cpha_r    <= cpha_cfg;
                clk_div_r <= (clk_div_cfg < 2) ? 16'd2 : clk_div_cfg;
                spi_busy  <= 1'b1;
                hp_cnt    <= 4'b0;
                div_cnt   <= 16'b0;
            end
        end else begin
            // Transfer in progress
            if (div_cnt < clk_div_r - 1) begin
                div_cnt <= div_cnt + 1;
            end else begin
                div_cnt <= 16'b0;
                sclk    <= ~sclk;  // toggle SCLK

                // Determine edge type using current (pre-toggle) SCLK value
                // sclk == cpol_r → transitioning to ~cpol_r → LEADING edge
                // sclk != cpol_r → transitioning to  cpol_r → TRAILING edge

                if (sclk == cpol_r) begin
                    // ---- LEADING EDGE ----------------------------------------
                    if (!cpha_r) begin
                        // CPHA=0: sample MISO on leading edge
                        rx_shift <= {rx_shift[6:0], miso};
                    end
                end else begin
                    // ---- TRAILING EDGE ---------------------------------------
                    if (cpha_r) begin
                        // CPHA=1: sample MISO on trailing edge
                        rx_shift <= {rx_shift[6:0], miso};
                    end
                    // Both modes: shift MOSI for next bit
                    tx_shift <= {tx_shift[6:0], 1'b0};

                    if (hp_cnt == 4'd15) begin
                        // Transfer complete
                        rx_data_r <= cpha_r ? {rx_shift[6:0], miso} : rx_shift;
                        //rx_valid  <= 1'b1;
                        spi_busy  <= 1'b0;
                        sclk      <= cpol_r;  // return to idle level
                    end
                end

                hp_cnt <= hp_cnt + 1;
            end
        end
    end

endmodule
`default_nettype wire