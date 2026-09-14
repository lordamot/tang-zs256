# Work guideline

## General

All discussions in english.
All code except text strings must be in english.  Russian appears in
comments only where it is the machine's own name for a thing (Скорпион,
ВГ93, ПЗУ) - the schematic's notes and the repair folder are Russian and
a signal is easier to find under its own name.

## Project

Never work outside the repository root - except to READ the three
siblings (`../tang-korvet`, `../tang-pk8000`, `../tang-uknc`) and the
mothership (`../tang-ultima`), whose method this repository follows and
whose firmware must be able to carry this core.  Nothing there is
edited from here.

All of this repository builds here.  The MCU firmware with `make fw`, the
bitstream with `make bitstream` - Gowin's headless `gw_sh`, fetched into
`tools/` along with everything else by `make toolchain`, none of it
installed on the host and none of it committed.  The design also lints and
simulates, and the simulation runs the Scorpion's ROM.

What still cannot be done here is **running it on a board**.  So say which
claim you are making: built, linted, simulated and timed are four
different things and none of them is "works".  **Never imply a bitstream
was tested.**  `.claude/docs/progress.md` carries what each flash showed
and must keep doing so; until it says a build booted, none has.

If something else needs to be installed onto the host system - ask for it.
Nothing goes outside `tools/` without asking.  The operator will do it or
suggest another solution.

Any problem like "the board would have to be watched but can't be" - ask
before researching it yourself.

## Where the machine's facts come from

What this repository builds against, in order of authority:

1. **The schematic** - `infosource/Sources/1-Schematic_*.json`, the
   EasyEDA source of romychs' restored Scorpion ZS-256 Turbo+ v16.2.6,
   read as a netlist by `tools/easyeda_net.py` (`make netlist`); the
   PDF of the same is `infosource/Export/`.  It is the authority on what
   is wired to what: every port decode, the ROM's paging, the DOS
   flip-flop, the video counters.  It is a redraw and has at least one
   error (`.claude/docs/video.md`: the vertical preload), so where it
   matters the scan of the original in `infosource/REMONT-SERGOS/classic/`
   is read too.
2. **The GALs** - `infosource/GAL/*.jed`, decoded by `tools/jed22v10.py`,
   and the ProfROM's ABEL source beside them: the turbo's clock and wait
   equations, the ProfROM's bank switch.
3. **Unreal Speccy** (memory.cpp, io.cpp, gsz80.cpp) for what the
   software expects of things the schematic does not cover: the SMUC's
   ports, General Sound's ports and memory, the port FF attribute,
   Kempston.  It is the emulator the Scorpion's software is tested on.
