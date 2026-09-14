# ZS-256 Nano

**Scorpion ZS-256 Turbo+** - петербургский клон ZX Spectrum Сергея
Зонова (1991-98): Z80 на 3,5 МГц с «турбо» 7 МГц, 256 КБ, Сервис-монитор
и TR-DOS в ПЗУ, Beta Disk, AY - вместе с тремя его обычными спутниками,
**ProfROM**, **SMUC** (IDE, часы, NVRAM) и **General Sound** - на
**Tang Nano 20K** с платой **BL616** (M0S Dock) рядом.  Сделано по образцу
и на основе [Korvet Nano](https://github.com/lordamot/tang-korvet), через
него [PK8000 Nano](https://github.com/lordamot/tang-pk8000) и
[UKNC Nano](https://github.com/lordamot/tang-uknc) (аппаратная часть -
Алексей Гуров, линия 2.x - Сергей Лемешев и Claude Code): оттуда взяты
связь с BL616, HDMI-кодер со звуком, расписание SDRAM, инструменты и
метод.  Процессор - tv80 (Guy Hutchison, MIT).  Схема - реставрация
[romychs](https://github.com/romychs/Scorpion256TPlus) платы v16.2.6,
прочитанная как список цепей; ГАЛы - из её же прошивок.  Собрано так,
чтобы быть четвёртым ядром [Tang Ultima](https://github.com/lordamot/tang-ultima).
Версия - в файле `VERSION`, история - в `CHANGELOG.md`, лицензия - MIT
(`LICENCE.md`).  *English below.*

**Состояние (14 сентября 2026): собирается, проходит временной анализ,
в симуляции проходит тесты ПЗУ и показывает меню Скорпиона.  На плате
запускалось - GS работает в том числе.**

## Что умеет

- Z80 на 3,5 МГц, точные такты; турбо 7 МГц как на плате - включается
  чтением порта 7FFD, выключается чтением 1FFD (или из меню: всегда/никогда).
- Память Скорпиона: 256 КБ (или 1 МБ по ZS-1024), порты 7FFD и 1FFD как
  их дешифрует плата, ОЗУ 0 в области ПЗУ, теневой Сервис-монитор,
  триггер DOS точно по схеме (вход по 3Dxx, выход по первой выборке из
  ОЗУ, кнопка Magic - NMI в монитор).
- ПЗУ - файлом с карты: обычное 64 КБ или **ProfROM** 256 КБ, банки
  которого переключаются как в ГАЛе (чтение 0100h-010Fh сервис-ПЗУ).
- Экран 256x192 с бордюром, 312 строк по 224 такта, прерывание 32 такта,
  порт FF с атрибутом; по HDMI как 1056x544 при 50 Гц.
- Клавиатура USB как матрица 8x5 с аккордами (Backspace, стрелки,
  знаки), джойстик USB как Kempston, мышь USB как Kempston mouse.
- AY-3-8912 (ABC/ACB/моно), бипер, MIC.
- Beta Disk (ВГ93) с четырьмя дисководами из образов `.trd`.
- **SMUC**: IDE-диск из образа на карте (LBA и CHS), часы DS12887,
  NVRAM 24C16 - порты как в Unreal Speccy, под ProfROM 4 и iS-DOS.
- **General Sound**: свой Z80 (~12 МГц), 512 КБ, четыре ЦАП, прошивка
  gs105a - файлом с карты.
- Меню по **F12**: четыре дисковода, HDD, сброс, Magic, «Hardware»
  (ПЗУ, турбо, память, каждое устройство, стерео AY, джойстик, мышь,
  громкость, защита записи), «About», «Debug», сохранение настроек.

Чего пока нет: магнитофона файлами (.tap), .scl, принтера, RS-232,
Covox.  Состояние и порядок - в `.claude/docs/progress.md`.

## Что нужно

- Tang Nano 20K, плата BL616 (M0S Dock), SD-карта FAT32, USB-клавиатура,
  USB-мышь и джойстик по желанию.
- Семь проводов между платами - распиновка **как в исходном MiSTeryNano**,
  как у трёх машин-родственников:

```
Tang Nano 20K   BL616
42              io10   MISO
41              io11   MOSI
56              io12   CSN
54              io13   SCK
51              io14   IRQ
GND             GND
+5              +5
```

Звук I²S - на выводах 71 (BCK), 72 (WS), 73 (DIN), 74 (разрешение
усилителя); по HDMI звук идёт сам.  Кнопка S1 - сброс, S2 - Magic.

## Карта

- `/zs256.rom` - ПЗУ: `soft/rom/scorp294.rom` (64 КБ) или ProfROM
  (`soft/rom/prof401.rom`, 256 КБ).  Другой файл - через меню (ROM).
- `/gs105a.rom` - прошивка General Sound: `soft/rom/gs105a.rom`.
- Образы `.trd` - где угодно; дисководы A-D выбираются в меню.
- Образ диска для SMUC (`.img`, `.hdd`, сырые секторы) - где угодно;
  «HDD» в меню.
- `/zs256.ini` - настройки («Save settings»).

Под Tang Ultima всё то же лежит в папке `/zs256/`.

## Как прошить

**BL616** - через его загрузчик: удерживая **BOOT**, подключить USB (или
нажать **RST**), отпустить BOOT; плата появится как последовательный
порт.  Дальше либо BLDevCube (чип BL616/BL618, вкладка MCU, файл
`bin/bl616.bin`, адрес `0x00000000`, скорость 2000000, Create & Download),
либо из этого репозитория:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

После прошивки нажать RST.

**Tang Nano 20K** - через openFPGALoader (или Gowin Programmer):

```sh
openFPGALoader -b tangnano20k -f bin/tang.fs     # во флеш
make flash-fpga-flash                            # то же из репозитория
```

и **выключить-включить питание**: после записи во флеш плата продолжает
работать со старой прошивкой, пока её не перезапустить.

## Как пользоваться

Включить - около трёх секунд ПЗУ проверяет память и прерывания (экран
«fast test of computer»), потом меню Скорпиона: 128 TR-DOS, 128 BASIC,
Calculator, 48 BASIC, 48 TR-DOS.  С диском в A: «128 TR-DOS» грузит
`boot`.  **F12** открывает меню; курсор - по пунктам, влево/вправо -
значение, пробел или Enter - выбрать, ESC - закрыть.  Раскладка:
буквы, цифры, Enter, пробел - как есть; Shift - Caps Shift, Ctrl и Alt
- Symbol Shift; Backspace - DELETE, стрелки - CS+5..8, Caps Lock -
CAPS LOCK, Esc - BREAK, Tab - расширенный режим; `- = ; ' , . /` дают
свои знаки; подробно - `howto.md`.

## Как собрать

```sh
make toolchain    # один раз, ~7 ГБ в tools/
make lint         # Verilator, секунды
make sim          # машина целиком, до тестов ПЗУ (минуты); RUN_MS=3000 - до меню
make frames       # то же, кадры экрана в sim/out/*.ppm
make bitstream    # прошивка ПЛИС -> bin/tang.fs, с проверкой временных ограничений
make fw           # прошивка BL616 -> build/fw/bl616.bin
```

---

# ZS-256 Nano (English)

The **Scorpion ZS-256 Turbo+** - Sergey Zonov's ZX Spectrum clone from
St. Petersburg (1991-98): a Z80 at 3.5 MHz with a 7 MHz "turbo", 256 KB,
the Service Monitor and TR-DOS in its ROM, a Beta Disk and an AY - with
the three peripherals a Scorpion usually has beside it, the
**ProfROM**, the **SMUC** (IDE, clock, NVRAM) and **General Sound** -
on a **Tang Nano 20K** with a **BL616** board (M0S Dock) beside it.
Modelled on and built from [Korvet Nano](https://github.com/lordamot/tang-korvet)
and through it [PK8000 Nano](https://github.com/lordamot/tang-pk8000) and
[UKNC Nano](https://github.com/lordamot/tang-uknc) (hardware by Alexey
Gurov; the 2.x line by Sergei Lemeshev and Claude Code): the BL616 link,
the HDMI encoder with audio, the SDRAM timetable, the tools and the
method are taken from there.  The CPU is tv80 (Guy Hutchison, MIT).  The
machine is read off [romychs'](https://github.com/romychs/Scorpion256TPlus)
restored schematic (v16.2.6) as a netlist, and its GALs off their fuse
maps.  Built to be the fourth core of
[Tang Ultima](https://github.com/lordamot/tang-ultima).  The version is
in `VERSION`, the history in `CHANGELOG.md`, the licence is MIT
(`LICENCE.md`).

**State (14 September 2026): builds, meets timing, in simulation passes
the ROM's tests and shows the Scorpion's menu.  Ran on a board - works, GS plays.**

## Features

- The Z80 at 3.5 MHz, cycle-exact; the 7 MHz turbo as the board has it
  - on by a read of port 7FFD, off by a read of 1FFD (or forced from
  the menu).
- The Scorpion's memory: 256 KB (or 1 MB as a ZS-1024), ports 7FFD and
  1FFD as the board decodes them, RAM 0 under the ROM, the shadow Service
  Monitor, the DOS flip-flop exactly as the schematic has it (in at
  3Dxx, out at the first fetch from RAM, the Magic button an NMI into
  the monitor).
- The ROM as a file from the card: a plain 64 KB one, or a 256 KB
  **ProfROM** with its banks switched as the GAL does (a read of
  0100h-010Fh of the Service ROM).
- The 256x192 display with its border, 312 lines of 224 T-states, the
  32 T-state interrupt, port FF with the attribute; over HDMI as
  1056x544 at 50 Hz.
- A USB keyboard as the 8x5 matrix with chords (Backspace, the cursor
  keys, the punctuation), a USB joystick as Kempston, a USB mouse as a
  Kempston mouse.
- The AY-3-8912 (ABC/ACB/mono), the beeper, MIC.
- The Beta Disk (ВГ93) with four drives from `.trd` images.
- **SMUC**: an IDE disk from an image on the card (LBA and CHS), the
  DS12887 clock, the 24C16 NVRAM - the ports as Unreal Speccy has them,
  for ProfROM 4 and iS-DOS.
- **General Sound**: its own Z80 (about 12 MHz), 512 KB, four DACs, the
  gs105a firmware as a file from the card.
- A menu on **F12**: four drives, HDD, Reset, Magic, "Hardware" (the
  ROM, turbo, RAM size, each device, AY stereo, joystick, mouse, volume,
  write protection), About, Debug, settings saved to the card.

Not yet: tape as files (.tap), .scl, the printer, RS-232, Covox.
`.claude/docs/progress.md` has the state.

## What you need

- A Tang Nano 20K, a BL616 board (M0S Dock), a FAT32 SD card, a USB
  keyboard; a USB mouse and joystick if wanted.
- Seven wires between the boards - the **stock MiSTeryNano pinout**, as
  the three siblings wire it (table above).  I²S audio on pins 71
  (BCK), 72 (WS), 73 (DIN), 74 (amplifier enable); HDMI carries the
  sound itself.  S1 is reset, S2 the Magic button.

## The card

- `/zs256.rom` - the ROM: `soft/rom/scorp294.rom` (64 KB) or a ProfROM
  (`soft/rom/prof401.rom`, 256 KB).  Another file: the menu's ROM entry.
- `/gs105a.rom` - General Sound's firmware: `soft/rom/gs105a.rom`.
- `.trd` images anywhere; drives A-D are chosen in the menu.
- A disk image for the SMUC (`.img`, `.hdd`, raw sectors) anywhere;
  "HDD" in the menu.
- `/zs256.ini` - the settings ("Save settings").

Under Tang Ultima the same files live in `/zs256/`.

## How to flash

**BL616**, through its bootloader: hold **BOOT**, plug in USB (or press
**RST**), release BOOT; the board shows up as a serial port.  Then either
BLDevCube (chip BL616/BL618, MCU tab, file `bin/bl616.bin`, address
`0x00000000`, baud 2000000, Create & Download) or, from this repository:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

Press RST afterwards.

**Tang Nano 20K**, with openFPGALoader (or the Gowin Programmer):

```sh
openFPGALoader -b tangnano20k -f bin/tang.fs     # to flash
make flash-fpga-flash                            # the same from the repository
```

then **power-cycle the board**: after a write to flash it keeps running
the old bitstream until it is restarted.

## How to use it

Power on; for about three seconds the ROM tests the memory and the
interrupts ("fast test of computer"), then the Scorpion's menu: 128
TR-DOS, 128 BASIC, Calculator, 48 BASIC, 48 TR-DOS.  With a disk in A:
"128 TR-DOS" loads `boot`.  **F12** opens the menu; cursor keys move,
left and right step a value, Space or Enter selects, ESC closes.  Keys:
letters, digits, Enter and Space as they are; Shift is Caps Shift, Ctrl
and Alt Symbol Shift; Backspace DELETE, the cursor keys CS+5..8, Caps
Lock CAPS LOCK, Esc BREAK, Tab the extended mode; `- = ; ' , . /` give
their symbols; the whole table is in `howto.md`.

## How to build

```sh
make toolchain    # once, ~7 GB into tools/
make lint         # Verilator, seconds
make sim          # the whole machine, through the ROM's tests (minutes); RUN_MS=3000 for the menu
make frames       # the same, with the screen as sim/out/*.ppm
make bitstream    # the FPGA bitstream -> bin/tang.fs, through the timing gate
make fw           # the BL616 firmware -> build/fw/bl616.bin
```

## Acknowledgements

Sergey Zonov (the machine), romychs and the zx-pk.ru Scorpion thread
(the restored schematic and board), savelij (the ZS-1024 material the
restoration drew on), Stinger / X-Trade (General Sound and its
firmware), psbhlw (the firmware sources and fixes), the Unreal Speccy
authors (whose model of the SMUC and General Sound the software is
written against), Guy Hutchison (tv80), MikeJ and Sorgelig (the WD1793
and YM2149 cores, MiSTer), Till Harbaum (MiSTeryNano, whose firmware and
MCU link all of this runs on), Alexey Gurov (UKNC Nano's hardware).
Authors of this repository: Sergei Lemeshev and Claude Code.
