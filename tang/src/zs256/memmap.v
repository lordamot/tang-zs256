`timescale 1ns / 1ps
//========================================================================
// memmap.v - what each address is: the Scorpion's paging, the DOS
// flip-flop, the ProfROM's bank, the turbo flag.
//
// Straight from the schematic (infosource/, netlist by
// tools/easyeda_net.py; .claude/docs/platform.md has the account):
//
//  * Port 7FFD (DD46, clocked by WR_7FFD = A15=0 A14=1 with CSFD): bits
//    2..0 the RAM page at C000, 3 the screen (page 5 or 7), 4 ROM1 (0
//    the 128 BASIC, 1 the 48), 5 the lock - the register's clock is
//    gated by its own bit 5 (DD45), so once set nothing changes until
//    reset.  CSFD is A0=1, A1=0, A5=1, IORQ, not M1 (DD32's Y5), so
//    only A15, A14, A5, A1, A0 are decoded, as Unreal Speccy has it.
//  * Port 1FFD (DD47, WR_1FFD = A15=0 A14=0): bit 0 RAM page 0 at
//    0000-3FFF (RB), bit 1 the Service Monitor ROM at 0000 (SYS), bit 2
//    the printer strobe, bit 4 the RAM page's bit 3 (256 KB); bits 6, 7
//    the page's bits 4, 5 on a ZS-1024 (Unreal), optional here.
//  * The ROM chip's A15 (CS1) = DOS | SYS; A14 (CS27) = !SYS & ROM1: so
//    page 0 is the 128 BASIC, 1 the 48, 2 the Service Monitor, 3 TR-DOS,
//    in the 64 KB image (soft/rom/scorp294.rom), and the ProfROM's A16,
//    A17 pick one of four such images.
//  * DOS (DD50.1): set by an M1 fetch at 3Dxx from the ROM with ROM1=1
//    (DD49's decode of A13..A8 = 111101 with M1 and ROM); clocked at
//    every M1 fetch from RAM (RAMM1) with the complement of DD50.2 -
//    which every ROM read sets, so the first opcode fetched from RAM
//    after the ROM turns DOS off, unless the Magic button (MG) was down
//    at the RAM fetch before, which is also what pulls NMI: pressing
//    Magic in RAM gives an NMI with DOS on, and 0066h is then in the
//    TR-DOS ROM (or the Service ROM with the 128 BASIC selected).
//  * ProfROM (DD41, the GAL in infosource/GAL/): a read of the Service
//    ROM page at 0100h-010Fh steps the bank by the table on A3, A2 -
//    0100h holds, 0104h sets 3 (2 from 3), 0108h swaps 0<->2 and 1<->2
//    ... the table is the GAL's, quoted below.  The bank is masked to
//    what the ROM image has: a 64 KB image never switches.
//  * Turbo (DD9.2): set by a READ of 7FFD (n417), cleared by a read of
//    1FFD (n414) - "IN A,(7FFD) turbo on, IN A,(1FFD) off", zxpress
//    #3979 - and toggled by the button SW1, which the OSD stands in for.
//    What turbo does to the bus is top.v's (the GAL DD30's equations,
//    tools/jed22v10.py).
//
// The decode here is combinational on the CPU's request (z80bus.v's A,
// io, m1, we) and the registers; membus.v takes `rom` and the pages to
// the SDRAM.
//========================================================================
module memmap (
    input             clk,
    input             reset,        // the machine's reset

    // the CPU's request (z80bus.v)
    input             req,
    input      [15:0] A,
    input             io,
    input             m1,
    input             we,
    input      [7:0]  wdata,
    input             io_wr_stb,    // one clock: an I/O write is being served
    input             io_rd_stb,    // one clock: an I/O read is being served
    input             mem_stb,      // one clock: a memory access is being taken

    // the OSD
    input      [1:0]  profrom_mask, // 0 a 64 KB image, 1 128 KB, 3 256 KB
    input             ram1024,      // 1FFD bits 7:6 extend the page (ZS-1024)
    input      [1:0]  turbo_mode,   // 0 as the ports say, 1 always on, 2 always off
    input             magic_n,      // the Magic button, active low

    // what the address is, for this request
    output            rom,          // 0000-3FFF and a ROM is there
    output     [3:0]  rom_page,     // {bank, CS1, CS27}: 16 KB pages of the 256 KB image
    output     [5:0]  ram_page,     // the RAM page (16 KB) the address is in
    output            screen7,      // 7FFD bit 3: the screen is page 7

    output reg        dos,
    output reg        turbo,
    output            nmi_n,
    output reg [7:0]  p7FFD,
    output reg [7:0]  p1FFD,
    output reg [1:0]  profrom_bank
);

//------------------------------------------------------------------------
// The ports
//------------------------------------------------------------------------
wire csfd    = io && A[0] && !A[1] && A[5] && !m1;
wire is_7ffd = csfd && !A[15] &&  A[14];
wire is_1ffd = csfd && !A[15] && !A[14];

reg mg_q = 1'b1;                     // DD50.2: 0 = the Magic button was seen
assign nmi_n = mg_q;

//------------------------------------------------------------------------
// The decode
//------------------------------------------------------------------------
wire rom_area = (A[15:14] == 2'b00);
assign rom    = rom_area && !p1FFD[0];
wire dos_entry;
// the door's own fetch already reads the TR-DOS page: the set is
// asynchronous on the board (R64/C17) and lands inside that M1 cycle
wire cs1      = dos | p1FFD[1] | dos_entry;
wire cs27     = !p1FFD[1] & p7FFD[4];
assign rom_page = {profrom_bank, cs1, cs27};

wire [5:0] top_page = {ram1024 ? p1FFD[7:6] : 2'b00, p1FFD[4], p7FFD[2:0]};
assign ram_page = (A[15:14] == 2'b11) ? top_page :
                  (A[15:14] == 2'b10) ? 6'd2 :
                  (A[15:14] == 2'b01) ? 6'd5 : 6'd0;
assign screen7 = p7FFD[3];

// TR-DOS's door: an opcode fetch at 3Dxx from the 48 BASIC ROM
assign dos_entry = req && !io && m1 && rom && p7FFD[4] && (A[13:8] == 6'b111101);
// an opcode fetch from RAM: the DOS flip-flop's clock
wire ram_m1    = mem_stb && m1 && !rom;
// a ROM read: sets DD50.2
wire rom_rd    = mem_stb && !we && rom;
// the ProfROM's switch: a read of the Service ROM at 0100h..010Fh
wire prof_sw   = rom_rd && cs1 && !cs27 && (A[13:4] == 10'h010);

reg [1:0] prof_next;
always @(*) case ({A[3:2], profrom_bank})   // DD41's truth table (infosource/GAL/profrom.jed)
    4'b00_00: prof_next = 2'd0; 4'b00_01: prof_next = 2'd1; 4'b00_10: prof_next = 2'd2; 4'b00_11: prof_next = 2'd3;
    4'b01_00: prof_next = 2'd3; 4'b01_01: prof_next = 2'd3; 4'b01_10: prof_next = 2'd3; 4'b01_11: prof_next = 2'd2;
    4'b10_00: prof_next = 2'd2; 4'b10_01: prof_next = 2'd2; 4'b10_10: prof_next = 2'd0; 4'b10_11: prof_next = 2'd1;
    default:  prof_next = (profrom_bank == 2'd0) ? 2'd1 : (profrom_bank == 2'd2) ? 2'd1 : 2'd0;
endcase

reg turbo_ff = 1'b0;
always @(*) case (turbo_mode)
    2'd1:    turbo = 1'b1;
    2'd2:    turbo = 1'b0;
    default: turbo = turbo_ff;
endcase

always @(posedge clk) begin
    if (reset) begin
        p7FFD <= 8'd0; p1FFD <= 8'd0; dos <= 1'b0; mg_q <= 1'b1;
        profrom_bank <= 2'd0; turbo_ff <= 1'b0;
    end else begin
        if (io_wr_stb && is_7ffd && !p7FFD[5]) p7FFD <= wdata;
        if (io_wr_stb && is_1ffd)              p1FFD <= wdata;
        if (io_rd_stb && is_7ffd) turbo_ff <= 1'b1;
        if (io_rd_stb && is_1ffd) turbo_ff <= 1'b0;

        // DD50.1 and DD50.2: the RAM fetch clocks both, a ROM read sets
        // the second, the 3Dxx fetch sets the first
        if (ram_m1) begin
            dos  <= !mg_q;
            mg_q <= magic_n;
        end
        if (rom_rd)    mg_q <= 1'b1;
        if (dos_entry) dos  <= 1'b1;

        if (prof_sw) profrom_bank <= prof_next & profrom_mask;
    end
end

endmodule
