// -----------------------------------------------------------------------------
// spi_flash_model.v — Simulation-only SPI NOR flash (READ 0x03, SPI mode 0)
//
// - Image file: one hex byte per line (see bin2hex.py --flash); unused = 0xFF
// - Command 0x03 + 24-bit address, then bytes stream out with auto-increment
// - Samples MOSI on SCLK rising edge; updates MISO on SCLK falling edge
// -----------------------------------------------------------------------------

`default_nettype none

module spi_flash_model #(
    parameter         FILE  = "flash.hex",
    parameter integer DEPTH = 65536
)(
    input  wire sclk,
    input  wire cs_n,
    input  wire mosi,
    output wire miso
);

    localparam [1:0] S_CMD = 2'd0, S_ADDR = 2'd1, S_DATA = 2'd2, S_IGNORE = 2'd3;

    reg [7:0]  mem [0:DEPTH-1];
    reg [1:0]  state;
    reg [7:0]  cmd_shift;
    reg [23:0] addr;
    reg [4:0]  nbits;
    reg [7:0]  out_shift;
    reg [3:0]  out_bits;
    reg        first;
    reg        miso_r;

    assign miso = (cs_n === 1'b0) ? miso_r : 1'b0;

    // ---- Load image -----------------------------------------------------------
    integer     fd, rc, n, i;
    reg [7:0]   b;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 8'hFF;   // erased flash
        n  = 0;
        fd = $fopen(FILE, "r");
        if (fd == 0) begin
            $display("WARN: [FLASH] image %0s not found — flash stays erased", FILE);
        end else begin
            rc = $fscanf(fd, "%h\n", b);
            while (rc == 1) begin
                mem[n] = b;
                n  = n + 1;
                rc = $fscanf(fd, "%h\n", b);
            end
            $fclose(fd);
            $display("INFO: [FLASH] loaded %0d bytes from %0s", n, FILE);
        end
        state = S_CMD; nbits = 0; first = 0; miso_r = 1'b0;
        cmd_shift = 0; addr = 0; out_shift = 0; out_bits = 0;
    end

    // ---- Chip select ------------------------------------------------------------
    always @(negedge cs_n) begin
        state = S_CMD; nbits = 0; cmd_shift = 0; first = 0; miso_r = 1'b0;
    end
    always @(posedge cs_n) begin
        state = S_CMD; nbits = 0;
    end

    // ---- Receive on SCLK rising edge -----------------------------------------------
    always @(posedge sclk) begin
        if (cs_n === 1'b0) begin
            case (state)
                S_CMD: begin
                    cmd_shift = {cmd_shift[6:0], mosi};
                    nbits = nbits + 1;
                    if (nbits == 8) begin
                        nbits = 0;
                        if (cmd_shift == 8'h03) state = S_ADDR;
                        else begin
                            state = S_IGNORE;
                            $display("WARN: [FLASH] unsupported command 0x%02h", cmd_shift);
                        end
                    end
                end
                S_ADDR: begin
                    addr  = {addr[22:0], mosi};
                    nbits = nbits + 1;
                    if (nbits == 24) begin
                        nbits = 0;
                        first = 1;                   // first data bit goes out on next falling edge
                        state = S_DATA;
                        $display("INFO: [FLASH] READ @0x%06h", addr);
                    end
                end
                default: ;
            endcase
        end
    end

    // ---- Drive MISO on SCLK falling edge ---------------------------------------------
    always @(negedge sclk) begin
        if (cs_n === 1'b0 && state == S_DATA) begin
            if (first) begin
                first = 0;
                out_shift = mem[addr[15:0]];
                miso_r = out_shift[7]; out_bits = 1;
            end else if (out_bits == 8) begin        // byte done: load next
                addr = addr + 1;
                out_shift = mem[addr[15:0]];
                miso_r = out_shift[7]; out_bits = 1;
            end else begin
                out_shift = {out_shift[6:0], 1'b0};
                miso_r = out_shift[7]; out_bits = out_bits + 1;
            end
        end
    end

endmodule
`default_nettype wire