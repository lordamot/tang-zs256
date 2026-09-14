`timescale 1ns / 1ps
//========================================================================
// video.v - the Scorpion's display, and the HDMI raster it is shown on.
//
// The machine's raster is the schematic's (infosource/, DD3-DD6 and the
// two flip-flops DD8; .claude/docs/video.md): a line is 448 pixel
// clocks of 7 MHz = 224 T-states - 256 of paper, 64 of right border,
// 64 of sync, 64 of left border - and a frame is 312 lines - 64 of top
// border, 192 of paper, 40 of bottom border, 16 of sync - 69888
// T-states, 50.08 Hz.  (The v16.2.6 redraw's counter preload gives 316
// lines; the original schematic's, DD5.D3 and DD6.D2 on BK-, gives 312,
// which is also what the emulators use.)  The interrupt is the 32
// T-states at the start of the first top border line, 64 lines before
// the paper.  Here the clock is 42 MHz, a pixel six clocks, a line 2688
// and the frame 20.0 ms; hcnt 0 is paper column 0, vcnt 0 the first
// line of the top border.
//
// Pixels come from screen.v, the display's copy of page 5 or 7: a cell
// of eight pixels is fetched during the cell before it - the pixel byte
// on the cell's first clock, the attribute on the second - and shifted
// out on the machine's pixel clock; the border colour (port FE) is
// taken at every cell boundary, as DD33/DD34's clock H2 takes it, so
// it changes in steps of 8 pixels (Unreal's "4TBorder").  The last
// attribute fetched is what port FF returns inside the paper (DD53).
// FLASH toggles every 16 frames (DD7).
//
// The HDMI side reads the line buffer back twice, so every machine line
// is two output lines of 1344 clocks (32.0 us) with 1056 active pixels -
// each of 352 machine pixels (48 of left border, the paper, 48 of right
// border) three times - which makes a 1056 x 544 picture (272 machine
// lines: 40 of top border, the paper, 40 of bottom) in a 1344 x 624
// frame at 31.25 kHz and 50.08 Hz.  Not a CEA mode; the Korvet's is
// not either and its sinks took it.  On a 16:9 sink the picture is a
// third too wide unless the sink is told 4:3, which then comes out
// right (the machine's own aspect is about 5:4 in this frame).
//
//   out_h 0..1343 : DE 0..1055, front porch 1056..1079, HSYNC 1080..1143,
//                   back porch 1144..1343 (200 clocks: hdmi_tx.v's data
//                   island wants 154 with four packets)
//   out_v 0..623  : DE 50..593 (display line n, drawn during machine
//                   line n, is read out during n+1), VSYNC 600..605
//========================================================================
module video (
    input             clk,
    input      [11:0] hcnt,         // 0..2687
    input      [8:0]  vcnt,         // 0..311

    input             screen7,      // 7FFD bit 3
    input      [2:0]  border,       // port FE bits 2:0

    // screen.v
    output     [13:0] scr_adr,
    input      [7:0]  scr_data,

    // to the machine
    output            int_n,        // the 32 T-state interrupt
    output            paper,        // inside the paper area (DD13.2's BRD-)
    output reg [7:0]  attr_ff,      // the last attribute fetched (port FF)
    output            flash,        // the flash phase

    // to the encoder, one clock a pixel
    output reg        hs,
    output reg        vs,
    output reg        de,
    output reg [7:0]  r,
    output reg [7:0]  g,
    output reg [7:0]  b
);

//------------------------------------------------------------------------
// Where we are
//------------------------------------------------------------------------
reg  [8:0] px   = 9'd0;      // the machine pixel, 0..447
reg  [2:0] pclk = 3'd0;      // the clock within it, 0..5
always @(posedge clk) begin
    if (hcnt == 12'd0) begin px <= 9'd0; pclk <= 3'd0; end
    else if (pclk == 3'd5) begin pclk <= 3'd0; px <= px + 9'd1; end
    else pclk <= pclk + 3'd1;
end

wire       v_paper = (vcnt >= 9'd64) && (vcnt < 9'd256);
wire [7:0] y       = vcnt[7:0] - 8'd64;
wire       h_paper = (px < 9'd256);
assign paper = v_paper && h_paper;
assign int_n = !(vcnt == 9'd0 && hcnt < 12'd384);

// the flash phase: the frame count's bit 4
reg [4:0] frames = 5'd0;
always @(posedge clk) if (vcnt == 9'd0 && hcnt == 12'd0) frames <= frames + 5'd1;
assign flash = frames[4];

//------------------------------------------------------------------------
// The fetch: the next cell, during this one.  The next cell is px + 8
// of this line, or cell 0 of the next line when this is the last cell
// of the left border.
//------------------------------------------------------------------------
wire        last_cell = (px == 9'd440);
wire [8:0]  npx       = last_cell ? 9'd0 : px + 9'd8;
wire [8:0]  nline     = last_cell ? ((vcnt == 9'd311) ? 9'd0 : vcnt + 9'd1) : vcnt;
wire        nfetch    = (nline >= 9'd64) && (nline < 9'd256) && (npx < 9'd256);
wire [7:0]  ny        = nline[7:0] - 8'd64;
wire [4:0]  nx        = npx[7:3];
wire        cell_start = (px[2:0] == 3'd0) && (pclk == 3'd0);

reg  [13:0] radr = 14'd0;
reg  [7:0]  f_pix = 8'd0, f_attr = 8'd0;
reg         f_valid = 1'b0;
reg  [3:0]  fstep = 4'd0;

// the address: pixel byte {y7 y6, y2 y1 y0, y5 y4 y3, x}, attribute
// 1800h + {y7..y3, x}, on the page 7FFD says
assign scr_adr = radr;
always @(posedge clk) begin
    if (cell_start) begin
        fstep <= nfetch ? 4'd1 : 4'd0;
        radr  <= {screen7, ny[7:6], ny[2:0], ny[5:3], nx};
    end else if (fstep != 4'd0) begin
        fstep <= fstep + 4'd1;
        case (fstep)
            4'd1: radr <= {screen7, 2'b11, 1'b0, ny[7:3], nx};   // 1800h + row * 32 + x
            4'd2: f_pix  <= scr_data;
            4'd3: begin f_attr <= scr_data; attr_ff <= scr_data; fstep <= 4'd0; end
            default: ;
        endcase
    end
    if (cell_start) f_valid <= nfetch;
end

//------------------------------------------------------------------------
// The render: at each cell boundary the fetched cell (or the border) is
// taken, then shifted a bit a pixel.  The colour is four bits,
// {bright, green, red, blue}, into the line buffer.
//------------------------------------------------------------------------
reg  [7:0] s_pix  = 8'd0;
reg  [7:0] s_attr = 8'd0;
reg        s_paper = 1'b0;
reg  [2:0] s_border = 3'd0;

always @(posedge clk) begin
    if (cell_start) begin
        s_pix    <= f_pix;
        s_attr   <= f_attr;
        s_paper  <= f_valid;
        s_border <= border;
    end else if (pclk == 3'd5)
        s_pix <= {s_pix[6:0], 1'b0};
end

wire       inv   = s_attr[7] & flash;
wire       dot   = s_pix[7] ^ inv;
wire [3:0] pix   = s_paper ? {s_attr[6], (dot ? s_attr[2:0] : s_attr[5:3])} : {1'b0, s_border};

// the display position: the left border (px 400..447) leads the line
// that follows, so it goes into the next display line's buffer
wire       vis      = (px >= 9'd400) || (px < 9'd304);
wire [8:0] dpos     = (px >= 9'd400) ? px - 9'd400 : px + 9'd48;
wire [8:0] dline    = (px >= 9'd400) ? vcnt + 9'd1 : vcnt;

// two lines of 352: the one being drawn and the one being shown
reg [3:0] lbuf [0:1023];
always @(posedge clk)
    if (vis && pclk == 3'd1) lbuf[{dline[0], dpos}] <= pix;

//------------------------------------------------------------------------
// The output raster, two lines an input line
//------------------------------------------------------------------------
wire        second = (hcnt >= 12'd1344);
wire [10:0] out_h  = second ? hcnt[10:0] - 11'd1344 : hcnt[10:0];
wire [9:0]  out_v  = {vcnt, second};

wire de_n = (out_h < 11'd1056) && (vcnt >= 9'd25) && (vcnt <= 9'd296);
wire hs_n = (out_h >= 11'd1080) && (out_h < 11'd1144);
wire vs_n = (out_v >= 10'd600) && (out_v < 10'd606);

// out_h / 3, a pixel three clocks wide
reg [8:0] ox = 9'd0;
reg [1:0] o3 = 2'd0;
always @(posedge clk) begin
    if (out_h == 11'd0) begin ox <= 9'd0; o3 <= 2'd0; end
    else if (o3 == 2'd2) begin o3 <= 2'd0; ox <= ox + 9'd1; end
    else o3 <= o3 + 2'd1;
end

reg [3:0] q;
always @(posedge clk) begin
    q  <= lbuf[{~vcnt[0], ox}];
    hs <= hs_n;
    vs <= vs_n;
    de <= de_n;
end

// the Spectrum's palette: a lit component is CDh, or FFh when bright
wire [7:0] on = q[3] ? 8'hFF : 8'hCD;
always @(*) begin
    g = q[2] ? on : 8'h00;
    r = q[1] ? on : 8'h00;
    b = q[0] ? on : 8'h00;
end

endmodule
