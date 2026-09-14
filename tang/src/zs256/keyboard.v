`timescale 1ns / 1ps
//========================================================================
// keyboard.v - the Spectrum's 8 x 5 matrix, filled from the MCU's bytes.
//
// The USB keyboard is read by the BL616 and every press or release
// arrives here as one byte through hid.v (mnano/zs256.h says which key
// is which code): bit 7 set for a release, bits 6:0 the code -
//
//   1..40     a key of the matrix, row * 5 + column + 1
//   41..80    the same key with Caps Shift held for it
//   81..120   the same key with Symbol Shift held for it
//   121       Caps Shift and Symbol Shift together (extended mode)
//   0         no key (the firmware's MISS)
//
// so that a PC key with no place on the machine - Backspace, the cursor
// keys, the punctuation - can be one of the machine's two-key chords.
// Each key is a bit in one of three maps - down plain, down with Caps
// Shift, down with Symbol Shift - and a shift is held while any bit of
// its map is set, so two chords sharing a shift, or a shift the user
// holds for its own sake, come and go without dropping each other, and
// a press repeated or a release without its press (the USB report
// packs its slots, and the firmware's diff used to send both) changes
// nothing: the first cut counted the chords' shifts and a double press
// left a shift held for good (the first board, 14 Sep 2026).
//
// The matrix, rows by the address bit that reads them (port FE):
//   A8:  CS  Z  X  C  V      A12: 0  9  8  7  6
//   A9:  A   S  D  F  G      A13: P  O  I  U  Y
//   A10: Q   W  E  R  T      A14: EN L  K  J  H
//   A11: 1   2  3  4  5      A15: SP SS M  N  B
// A read with several row bits low ANDs the rows, as the wiring does.
//========================================================================
module keyboard (
    input             clk,
    input             reset,

    input      [7:0]  code,         // hid.v's keyboard byte
    input             stb,          // one clock: a byte arrived

    input      [7:0]  rows_n,       // A15..A8 of the read
    output     [4:0]  bits          // D4..D0, active low
);

reg [39:0] plain = 40'd0;      // keys down on their own
reg [39:0] withcs = 40'd0;     // keys down as a Caps Shift chord
reg [39:0] withss = 40'd0;     // keys down as a Symbol Shift chord
reg        ext   = 1'b0;       // the CS+SS chord

wire        up = code[7];
wire [6:0]  c       = code[6:0];
wire [6:0]  k7      = (c >= 7'd81) ? c - 7'd81 : (c >= 7'd41) ? c - 7'd41 : c - 7'd1;
wire [5:0]  k       = k7[5:0];
wire        is_key  = (c >= 7'd1)  && (c <= 7'd40);
wire        is_cs   = (c >= 7'd41) && (c <= 7'd80);
wire        is_ss   = (c >= 7'd81) && (c <= 7'd120);

always @(posedge clk) begin
    if (reset) begin
        plain <= 40'd0; withcs <= 40'd0; withss <= 40'd0; ext <= 1'b0;
    end else if (stb) begin
        if (is_key) plain[k]  <= !up;
        if (is_cs)  withcs[k] <= !up;
        if (is_ss)  withss[k] <= !up;
        if (c == 7'd121) ext <= !up;
    end
end

wire [39:0] down = plain | withcs | withss |
                   {39'd0, (withcs != 40'd0) | ext} |          // key 0: Caps Shift
                   ({39'd0, (withss != 40'd0) | ext} << 36);   // key 36: Symbol Shift

// AND the selected rows: a bit is low when its key is down in any of them
reg [4:0] hit;
integer r;
always @(*) begin
    hit = 5'd0;
    for (r = 0; r < 8; r = r + 1)
        if (!rows_n[r]) hit = hit | down[r*5 +: 5];
end
assign bits = ~hit;

endmodule
