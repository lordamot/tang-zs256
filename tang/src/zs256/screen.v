`timescale 1ns / 1ps
//========================================================================
// screen.v - the display's own copy of the two screen pages.
//
// The Scorpion's video circuit reads its pixels and attributes out of
// the DRAM in the gaps between the processor's cycles; here the DRAM is
// the SDRAM and its slots are the processors', so the display keeps a
// copy of the 6912 bytes of page 5 and of page 7 in BSRAM and reads
// that.  membus.v hands every write into those bytes over as it takes
// it (from the Z80 or from the MCU's loader), so the copy is never
// behind the SDRAM by more than a clock, and nothing reads the screen
// out of the SDRAM.  16 KB, of which 13.5 are used: {page 7, offset}.
//
// One write port, one read port a clock behind its address: Gowin's
// simple dual-port BSRAM, eight blocks.
//========================================================================
module screen (
    input             clk,

    input             we,
    input      [13:0] wadr,
    input      [7:0]  wdata,

    input      [13:0] radr,
    output reg [7:0]  rdata
);

reg [7:0] mem [0:16383];

always @(posedge clk) begin
    if (we) mem[wadr] <= wdata;
    rdata <= mem[radr];
end

endmodule
