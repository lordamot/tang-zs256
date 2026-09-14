# The machine: the Scorpion ZS-256 Turbo+

Sergey Zonov's ZX Spectrum clone (Scorpion, St. Petersburg, 1991-98):
a Z80B at 3.5 MHz with a 7 MHz "turbo", 256 KB of DRAM in sixteen 16 KB
pages, a 64 KB ROM of four pages (the 128 BASIC, the 48 BASIC, the
Service Monitor, TR-DOS), an AY-3-8912, a Beta Disk interface (ВГ93)
and a ZX-BUS with two slots - onto which this repository also puts the
ProfROM (in place of the 64 KB ROM), the SMUC and General Sound.

Everything below is read off the schematic of romychs' restored board,
v16.2.6 (`infosource/Sources/`, as a netlist through `make netlist`;
part numbers are that schematic's), the GALs (`infosource/GAL/`,
`tools/jed22v10.py`) and, where said, Unreal Speccy or the original's
scan.  `fpga.md` says what the design makes of it.

## The memory map

```
0000-3FFF  ROM page {CS1, CS27}, or RAM page 0 with 1FFD bit 0
4000-7FFF  RAM page 5 (the screen)
8000-BFFF  RAM page 2
C000-FFFF  RAM page {1FFD bit 4, 7FFD bits 2:0}   (16 pages; a ZS-1024 adds 1FFD bits 7:6)
```

The ROM chip is a 27C020 (DD29), 256 KB: A17, A16 from the ProfROM GAL
(bank 0..3, a 64 KB image each), A15 = CS1, A14 = CS27:

```
CS1  = DOS | SYS              DD69.4 (NAND of DOS- and !SYS)
CS27 = !SYS & ROM1            DD66.2
```

with SYS = 1FFD bit 1, ROM1 = 7FFD bit 4, DOS the flip-flop below.  So a
64 KB image is: page 0 the 128 BASIC, 1 the 48 BASIC, 2 the Service
Monitor, 3 TR-DOS - `soft/rom/scorp294.rom` is laid out so, and so are
the four banks of a ProfROM (`soft/rom/prof401.rom`).  Unreal Speccy
loads them in the same order (`base_128_rom`, `sos`, `sys`, `dos`).

## The ports

DD32 (ИД7) decodes the board's own ports on **A0, A1, A5** only, with
IORQ (through IORQGE from the ZX-BUS) and M1 high, and is disabled by
**A1 & DOS** (DD66.3 into E1):

| A0 A1 A5 | port | DD32 | what |
|---|---|---|---|
| 0 1 1 | FE | Y6 | written: DD35 - border bits 2:0, MIC bit 3, beeper bit 4; read: the keyboard (below) |
| 1 1 0 | 1F | Y3 | read: Kempston joystick bits 4:0, bit 5 low, bit 6 DRQ, bit 7 INTRQ |
| 1 1 1 | FF | Y7 | read: DD53's latch of the byte the video circuit fetched, while BRD- (paper) |
| 1 0 1 | xxFD | Y5 = CSFD | DD52 on A14, A15, WR: 1FFD, 7FFD written; BFFD, FFFD written, FFFD read |

7FFD (DD46): bits 2:0 the RAM page, 3 the screen (0 page 5, 1 page 7),
4 ROM1, 5 the lock - the register's clock is gated by its own bit 5
(DD45), so once locked it stays until reset.  1FFD (DD47): bit 0 RAM
page 0 at 0000 (RB), bit 1 SYS, bit 2 the printer strobe (STB), bit 4
the RAM page's bit 3; bits 6, 7 unused here (the ZS-1024's extra page
bits, Unreal), bit 3 or 5 the RS-232 TX.

The AY: BDIR = write to BFFD or FFFD (DD48.1), BC1 = any FFFD access
(DD48.2), so FFFD written latches the register number, BFFD written the
value, FFFD read gives the register; its clock is H1, 1.75 MHz.  BC2 is
A13 on the board, which every owner ties high (`infosource/fixes/
ay-fix`); here A13 is not decoded, which is the same thing.

