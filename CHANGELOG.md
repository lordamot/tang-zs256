# Changelog

## 0.1.3 alpha - 14 September 2026

Confirmed on the board.

- General Sound's RAM is 2 MB, the card's most: the page register is six
  bits, 63 window pages of 32 KB, SDRAM words 80000h-FFFFFh.  Its ROM's
  SDRAM copy moves out of the way to 400000h (byte address, `ROM_ADDR_GS`
  in the firmware and the snoop in `top.v`) - **flash the firmware and
  the bitstream together**, an old firmware puts the ROM where the new
  core has RAM.  The card's RAM test at reset takes about four times
  longer (a few seconds; the same on a 2 MB card).

## 0.1.2 alpha - 14 September 2026

The first build known to work on a board: the OSD, the ROM from the
card, the Scorpion, TR-DOS booting a real disk, the keyboard, General
Sound playing modules - reported by the operator on a Tang Nano 20K.

- The interrupt acknowledge could read a card's register as the IM 2
  vector: `ports.v` selected General Sound (B3/BB) and the SMUC on the
  address alone, and an acknowledge is an I/O cycle with M1 and the PC
  on the bus.  A program whose PC ended in BBh at the interrupt jumped
  through the card's status byte and died with interrupts off - ZPLAY's
  shell, one key in, on the first board.  The cards' selects now carry
  M1 as their own decoders do.  Found with the disk in simulation.
- The testbench: `+KEYS2=`/`+TYPE2_MS=` for a second, later batch of
  keys (`zz` a second's pause), `+IFFTRACE` for IFF1 and every
  acknowledge with the PC, a General Sound status-poll count.

## 0.1.1 alpha - 14 September 2026

The first board.  0.1.0 boots on a Tang Nano 20K: the OSD, the ROM from
the card, the Scorpion running.  Two defects seen there and fixed here,
General Sound confirmed on the board the same afternoon; the keyboard
had a second cause (0.1.2):

- The keyboard lost itself under fast typing: the firmware's slot-wise
  diff of the USB report sent a spare release and press when a held key
  changed slot, and `keyboard.v` counted its chords' shifts, so a chord
  key (cursor, Backspace, punctuation) pressed twice left Caps or
  Symbol Shift held.  `usb_host.c` diffs the reports as sets and sends
  releases with the OSD open; `keyboard.v` keeps a bitmap per shift.
- General Sound played noise: every access of its Z80 waited on the
  SDRAM's slot B and the card ran at half its 12 MHz, behind its 37.5
  kHz interrupt.  Its ROM and its fixed 16 KB are BSRAM now (41 of 46
  blocks), answered with no wait; only the window's RAM pages take the
  slot.  The INT is held until acknowledged (a 48-clock pulse was
  missed under a waited instruction) and the host/card flags are
  set-wins.
- Builds, meets timing (Fmax 49.3 on clk42), lints, simulates.

## 0.1.0 alpha - 14 September 2026

The first cut.  Authors: Sergei Lemeshev and Claude Code.  Not yet run
on a board.

- The Scorpion ZS-256 Turbo+ on the Tang Nano 20K, in Korvet Nano's
  framework: tv80 on a 42 MHz clock with exact T-states; the paging, the
  DOS flip-flop, the ProfROM's bank switch and the turbo read off the
  restored schematic's netlist and its GALs; 256 KB (or 1 MB) and the
  ROM image in the SDRAM through a two-slot timetable; the display with
  its own copy of the screen pages, 312 lines of 224 T-states, out as
  1056x544 at 50 Hz over HDMI with audio.
- The ports as the board decodes them, the Beta Disk with four .trd
  images, the AY, Kempston joystick and mouse, the keyboard as the
  matrix with chords.
- The three peripherals: the ProfROM; the SMUC with an IDE disk from an
  image on the card, the DS12887 clock and the 24C16 NVRAM; General
  Sound with its own tv80, 512 KB and four DACs.
- The BL616 firmware for it (core id 9), with the ROM images loaded from
  the card at start over a 24-bit SYS command 6, and a menu with the
  ROM, the devices and the Magic button; `make menu-test` walks it.
- tang-ultima's three blocks (flashwr, coreload, RECONFIG_N) as in the
  siblings, so the core can be installed and switched from there.
- Tools: `easyeda_net.py` (the schematic as a netlist), `jed22v10.py`
  (a GAL's equations), `trd.py` (TR-DOS images).
- In simulation the ROM passes its memory and interrupt tests, shows the
  Scorpion's menu, enters TR-DOS and reads the disk.
