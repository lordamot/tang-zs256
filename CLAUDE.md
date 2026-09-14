# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in
this repository.

## Project overview

This is the **Scorpion ZS-256 Turbo+** - Sergey Zonov's ZX Spectrum
clone of the 1990s, a Z80 at 3.5 MHz with a 7 MHz turbo, 256 KB, the
Service Monitor and TR-DOS in its ROM, a Beta Disk and an AY - with the
three peripherals a Scorpion is usually seen with, the **ProfROM**, the
**SMUC** (IDE, clock, NVRAM) and **General Sound** - reimplemented on a
**Tang Nano 20K** (Gowin GW2AR-18C), with a **Bouffalo BL616** board
alongside it providing USB HID, the SD card and the on-screen menu.  It
is a sibling of **Korvet Nano** (`../tang-korvet`), **PK8000 Nano**
(`../tang-pk8000`) and **UKNC Nano** (`../tang-uknc`): the MiSTeryNano
side, the HDMI encoder, the SDRAM timetable, the toolchain, the Makefile
and the method are taken from there, and the machine itself is new.  It
is built to be a fourth core of **Tang Ultima** (`../tang-ultima`),
which switches one board between the machines from the OSD.  Started
13 Sep 2026.

Two halves, two toolchains, and **both build here**:

```
tang/     the FPGA design      - make bitstream  (gw_sh, headless Gowin, ~1 min)
mnano/    the BL616 firmware   - make fw
bin/      the two shipped binaries, both rebuilt from these sources
sim/      testbench, SDRAM model and the stand-ins for the vendor primitives
tools/    the fetched toolchain - make toolchain, ~7 GB, not committed (scripts are)
soft/     the ROM images (soft/rom/) and a test disk
infosource/  the operator's sources: the schematic (EasyEDA JSON, PDF), the
          GALs, the ROMs, the original's scans, repair notes; not part of the build
```

`make lint` and `make sim` are the cheap checks; `make bitstream` is the
real one.  `make help` lists the rest.  **What cannot be done here is
running it on a board.  Nothing has been on a board yet.**  See
`.claude/docs/progress.md` for what each build showed; anything built is
untested on the board until it says otherwise there.  So "it builds",
"it lints", "it boots in simulation" and "it meets timing" are four
different claims, none of them is "it works", and you should say which
one you are making.

The machine, as implemented: tv80 on a 42 MHz clock with the T-state
as twelve enables (six in turbo); the paging, the DOS flip-flop, the
ProfROM's bank switch and the turbo flag exactly as the schematic's
gates and GALs have them (`memmap.v`); the 256 KB (or 1 MB), the ROM
image and General Sound's memory in the SDRAM through a two-slot
timetable; the display with its own copy of the screen pages in BSRAM,
312 lines of 224 T-states, out as 1056x544 over HDMI; the ports as the
board decodes them, the Beta Disk with four .trd images, the AY, the
SMUC's IDE on a disk image, its DS12887 and 24C16, General Sound as a
second tv80 with its DACs; the keyboard from USB as the 8 x 5 matrix
with chords; Kempston joystick and mouse.

Key documentation: `.claude/docs/platform.md` (the machine: the memory
map, every port, the DOS flip-flop, the turbo, the ProfROM, the video
counters, where the facts come from), `.claude/docs/fpga.md` (the
implementation: the clock, the timetable, the memory, the I/O bus, the
files), `.claude/docs/video.md` (the display), `.claude/docs/mcu.md`
(the firmware, the keymap, the menu letters, the ROM loader),
`.claude/docs/build.md` (both toolchains, the Makefile, what lint and
simulation cover, flashing, reading the board), `.claude/docs/tools.md`
(`tools/` and the ROM data), `.claude/docs/progress.md` (state, defects,
what is next).  Follow `.claude/rules/guideline.md`,
`.claude/rules/git.md` and `.claude/rules/timing.md`.

## Traps worth remembering

- **`tang/zs256.gprj` is the source of truth for what gets built.**
  Every file under `tang/src/` is in it and every module in it is
  instantiated; keep it that way.  `tools/srcs.py` reads it for lint
  and sim, `tools/gowin_tcl.py` for the bitstream.