**The keyboard read** (DD36, DD37: two КП11 muxes, SE = A0): with A0 = 0
bits 4:0 are the matrix, 5 DSR5 (high), 6 the tape input, 7 BUSY (high);
with A0 = 1 bits 4:0 are the Kempston joystick, 5 low, 6 DRQ, 7 INTRQ.
Their enable CSKB- = CSRD & (RD- | (!Y6 & !Y3)): a read of FE or 1F
(DD32 up), or CSRD.

**With DOS on** DD32 is disabled for every port with A1 = 1, and DD65
(ИД7 on A1, A7, WR with A0 = 1 and not M1) takes over:

| A1 A7 WR | port | what |
|---|---|---|
| 1 0 0 | 1F 3F 5F 7F | the ВГ93 written, register A6:A5 |
| 1 0 1 | the same | the ВГ93 read |
| 1 1 0 | FF | TM9: the system register DD57 - bits 1:0 the drive, 2 the chip's reset (0), 3 HLT, 4 the side (0 = side 1), 6 the density |
| 1 1 1 | FF | CSRD: the mux with A0 = 1 - joystick, DRQ, INTRQ |

so in DOS mode port FE is nobody's: a read gets the floating bus (FFh
here), a write goes nowhere, and TR-DOS reads the keyboard through the 48
BASIC ROM from RAM, where DOS is off.  The xxFD ports work in both.

