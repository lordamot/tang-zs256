# The BL616 firmware: `mnano/`

MiSTeryNano's firmware (Till Harbaum), as Korvet Nano carried it, with
the Корвет's parts taken out (the ExtROM controller) and the Scorpion's
put in.  The MCU does what the FPGA cannot: USB host (keyboard, mouse,
joysticks), the SD card's file system, the on-screen menu, and it hands
the FPGA its settings over SPI - and, new here, it loads the machine's
ROM images into the core at start (`romload.c`).  The FPGA side of
every one of these is under `tang/src/mister/`.

Built by `make fw` (`.claude/docs/build.md`); flashed by `make flash-mcu
COMX=/dev/ttyACM0`; the shipped binary is `bin/bl616.bin`.

## The core id

`sysctrl.v` answers CMD 0 with `5c 42 09`; 09 is `CORE_ID_ZS256` in
`sysctrl.h`, index 9 of every table the firmware selects by core:
`core_names[]` (sysctrl.c), `keymap[]` and `modifier[]` (usb_host.c),
`settings_file[]` (menu.c: `/sd/zs256.ini`), the forms and variables
(menu.c).  The other MiSTeryNano cores' tables are still there; the
UKNC's (5), the PK8000's (7) and the Korvet's (8) are `NULL`.

## The keyboard

`mnano/zs256.h`: `keymap_zs256[]` indexed by USB HID usage,
`modifier_zs256[8]` by modifier bit.  A code is `ZK(row, col) = row * 5
+ col + 1` (1..40, the matrix as port FE reads it: row 0 is A8 - CS Z X
C V - row 7 is A15 - Space SS M N B), `ZCS(row, col)` the same key with
Caps Shift held (41..80), `ZSS` with Symbol Shift (81..120), `ZEXT`
(121) both; 0 is `MISS`, a key the machine does not have (F12 among
them - it is the OSD's).  The generic path in `usb_host.c` sends a
press as the code and a release as `0x80 | code` through HID CMD 1;
`hid.v` hands the byte to `keyboard.v` with a strobe, and the matrix
lives there, the chords' shifts counted so that they never drop each
other.

The mapping: letters, digits, Enter and Space are their keys; Shift is
Caps Shift, Ctrl and Alt Symbol Shift, so the machine's own chords work
from the PC keys (Shift+1 EDIT, Ctrl+P the quote); Backspace and Delete
are DELETE (CS+0), the cursor keys CS+5..8, Caps Lock CS+2, Esc and
Pause BREAK (CS+Space), Tab the extended mode, Home EDIT, Insert
GRAPHICS, PgUp/PgDn TRUE/INV VIDEO; the PC's unshifted punctuation keys
give their symbols as Symbol Shift chords (`-` `=` `;` `'` `,` `.` `/`),
and the keypad likewise.  A shifted PC punctuation key (Shift+`-`) gives
CS+SS+J, which the machine reads as its extended-mode symbol - not the
PC's `_`; that is the price of a positional map and is documented in
`howto.md`.

## The mouse and the joystick

The USB mouse's reports go to the core as they arrive (HID CMD 2:
buttons, dx, dy) and `top.v` sums them into the Kempston mouse's X and Y
counters, up being up; the buttons are on FADF.  A USB joystick's
digital byte (HID CMD 3) is the Kempston joystick's byte as it is - the
bit order is the same.

## The menu

```
ZS-256 Nano                  Hardware
  Floppy A:   <file>           ROM:            <file>                    (slot 5: romload.c)
  Floppy B:   <file>           Turbo:          Ports|On|Off              (T)
  Floppy C:   <file>           RAM:            256K|1024K                (m)  resets
  Floppy D:   <file>           Floppy:         Off|On                    (f)
  HDD:        <file>           SMUC:           Off|On                    (u)
  Reset              (R)       General Sound:  Off|On                    (g)
  Magic (NMI)        (h)       AY:             Off|On                    (y)
  Hardware  >                  AY stereo:      ABC|ACB|Mono              (s)
  About     >                  Joystick:       Off|Kempston              (j)
  Debug     >                  Mouse:          Off|Kempston              (M)
  Save settings                Volume:         Mute|33%|66%|100%         (A)
                               Floppy A..D prot.: Off|On                 (p q k l)
```