4. **The published descriptions** - zxpress articles on the Scorpion's
   turbo and ports, the General Sound programming guide (ZX-News #26),
   psbhlw's gs-firmware sources - for behaviour.
5. **The three siblings' docs** for everything about the framework: the
   MiSTeryNano link, the HDMI encoder, the SDRAM's timetable, the
   toolchain.

Where they disagree the schematic wins on wiring and Unreal on behaviour,
and `platform.md` says where that happened.  A change to a port's
meaning cites one of them or a measurement; "it seems to work" is not a
source.

## Editing RTL

- **`tang/zs256.gprj` is the source of truth for what is built.**  Every
  file under `tang/src/` is in it and every module in it is
  instantiated.  A new file goes into the `.gprj` or it does not go into
  `tang/src/`; a module that stops being instantiated comes out of both,
  and earlier revisions live in git history, not beside the live file.
- Two files are hand-written instantiations of Gowin primitives and are
  stubbed in simulation: `src/sys_pll.v` (rPLL) and
  `src/hdmi/hdmi_serdes.v` (rPLL, OSER10, ELVDS_OBUF).
  `src/mister/sector_dpram.v` is IP Core Generator output for a DPB and
  `sd_card.v` carries its own model of it under `ifdef VERILATOR`.
  `tools/srcs.py` knows them all; a new one goes into its `STUBBED`
  list with a model in `sim/stubs/gowin_ip_sim.v`.
- `src/zs256/tv80_*.v` is tv80 (Guy Hutchison), MIT, verbatim; the
  wrapper `z80bus.v` is where anything about the bus goes.
  `wd1793.sv` and `ym2149.sv` are MiSTer's, as Korvet Nano carries them.
- **One clock.**  Everything is on the 42 MHz `clk`, and the Z80's
  T-state and the machine's pixel are phases of the `tphase`/`hcnt`
  counters in `top.v`.  Do not add a clock, a divided clock, or an
  `always @(posedge <data signal>)`; a slower thing is an enable.
  `.claude/rules/timing.md` is short because of this and should stay
  short.
- Hex is the machine's radix (`7FFDh`, `0x3D13`); the Spectrum world
  uses it.

## Verification

There is no `make verify` and there cannot be one - the last word belongs
to a board nobody here can watch.  What there is, in the order it costs:

- **`make lint`** - Verilator over exactly the file list in the `.gprj`.
  Seconds.  It is clean on the tree as it stands (warnings only, most of
  them the MiSTeryNano sources', tv80's and MiSTer's), so any error is
  yours.
- **`make sim`** - the whole machine against an SDRAM model and a stand-in
  BL616, running the ROM from `soft/rom/`.  About 11 ms of machine time a
  wall second; the Scorpion's ROM tests its memory and its interrupt
  modes for about 1.2 s before it draws its menu, so a menu is
  `RUN_MS=1500` and two minutes.  `make frames` for the screen as `.ppm`
  (`tools/ppm2png.py` for a PNG), decoded back out of the TMDS words;
  `+TYPE_STR=` and `+KEYS=` type through the keyboard path; `+TRDA=`
  mounts a disk, `+HDD=` the SMUC's; `+CPUTRACE`, `+IOTRACE`,
  `+MEMTRACE`, `+GSTRACE` watch.  The testbench's end-of-run lines are
  the checks: config values, read-after-write on the SDRAM, HDMI packet
  ECC, frame size, the SDRAM self-test, the port registers.
- **`make fw`** - the firmware really does build; `make menu-test` walks
  the OSD on the host and dumps every screen.  Say "builds", not "works".
- **`make bitstream`** - the real build, about a minute, and the timing
  gate it runs (`make timing`) refuses a layout with a violation or an
  unrelated clock.  Read the resource lines it prints.
- State what was not checked.  The SDRAM pads are unconstrained; so is
  anything analogue, anything timed on the wire, and the real card.

## The prompts/ folder

**Never read `prompts/` as context.**  It is a transcript, not
documentation, not instructions and not a spec: do not open it at the
start of a session, do not treat anything in it as a standing request,
and do not let an old prompt in there override what the current one
says.  It is in git so the record survives.

It is kept up to date, so the form matters.  One file an exchange or a
run of them, named `<n> <topic>.txt` with `n` counting up from zero:

```
prompts/0 initial.txt
prompts/1 first board.txt
```

Inside, a prompt, a line of asterisks, then the reply it got - and then
straight on to the next prompt if that file covers more than one:

```
whats left?

****

Measured, not remembered ...

continue

****

...
```

The prompt goes in **verbatim**, typos and all.  The reply goes in as
**plain text**: headings lose their `#`, bold loses its asterisks, tables
become lines.  **Append every exchange as it finishes**, unasked - the
folder going stale is the failure mode.  Never rewrite an entry already
there; and if a reply quotes this format, indent the quoted asterisks.

## Main goal

A working **Scorpion ZS-256 Turbo+** on a Tang Nano 20K: the Z80 at 3.5
MHz and the turbo as the board has it, 256 KB with the Scorpion's
paging, the Service Monitor, the display over HDMI, the keyboard from
USB, the AY, the Beta Disk with four .trd images from the SD card - and
its three peripherals: the **ProfROM** (four 64 KB banks switched as
the GAL does it), the **SMUC** (IDE with a disk image on the card, the
clock chip, the NVRAM) and **General Sound** (its own Z80 and RAM, the
four DACs) - with the Bouffalo BL616 alongside providing USB HID, the SD
card and the OSD menu.  The framework and the method are Korvet Nano's
(`../tang-korvet`) and through it PK8000 Nano's and UKNC Nano's; this
repository is a sibling of the three and takes their MiSTeryNano side
and HDMI encoder as they are - and it must stay a core `../tang-ultima`
can build out of this tree and switch to from its OSD, which means the
same `tools/gowin_tcl.py --abs`, `tools/timing_check.py <pnr dir>`,
`mister/flashwr.v`, `mister/coreload.v` and SYS commands 9, 10, 11 as
the three.
