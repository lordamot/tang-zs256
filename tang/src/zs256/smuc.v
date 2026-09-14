`timescale 1ns / 1ps
//========================================================================
// smuc.v - SMUC, the Scorpion & MOA Universal Controller: an IDE port,
// a clock chip and an NVRAM on the ZX-BUS.
//
// The card decodes A12 = A11 = A7 = A5 = A1 = 1, A0 = 0, A6 = 0 (its
// ports are all xxBA and xxBE) and then A15, A13 and A2, as Unreal
// Speccy has it (io.cpp, the IDE_SMUC scheme), which is what the
// software written for it - ProfROM 4, iS-DOS, TASiS - was tested on:
//
//   5FBA  read   3Fh
//   5FBE  read   57h        the card's version
//   7FBE  read   57h
//   7FBA  write  the "virtual" register; read: it, with 3Fh in the low bits
//   DFBA  write  the clock's address, or with FFBA bit 7 set its data;
//         read   the clock's data
//   FFBA  write  bit 7 the mode below, bit 0 resets the drive, bits 6, 4
//                and 5 the NVRAM's SCL, SDA and WP; read: SDA on bit 6
//   xxBE  A15 = 1: the IDE (ide.v).  FFBA bit 7 clear: A13 = 0 the
//         high-byte latch - written before the data register's low
//         byte, read after it; A13 = 1 the drive's register A10..A8,
//         the data register at 0.  Bit 7 set: A8 = 0 the control block
//         (device control written, alternate status read), A8 = 1 reads FFh.
//
// The bus is 8 bits and the drive's data register is 16: a write puts
// the latched high byte with the low byte written; a read gives the
// low byte and keeps the high one for the next read of the latch.
//========================================================================
module smuc (
    input             clk,
    input             reset,
    input             en,           // the OSD's switch: without it the card is not there

    // the bus: a strobe with the request
    input             io_stb,
    input      [15:0] A,
    input             we,
    input      [7:0]  wdata,
    output            sel,          // this address is the card's (IORQGE)
    output reg [7:0]  rdata,        // valid two clocks after the strobe

    // the disk image (sd_card.v slot 4)
    input             hd_mounted,
    input      [31:0] hd_size,
    output            hd_present,
    output            hd_rd,
    output            hd_wr,
    output     [31:0] hd_sector,
    input             hd_ack,
    input             hd_done,
    input             hd_outen,
    input      [8:0]  hd_outaddr,
    input      [7:0]  hd_outbyte,
    output     [7:0]  hd_inbyte,
    output            hd_busy
);

wire family = en && A[12] && A[11] && A[7] && !A[6] && A[5] && A[1] && !A[0];
assign sel  = family;

wire p_5fba = family && !A[2] && !A[15] && !A[13];
wire p_7fba = family && !A[2] && !A[15] &&  A[13];
wire p_dfba = family && !A[2] &&  A[15] && !A[13];
wire p_ffba = family && !A[2] &&  A[15] &&  A[13];
wire p_vers = family &&  A[2] && !A[15];             // 5FBE, 7FBE
wire p_ide  = family &&  A[2] &&  A[15];

reg [7:0] r_ffba = 8'd0, r_7fba = 8'd0;
reg [7:0] hi_latch_w = 8'd0, hi_latch_r = 8'd0;

// the drive
wire        ide_ctrl = r_ffba[7];
wire        ide_stb  = io_stb && p_ide && (ide_ctrl ? !A[8] : A[13]);
wire [2:0]  ide_reg  = ide_ctrl ? 3'd0 : A[10:8];
wire [15:0] ide_rdata;

ide drive (
    .clk(clk), .reset(reset || !en || (io_stb && p_ffba && we && wdata[0])),
    .stb(ide_stb), .reg_a(ide_reg), .ctrl(ide_ctrl), .we(we), .wdata({hi_latch_w, wdata}), .rdata(ide_rdata),
    .mounted(hd_mounted), .image_size(hd_size), .present(hd_present),
    .sd_rd(hd_rd), .sd_wr(hd_wr), .sd_sector(hd_sector), .sd_ack(hd_ack), .sd_done(hd_done),
    .outen(hd_outen), .outaddr(hd_outaddr), .outbyte(hd_outbyte), .inbyte(hd_inbyte), .busy(hd_busy)
);

// the clock
wire [7:0] rtc_rdata;
rtc clock (
    .clk(clk), .reset(reset),
    .stb(io_stb && p_dfba), .we(we), .sel_adr(!r_ffba[7]), .wdata(wdata), .rdata(rtc_rdata)
);

// the NVRAM
wire sda_in;
nvram eeprom (
    .clk(clk), .reset(reset),
    .stb(io_stb && p_ffba && we), .wdata(wdata), .sda_in(sda_in)
);

always @(posedge clk) begin
    if (reset) begin
        r_ffba <= 8'd0; r_7fba <= 8'd0; hi_latch_w <= 8'd0; hi_latch_r <= 8'd0;
    end else if (io_stb) begin
        if (we) begin
            if (p_ffba) r_ffba <= wdata;
            if (p_7fba) r_7fba <= wdata;
            if (p_ide && !ide_ctrl && !A[13]) hi_latch_w <= wdata;
        end else begin
            if (p_ide && !ide_ctrl && A[13] && A[10:8] == 3'd0) hi_latch_r <= ide_rdata[15:8];
        end
    end
end

// the answer, registered a clock after the strobe (the drive's buffer
// reads a clock behind): rdata stands from two clocks after it
reg [7:0] ans = 8'hFF;
reg       stb_d = 1'b0;
always @(posedge clk) begin
    stb_d <= io_stb;
    if (stb_d) rdata <= ans;
    if (io_stb) begin
        ans <= 8'hFF;
        if (p_5fba) ans <= 8'h3F;
        if (p_vers) ans <= 8'h57;
        if (p_7fba) ans <= r_7fba | 8'h3F;
        if (p_dfba) ans <= rtc_rdata;
        if (p_ffba) ans <= {1'b1, sda_in, 6'b111111};
        if (p_ide) begin
            if (ide_ctrl) ans <= A[8] ? 8'hFF : ide_rdata[7:0];
            else if (!A[13]) ans <= hi_latch_r;
            else ans <= ide_rdata[7:0];
        end
    end
end

endmodule
