`timescale 1ns / 1ps
//========================================================================
// nvram.v - the SMUC's NVRAM: a 24C16 EEPROM, 2 KB, on two bits of port
// FFBA, driven bit by bit as I2C.
//
// The port's bit 6 is SCL, bit 4 SDA out of the Spectrum, bit 5 the
// write-protect input; reading the port gives SDA on bit 6 (Unreal
// Speccy's NVRAM: FFh when the line is high, BFh when the chip pulls it
// low).  The protocol is the 24C16's: a start, the device byte
// 1010 b10 b9 b8 R/W, then for a write the low address byte and data
// bytes (the address wrapping in its 16-byte page), for a read the data
// bytes as long as the master acknowledges.  A read without an address
// starts at the current address, as the chip does.  The memory is
// BSRAM; nothing keeps it across a power cycle yet.
//========================================================================
module nvram (
    input             clk,
    input             reset,

    input             stb,          // one clock: port FFBA written
    input      [7:0]  wdata,
    output            sda_in        // what a read of the port sees on bit 6
);

localparam [2:0] IDLE = 3'd0, RCV_CMD = 3'd1, RCV_ADDR = 3'd2, RCV_DATA = 3'd3, SEND = 3'd4, RD_ACK = 3'd5;

reg [7:0]  mem [0:2047];
reg [2:0]  state = IDLE;
reg [10:0] address = 11'd0;
reg [7:0]  datain = 8'd0, dataout = 8'd0;
reg [3:0]  bitsin = 4'd0, bitsout = 4'd0;
reg        out = 1'b1;        // the chip's SDA when driving
reg        out_z = 1'b1;      // the chip is not driving
reg        scl = 1'b0, sda = 1'b1;   // the master's lines, as last written
reg        load = 1'b0;       // dataout <= mem[address] next clock
reg [7:0]  q = 8'd0;
reg        wr = 1'b0;
reg [10:0] wr_adr = 11'd0;
reg [7:0]  wr_data = 8'd0;

assign sda_in = out_z ? sda : out;

always @(posedge clk) begin
    if (wr) mem[wr_adr] <= wr_data;
    q <= mem[address];
end

wire n_scl = wdata[6];
wire n_sda = wdata[4];

always @(posedge clk) begin
    wr <= 1'b0;
    if (load) begin dataout <= q; load <= 1'b0; end
    if (reset) begin
        state <= IDLE; out_z <= 1'b1; out <= 1'b1; bitsin <= 4'd0; bitsout <= 4'd0; scl <= 1'b0; sda <= 1'b1;
    end else if (stb) begin
        scl <= n_scl;
        sda <= n_sda;
        if (n_scl != scl) begin
            if (n_scl) begin
                // the clock rises: the chip reads SDA
                if (state == RD_ACK) begin
                    if (n_sda) state <= IDLE;               // no acknowledge: the master is done
                    else begin
                        state <= SEND; load <= 1'b1; address <= address + 11'd1; bitsout <= 4'd0; out_z <= 1'b1;
                    end
                end else if (state == RCV_CMD || state == RCV_ADDR || state == RCV_DATA) begin
                    if (out_z) begin datain <= {datain[6:0], n_sda}; bitsin <= bitsin + 4'd1; end
                end
            end else begin
                // the clock falls: the chip sets SDA
                if (bitsin == 4'd8) begin
                    bitsin <= 4'd0;
                    case (state)
                    RCV_CMD: begin
                        if (datain[7:4] != 4'hA) state <= IDLE;
                        else begin
                            address[10:8] <= datain[3:1];
                            if (datain[0]) begin state <= SEND; load <= 1'b1; bitsout <= 4'd0; end
                            else state <= RCV_ADDR;
                        end
                    end
                    RCV_ADDR: begin address[7:0] <= datain; state <= RCV_DATA; end
                    RCV_DATA: begin
                        wr <= 1'b1; wr_adr <= address; wr_data <= datain;
                        address[3:0] <= address[3:0] + 4'd1;
                    end
                    default: ;
                    endcase
                    if (datain[7:4] == 4'hA || state != RCV_CMD) begin out <= 1'b0; out_z <= 1'b0; end   // the acknowledge
                end else if (state == SEND) begin
                    if (bitsout == 4'd8) begin state <= RD_ACK; out_z <= 1'b1; end
                    else begin out <= dataout[7]; dataout <= {dataout[6:0], 1'b0}; bitsout <= bitsout + 4'd1; out_z <= 1'b0; end
                end else
                    out_z <= 1'b1;
            end
        end else if (n_scl && n_sda != sda) begin
            // SDA moving while the clock is high: a start or a stop
            if (n_sda) state <= IDLE;
            else begin state <= RCV_CMD; bitsin <= 4'd0; end
            out_z <= 1'b1;
        end
    end
end

endmodule