**An interrupt acknowledge** (M1 with IORQ, the PC on A15..A0) selects
nothing: DD32 and DD65 both have M1 in their enables, and so do the
cards on the bus (General Sound's decoder through VD10, the SMUC's
ИД7).  The byte the Z80 reads is the open bus, FFh, which is what every
IM 2 program written for the Pentagon and the Scorpion relies on (I =
3Bh, the vector through the 48 ROM's 3BFF/3C00 and a JR at FFFF).  The
core gives FFh and lets no port answer an M1 cycle.

**The DOS flip-flop** (DD50.1): set asynchronously by DD49's decode of an
M1 fetch at 3Dxx (A13..A8 = 111101, M1, MREQ) from the ROM (ROM = NOR of
A15, A14, RB) with ROM1 = 1; clocked at every M1 fetch from RAM (RAMM1,
DD10.4) with the complement of DD50.2's Q.  DD50.2 is set by every ROM
read (RDR-) and clocked at RAMM1 with the Magic button (MG, high when
idle), and its Q is NMI-.  So: the first opcode fetched from RAM after a
ROM read turns DOS off; the Magic button, seen at a RAM fetch, pulls NMI
and makes the NEXT RAM fetch turn DOS on - so 0066h is fetched from the
TR-DOS ROM (or the Service ROM with the 128 BASIC selected), which is
how the Magic button reaches the Service Monitor.  The chain only works
from RAM: pressing Magic while the ROM executes does nothing until the
processor fetches from RAM.

**Turbo** (DD9.2): set by a READ of 7FFD (DD52's Y3), cleared by a read
of 1FFD (Y1), toggled by the button SW1 through DD55.2 at each frame.
The GAL DD30 (`tools/jed22v10.py infosource/GAL/turbo.jed`, with the
registered feedbacks read as /Q) then gives the Z80 the 7 MHz clock
whenever the flag is on and no interrupt is pending, and inserts WAIT on
RAM accesses until the DRAM's slot (the CPU's half of H1 inside the
paper, any clock in the border) and stretches I/O cycles by one clock.
ROM and register accesses run at 7 MHz unwaited.  What this design does
with it is in `fpga.md`.

**The ProfROM** (DD41, `infosource/GAL/Source_ProfROM_GAL22v10.txt`): a
read of the Service ROM page (CS1 = 1, CS27 = 0) at 0100h-010Fh steps
the bank by A3, A2:

```
A3A2   from bank 0 1 2 3
 00        to   0 1 2 3   (nothing)
 01             3 3 3 2
 10             2 2 0 1
 11             1 0 1 0
```

Unreal's `set_scorp_profrom` has the same table.

## The video

The counters DD3, DD4 (H, clocked by the 7 MHz pixel clock) and DD5, DD6
(V, clocked once a line), with the two flip-flops DD8.1 (BC-) and DD8.2
(BK-) that flip at each counter's load:

- a line is 448 pixel clocks (224 T): H = 0..255 with BC- = 1 is the
  paper, then a load to 40h and H = 40h..FFh with BC- = 0 is the right
  border (64), sync (CC-, 64) and left border (64);
- a frame is 312 lines: V = 0..191 with BK- = 1 is the paper, then a load
  to 48h and V = 48h..BFh with BK- = 0 is the bottom border (40), sync
  (KC-, 16, V = 70h..7Fh) and top border (64).  **The v16.2.6 redraw has
  DD5.D2 and DD6.D2 on BK-, a load of 44h and 316 lines; the original's
  scan (`infosource/REMONT-SERGOS/classic/scorp_shem/sc_3_sm.jpg`) has
  DD5.D3 and DD6.D2 on BK-, 48h and 312, which is what the emulators use
  (Unreal: 69888 T, paper 14344 T after the interrupt) and what is built.**
- the interrupt (DD2.2): INT- falls at the rising edge of KC- - the end of
  the sync, the first line of the top border, at H = 0 - and rises when
  H6 rises, 64 pixel clocks later: 32 T-states, 64 lines before the
  paper.
- the border is DD33/DD34's latch of port FE, clocked by H2 (every 8
  pixels: Unreal's "4TBorder"); FLASH is DD7's frame counter, toggling
  every 16 frames; port FF reads DD53, the latch of the memory data bus at
  H2- - the attribute of the cell being fetched - while both BC- and BK-
  are high, FFh elsewhere.

There is no contention: the DRAM is time-shared by H1 (the video's half
and the processor's), and the processor never waits in the 3.5 MHz mode.

## What is on the ZX-BUS here

**SMUC** (Scorpion & MOA Universal Controller): the ports as Unreal
Speccy decodes them, `smuc.v`'s header has the table - 5FBA, 7FBA, DFBA,
FFBA, 5FBE/7FBE and the IDE at xxBE with A15 = 1, the drive's register
on A10..A8, the high byte of its 16-bit data through a latch.  The clock
is a DS12887 (`rtc.v`), the NVRAM a 24C16 on two bits of FFBA
(`nvram.v`).  The disk is an image file on the card, geometry 16 x 32,
LBA and CHS (`ide.v`).

**General Sound**: ports B3 and BB, the card's own Z80, ROM and RAM as
`gs.v`'s header has them, from Unreal's gsz80.cpp and Stinger's guide.

**Kempston mouse**: FADF buttons, FBDF X, FFDF Y, from the USB mouse.

## Where the facts came from, and where they disagree

- Unreal decodes FE as `(port & 0x23) == 0x22` and 7FFD/1FFD as
  `(port & 0xC023)` - the same bits as DD32 and DD52.  It does not
  disable FE in DOS mode (it reads any even port); the board does, and
  the board is built.
- Unreal's Scorpion has 1FFD bit 2 enable the DOS ports ("the GMX
  book"); the board's bit 2 is the printer strobe, and the board is
  built.
- The redraw's 316 lines against the original's 312: above.
- Unreal runs General Sound at 24 MHz and maps its fixed 4000-7FFF
  window onto RAM page 3, which would alias it with window page 1;
  Stinger's guide says 112 of 128 KB are usable, which needs the fixed
  window outside every page.  It is outside here (page 0 of the RAM),
  and the card's firmware finds all 63 window pages of 2 MB (15 of 512 KB until 14 Sep 2026), where Unreal's aliasing would fail page 1's test.
