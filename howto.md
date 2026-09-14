# ZS-256 Nano - how to

The short form.  `README.md` has the wiring and the flashing; the long
form of everything is under `.claude/docs/`.

## 1. What you get

A Scorpion ZS-256 Turbo+ that starts into its own menu after its
memory and interrupt tests - 128 TR-DOS, 128 BASIC, Calculator, 48
BASIC, 48 TR-DOS - on HDMI at 1056x544 (the machine's 50 Hz), with a USB
keyboard, joystick and mouse on the BL616, and the beeper, the AY and
General Sound over HDMI and the dock's I2S output.  Software comes in
from the SD card: `.trd` floppies through the Beta Disk, a disk image
through the SMUC's IDE, the ROM itself (a plain 64 KB one or a ProfROM)
as a file.  Not on a board yet (14 Sep 2026).

## 2. The keyboard

The machine's keyboard is the Spectrum's 8 x 5 matrix and the USB
keyboard is mapped onto it (`mnano/zs256.h`).  Its own keys are where a
PC keyboard has them: the letters, the digits, Enter, Space; the two
shifts are

| Spectrum key | PC key |
|---|---|
| Caps Shift | Shift (left or right) |
| Symbol Shift | Ctrl, Alt (left or right) |

so the machine's chords work as on its own keyboard: Shift+1 is EDIT,
Shift+0 DELETE, Ctrl+P the quote, Ctrl+J minus.  On top of that a PC key
with no place on the machine is one of those chords:

| PC key | what the machine gets |
|---|---|
| Backspace, Delete | DELETE (Caps Shift + 0) |
| cursor left/down/up/right | Caps Shift + 5/6/7/8 |
| Caps Lock | CAPS LOCK (Caps Shift + 2) |
| Esc, Pause | BREAK (Caps Shift + Space) |
| Tab | extended mode (Caps Shift + Symbol Shift) |
| Home | EDIT (Caps Shift + 1) |
| Insert | GRAPHICS (Caps Shift + 9) |
| PgUp, PgDn | TRUE VIDEO, INV VIDEO (Caps Shift + 3, 4) |
| `-` `=` `;` `'` `,` `.` `/` | the symbol: Symbol Shift + J, L, O, 7, N, M, V |
| keypad `/` `*` `-` `+` `.` | Symbol Shift + V, B, J, K, M |
| keypad digits, Enter | the digits, Enter |
| F12 | the OSD - never reaches the machine |

A shifted PC punctuation key (Shift+`-`) gives Caps Shift with the
chord, which the machine reads as the extended-mode symbol on that key,
not the PC's character: type the machine's way (Ctrl+J for `-`, Ctrl+K
for `+`).  `[` `]` `\` `` ` `` and the F keys do nothing.

## 3. The joystick and the mouse

A USB joystick is the Kempston joystick (port 1F); "Joystick: Off" in
the menu leaves the port reading zero.  A USB mouse is a Kempston mouse
(FADF, FBDF, FFDF), up being up.

## 4. The menu

F12.  Cursor keys move, left/right step a value, Space or Enter selects,
Esc closes.

- **Floppy A..D** - the image slots on the card (`.trd`).
- **HDD** - the SMUC's disk image (`.img`, `.hdd`: raw 512-byte sectors).
- **Reset** - the machine restarts.
- **Magic (NMI)** - the Magic button: the NMI into the Service Monitor
  (it takes effect when the machine next fetches an opcode from RAM, as
  on the board; in the BASIC editor, which runs in ROM, it waits).
  S2 on the Tang does the same.
- **Hardware** - **ROM** (a ROM file from the card: 64 KB, or a 256 KB
  ProfROM; a change restarts the machine); **Turbo** (Ports: 7 MHz as
  IN 7FFD / IN 1FFD say, the board's way; On; Off); **RAM** (256K, or
  1024K as a ZS-1024, 1FFD bits 7:6; a change restarts); **Floppy**
  (the Beta Disk); **SMUC**; **General Sound**; **AY**; **AY stereo**
  (ABC, ACB, Mono); **Joystick**; **Mouse**; Volume; write protection
  for the four floppies.
- **About**, **Debug** (where the processor is and what the paging
  registers hold - for when it does not start, `.claude/docs/build.md`).
- **Save settings** - writes `/zs256.ini` on the card; loaded at power-up.

## 5. The ROM

`/zs256.rom` on the card is what the machine runs; `soft/rom/` has
v2.94 (the board's authors' choice), v2.95 and two ProfROM 4.01 images.
A ProfROM's four banks switch as on the board: bank 0 is the ordinary
ROM, the Service Monitor's menu (Magic, or the boot menu's entries)
reaches the rest.  General Sound's firmware is `/gs105a.rom`.  Both are
loaded by the BL616 at power-up; the Debug page says what was loaded.

## 6. The SMUC

With "SMUC: On" (the default) the card is on the bus: an IDE drive
(when a disk image is mounted as HDD), the DS12887 clock (running from
00:00 1 January 2000 until set; nothing keeps it across a power cycle),
the 24C16 NVRAM (kept until power-off).  A ProfROM 4 boots from the IDE
disk through its own menu; iS-DOS with its SMUC drivers sees the disk
as usual.  The image is raw sectors, LBA from 0; the geometry the drive
reports is 16 heads x 32 sectors.

## 7. If it does not start

- No picture at all: the monitor may not take 1056x544 at 50 Hz - try
  another; and check the seven wires (`README.md`).
- A picture but only the border, for ever: the ROM is not loaded (no
  `/zs256.rom`, or the card was not ready) - the Debug page says "ROM 0
  KB"; put the file on the card and reset.
- The tests but no menu: the SDRAM.  This is the one thing simulation
  cannot vouch for; the Debug page's "bist" and "late" say what the
  controller's self-test found.
- The picture but no keys: the BL616 is not talking - its firmware, the
  wires, or the card missing (the firmware still runs without one).
- Flashing: replug, flash, power-cycle, in that order
  (`.claude/docs/build.md`).
