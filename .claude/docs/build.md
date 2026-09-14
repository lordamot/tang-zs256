# Building and flashing

Two binaries, two toolchains.  What ships prebuilt is:

```
bin/tang.fs      the FPGA bitstream   (make bitstream)
bin/bl616.bin    the MCU firmware     (make fw, copied by hand)
```

A user who only wants to run the machine flashes those two, puts the
ROMs on the card, and needs no toolchain at all.  That is the point of
committing them.

**Both halves build on this host.**  Everything they need lives under
`tools/`, fetched by `make toolchain` - about 7 GB including Gowin -
nothing is installed on the host and `tools/` is in `.gitignore`.  On
this machine `tools/` was made as hard links into `../tang-korvet/tools/`
(13 Sep 2026), itself hard links into PK8000 Nano's - the same content
at no cost in disk; a clone elsewhere runs `make toolchain`.

```
make toolchain   fetch the toolchain into tools/  (~7 GB, once)
make lint        Verilator over the whole design - the fast check, seconds
make sim         run the machine (RUN_MS=1500; ~11 ms a second)
make frames      the same, writing video frames as .ppm (PPM_FROM=1200)
make wave        the same, dumping a VCD, then open it (WAVE_MS=2)
make bitstream   build the FPGA bitstream -> bin/tang.fs (about a minute)
make timing      the timing gate alone, on the last PnR report
make fw          build the BL616 firmware -> build/fw/bl616.bin
make menu-test   the OSD menu on the host: every form walked, screens as PNG
make card        say what goes onto the SD card
make netlist     the schematic's netlist -> build/netlist.txt
make flash-fpga  openFPGALoader the shipped bitstream to SRAM
make flash-mcu   flash the firmware over UART (COMX=/dev/ttyACM0)
```

`SIMARGS="+CPUTRACE +TRACE_MS=100"` and the like pass plusargs to the
simulator; `sim/tb/tb_top.v`'s header lists them.

## The FPGA half

Toolchain: **Gowin EDA Education edition**, V1.9.11.03, in
`tools/gowin/`.  `make bitstream` drives its headless shell with a Tcl
generated from `tang/zs256.gprj` and the IDE's own
`tang/impl/zs256_process_config.json` (`tools/gowin_tcl.py`), so the
command line and an IDE build read the same list and options.  The
result is `tang/impl/pnr/zs256.fs`, copied to `bin/tang.fs` when the
timing gate passes.  `gw_sh`'s three quirks - its bundled libraries
fight a current Linux, its option names differ from the IDE's, and
`-use_sspi_as_gpio 1` is not optional - are handled by `tools/fetch.sh`
and the Makefile; UKNC Nano's `.claude/docs/build.md` has the account.

The timing gate (`tools/timing_check.py`, `.claude/rules/timing.md`)
wants `clk27`, `clk42` and `spi_clk` in the report, no violations, no
undeclared or unrelated clock.  `../tang-ultima` runs the same two
scripts out of its own build directory (`gowin_tcl.py --abs`,
`timing_check.py <pnr dir>`).

## What lint and simulation cover

`make lint` runs Verilator over exactly the `.gprj`'s list with the
stubs standing in.  It is clean but for warnings, most of them the
MiSTeryNano sources', tv80's and MiSTer's (timescale, unused bits,
widths); any error is yours.

`make sim` builds the whole machine into a Verilator binary against a
functional SDRAM model (32 bits wide) and a stand-in BL616 that speaks
the real SPI protocol, preloads the model with the ROMs from `soft/rom/`
(`+ROM=`, `+GSROM=`; `+ROMSPI=` sends the Scorpion's the firmware's way
instead, over CMD 6), and runs the machine.  The testbench's end-of-run
lines are the checks:

```
[tb] config checks: 0 wrong                     the OSD values landed in sysctrl
[tb] cpu: N opcode fetches, ... interrupts      the core runs; the 50 Hz is taken
[tb] ports: 7FFD .. 1FFD .. FE .. dos turbo     what the machine set its registers to
[tb] read-after-write: N checked, 0 wrong       every SDRAM word read back as written, both ports
[tb] sdram self-test: done 1, fail 0, late 0    the controller's own four words
[tb] sd transfers N; screen writes N; gs: ...   the disk was read; the display copy written; General Sound runs
[tb] hdmi: ... 0 ecc errors                     the data islands are well formed
[tb] hdmi frame: 1056 x 544                     the raster is what video.md says
```

