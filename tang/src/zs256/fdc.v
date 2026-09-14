`timescale 1ns / 1ps
//========================================================================
// fdc.v - the Scorpion's Beta Disk: a КР1818ВГ93 with four .trd images.
//
// The chip is MiSTer's wd1793.sv (MikeJ, Sorgelig) in its sector-image
// mode, as Korvet Nano uses it: a .trd is 80 tracks x 2 sides x 16
// sectors of 256 bytes in track-side-sector order, 655360 bytes, the
// image the TR-DOS world exchanges; a 40-track or one-sided image is
// just shorter.  The registers are the Beta 128's, reached only with
// DOS on (memmap.v), A0 = A1 = 1 (DD65's decode, .claude/docs/platform.md):
//
//   A7 = 0   the ВГ93, its register on A6, A5: 1F command/status,
//            3F track, 5F sector, 7F data
//   A7 = 1   the system register (DD57), written: bits 1:0 the drive,
//            2 the chip's reset (0 resets), 3 HLT, 4 the side (0 is
//            side 1), 6 the density; read (CSRD): bit 6 DRQ, bit 7
//            INTRQ, the rest the Kempston joystick (ports.v)
//
// The chip wants its rd/wr as levels a few of its clock enables long
// (it edge-detects them on `ce`, the machine's 3.5 MHz whatever the
// processor's speed), so a one-clock strobe from the bus is stretched
// to 24 clocks; the register's byte is on the bus from the strobe on
// and taken three clocks after it.
//========================================================================
module fdc (
    input             clk,
    input             reset,
    input             ce,           // 3.5 MHz enable
    input             en,           // the OSD's floppy switch

    // the bus: a strobe with the request, DOS on, A0 = A1 = 1
    input             io_stb,
    input      [7:0]  a,
    input             we,
    input      [7:0]  wdata,
    output reg [7:0]  rdata,        // the ВГ93's register, valid three clocks after rd_stb
    output            drq,
    output            intrq,

    // the images
    input      [3:0]  mounted,      // one clock each: slots 0..3
    input      [31:0] image_size,
    input      [3:0]  present,
    input      [3:0]  wprot,

    // the SD path: client 0..3 by drive
    output     [1:0]  drive,
    output            sd_rd,
    output            sd_wr,
    output     [31:0] sd_sector,
    input             sd_ack,
    input             sd_done,
    input             outen,
    input      [8:0]  outaddr,
    input      [7:0]  outbyte,
    output     [7:0]  inbyte,

    output            busy          // for an LED
);

//------------------------------------------------------------------------
// The system register
//------------------------------------------------------------------------
reg [7:0] sysreg = 8'h00;
assign drive = sysreg[1:0];
wire      side  = !sysreg[4];
wire      wd_reset = reset || !en || !sysreg[2];

wire sys_wr = io_stb && we && a[7];
wire wd_acc = io_stb && !a[7];

always @(posedge clk) begin
    if (reset) sysreg <= 8'h00;
    else if (sys_wr) sysreg <= wdata;
end

//------------------------------------------------------------------------
// The chip
//------------------------------------------------------------------------
reg  [1:0]  a_r = 2'd0;
reg  [7:0]  wd_din = 8'd0;
reg  [4:0]  rd_hold = 5'd0, wr_hold = 5'd0;
reg  [2:0]  rd_pipe = 3'd0;

wire [7:0] wd_dout;
wire       wd_rd = (rd_hold != 5'd0);
wire       wd_wr = (wr_hold != 5'd0);
wire       wd_io = en && (wd_rd || wd_wr);

wd1793 #(.RWMODE(1), .EDSK(0)) chip (
    .clk_sys     (clk),
    .ce          (ce),
    .reset       (wd_reset),
    .io_en       (wd_io),
    .rd          (wd_rd),
    .wr          (wd_wr),
    .addr        (a_r),
    .din         (wd_din),
    .dout        (wd_dout),
    .drq         (drq),
    .intrq       (intrq),
    .busy        (busy),
    .wp          (wprot[drive]),
    .size_code   (3'd1),           // 16 x 256
    .layout      (1'b0),           // track, side, sector
    .side        (side),
    .ready       (present[drive]),
    .img_mounted (|mounted),
    .img_size    (image_size),
    .prepare     (),
    .sd_lba      (sd_sector),
    .sd_rd       (sd_rd),
    .sd_wr       (sd_wr),
    .sd_ack      (sd_ack),
    .sd_buff_addr(outaddr),
    .sd_buff_dout(outbyte),
    .sd_buff_din (inbyte),
    .sd_buff_wr  (outen && sd_ack),
    .input_active(1'b0),
    .input_addr  (20'd0),
    .input_data  (8'd0),
    .input_wr    (1'b0),
    .buff_addr   (),
    .buff_read   (),
    .buff_din    (8'd0)
);

always @(posedge clk) begin
    rd_pipe <= {rd_pipe[1:0], wd_acc && !we && en};
    if (rd_hold != 5'd0) rd_hold <= rd_hold - 5'd1;
    if (wr_hold != 5'd0) wr_hold <= wr_hold - 5'd1;
    if (reset) begin
        rd_hold <= 5'd0; wr_hold <= 5'd0;
    end else begin
        if (wd_acc && !we && en) begin a_r <= a[6:5]; rd_hold <= 5'd24; end
        if (wd_acc &&  we && en) begin a_r <= a[6:5]; wd_din <= wdata; wr_hold <= 5'd24; end
    end
    if (rd_pipe[1]) rdata <= en ? wd_dout : 8'hFF;
end

endmodule
