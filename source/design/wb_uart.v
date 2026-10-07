// -----------------------------------------------------------------------------
// wb_uart.v — UART TX peripheral, Wishbone B4 slave
//
// Register map (word-aligned offsets from base address):
//   +0x00  DATA    (W) — byte to transmit; (R) — last transmitted byte
//   +0x04  STATUS  (R) — bit[0] = tx_busy
//
// Frame format: 8N1 (8 data bits, no parity, 1 stop bit)
// TX line idles HIGH; start bit LOW, data LSB-first, stop bit HIGH.
//
// Parameters:
//   CLK_FREQ  : system clock frequency in Hz   (default 50 MHz)
//   BAUD_RATE : desired baud rate              (default 115200)
// -----------------------------------------------------------------------------

`default_nettype none

module wb_uart #(
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
    // UART TX line (idles HIGH)
    output reg         uart_tx
);

    // -------------------------------------------------------------------------
    // Baud rate
    // -------------------------------------------------------------------------
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // -------------------------------------------------------------------------
    // TX state machine encoding
    // -------------------------------------------------------------------------
    localparam [1:0]
        TX_IDLE  = 2'd0,
        TX_START = 2'd1,
        TX_DATA  = 2'd2,
        TX_STOP  = 2'd3;

    reg  [1:0]                    tx_state;
    reg  [$clog2(CLKS_PER_BIT):0] baud_cnt;
    reg  [7:0]                    tx_shift;
    reg  [2:0]                    bit_idx;
    reg                           tx_busy;
    reg  [7:0]                    tx_data_r;  // last written byte (read-back)

    // -------------------------------------------------------------------------
    // Wishbone handshake
    // -------------------------------------------------------------------------
    wire access = wb_cyc_i && wb_stb_i && !wb_ack_o;

    // Write to DATA register triggers TX (ignored when busy)
    wire tx_start = access && wb_we_i
                    && (wb_adr_i[3:2] == 2'b00)
                    && wb_sel_i[0]
                    && !tx_busy;

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            wb_dat_o  <= 32'b0;
            tx_data_r <= 8'b0;
        end else if (access) begin
            wb_ack_o <= 1'b1;
            if (wb_we_i) begin
                // DATA write — capture byte for read-back
                if ((wb_adr_i[3:2] == 2'b00) && wb_sel_i[0])
                    tx_data_r <= wb_dat_i[7:0];
            end else begin
                case (wb_adr_i[3:2])
                    2'b00:   wb_dat_o <= {24'b0, tx_data_r};
                    2'b01:   wb_dat_o <= {31'b0, tx_busy};
                    default: wb_dat_o <= 32'hDEAD_BEEF;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // TX state machine
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            tx_state <= TX_IDLE;
            tx_busy  <= 1'b0;
            uart_tx  <= 1'b1;
            baud_cnt <= 0;
            bit_idx  <= 0;
            tx_shift <= 8'b0;
        end else begin
            case (tx_state)

                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    if (tx_start) begin
                        tx_shift <= wb_dat_i[7:0];  // capture byte
                        tx_busy  <= 1'b1;
                        baud_cnt <= 0;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    uart_tx <= 1'b0;                // start bit (LOW)
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        tx_state <= TX_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                TX_DATA: begin
                    uart_tx <= tx_shift[0];         // LSB first
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        tx_shift <= {1'b0, tx_shift[7:1]};   // shift right
                        if (bit_idx == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                TX_STOP: begin
                    uart_tx <= 1'b1;                // stop bit (HIGH)
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        tx_busy  <= 1'b0;
                        tx_state <= TX_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire