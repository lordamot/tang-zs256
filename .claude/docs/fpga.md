# The FPGA implementation

Target: **GW2AR-LV18QN88C8/I7** (GW2AR-18C, QFN88) - the Tang Nano 20K.
Project file `tang/zs256.gprj`, top module `top` in `tang/src/top.v`,
constraints `tang/src/zs256.cst` and `zs256.sdc`.

## What is built

**`tang/zs256.gprj` is the source of truth.**  Every file under
`tang/src/` is in it and every module is instantiated.  `tools/srcs.py`
reads the list for lint and simulation, `tools/gowin_tcl.py` for the
bitstream.

| role | files |
|---|---|
| top | `top.v` - the clock, the resets, the counters, the I/O bus, the mix, and every instance |
| the processors | `zs256/tv80_*.v` (tv80, verbatim), `zs256/z80bus.v` (a Z80 on an enable, its bus as one request) - instantiated twice, for the Scorpion and for General Sound |
| the memory | `zs256/memmap.v` (the paging, the DOS flip-flop, the ProfROM bank, the turbo flag), `zs256/membus.v` (the Scorpion's side of the SDRAM, the screen copy, the loader port), `zs256/sdram.v` (the timetable), `zs256/screen.v` (the display's copy of pages 5 and 7), `zs256/poke.v` (the MCU's bytes) |
| the display | `zs256/video.v` |
| the devices | `zs256/keyboard.v` (the matrix), `zs256/ports.v` (the I/O decode), `zs256/fdc.v` + `wd1793.sv` (the Beta Disk), `zs256/ay.v` + `ym2149.sv`, `zs256/gs.v` (General Sound), `zs256/smuc.v` + `ide.v` + `rtc.v` + `nvram.v`, `zs256/sd_arbiter.v` |
| clock, sound | `sys_pll.v` (rPLL by hand: 27 -> 42 MHz), `i2s_tx.v` |
| MiSTeryNano | `mister/{mcu_spi,sysctrl,hid,osd_u8g2,sd_card,sd_rw,sdcmd_ctrl,sector_dpram,flashwr,coreload}.v` - Korvet Nano's copies; `sysctrl.v` rewritten for this core's letters and a 24-bit CMD 6 |
| HDMI | `hdmi/{hdmi_tx,tmds_channel,hdmi_packet,hdmi_serdes}.v` - UKNC Nano's encoder with audio, at 42 MHz with four packets an island |

Stubbed in simulation (`tools/srcs.py`'s `STUBBED`): `sys_pll.v`,
`hdmi/hdmi_serdes.v` and `mister/sector_dpram.v` by
`sim/stubs/gowin_ip_sim.v`; and `mister/sd_card.v` with `sd_rw.v` and
`sdcmd_ctrl.v` by `sim/stubs/sd_card_sim.v`, which serves image files
from the host on the same core-side interface (`+TRDA=`..`+TRDD=`,
`+HDD=`).

## Resources

The first build (14 September 2026): logic 9166/20736 (45%), registers
3279, BSRAM 17/46, Fmax 48.6 MHz on the 42 MHz clock, the critical path
tv80's register file.  0.1.1 (the same day, General Sound's memories in
BSRAM): logic 9311 (45%), registers 3314, BSRAM 41/46, Fmax 49.3; 0.1.2
(the M1 qualifiers) logic 9229.  BSRAM: the screen copy 8 blocks, the OSD 1, the
card's sector buffer 1, the ВГ93's 2, the drive's 2, the NVRAM 1, the
line buffer and small things the rest.  The RAM, the ROM and General
Sound's memory are in the SDRAM.

## The clocks

```
clk27            27 MHz     the crystal, pin 4
  `- sys_pll (x14 / 9)
      |- clk           42 MHz    CLKOUT: everything
      `- O_sdram_clk   42 MHz    CLKOUTP, 90 degrees behind: the SDRAM pad only
  `- hdmi_ser/pll_hdmi (x5, referenced to clk)
      `- clk_serial   210 MHz    the four OSER10s
m0s[3]           20 MHz     the BL616's SPI clock, asynchronous, into mcu_spi.v
```

That is all of them.  Every flop of the design is on `clk`; the Z80's
T-state, the machine's pixel, the HDMI pixel, General Sound's T-state,
the AY's clock, the clock chip's second and the I2S bit clock are phases
or enables of it.  `zs256.sdc` declares `clk27`, `clk42` and `spi_clk`.
Why 42: it is the multiple of 3.5 MHz an rPLL reaches from 27 (14/9,
with the phase detector at its 3 MHz floor), and a Spectrum wants exact
T-states - its tape loaders, its 50 Hz music and its multicolour effects
count them.  Korvet Nano's 40.5 would have been 1.25% off everywhere.

## The timetable

A T-state of the Z80 is twelve clocks, `tphase` 0..11; its enable is at
phase 0 (and 6 as well in turbo, when a T-state is six).  The SDRAM's
two six-clock slots start one clock after the enable:

```
tphase   0   1   2   3   4   5   6   7   8   9  10  11
        cen |------- slot A --------|-------- slot B --------
            ACT RD  -   cap late -   ACT RD  -   cap late -
```

- **Slot A is the Scorpion's.**  z80bus.v registers the core's request
  on the enable that ends T1, so it is up on slot A's first clock and
  served in the same T-state: the word is captured on the slot's clock 3
  (phase 4) and the byte is on the core's data input by phase 5, long
  before the end of T2, where tv80 takes it.  No wait states at 3.5
  MHz.  In turbo the T-states are six clocks and a request made in a
  T-state that begins at phase 6 waits for the next slot A - one wait
  state, as the board's GAL inserts on its RAM accesses too.
- **Slot B is General Sound's window**, its Z80 enabled every third
  clock (14 MHz).  The first cut put all of the card's memory behind the
  slot; every access then waited about four of its T-states and the
  card ran at half its 12 MHz, its sample generator fell behind its
  37.5 kHz interrupt and a module played as noise on the first board.
  Now the card's ROM and its fixed 16 KB (4000-7FFF: variables, stack,
  the DAC buffers) are BSRAM inside `gs.v`, answered within T2 with no
  wait, and only the window's RAM pages (8000-FFFF, page 1 up) take the
  slot.  The ROM copy is filled by the loader as it writes the image to
  280000h (top.v snoops `poke.v`'s bytes; the SDRAM's copy stays, unread).
  The MCU's loader (`poke.v`) takes slot A when
  the Scorpion does not ask, which at start is always.  Refresh takes
  any slot nobody asks for, counted so that nothing is lost.