- **There is one clock, and everything is a phase of it.**  `clk` is
  42 MHz; `tphase` (0..11) is the Z80's T-state, `hcnt`/`vcnt` the
  machine's raster, and they run from PLL lock.  The SDRAM's slot A is
  phases 1..6 (the Scorpion's), slot B 7..12 (General Sound's, the
  loader's), and the Z80's enable at phase 0 is one clock BEFORE slot A
  so that a request registered on it is served in the same T-state.
  Put the slot on phase 0 and every cycle costs a wait state (found the
  first evening).  Do not add a clock, a divided clock, or a flop clocked
  by a data signal; do not touch memory outside a slot.
- **General Sound's Z80 must not wait for the SDRAM on every access.**
  Its ROM and its fixed 16 KB are BSRAM in `gs.v`, answered inside T2;
  only the window's RAM pages take slot B.  With everything behind the
  slot the card ran at half speed, its generator fell behind its 37.5
  kHz interrupt and modules played as noise (the first board).  The
  ROM copy is filled by snooping the loader's bytes to 400000h - the
  simulation preloads `uut.gsound.rom` alongside the SDRAM model.  Its
  INT is held until acknowledged; the card's is an RC pulse of some
  microseconds and a short pulse was missed under a waited instruction.
- **tv80 holds T1 for an extra enable in an I/O cycle and two in an
  interrupt acknowledge** (IOWait).  `z80bus.v` raises one request per
  M-cycle (`armed`); without that an IN read its port twice and an
  interrupt acknowledged three times.
- **The ROM is not in the bitstream.**  The firmware sends
  `/zs256.rom` (64 KB, or a 256 KB ProfROM) and `/gs105a.rom` from the
  card over SYS CMD 6 - THREE address bytes here, two in the siblings -
  while the machine is in reset, and tells the core the ProfROM's bank
  mask with 'P'.  The simulation preloads the SDRAM model instead
  (`+ROM=`), or sends it the firmware's way (`+ROMSPI=`).  No file, no
  machine: it executes zeros.
- **The ROM image's pages are 128, 48, SYS, DOS** in that order, the
  ROM chip's A15 = DOS | SYS and A14 = !SYS & ROM1 (`platform.md`); a
  ProfROM is four of those.  `soft/rom/` has them.
- **The DOS flip-flop is the schematic's, not an emulator's shortcut**:
  set by the 3Dxx fetch, cleared at the first opcode fetch from RAM after
  a ROM read, and the Magic button needs a RAM fetch to fire.  The 3Dxx
  fetch itself already reads the TR-DOS page (`dos_entry` is in `cs1`
  combinationally); take that out and TR-DOS's entry byte comes from the
  48 BASIC ROM.
- **An interrupt acknowledge is an I/O cycle with M1 and the PC on the
  address bus, and in IM 2 the byte it reads is the vector.**  Every
  port select in `ports.v` carries `not_m1`, the cards' included (their
  own decoders do); the acknowledge reads FFh.  Without it a program
  whose PC ended in BBh at the interrupt took General Sound's status as
  its vector and died with interrupts off (ZPLAY's shell, first board).
- **In DOS mode port FE is nobody's** on this board (DD32 is disabled
  for A1 = 1 while DOS is on); the emulators let it through.  The board
  is built.  `platform.md` has the whole decode.
- **The frame is 312 lines, not the redraw's 316.**  The v16.2.6
  schematic's vertical preload is wrong by one pin; the original's scan
  and every emulator say 312 (69888 T).  `video.md`.
- **The display is 1056x544 in a 1344x624 frame at 50.08 Hz, not a CEA
  mode.**  Whether a given sink takes this is a board question, and a
  black screen on a board is that before it is anything else.  On a 16:9
  sink it is a third too wide unless the sink is set to 4:3.
- **The write into a screen page goes two places** (`membus.v`): the
  SDRAM and `screen.v`'s copy.  The display reads only the copy; a path
  that writes the SDRAM without the copy (a future DMA, say) shows
  nothing.
- **`keyboard.v`'s code byte** is `row * 5 + col + 1`, +40 with Caps
  Shift, +80 with Symbol Shift, 121 both, bit 7 for release -
  `mnano/zs256.h` and the core must keep agreeing.
- **The firmware's core id is 9** (`CORE_ID_ZS256`), and every table the
  firmware selects by core is indexed by it - `settings_file[]`,
  `keymap[]`, `modifier[]`, `core_names[]`.  A menu value is three
  edits: the letter in the form string, `variables_zs256[]`, and
  `sysctrl.v`.  'm' sends a reset after itself; 'R', 'S', 'h' are
  buttons, not variables; 'P' is romload.c's.
- **Slot 5 is browsed, never mounted** (`SDC_SLOT_ROM`): the ROM's
  file selector remembers the name and `romload.c` sends the file;
  `MAX_DRIVES` stays 5 (four floppies, the SMUC's disk), which is what
  `../tang-ultima` expects of a core.
- **`hdmi_tx.v` sends FOUR packets an island here** (the back porch is
  200 clocks) and `ACR_CTS` is 42000 for exactly 48 kHz.  Changing the
  raster's blanking means checking `DI_PKTS` against it.
- **`tools/` on this host is hard links into `../tang-pk8000/tools/`**
  (through Korvet Nano's).  Same files, same inodes; an in-place edit to
  one is an edit to all.  Nothing in `tools/` is edited in place - a new
  toolchain version is a fresh fetch.
- **Flashing the FPGA is replug, flash, power-cycle - in that order**,
  and the BL616 must be in boot mode (hold BOOT, tap RESET, release
  BOOT).  `.claude/docs/build.md`.
- **Gowin's synthesis will not read a file that says `` `default_nettype
  none``** and its place-and-route refuses an inferred dual-port RAM
  that reads the old data on a write (PA2122).  An inferred RAM here is
  read-only-or-write on a port, never both in one clock; `screen.v`,
  `ide.v`'s buffer and `nvram.v` are written that way.
- **The SD request must stay up until the card is busy on it**
  (`sd_arbiter.v` latches the direction and the sector at the grant).
- **`prompts/` is a transcript, not context.**  Never read it at the
  start of a session; append every exchange as it finishes, in the form
  `.claude/rules/guideline.md` gives.
