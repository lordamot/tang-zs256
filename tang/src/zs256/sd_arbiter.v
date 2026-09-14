`timescale 1ns / 1ps
//========================================================================
// sd_arbiter.v - one owner at a time on the SD path.
//
// sd_card.v serves one sector transfer at a time and the MCU picks the
// requester from a one-hot mask, so two requesters visible at once are
// misread (UKNC Nano put a hard disk's home block into a floppy's
// sector that way).  Five clients here - the four floppies (slots 0..3)
// and the ROM loader (4) - each
// raise a request level with a sector number, and this hands the path
// to the lowest-numbered one that asks while the path is idle, keeps
// it until sd_card.v reports the transfer done, and gates the byte
// stream to the owner.
//
// Protocol on the client side:
//   rd/wr     a level, held at least until ack rises; the direction
//             and the sector are taken at the grant, and dropping rd/wr
//             after ack (which every client here does) changes nothing
//   sector    the sector within the image, in 512-byte units
//   ack       a level: this client owns the path, from the grant to
//             the end of its transfer
//   done      one clock at the end of the transfer, with ack still up
//   outen/outaddr/outbyte   a byte of the sector arriving (reads),
//             gated to the owner
//   inbyte    the owner's byte for outaddr (writes)
// On sd_card.v's side: rstart/wstart one-hot, held from the grant
// until rbusy rises (as fdd4.v did it), rsector, rbusy, rdone.  Held
// is the point: the MCU polls rstart/wstart as a level and takes the
// direction from it when it starts the transfer, milliseconds after
// the request.  The first version dropped the request as soon as the
// client dropped rd on ack, one clock after the grant, and the card
// model then read it as a write (4 Sep 2026).
//========================================================================
module sd_arbiter (
    input             clk,
    input             reset,

    input      [4:0]  c_rd,
    input      [4:0]  c_wr,
    input      [159:0] c_sector,    // 5 x 32, client 0 in bits 31:0
    input      [39:0] c_inbyte,     // 5 x 8
    output     [4:0]  c_ack,
    output reg [4:0]  c_done,
    output     [4:0]  c_outen,

    output reg [4:0]  rstart,
    output reg [4:0]  wstart,
    output reg [31:0] rsector,
    output reg [7:0]  inbyte,
    input             rbusy,
    input             rdone,
    input             outen
);

localparam [1:0] S_IDLE = 2'd0, S_REQ = 2'd1, S_XFER = 2'd2;

reg [1:0] state = S_IDLE;
reg [2:0] owner = 3'd0;
reg       is_wr = 1'b0;

wire [4:0] want  = c_rd | c_wr;
wire [2:0] grant = want[0] ? 3'd0 : want[1] ? 3'd1 : want[2] ? 3'd2 : want[3] ? 3'd3 : 3'd4;

assign c_ack   = (state == S_IDLE) ? 5'd0 : (5'd1 << owner);
assign c_outen = (state == S_XFER && outen) ? (5'd1 << owner) : 5'd0;

integer i;
always @(*) begin
    inbyte = 8'h00;
    for (i = 0; i < 5; i = i + 1)
        if (owner == i[2:0]) inbyte = c_inbyte[i*8 +: 8];
end

always @(posedge clk) begin
    c_done <= 5'd0;
    if (reset) begin
        state  <= S_IDLE;
        rstart <= 5'd0;
        wstart <= 5'd0;
        owner  <= 3'd0;
    end else case (state)
        S_IDLE: begin
            rstart <= 5'd0;
            wstart <= 5'd0;
            if (!rbusy && want != 5'd0) begin
                // the lowest-numbered client that asks; its direction
                // and sector are taken now
                owner   <= grant;
                is_wr   <= c_wr[grant];
                rsector <= c_sector[grant*32 +: 32];
                state   <= S_REQ;
            end
        end
        S_REQ: begin
            // present the request until the card is busy on it
            rstart <= is_wr ? 5'd0 : (5'd1 << owner);
            wstart <= is_wr ? (5'd1 << owner) : 5'd0;
            if (rbusy) begin
                rstart <= 5'd0;
                wstart <= 5'd0;
                state  <= S_XFER;
            end
        end
        S_XFER: begin
            if (rdone) begin
                c_done[owner] <= 1'b1;
                state <= S_IDLE;
            end
        end
        default: state <= S_IDLE;
    endcase
end

endmodule