- The display never touches the SDRAM: `screen.v` is a copy of pages 5
  and 7 in BSRAM, written through by every write into them (from the Z80
  or the loader), read by `video.v` a cell ahead.

Every access is ACTIVE, then READ or WRITE with auto-precharge (A10 set),
the read captured on slot clock 3 by the arithmetic in `sdram.v`'s
header, with PK8000 Nano's self-test that moves it to clock 4 if a board
says so - the slot is six clocks where Korvet Nano's is eight, the chip's
row cycle (about 63 ns) fits twice over.

## The memory

```
SDRAM words 00000h-3FFFFh   the RAM, 64 pages of 16 KB (page p at p * 1000h)
            40000h-4FFFFh   the ROM, 16 pages: four 64 KB banks of {128, 48, SYS, DOS}
            80000h-9FFFFh   General Sound's window RAM, 15 pages of 32 KB (page n at n * 2000h)
            A0000h-A1FFFh   General Sound's ROM, 32 KB - written by the loader, read by nobody:
                            gs.v keeps the copy the card runs from (BSRAM), and its fixed 16 KB
```

(word = byte address / 4, the byte by its lane; the loader's CMD 6
address is the byte address: the ROM goes to 100000h, GS's to 280000h.)
`memmap.v` turns a Z80 address into `rom`, `rom_page`, `ram_page` from
7FFD, 1FFD, DOS and the ProfROM bank; `membus.v` makes the word address.
Nothing is built into the bitstream: the firmware sends the ROM images
from the card at start (`mnano/romload.c`), and until it has the machine
executes zeros.

## The I/O bus

A request with `io` set is strobed once, on its first clock (`io_stb`
in top.v); a write is done then, a read is answered four clocks later
from `ports.v`'s mux, by which time the ВГ93 (three clocks) and the
SMUC (two) have their bytes on it.  tv80's I/O cycle has the chip's
automatic wait state, so the answer is inside T2 in either speed.
`ports.v` is the decode, `platform.md` the table.

The Scorpion's turbo: `memmap.v`'s flag (IN 7FFD on, IN 1FFD off, or
the OSD's 'T' forcing it) makes `cen_cpu` fire at phase 6 too.  The
board's GAL runs the 7 MHz clock and inserts waits on RAM only; here
RAM and ROM alike wait for slot A when they miss it (half the cycles,
one T-state each), so turbo is about 1.5x, which is also about what the
board gets.

## Reset

`sdram.v`'s `init` is the root: `hcnt`/`tphase` run from PLL lock, the
MiSTeryNano side waits 2^23 clocks after `init` (`por_done`, 200 ms) and
takes `mist_rst` until then, and the Scorpion is held by `cpu_rst` while
`mist_rst` or the OSD's 'R' bit 0 or `~init` is up and for 16 T-states
after.  The MCU sends R=3 at start, loads the ROMs, and sends R=0 when
it has sent the settings, so the machine starts with its ROM in place.
General Sound is reset with the machine and by its OSD switch.  S1
(`buts[0]`) resets everything; S2 (`buts[1]`) is the Magic button.

## The SD path

`sd_card.v` (MiSTeryNano's) has one sector interface for the machine:
request levels `rstart[4:0]`/`wstart[4:0]` one-hot by image slot, the
sector within the image, then `rbusy`, the 512 bytes on
`outen/outaddr/outbyte` (or taken from `inbyte` at `outaddr` for a
write), and `rdone`.  Five clients share it through `sd_arbiter.v`:
slots 0..3 the four floppies (one ВГ93; the system register's drive bits
pick the slot), slot 4 the SMUC's disk (`ide.v`).  The ROM images are
NOT on this path: the firmware reads them through FatFs and sends the
bytes over SYS CMD 6.

## Pinout

The board as Korvet Nano wires it, unchanged - `README.md` has the
table.  The SDRAM is in the package and its pins are the tool's, all 32
data lines used.  The USB-C serial (pin 69) is tang-ultima's UART to the
on-board BL616 (`mister/coreload.v`, SYS command 11), pin 48 its
dormant RECONFIG_N pulse (command 9), pins 59-62 the configuration
flash under `mister/flashwr.v` (command 10) - the same three blocks as
in the siblings, so that `../tang-ultima` can install and switch this
core like the other three.
