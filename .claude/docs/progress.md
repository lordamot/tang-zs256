# Progress

What each build showed, what is known not to work, what is next.

## The first board (14 September 2026, afternoon)

The first-night build (`make flash-mcu`, `make flash-fpga-flash`) **boots
on a Tang Nano 20K**: the OSD comes up, the ROM loads from the card, the
Scorpion runs and is generally usable; the SDRAM at 42 MHz with six-clock
slots, the HDMI mode and the SPI link all work on this board.  Reported
by the operator, not watched from here.  Two defects seen:

1. **The keyboard "hangs from time to time".**  Diagnosed as a shift held
   for good: the firmware compared the USB report slot by slot, a
   keyboard packs its slots, so releasing the first of two held keys
   sent the core "release B, press B" for the second; `keyboard.v`
   counted its chord shifts, and a chord key (cursor, Backspace, the
   punctuation) pressed twice and released once left Caps or Symbol
   Shift down.  Fixed both sides: `usb_host.c` diffs the reports as
   sets (and sends releases with the OSD open too), `keyboard.v` keeps
   a bitmap per shift.  Flashed: still failed - in ZPLAY's shell one
   cursor key press and the keyboard is dead.  Reproduced in simulation
   with the disk (`soft/ZPLAY50.TRD`, the operator's) and traced: the
   shell runs IM 2 with I = 3Bh and takes its vector from the bus
   (FFh -> the 48 ROM's 3BFF/3C00 -> FFFF -> a JR into FFF4).  An
   interrupt acknowledge is an I/O cycle with M1 and the PC on the
   address bus, and `ports.v` selected General Sound on A7..A0 = B3/BB
   without M1 - so the acknowledge whose PC was 63BBh (the `JP z`
   after `BIT 4,A` in the key loop) read the card's status, 7Eh, as
   its vector, and the CPU went through 3B7Eh into nowhere with
   interrupts off; the next key's HALT was the hang.  The SMUC's
   select lacked M1 too.  Fixed in `ports.v`: every card's select is
   qualified by M1, as the cards' own decoders are (VD10 on the GS
   schematic).  Confirmed in simulation: Down moves the shell's bar,
   Space selects, interrupts keep coming, the file loads and plays.
   The chord fix stands on its own.  **Flashed (0.1.2): confirmed on
   the board** - the shell's arrows work, the keyboard stays alive,
   the module plays.
2. **General Sound plays noise instead of a module** (ZPLAY 5.0).
   Diagnosed from the firmware source (psbhlw/gs-firmware) and a
   measurement in simulation: the card's Z80 waited about four of its
   T-states on every memory access through slot B and ran at roughly
   half its 12 MHz; its 37.5 kHz interrupt handler only reads the DAC
   buffers at 6000h-63FFh and the main loop's generator has to fill
   them in time - it did not, and the DACs played stale buffers.  Also
   the INT was a 48-clock pulse, shorter than a waited instruction
   (the card's is an RC pulse of some microseconds), and a same-clock
   host write / card read of the data register lost the flag.  Fixed:
   the ROM and the fixed 16 KB are BSRAM in `gs.v`, answered inside
   T2 with no wait (the ROM copy filled by snooping the loader); the
   INT is held until acknowledged; the flags are set-wins.  In
   simulation the card's fetch rate in its ROM checksum loop is 14 MHz
   with no wait state (1.37 M fetches/s in a loop of 181 T).
   **Flashed the same afternoon: General Sound plays the module** -
   the card's Z80, its ROM and RAM, the host's ports, the DAC path and
   the audio out are all confirmed on the board.  `soft/ZPLAY50.TRD`
   is the operator's player, kept for the simulation.

The build with the GS and chord fixes (0.1.1): passed the timing gate
(Fmax 49.3 on clk42, logic 45%, BSRAM 41/46 - the GS's 24 blocks on top
of 17); flashed, GS confirmed.  The build with the acknowledge fix
(0.1.2) passes the gate; flashed, and the operator reports everything
working: the OSD, the ROM from the card, the Scorpion, TR-DOS booting a
real disk, the keyboard with its chords, General Sound playing modules.
**0.1.2 is the first build known to work on a board.**

## State (14 September 2026, the first night)

- **Builds**: `make bitstream` passes the timing gate at 42 MHz (Fmax
  48.6, logic 45%, BSRAM 17/46); `make fw` builds; `make menu-test`
  walks the forms with 0 errors; `make lint` is clean of errors.
- **Simulates**: with `soft/rom/scorp294.rom` the ROM runs its memory
  test (about 1.1 s), its three interrupt-mode HALTs, draws "fast test
  of computer", probes the floppy through TR-DOS, and at about 2.6 s
  shows the Scorpion's menu ("1992-94 Scorpion ZS 256"); the 50 Hz
  interrupt is taken every frame from then on.  Enter on "128 TR-DOS"
  with `soft/boot.trd` in A: TR-DOS reads the disk (32 sector
  transfers) - whether the boot file then runs is being looked at
  (the trace at 5 s of machine time, `sim/out/dos_trace.txt`).
  General Sound's Z80 runs its firmware to the command loop.  The
  SDRAM's read-after-write check is clean on both ports (2.5 million
  words).
- **Not on a board** as of that night; it went on one the next
  afternoon, above.

## Defects and open questions

1. Settled: a real disk (`soft/ZPLAY50.TRD`) autoboots, on the board
   and in simulation; the hand-built `soft/boot.trd` from `tools/trd.py`
   was the suspect and remains unverified.
2. Turbo is approximate: 7 MHz with a wait state on half the memory
   cycles (RAM and ROM alike), about 1.5x; the board's GAL leaves ROM
   unwaited.  Untested beyond lint.
3. The SMUC's IDE, clock and NVRAM, the ProfROM's switch and General
   Sound's DACs are lint-clean and reasoned from Unreal's model; none has
   been exercised by software in simulation yet.  A ProfROM 4 boot
   (`+ROM=soft/rom/prof401.rom`) and a disk image with a FAT32 volume
   are the next runs.
4. The 312/316-line question is settled for the original board
   (`video.md`); a board built from the v16.2.6 redraw would differ by
   four lines a frame.
5. Port FE in DOS mode is not decoded, as the board has it; if any TR-DOS
   variant reads the keyboard from the ROM it will not see it.
6. Nothing keeps the clock chip's time or the NVRAM across a power
   cycle; the firmware could save and restore them with the settings.
7. No .tap, no .scl (the MCU could convert to a temporary .trd), no
   printer, no RS-232, no Covox.

## Next

- Board tests still outstanding: turbo (item 2 below), the SMUC's IDE
  with a disk image, the clock and NVRAM, a ProfROM 4 boot, the
  Kempston mouse and joystick, the AY through a program that uses it,
  the Magic button.
- Get the boot file running in simulation; then a ProfROM 4 boot with an
  HDD image; then General Sound with a program that talks to it.
- `../tang-ultima`: add the core (`mcu.md`'s last section says what).
