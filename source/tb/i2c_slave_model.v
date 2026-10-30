// -----------------------------------------------------------------------------
// i2c_slave_model.v — Simulation-only behavioral I2C slave
//
// - 7-bit address (ADDR), 8-byte memory with auto-incrementing pointer
// - Write: [S][ADDR+W][A][ptr][A][data][A]...[P]  (first byte sets the pointer)
// - Read : [S][ADDR+R][A][data][A]...[data][N][P] (reads from pointer)
// - Open-drain: drives SDA low or releases it (Z); needs an external pullup
// - START/STOP detected from SDA edges while SCL is high
// -----------------------------------------------------------------------------

`default_nettype none

module i2c_slave_model #(
    parameter [6:0] ADDR = 7'h28
)(
    input wire scl,
    inout wire sda
);

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_ADDR      = 4'd1,
        S_ADDR_ACK  = 4'd2,
        S_PTR       = 4'd3,
        S_PTR_ACK   = 4'd4,
        S_WDATA     = 4'd5,
        S_WDATA_ACK = 4'd6,
        S_RDATA     = 4'd7,
        S_RDATA_ACK = 4'd8;

    reg [7:0] mem [0:7];
    reg [3:0] state;
    reg [3:0] nbits;
    reg [7:0] shift;
    reg [2:0] ptr;
    reg       rw;
    reg       master_nack;
    reg       sda_rel;          // 1 = release SDA, 0 = drive low
    integer   i;

    assign sda = sda_rel ? 1'bz : 1'b0;

    initial begin
        for (i = 0; i < 8; i = i + 1) mem[i] = 8'hC0 + i;
        state = S_IDLE; nbits = 0; shift = 0; ptr = 0;
        rw = 0; master_nack = 0; sda_rel = 1'b1;
    end

    // START / repeated START: SDA falls while SCL is high
    always @(negedge sda)
        if (scl === 1'b1) begin
            state = S_ADDR; nbits = 0; shift = 0;
        end

    // STOP: SDA rises while SCL is high
    always @(posedge sda)
        if (scl === 1'b1) state = S_IDLE;

    // Sample on SCL rising edge
    always @(posedge scl) begin
        case (state)
            S_ADDR, S_PTR, S_WDATA: begin
                shift = {shift[6:0], sda};
                nbits = nbits + 1;
            end
            S_RDATA_ACK: master_nack = sda;
            default: ;
        endcase
    end

    // Drive on SCL falling edge
    always @(negedge scl) begin
        case (state)
            S_ADDR: if (nbits == 8) begin
                if (shift[7:1] == ADDR) begin
                    rw = shift[0]; sda_rel = 1'b0; state = S_ADDR_ACK;
                end else
                    state = S_IDLE;          // not us: stay off the bus (NACK)
            end
            S_ADDR_ACK: begin
                nbits = 0;
                if (rw) begin
                    shift = mem[ptr]; sda_rel = shift[7]; nbits = 1;
                    state = S_RDATA;
                end else begin
                    sda_rel = 1'b1; state = S_PTR;
                end
            end
            S_PTR: if (nbits == 8) begin
                ptr = shift[2:0]; sda_rel = 1'b0; state = S_PTR_ACK;
            end
            S_PTR_ACK: begin
                sda_rel = 1'b1; nbits = 0; state = S_WDATA;
            end
            S_WDATA: if (nbits == 8) begin
                mem[ptr] = shift; ptr = ptr + 1;
                sda_rel = 1'b0; state = S_WDATA_ACK;
            end
            S_WDATA_ACK: begin
                sda_rel = 1'b1; nbits = 0; state = S_WDATA;
            end
            S_RDATA: begin
                if (nbits < 8) begin
                    shift = {shift[6:0], 1'b0};
                    sda_rel = shift[7]; nbits = nbits + 1;
                end else begin
                    sda_rel = 1'b1; state = S_RDATA_ACK;   // master ACK/NACK
                end
            end
            S_RDATA_ACK: begin
                if (!master_nack) begin
                    ptr = ptr + 1; shift = mem[ptr];
                    sda_rel = shift[7]; nbits = 1; state = S_RDATA;
                end else begin
                    sda_rel = 1'b1; state = S_IDLE;
                end
            end
            default: ;
        endcase
    end

endmodule
`default_nettype wire