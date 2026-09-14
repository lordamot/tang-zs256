`timescale 1ns / 1ps
//========================================================================
// gs.v - General Sound: X-Trade's sound card (1997), a computer of its
// own on the ZX-BUS.
//
// A Z80 at 12 MHz with 32 KB of ROM and 2 MB of RAM (the card's most:
// its page register is six bits, 63 pages of 32 KB), four 8-bit DACs
// with 6-bit volumes, and four registers the Spectrum sees:
//
//   port BBh  written: the command (sets the status's bit 0)
//             read: the status - bit 7 the data flag, bit 0 the command flag
//   port B3h  written: a byte for the card (sets bit 7)
//             read: a byte from the card (clears bit 7)
//
// (Stinger's programming guide, ZX-News #26; gs105a.rom is the card's
// firmware, from psbhlw/gs-firmware).  Inside, the card's Z80 sees
//
//   0000-3FFF  the ROM's first half
//   4000-7FFF  16 KB of RAM, always the same (the firmware's variables
//              and stack; not part of any window page)
//   8000-FFFF  a 32 KB window: page 0 the whole ROM, page n the RAM's
//              32 KB block n (port 0's value, 1..63)
//   6000-7FFF  read: the byte read goes to the DAC of channel A9:A8
//              (LD A,(6000h) plays a sample byte on channel 0)
//
//   port 00 written: the page;   01 read: the command from the host
//   02 read: the data byte from the host, and the data flag falls
//   03 written: a byte for the host, and the data flag rises
//   04 read: the status;         05 read or written: the command flag falls
//   06..09 written: the volumes of channels 0..3, six bits
//   0A: bit 7 of the status <= the page's bit 0;  0B: bit 0 <= volume 0's bit 5
//   INT every 320 clocks of 12 MHz (37.5 kHz), IM 1
//
// which is Unreal Speccy's model (gsz80.cpp), less its NGS extensions.
//
// Here: the card's Z80 is tv80 through z80bus.v on an enable every
// third clock, 14 MHz.  Its ROM and its fixed 16 KB are BSRAM and answer
// inside T2, no wait state - the firmware's interrupt handler and its
// sample generator run there, and the card is a computer keeping up
// with a 37.5 kHz sample clock: through the SDRAM's slot B every access
// waited about four T-states and the card ran at half its speed, the
// generator fell behind the interrupt and the DACs played whatever was
// in the buffers (found on the first board, 14 Sep 2026).  The window's
// RAM pages are the SDRAM's slot B (words 80000h-FFFFFh, 2 MB), one
// access a T-state of the host's, waited.  The ROM copy is filled by
// the MCU's loader as it writes the image (ld_we: top.v snoops poke.v's
// bytes to 400000h, the SDRAM's copy of the ROM stays unread).
//
// The interrupt is set by a 42 MHz / 1120 counter and held until the
// acknowledge: on the card it is an RC pulse of some microseconds
// (DD17.6, C18, R8 on the schematic), longer than any instruction, and
// a pulse of a fixed few T-states here was missed under a waited
// instruction.  The flags are set-wins: the card's own are flip-flops
// set by one side and cleared by the other, and a byte written on the
// clock its predecessor is read must stay flagged.
// Channels 0 and 1 are the left output, 2 and 3 the right; a sample is
// (byte - 128) * volume, 14 bits signed a channel.
//========================================================================
module gs (
    input             clk,
    input             reset,        // the card's reset: the machine's, or the OSD's switch off

    // the host's port access: a strobe with the request, A7..A0 = B3 or BB
    input             io_stb,
    input             a3,           // 1: BB (command/status), 0: B3 (data)
    input             we,
    input      [7:0]  wdata,
    output     [7:0]  rdata,

    // the MCU's loader writing the ROM image (top.v)
    input             ld_we,
    input      [14:0] ld_adr,
    input      [7:0]  ld_data,

    // sdram.v's slot B: the window's RAM pages
    output            b_req,
    output            b_we,
    output     [20:0] b_adr,
    output     [31:0] b_wdata,
    output     [3:0]  b_wmask,
    input             b_take,
    input      [31:0] b_rdata,
    input             b_ack,

    output signed [15:0] out_l,
    output signed [15:0] out_r,

    // for the testbench
    output     [15:0] dbg_pc,
    output            dbg_m1
);

//------------------------------------------------------------------------
// The host's side
//------------------------------------------------------------------------
reg [7:0] cmd    = 8'd0;     // BB written
reg [7:0] to_gs  = 8'd0;     // B3 written
reg [7:0] to_zx  = 8'd0;     // port 03 written
reg       f_cmd  = 1'b0;     // status bit 0
reg       f_data = 1'b0;     // status bit 7
reg       cmd_set, cmd_clr, dat_set, dat_clr;     // this clock's events

assign rdata = a3 ? {f_data, 6'b111111, f_cmd} : to_zx;

//------------------------------------------------------------------------
// The card's Z80
//------------------------------------------------------------------------
reg [1:0] div3 = 2'd0;
always @(posedge clk) div3 <= (div3 == 2'd2) ? 2'd0 : div3 + 2'd1;
wire cen = (div3 == 2'd0);

wire [15:0] A;
wire [7:0]  dout;
wire        req, io, we_z, m1;
reg  [7:0]  din;
reg         ack;
reg         int_n = 1'b1;

z80bus cpu (
    .clk(clk), .reset(reset), .cen(cen),
    .A(A), .dout(dout), .din(din), .req(req), .io(io), .we(we_z), .m1(m1), .ack(ack),
    .int_n(int_n), .nmi_n(1'b1), .halt_n(), .rfsh_n(), .iff1(),
    .pc_now(dbg_pc), .m1_now(dbg_m1)
);

// the interrupt: 42 MHz / 1120 = 37.5 kHz, held until acknowledged
reg [10:0] icnt = 11'd0;
wire       inta;
always @(posedge clk) begin
    if (reset) begin icnt <= 11'd0; int_n <= 1'b1; end
    else begin
        icnt <= (icnt == 11'd1119) ? 11'd0 : icnt + 11'd1;
        if (inta) int_n <= 1'b1;
        if (icnt == 11'd0) int_n <= 1'b0;
    end
end

//------------------------------------------------------------------------
// The memory: what the address is, and who answers it
//
//   0000-3FFF   the ROM's first half         BSRAM, no wait
//   4000-7FFF   the fixed 16 KB              BSRAM, no wait
//   8000-FFFF   page 0: the whole ROM        BSRAM, no wait
//               page n: RAM block n          SDRAM slot B, waited
//
// A request (z80bus.v: from the enable that ends T1) is seen here on
// the next clock, the BSRAM's registered read is out on the one after,
// and the ack goes with it: req falls before the enable that ends T2
// samples WAIT, so the cycle costs nothing.  A write into the fixed RAM
// is taken and acked on the first clock; a write into the ROM is
// dropped.  Each BSRAM has one write port and one read port and no port
// does both in a clock (Gowin's PA2122).
//------------------------------------------------------------------------
reg  [5:0]  page = 6'd0;               // port 00, six bits: 63 RAM pages
wire        lowrom = (A[15:14] == 2'b00);
wire        fixed  = (A[15:14] == 2'b01);
wire        w_rom  = A[15] && (page == 6'd0);
wire        w_ram  = A[15] && (page != 6'd0);
wire [14:0] rom_adr = lowrom ? {1'b0, A[13:0]} : A[14:0];
// the window's word address: RAM 80000h + page * 2000h + A[14:2]
wire [20:0] ram_adr = {2'b01, page, A[14:2]};

reg  [7:0]  rom  [0:32767];
reg  [7:0]  fram [0:16383];
reg  [7:0]  rom_q, fram_q;

reg         served  = 1'b0;
reg         rd_wait = 1'b0;            // a slot B read is out
reg         fast_rd = 1'b0;            // a BSRAM read: its byte is out this clock
wire        mem_want = req && !io && !served;
wire        bsram    = lowrom || fixed || w_rom;
wire        fast_go  = mem_want && bsram && !we_z;
wire        fram_wr  = mem_want && fixed && we_z;
wire        rom_wr   = mem_want && (lowrom || w_rom) && we_z;

always @(posedge clk) begin
    if (ld_we)   rom[ld_adr] <= ld_data;
    rom_q <= rom[rom_adr];
end
always @(posedge clk) begin
    if (fram_wr) fram[A[13:0]] <= dout;
    fram_q <= fram[A[13:0]];
end
wire [7:0] fast_byte = fixed ? fram_q : rom_q;

assign b_req   = mem_want && w_ram;
assign b_we    = we_z;
assign b_adr   = ram_adr;
assign b_wdata = {4{dout}};
assign b_wmask = 4'b0001 << A[1:0];

wire [7:0] mem_byte = (A[1:0] == 2'd0) ? b_rdata[7:0]   :
                      (A[1:0] == 2'd1) ? b_rdata[15:8]  :
                      (A[1:0] == 2'd2) ? b_rdata[23:16] : b_rdata[31:24];

//------------------------------------------------------------------------
// The DACs: a read anywhere in 6000h-7FFFh lands its byte in channel A9:A8
//------------------------------------------------------------------------
reg [7:0] dac [0:3];
reg [5:0] vol [0:3];
integer i;
initial for (i = 0; i < 4; i = i + 1) begin dac[i] = 8'h80; vol[i] = 6'd0; end

//------------------------------------------------------------------------
// The card's ports, and the answers
//------------------------------------------------------------------------
wire io_want = req && io && !served;
assign inta  = io_want && m1;
reg  [7:0] io_byte;
always @(*) begin
    case (A[3:0])
        4'h1: io_byte = cmd;
        4'h2: io_byte = to_gs;
        4'h4: io_byte = {f_data, 6'b000000, f_cmd};
        default: io_byte = 8'hFF;
    endcase
end

// the flags' events this clock, resolved below with set winning
always @(*) begin
    cmd_set = io_stb && we && a3;
    dat_set = (io_stb && we && !a3) || (io_want && !inta && A[3:0] == 4'h3);
    dat_clr = (io_stb && !we && !a3) || (io_want && !inta && !we_z && A[3:0] == 4'h2);
    cmd_clr = io_want && !inta && A[3:0] == 4'h5;
end

reg  [7:0] din_r  = 8'd0;
reg        ack_r  = 1'b0;
always @(*) begin
    ack = ack_r || fast_rd;
    din = fast_rd ? fast_byte : din_r;
end

always @(posedge clk) begin
    ack_r   <= 1'b0;
    fast_rd <= 1'b0;
    if (reset) begin
        served <= 1'b0; rd_wait <= 1'b0; page <= 6'd0;
        cmd <= 8'd0; to_gs <= 8'd0; to_zx <= 8'd0; f_cmd <= 1'b0; f_data <= 1'b0;
        for (i = 0; i < 4; i = i + 1) begin dac[i] <= 8'h80; vol[i] <= 6'd0; end
    end else begin
        if (!req) served <= 1'b0;

        // the host's side
        if (io_stb && we) begin
            if (a3) cmd   <= wdata;
            else    to_gs <= wdata;
        end

        // the flags: 0A and 0B load them outright (Unreal), else set wins
        if (io_want && !inta && A[3:0] == 4'hA)      f_data <= page[0];
        else if (dat_set)                            f_data <= 1'b1;
        else if (dat_clr)                            f_data <= 1'b0;
        if (io_want && !inta && A[3:0] == 4'hB)      f_cmd  <= vol[0][5];
        else if (cmd_set)                            f_cmd  <= 1'b1;
        else if (cmd_clr)                            f_cmd  <= 1'b0;

        // memory: the BSRAM answers on the next clock, a ROM write is
        // dropped, the window's RAM goes to the SDRAM
        if (fast_go) begin served <= 1'b1; fast_rd <= 1'b1; end
        if (fast_rd && A[15:13] == 3'b011) dac[A[9:8]] <= fast_byte;
        if (fram_wr || rom_wr) begin served <= 1'b1; ack_r <= 1'b1; end
        if (b_take) begin
            served <= 1'b1;
            if (we_z) ack_r <= 1'b1; else rd_wait <= 1'b1;
        end
        if (b_ack && rd_wait) begin
            rd_wait <= 1'b0;
            ack_r <= 1'b1;
            din_r <= mem_byte;
        end

        // the card's own ports: answered at once
        if (io_want) begin
            served <= 1'b1;
            ack_r <= 1'b1;
            din_r <= inta ? 8'hFF : io_byte;
            if (!inta && we_z) case (A[3:0])
                4'h0: page <= dout[5:0];
                4'h3: to_zx <= dout;
                4'h6, 4'h7, 4'h8, 4'h9: vol[A[1:0] + 2'd2] <= dout[5:0];   // 6..9 -> 0..3
                default: ;
            endcase
        end
    end
end

//------------------------------------------------------------------------
// The mix: (byte - 128) * volume, two channels a side
//------------------------------------------------------------------------
wire signed [8:0]  s0 = {1'b0, dac[0]} - 9'd128;
wire signed [8:0]  s1 = {1'b0, dac[1]} - 9'd128;
wire signed [8:0]  s2 = {1'b0, dac[2]} - 9'd128;
wire signed [8:0]  s3 = {1'b0, dac[3]} - 9'd128;
wire signed [15:0] m0 = s0 * $signed({1'b0, vol[0]});
wire signed [15:0] m1_ = s1 * $signed({1'b0, vol[1]});
wire signed [15:0] m2 = s2 * $signed({1'b0, vol[2]});
wire signed [15:0] m3 = s3 * $signed({1'b0, vol[3]});
reg signed [15:0] l = 16'sd0, r = 16'sd0;
always @(posedge clk) begin
    l <= m0 + m1_;      // +-16256 at most
    r <= m2 + m3;
end
assign out_l = l;
assign out_r = r;

endmodule
