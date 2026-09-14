`timescale 1ns / 1ps
//========================================================================
// membus.v - the Scorpion's memory: its Z80's side of the SDRAM.
//
// The SDRAM (sdram.v) gives this processor slot A of every T-state - the
// six clocks from phase 1 - for one 32-bit word access, four bytes a
// word, and everything the machine can address lives there:
//
//   words 00000h-3FFFFh  the RAM, 64 pages of 16 KB (the Scorpion's 16,
//                        or a ZS-1024's 64), page p at word p * 1000h
//   words 40000h-4FFFFh  the ROM image, 16 pages of 16 KB: the four
//                        64 KB banks of a ProfROM, or one 64 KB image
//                        in the first four pages (memmap.v)
//
// (the General Sound's RAM and ROM are in the same chip from word
// 80000h on, through slot B - gs.v.)  A byte is picked from the word
// by its lane, address bits 1:0, on a read, and written through the
// lane's DQM on a write.  memmap.v says which page an address is in.
//
// A read goes out on the first slot A after the request - the same
// T-state, in the 3.5 MHz mode, since z80bus.v raises the request one
// clock before the slot - and its byte is back with `ack` four clocks
// later, well inside T2.  A write is taken the same way and is done
// when it is taken.  A write to the ROM is answered and dropped.  A
// write into page 5 or 7 below 1B00h is also handed to the screen's
// own copy in BSRAM (screen.v), which is the only memory the display
// reads.
//
// The MCU's bytes - the ROM image at start, a POKE from the OSD - come
// in on the loader port with a byte address of the whole chip and take
// any slot A the processor does not want; they go through the same
// screen copy when they land in a screen page.
//========================================================================
module membus (
    input             clk,
    input             reset,

    // the CPU (z80bus.v)
    input             req,          // a memory request is up
    input      [15:0] A,
    input             we,
    input      [7:0]  wdata,
    output     [7:0]  rdata,
    output            ack,          // one clock: rdata valid / the write is taken
    output            stb,          // one clock: the access is being taken (memmap.v's clock)

    // what the address is (memmap.v)
    input             rom,
    input      [3:0]  rom_page,
    input      [5:0]  ram_page,

    // the MCU's loader port: a byte anywhere in the chip
    input             ld_req,       // level
    input      [23:0] ld_adr,       // byte address: word * 4 + lane
    input      [7:0]  ld_data,
    output            ld_ack,       // one clock: taken

    // the screen's copy
    output            scr_we,
    output     [13:0] scr_adr,      // {page 7, offset[12:0]}
    output     [7:0]  scr_data,

    // sdram.v's slot A
    output            a_req,
    output            a_we,
    output     [20:0] a_adr,
    output     [31:0] a_wdata,
    output     [3:0]  a_wmask,
    input             a_take,
    input      [31:0] a_rdata,
    input             a_ack
);

//------------------------------------------------------------------------
// The CPU's access
//------------------------------------------------------------------------
reg         served  = 1'b0;      // this request has been taken (or answered)
reg         rd_wait = 1'b0;      // a read is in flight, its ack to come
wire        cpu_want = req && !served;
wire [20:0] cpu_word = rom ? {5'b00100, rom_page, A[13:2]} : {3'b000, ram_page, A[13:2]};
wire        rom_wr   = cpu_want && we && rom;      // dropped, answered at once

// the loader's turn: no CPU request pending
wire        ld_want  = ld_req && !cpu_want && !rd_wait;

assign a_req   = (cpu_want && !rom_wr) || ld_want;
assign a_we    = ld_want ? 1'b1 : we;
assign a_adr   = ld_want ? ld_adr[22:2] : cpu_word;
assign a_wdata = ld_want ? {4{ld_data}} : {4{wdata}};
assign a_wmask = ld_want ? (4'b0001 << ld_adr[1:0]) : (4'b0001 << A[1:0]);

wire cpu_take = a_take && !ld_want;
assign ld_ack = a_take && ld_want;

assign stb    = cpu_take || rom_wr;
assign ack    = (cpu_take && we) || rom_wr || (a_ack && rd_wait);
assign rdata  = (A[1:0] == 2'd0) ? a_rdata[7:0]   :
                (A[1:0] == 2'd1) ? a_rdata[15:8]  :
                (A[1:0] == 2'd2) ? a_rdata[23:16] : a_rdata[31:24];

always @(posedge clk) begin
    if (reset) begin
        served <= 1'b0; rd_wait <= 1'b0;
    end else begin
        if (!req) served <= 1'b0;
        if (cpu_take || rom_wr) served <= 1'b1;
        if (cpu_take && !we) rd_wait <= 1'b1;
        if (a_ack && rd_wait) rd_wait <= 1'b0;
    end
end

//------------------------------------------------------------------------
// The screen's copy: a write into page 5 or 7 below 1B00h, from either
// side.  The loader's page is bits 15:14 of its byte address in RAM.
//------------------------------------------------------------------------
wire [5:0]  scr_page = ld_want ? ld_adr[19:14] : ram_page;
wire [13:0] scr_off  = ld_want ? ld_adr[13:0]  : A[13:0];
wire        in_ram   = ld_want ? (ld_adr[23:20] == 4'd0) : !rom;
wire        is_scr   = in_ram && (scr_page == 6'd5 || scr_page == 6'd7) && (scr_off < 14'h1B00);
assign scr_we   = a_take && a_we && is_scr;
assign scr_adr  = {scr_page[1], scr_off[12:0]};
assign scr_data = ld_want ? ld_data : wdata;

endmodule