The file entries are `sdc_image_open` slots: 0..3 the floppies (`.trd`),
4 the SMUC's disk (`.img`, `.hdd`); `sd_card.v`'s `image_mounted` index
is the same number.  Slot 5, the ROM (`.rom`), is `SDC_SLOT_ROM`:
browsed like the others, remembered in the settings as `drive5=`, but
never mounted - `rom_select()` sends the file into the core over CMD 6
and resets the machine.  The letters are `sysctrl.v`'s CMD 4 ids, and a
value needs three edits: the letter in the form string, an entry in
`variables_zs256[]` (the default), and a case in `sysctrl.v`.  A change
of the RAM size sends R=1, R=0 after the value.  "Magic" is a button:
'h' 1 then 0, a pulse the core stretches into the button's press.
"Save settings" writes `/zs256.ini` on the card; at start every
variable is sent once (A T m f u g y s j M p q k l), then the ROMs are
loaded and 'P' sent, then R 3 and R 0.  The Hardware form scrolls; its
return to the main form is by form number.  The version at the right of
the main form's caption is the first line of `VERSION`, read by
`CMakeLists.txt` into `CORE_VERSION`.

"About" is a page of text (`about_zs256[]`); "Debug" is `top.v`'s 32
bytes through CMD 7, formatted by `menu_debug_open`: the resets and the
memory's self-test, the last opcode and its address, HALT and EI, the
7FFD/1FFD/FE registers, DOS and turbo, the ProfROM bank, the fetch
counter, which images are in, General Sound's PC, and the ROM sizes
loaded.

`make menu-test` walks all of this on the host (`menu_test.c`) and
leaves each screen under `build/menu/` as text and PNG.  It is the only
way to see whether a label and its value fit the 128 pixels.

## The ROM loader

`romload.c`: `rom_boot()` at the end of `menu_init()`, with the machine
in reset, sends the Scorpion's ROM - the file the settings remember for
slot 5, else `/sd/zs256.rom` - to SDRAM byte address 100000h, 256 KB at
most, and `/sd/gs105a.rom` to 400000h, 32 KB; then 'P' says how many
ProfROM banks the image has (0 for 64 KB, 1 for 128, 3 for 256).  A
file is read through FatFs in 512-byte pieces, each one CMD 6
transaction (`sys_poke24`: three address bytes, then the bytes).  A
missing file is reported on the console and on the Debug page, and the
machine runs zeros.

Under `../tang-ultima` the card's root is `/sd/zs256/` (its
`ultima_root()`), and the default names are relative to it.

## The SD card

The card is in the Tang's slot and `sd_card.v` reads it; the firmware's
FatFs goes through that module over SPI, and the floppy and disk images
go the other way: a request from the FPGA is an interrupt, the MCU reads
which slot and which sector, translates it through the file's cluster
map and drives the card, and the bytes land in the FPGA (`fpga.md`, the
SD path).  Write protection is the FPGA's: the letters p, q, k, l reach
`fdc.v`.

## The SPI link

Mode 1, 20 MHz, four targets by the first byte (0 SYS, 1 HID, 2 OSD, 3
SDC); `mcu_spi.v` takes it through a handshake into the 42 MHz domain.
`-DM0S_DOCK=1` picks the pinout in `spi.c` that matches the seven wires
in `README.md`.  UKNC Nano's `.claude/docs/mcu.md` has the byte-level
protocol of each target; this core's SYS CMD 6 has three address bytes
(the siblings' has two), CMD 7 is its debug window, CMD 9, 10 and 11 are
tang-ultima's (`../tang-ultima/CLAUDE.md`) and the same as in the
siblings.

## For tang-ultima

What that firmware needs from here to carry this core: `zs256.h`, the
forms, variables and About text in `menu.c`, `settings_file[9]`,
`drivename()`'s names (A B C D HDD ROM), `romload.c` with its two
default names under `ultima_root()`, the `SDC_SLOT_ROM` handling in
the file selector, `sys_poke24()`, and `CORE_ID_ZS256` in every table.
`ultima_cores[]` gets `{ CORE_ID_ZS256, "ZS-256", "zs256", "zs256.ini" }`
and the Makefile's `CORES` gets `zs256` with `DIR_zs256 := $(ROOT)/../tang-zs256`
and `NAME_zs256 := zs256`.
