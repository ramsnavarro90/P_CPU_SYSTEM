// -----------------------------------------------------------------------------
// uart_monitor.v — Simulation-only UART RX monitor
//
// Connects to a uart_tx line, reconstructs bytes (8N1),
// accumulates characters into a line buffer, and prints
// the full line via $display when \n is received.
//
// \r is silently discarded — clean output on Linux terminals.
//
// Parameters:
//   CLK_FREQ  : matches testbench clock frequency
//   BAUD_RATE : matches DUT baud rate
//   MAX_LINE  : maximum characters per line before forced flush
//   PREFIX    : label printed before each line  e.g. "[SoC] Hello"
// -----------------------------------------------------------------------------

`default_nettype none

module uart_monitor #(
    parameter integer CLK_FREQ  = 100_000,
    parameter integer BAUD_RATE = 10_000,
    parameter integer MAX_LINE  = 256,
    parameter         PREFIX    = "SoC"
)(
    input wire clk,
    input wire uart_tx
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

    reg [7:0] line_buf [0:MAX_LINE-1];
    integer   line_len;
    reg [7:0] rx_byte;
    integer   bit_i;
    integer   j;

    initial begin
        line_len = 0;

        forever begin
            // Wait for start bit (uart_tx falls LOW)
            @(negedge uart_tx);

            // Skip to center of first data bit (1.5 bit periods)
            repeat(CLKS_PER_BIT + HALF_BIT) @(posedge clk);

            // Sample 8 data bits, LSB first
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                rx_byte[bit_i] = uart_tx;
                repeat(CLKS_PER_BIT) @(posedge clk);
            end

            // Dispatch received byte
            case (rx_byte)
                8'h0A: begin            // \n — flush line
                    $write("[%s] ", PREFIX);
                    for (j = 0; j < line_len; j = j + 1)
                        $write("%c", line_buf[j]);
                    $display("");       // newline
                    line_len = 0;
                end
                8'h0D: ;                // \r — discard silently
                default: begin          // printable character — accumulate
                    if (line_len < MAX_LINE - 1) begin
                        line_buf[line_len] = rx_byte;
                        line_len          = line_len + 1;
                    end else begin
                        // Buffer full — force flush with overflow warning
                        $write("[%s] ", PREFIX);
                        for (j = 0; j < line_len; j = j + 1)
                            $write("%c", line_buf[j]);
                        $display(" ... [LINE OVERFLOW]");
                        line_len = 0;
                    end
                end
            endcase
        end
    end

endmodule
`default_nettype wire