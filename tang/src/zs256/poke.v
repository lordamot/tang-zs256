`timescale 1ns / 1ps
//========================================================================
// poke.v - the MCU's way into the SDRAM: the ROM image at start, a POKE
// while the machine runs.
//
// sysctrl.v's CMD 6 carries a 24-bit byte address of the whole chip and
// then any number of bytes; each arrives here as a one-clock strobe.
// They are queued sixteen deep and handed to membus.v's loader port as
// it has a slot, so the SPI link's pace and the processor's own traffic
// never meet.  Nothing here knows what the bytes are: a byte to an
// address.  Korvet Nano's, with the address widened.
//========================================================================
module poke (
    input             clk,
    input             reset,

    input             stb,          // a byte from sysctrl.v
    input      [23:0] adr,
    input      [7:0]  data,

    input             ack,          // one clock: membus.v took the head (its ld_ack)
    output            req,          // a level: write req_data to req_adr
    output     [23:0] req_adr,
    output     [7:0]  req_data,
    output            pending
);

reg [31:0] fifo [0:15];
reg [4:0]  wp = 5'd0, rp = 5'd0;

wire empty = (wp == rp);
wire full  = (wp[3:0] == rp[3:0]) && (wp[4] != rp[4]);

assign pending  = !empty;
assign req      = !empty;
assign req_adr  = fifo[rp[3:0]][31:8];
assign req_data = fifo[rp[3:0]][7:0];

always @(posedge clk) begin
    if (reset) begin
        wp <= 5'd0; rp <= 5'd0;
    end else begin
        if (stb && !full) begin
            fifo[wp[3:0]] <= {adr, data};
            wp <= wp + 5'd1;
        end
        if (ack && !empty) rp <= rp + 5'd1;
    end
end

endmodule