The SDRAM model is FUNCTIONAL: it tracks rows and serves words, checks
no timing, and drives read data the way the chip does with the
90-degree clock.  Nothing here says anything about the real card, the
real SDRAM pads, the HDMI PHY or a monitor's opinion of a 50.08 Hz frame.

The Scorpion's ROM tests its memory (about a second) and its three
interrupt modes (three HALTs on the 50 Hz), then draws its menu at about
2.6 s of machine time; `RUN_MS=3000` shows the menu, `+KEYS=1f
+TYPE_MS=3300` presses Enter on "128 TR-DOS", and with `+TRDA=soft/boot.trd
+SDFAST` the boot file loads.  The runs `progress.md` reports:

```
make frames RUN_MS=3000 PPM_FROM=2900 PPM_MAX=1
make frames RUN_MS=5500 PPM_FROM=5400 PPM_MAX=1 SIMARGS="+TRDA=soft/boot.trd +SDFAST +KEYS=1f +TYPE_MS=3300"
```

`+TYPE_STR=` types text at the BASIC prompt (`_` for a space), `+KEYS=`
presses codes (hex pairs, keyboard.v's numbering); `+CPUTRACE`,
`+IOTRACE`, `+MEMTRACE`, `+GSTRACE` print what the processors do from
`+TRACE_MS=`; `+SCRDUMP` writes the screen page as a `.scr`;
`tools/ppm2png.py` turns a frame into a PNG.

On this host the simulation runs at about 11 ms of machine time a
second.  Runs are independent: run them in parallel from separate
directories that hold `build/`, `soft/` and `tang/` as symlinks and an
empty `sim/out/`, since the testbench writes its frames to `sim/out/`
relative to where it runs.

## The MCU half

The Bouffalo SDK (`master_legacy`) plus a T-Head RISC-V GCC, both in
`tools/`; `make fw` builds `mnano/` into `build/fw/bl616.bin` and it is
copied on to `bin/` by hand.  The three things UKNC Nano settled to make
that work (the SDK branch, the host-tool patch, the two `-D`s through
`BOARD`) are still in `tools/fetch.sh` and the Makefile and still
needed.  The version in the OSD's caption is the first line of
`VERSION`, read by `mnano/CMakeLists.txt` into `CORE_VERSION`.

## Flashing

**Tang Nano 20K**: `make flash-fpga` (SRAM, gone at power-off) or
`make flash-fpga-flash` (the SPI flash), then **power-cycle the board**
- `openFPGALoader -f -r` writes the flash and reports success but does
not reliably reconfigure the chip.  Once anything has opened
`/dev/ttyUSB*` the next flash fails with `ftdi_usb_reset failed` and
only replugging the cable clears it.  Replug, flash, power-cycle, in
that order.

**BL616**: hold BOOT, tap RESET, release BOOT; the chip enumerates as a
serial port (`/dev/ttyACM0`); `make flash-mcu COMX=/dev/ttyACM0` (needs
`dialout`; `sg dialout -c '...'` works without a relogin).  `BFLB IMG
LOAD HANDSHAKE FAIL` means the port opened and nothing answered: not in
boot mode, or the wrong port.  Press RST afterwards.

## Reading the board

The six LEDs, lit when the thing is true (`top.v`'s last lines; the
board's LEDs are active low and the assignments invert):

```
LED0  the power-on reset has finished (lit 200 ms after the memory is up)
LED1  the beeper (port FE bit 4) is high
LED2  DOS is on (TR-DOS's ROM is paged in) - or, at boot, the SDRAM
      self-test chose the late capture
LED3  a floppy, the disk or an SD transfer is busy - or, at boot, the
      SDRAM self-test FAILED both captures
LED4  the machine is held in reset
LED5  the SDRAM is initialised
```

A healthy start is LED5 then LED0 coming on, LED4 going out, and 2 and 3
dark; then LED2 flickers as the ROM probes the floppy, and the Scorpion's
menu is on the screen about three seconds after the firmware releases
the reset (its memory and interrupt tests take that long on the real
machine too).  The OSD on F12 says whether the MCU link works, and
needs no memory; its Debug page (`mcu.md`) says whether the ROM was
loaded, where the processor is and what the paging registers hold.

## The SD card

FAT32.  The firmware reads it through the FPGA's `sd_card.v` and keeps
its settings in `/zs256.ini`; the ROMs are `/zs256.rom` and
`/gs105a.rom` (or whatever the ROM entry of the menu picked); the floppy
images (`.trd`) and the SMUC's disk image (`.img`, `.hdd`) anywhere on
it.  `make card` says the same.  Under `../tang-ultima` all of it is in
`/zs256/` instead.
