`timescale 1ns / 1ps
//========================================================================
// ay.v - the AY-3-8912 on ports FFFD / BFFD.
//
// The chip is MiSTer's ym2149.sv (Sorgelig), clocked at the Scorpion's
// 1.75 MHz (H1: the 7 MHz pixel clock over four; here an enable every
// 24 clocks).  The bus is DD48's: a write to FFFD latches the register
// number, a write to BFFD the value, a read of FFFD the register - the
// port is CSFD with A15 = 1 and A14 telling the two apart (A13, the
// chip's BC2 on the board, is not decoded: the fix every Scorpion owner
// makes, infosource/fixes/ay-fix).  The core takes a one-clock BDIR/BC
// pulse for a write and answers a read combinationally.
//
// The three channels go out separately so that top.v can place them:
// ABC (A left, C right, B in both) is the board's jumper default.
//========================================================================
module ay (
    input             clk,
    input             reset,
    input             en,           // the OSD's switch

    input             io_stb,       // one clock, with the request: CSFD and A15
    input             a14,
    input             we,
    input      [7:0]  wdata,
    output     [7:0]  rdata,

    output     [7:0]  ch_a,
    output     [7:0]  ch_b,
    output     [7:0]  ch_c
);

// 42 MHz / 24 = 1.75 MHz
reg [4:0] div = 5'd0;
wire      ce  = (div == 5'd23);
always @(posedge clk) div <= ce ? 5'd0 : div + 5'd1;

wire wr_addr = io_stb && we && a14;      // FFFD
wire wr_data = io_stb && we && !a14;     // BFFD
wire rd_reg  = !a14 ? 1'b0 : 1'b1;       // a read is always FFFD's

wire [7:0] do_;
YM2149 chip (
    .CLK      (clk),
    .CE       (ce),
    .RESET    (reset | ~en),
    .BDIR     (wr_addr | wr_data),
    .BC       (wr_addr | !(wr_addr | wr_data)),   // 1 when reading, 1 for the address latch
    .DI       (wdata),
    .DO       (do_),
    .CHANNEL_A(ch_a),
    .CHANNEL_B(ch_b),
    .CHANNEL_C(ch_c),
    .SEL      (1'b0),
    .MODE     (1'b1),
    .ACTIVE   (),
    .IOA_in   (8'hFF),
    .IOA_out  (),
    .IOB_in   (8'hFF),
    .IOB_out  ()
);

assign rdata = (en && rd_reg) ? do_ : 8'hFF;

endmodule
