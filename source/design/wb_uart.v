// -----------------------------------------------------------------------------
// wb_uart.v — UART TX+RX peripheral, Wishbone B4 slave
//
// Register map:
//   +0x00  TX_DATA   (W) transmit byte; (R) last transmitted byte
//   +0x04  TX_STATUS (R) bit[0] = tx_busy
//   +0x08  RX_DATA   (R) received byte — reading clears rx_ready
//   +0x0C  RX_STATUS (R) bit[0]=rx_ready  bit[1]=rx_overflow
//
// Frame format: 8N1
// uart_rx input is double-synchronized (metastability protection).
// Baud divisor and TX enable are runtime inputs from wb_cfg.
// -----------------------------------------------------------------------------

`default_nettype none

module wb_uart (
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
    // Runtime config from wb_cfg
    input  wire [15:0] baud_div,
    input  wire        uart_en,
    // UART lines
    output reg         uart_tx,
    input  wire        uart_rx
);

    // -------------------------------------------------------------------------
    // Metastability protection — double-sync RX input
    // -------------------------------------------------------------------------
    reg rx_s1, rx_s2;
    always @(posedge wb_clk_i) begin
        rx_s1 <= uart_rx;
        rx_s2 <= rx_s1;
    end
    wire rx_in = rx_s2;

    wire [15:0] half_baud = baud_div >> 1;

    // -------------------------------------------------------------------------
    // TX state machine
    // -------------------------------------------------------------------------
    localparam [1:0] TX_IDLE=2'd0, TX_START=2'd1, TX_DATA=2'd2, TX_STOP=2'd3;

    reg  [1:0]  tx_state;
    reg  [15:0] tx_baud_cnt;
    reg  [7:0]  tx_shift;
    reg  [2:0]  tx_bit_idx;
    reg         tx_busy;
    reg  [7:0]  tx_data_r;

    // -------------------------------------------------------------------------
    // RX state machine
    // -------------------------------------------------------------------------
    localparam [1:0] RX_IDLE=2'd0, RX_START=2'd1, RX_DATA=2'd2, RX_STOP=2'd3;

    reg  [1:0]  rx_state;
    reg  [15:0] rx_baud_cnt;
    reg  [7:0]  rx_shift;
    reg  [2:0]  rx_bit_idx;
    reg  [7:0]  rx_data_r;
    reg         rx_ready;
    reg         rx_overflow;

    // -------------------------------------------------------------------------
    // Wishbone register access
    // -------------------------------------------------------------------------
    wire access   = wb_cyc_i && wb_stb_i && !wb_ack_o;
    wire tx_start = access && wb_we_i  && (wb_adr_i[3:2] == 2'b00)
                    && wb_sel_i[0] && !tx_busy && uart_en;
    wire rx_read  = access && !wb_we_i && (wb_adr_i[3:2] == 2'b10);

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        if (wb_rst_i) begin
            wb_dat_o <= 32'b0;
        end else if (access) begin
            wb_ack_o <= 1'b1;
            if (!wb_we_i) begin
                case (wb_adr_i[3:2])
                    2'b00: wb_dat_o <= {24'b0, tx_data_r};
                    2'b01: wb_dat_o <= {31'b0, tx_busy};
                    2'b10: wb_dat_o <= {24'b0, rx_data_r};
                    2'b11: wb_dat_o <= {30'b0, rx_overflow, rx_ready};
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // TX state machine
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            tx_state    <= TX_IDLE;
            tx_busy     <= 1'b0;
            uart_tx     <= 1'b1;
            tx_baud_cnt <= 16'b0;
            tx_bit_idx  <= 3'b0;
            tx_shift    <= 8'b0;
            tx_data_r   <= 8'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    if (tx_start) begin
                        tx_shift    <= wb_dat_i[7:0];
                        tx_data_r   <= wb_dat_i[7:0];
                        tx_busy     <= 1'b1;
                        tx_baud_cnt <= 16'b0;
                        tx_state    <= TX_START;
                    end
                end
                TX_START: begin
                    uart_tx <= 1'b0;
                    if (tx_baud_cnt == baud_div - 1) begin
                        tx_baud_cnt <= 16'b0;
                        tx_bit_idx  <= 3'b0;
                        tx_state    <= TX_DATA;
                    end else
                        tx_baud_cnt <= tx_baud_cnt + 1;
                end
                TX_DATA: begin
                    uart_tx <= tx_shift[0];
                    if (tx_baud_cnt == baud_div - 1) begin
                        tx_baud_cnt <= 16'b0;
                        tx_shift    <= {1'b0, tx_shift[7:1]};
                        if (tx_bit_idx == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_idx <= tx_bit_idx + 1;
                    end else
                        tx_baud_cnt <= tx_baud_cnt + 1;
                end
                TX_STOP: begin
                    uart_tx <= 1'b1;
                    if (tx_baud_cnt == baud_div - 1) begin
                        tx_baud_cnt <= 16'b0;
                        tx_busy     <= 1'b0;
                        tx_state    <= TX_IDLE;
                    end else
                        tx_baud_cnt <= tx_baud_cnt + 1;
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // RX state machine
    // Timing: detect falling edge → wait half_baud → sample start bit center
    //         → wait baud_div per bit → sample 8 data bits (LSB first)
    //         → verify stop bit → set rx_ready
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            rx_state    <= RX_IDLE;
            rx_baud_cnt <= 16'b0;
            rx_bit_idx  <= 3'b0;
            rx_shift    <= 8'b0;
            rx_data_r   <= 8'b0;
            rx_ready    <= 1'b0;
            rx_overflow <= 1'b0;
        end else begin
            // Reading RX_DATA clears flags
            if (rx_read) begin
                rx_ready    <= 1'b0;
                rx_overflow <= 1'b0;
            end

            case (rx_state)
                RX_IDLE: begin
                    if (!rx_in) begin          // falling edge = start bit
                        rx_baud_cnt <= 16'b0;
                        rx_state    <= RX_START;
                    end
                end
                RX_START: begin
                    // Sample at center of start bit (half_baud clocks)
                    if (rx_baud_cnt == half_baud - 1) begin
                        rx_baud_cnt <= 16'b0;
                        if (!rx_in) begin      // still low — valid start bit
                            rx_bit_idx <= 3'b0;
                            rx_state   <= RX_DATA;
                        end else
                            rx_state   <= RX_IDLE;  // noise — abort
                    end else
                        rx_baud_cnt <= rx_baud_cnt + 1;
                end
                RX_DATA: begin
                    // Sample each data bit (LSB first) at baud_div intervals
                    if (rx_baud_cnt == baud_div - 1) begin
                        rx_baud_cnt <= 16'b0;
                        rx_shift    <= {rx_in, rx_shift[7:1]};   // shift in MSB→LSB
                        if (rx_bit_idx == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_idx <= rx_bit_idx + 1;
                    end else
                        rx_baud_cnt <= rx_baud_cnt + 1;
                end
                RX_STOP: begin
                    if (rx_baud_cnt == baud_div - 1) begin
                        rx_baud_cnt <= 16'b0;
                        if (rx_in) begin       // valid stop bit
                            rx_data_r <= rx_shift;
                            if (rx_ready)
                                rx_overflow <= 1'b1;
                            rx_ready <= 1'b1;
                        end
                        // Framing error (stop bit low) — discard byte
                        rx_state <= RX_IDLE;
                    end else
                        rx_baud_cnt <= rx_baud_cnt + 1;
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire