# Tools and ROM data

The toolchain is fetched into `tools/` and driven from the `Makefile`;
`.claude/docs/build.md` says what builds here.  Beside it there is a
handful of small scripts, all committed (force-added past the `/tools/`
ignore line), and the ROM data under `soft/rom/`.

## `tools/`

| script | what |
|---|---|
| `fetch.sh` | fetches the toolchain (oss-cad-suite, CMake, Ninja, the RISC-V GCC, the Bouffalo SDK, Gowin EDA Education, gh), patches the SDK's host-tool selection, shadows Gowin's stale bundled libraries.  UKNC Nano's |
| `env.sh` | puts the same set on `PATH` for use by hand |
| `srcs.py` | prints the design's source list out of `tang/zs256.gprj`; `--ip` the stubbed files, `--cst`, `--sdc` |
| `gowin_tcl.py` | emits `tang/build.tcl` for `gw_sh`, from the same `.gprj` and the IDE's process config; `--abs` and `--multiboot-addr` for tang-ultima |
| `timing_check.py` | the timing gate (`.claude/rules/timing.md`); takes a PnR directory for tang-ultima |
| `easyeda_net.py` | the Scorpion's schematic (an EasyEDA JSON) as a netlist: every net with its pins, `--part DD32` a part's pins, `--parts` the parts.  `make netlist`.  Where `platform.md`'s port table came from |
| `jed22v10.py` | the equations of a GAL22V10 or 16V8 out of its JEDEC fuse map, with pin names given on the command line.  The turbo GAL's and the ProfROM's; a registered output's feedback is /Q, which the reader has to apply |
| `trd.py` | TR-DOS disk images: list, create, add a file, add a BASIC program from its lines (a small tokeniser).  `soft/boot.trd` is its |
| `bin2prom.py`, `mif.py` | Korvet Nano's ROM tools, kept for a future built-in ROM; unused here |
| `ppm2png.py` | the simulation's `.ppm` frames as PNG (`-s 2` scales down) |
| `osd_png.py` | the OSD test's text dumps -> PNG |
| `sdk-host-tools.patch` | the Bouffalo SDK's `cmake/bflb_flash.cmake` fix, applied at fetch |

## `soft/rom/`

| file | what |
|---|---|
| `scorp294.rom` | 65536 bytes: the Scorpion's ROM v2.94, the one the board's authors recommend; pages 128, 48, SYS (Service Monitor), TR-DOS 5.03 |
| `scorp295.rom` | v2.95, the same layout |
| `scorp401.rom` | 262144 bytes: ProfROM v4.01 - four banks of 64 KB, switched by the GAL's table at 0100h of the Service ROM |
| `prof401.rom` | 262144 bytes: ProfROM v4.01 "Classic-Scorp-Profi" |
| `scorptest.rom` | 65536 bytes: the board's test ROM |
| `gs105a.rom` | 32768 bytes: General Sound's firmware v1.05a (Stinger, 1997; psbhlw's patched 1.04, from andykarpov/tsconf-wxeda), sha256 e256c963... |

All from `infosource/ROM/` (romychs' repository) but General Sound's.
None is built into the bitstream: `zs256.rom` and `gs105a.rom` go onto
the card and the firmware loads them at start; the simulation reads
`scorp294.rom` and `gs105a.rom` from here.

## `soft/`

| file | what |
|---|---|
| `boot.trd` | a formatted disk with one BASIC file, `boot`, that prints a line: `tools/trd.py -c`, `-b`.  What the simulation boots from |
