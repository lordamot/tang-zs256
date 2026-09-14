`timescale 1ns / 1ps
//========================================================================
// ports.v - the Scorpion's I/O bus: who answers which port.
//
// The board's decode, out of the schematic (DD32, DD52, DD65 and the
// gates around them; .claude/docs/platform.md has the table), with the
// cards on the ZX-BUS ahead of it - each of them pulls IORQGE for its
// own ports, which blocks the board's decode:
//
//   the SMUC (smuc.v)      xxBA, xxBE - when it is on
//   General Sound (gs.v)   B3, BB
//   the Kempston mouse     FADF, FBDF, FFDF
//
// and then the board.  DD32 decodes A0, A1, A5 with IORQ and not M1, and
// is disabled by A1 & DOS (DD66.3), so with TR-DOS on only the xxFD
// ports are left of it:
//
//   DOS off:  FE   A0=0 A1=1 A5=1    written: border, MIC, beeper (DD35)
//                                   read: the keyboard, bit 6 the tape,
//                                   bit 5 and 7 high (DSR, BUSY)
//             1F   A0=1 A1=1 A5=0    read: the Kempston joystick, bit 5
//                                   low, bits 6, 7 the ВГ93's DRQ and INTRQ
//             FF   A0=1 A1=1 A5=1    read: the attribute the display is
//                                   fetching, or FFh in the border (DD53)
//             xxFD A0=1 A1=0 A5=1    A15 A14: 00 1FFD, 01 7FFD (memmap.v),
//                                   10 BFFD, 11 FFFD (ay.v)
//   DOS on:   A0=1 A1=1 (DD65):     A7=0 the ВГ93, A7=1 the system
//                                   register / the same byte as 1F above
//             xxFD as above; FE is nobody's: reads get FFh, writes nothing
//
// The read data is muxed here from what the devices answer; the strobes
// out are one clock with the request, on which the devices act.  A read
// takes four clocks from the strobe (top.v), which is what the ВГ93 and
// the SMUC need to answer.
//========================================================================
module ports (
    input             clk,
    input             reset,

    // the request, and its strobe
    input             io_stb,
    input      [15:0] A,
    input             we,
    input      [7:0]  wdata,
    input             m1,           // an interrupt acknowledge: FFh
    input             dos,

    // the OSD
    input             en_smuc,
    input             en_gs,
    input             en_mouse,
    input             en_joy,

    // what the devices answered (valid by the third clock after the strobe)
    input             smuc_sel,
    input      [7:0]  smuc_rdata,
    input      [7:0]  gs_rdata,
    input      [7:0]  ay_rdata,
    input      [7:0]  fdc_rdata,
    input             fdc_drq,
    input             fdc_intrq,
    input      [4:0]  kbd_bits,
    input             tape_in,
    input      [7:0]  attr_ff,
    input             paper,
    input      [7:0]  joystick,     // hid.v: bit 0 right? see below
    input      [7:0]  mouse_x,
    input      [7:0]  mouse_y,
    input      [1:0]  mouse_btn,    // {right, left}, pressed = 1

    output     [7:0]  rdata,

    // the strobes
    output            fe_wr,
    output reg [7:0]  p_fe,         // port FE as written
    output            fdc_stb,      // the ВГ93 or its system register (fdc.v decodes A7)
    output            ay_stb,       // CSFD with A15
    output            gs_stb,
    output            smuc_stb
);

wire not_m1 = !m1;
wire csfd   = not_m1 && A[0] && !A[1] && A[5];
wire y3     = not_m1 && A[0] &&  A[1] && !A[5];    // 1F
wire y6     = not_m1 && !A[0] && A[1] &&  A[5];    // FE
wire y7     = not_m1 && A[0] &&  A[1] &&  A[5];    // FF
wire dd32   = !(A[1] && dos);                        // DD32's E1

// Every card's decoder has M1 in it (General Sound's VD10, the SMUC's
// ИД7 enable), and it matters: an interrupt acknowledge is an I/O cycle
// with M1 and the PC on the address bus, and in IM 2 the byte it reads
// is the vector.  Without M1 here a program whose PC was xxBBh at the
// interrupt got General Sound's status for its vector and jumped into
// nowhere with interrupts off - ZPLAY's shell on the first board, one
// key press in (14 Sep 2026).  An acknowledge reads FFh below, as the
// board's open bus gives.
wire smuc_hit  = en_smuc && smuc_sel && not_m1;
wire gs_sel    = en_gs && not_m1 && (A[7:0] == 8'hB3 || A[7:0] == 8'hBB);
wire mouse_sel = en_mouse && (A[7:0] == 8'hDF) && !A[5] && not_m1;
wire ext_sel   = smuc_hit || gs_sel || mouse_sel;

assign smuc_stb = io_stb && smuc_hit;
assign gs_stb   = io_stb && gs_sel && !smuc_hit;
assign ay_stb   = io_stb && !ext_sel && csfd && A[15];
assign fe_wr    = io_stb && !ext_sel && we && y6 && dd32;
assign fdc_stb  = io_stb && !ext_sel && dos && not_m1 && A[0] && A[1];

always @(posedge clk) begin
    if (reset) p_fe <= 8'd0;
    else if (fe_wr) p_fe <= wdata;
end

// the Kempston byte: bit 0 right, 1 left, 2 down, 3 up, 4 fire, active
// high - hid.v's joystick byte is MiSTeryNano's {., ., ., fire, up, down,
// left, right}
wire [4:0] kemp = en_joy ? {joystick[4], joystick[3], joystick[2], joystick[1], joystick[0]} : 5'd0;
wire [7:0] joy_byte = {fdc_intrq, fdc_drq, 1'b0, kemp};
wire [7:0] kbd_byte = {1'b1, tape_in, 1'b1, kbd_bits};

reg [7:0] board;
always @(*) begin
    board = 8'hFF;
    if (m1) board = 8'hFF;
    else if (dos) begin
        if (A[0] && A[1] && A[7])  board = joy_byte;           // CSRD
        if (A[0] && A[1] && !A[7]) board = fdc_rdata;          // the ВГ93
        if (csfd && A[15] && A[14]) board = ay_rdata;          // FFFD
    end else begin
        if (y6)  board = kbd_byte;
        if (y3)  board = joy_byte;
        if (y7)  board = paper ? attr_ff : 8'hFF;
        if (csfd && A[15] && A[14]) board = ay_rdata;
    end
end

wire [7:0] mouse_byte = !A[8] ? {6'b111111, ~mouse_btn} :     // FADF: buttons, active low
                        !A[10] ? mouse_x : mouse_y;            // FBDF, FFDF

assign rdata = smuc_hit   ? smuc_rdata :
               gs_sel    ? gs_rdata :
               mouse_sel ? mouse_byte : board;

endmodule
