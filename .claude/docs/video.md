# The display

`tang/src/zs256/video.v`, with `screen.v` beside it.  The machine's side
is in `platform.md`; this is what the design makes of it.

## The machine's raster, in clocks

At 42 MHz a pixel is six clocks and a line 2688 (224 T-states):

```
hcnt      0..1535   the 256 paper pixels (cells 0..31)
       1536..1919   the right border (64 pixels)
       1920..2303   sync (64)
       2304..2687   the left border of the NEXT display line (64)
vcnt      0..63     the top border (V = 128..191 in the counters' numbering)
         64..255    the 192 paper lines
        256..295    the bottom border (40 lines)
        296..311    sync (16 lines)
```

The interrupt is `vcnt == 0 && hcnt < 384`: 32 T-states at the start
of the first top border line, 64 lines before the paper, which is
Unreal's Scorpion preset (paper 14336 + 8 T after the interrupt).

**312 lines, not 316.**  The v16.2.6 schematic loads the vertical
counter with 44h at the end of the paper (DD5.D2 and DD6.D2 on BK-), which
gives 124 border lines; the original schematic's scan
(`infosource/REMONT-SERGOS/classic/scorp_shem/sc_3_sm.jpg`, zoomed) has
DD5.D3 and DD6.D2 on BK-, 48h, 120 lines, and 312 is what Unreal Speccy
and the zxpress articles give the Scorpion.  The original is built; the
redraw's error is noted in `platform.md`.  A board built from the
redraw would run 1.3% slower per frame - visible in nothing but a demo's
multicolour.

## A cell

Eight pixels are a cell, 48 clocks, and the cell after the one being
shown is fetched during it: on the cell's first clock the pixel byte's
address goes to `screen.v` ({page, y7 y6, y2 y1 y0, y5 y4 y3, x}), on
the second the attribute's (1800h + row * 32 + x), the bytes come back
a clock later each, and at the next cell boundary both are handed to
the shift register with the border colour of that moment.  The cell
before cell 0 is the last cell of the left border, on the previous
machine line, with the next line's y.

The attribute fetched last is `attr_ff`, port FF's byte inside the
paper (`ports.v`); outside it port FF reads FFh.

## The colour

Four bits a pixel into the line buffer: {bright, green, red, blue}, from
the attribute's ink or paper by the pixel bit, with the flash inverting
the choice when the frame counter's bit 4 is set; the border's three
bits with bright clear.  A lit component is CDh, FFh when bright, the
usual palette.

## The output raster

The line buffer holds two display lines of 352 entries: the one being
drawn and the one being shown.  A display line is 48 pixels of left
border (drawn at the END of the previous machine line, into the next
buffer), the 256 of paper and 48 of right border - so a display line n
is complete at hcnt 1823 of machine line n and read out twice during
machine line n+1, each entry three clocks wide:

```
out_h 0..1343 : DE 0..1055, front porch 1056..1079, HSYNC 1080..1143 (64),
                back porch 1144..1343 (200: hdmi_tx.v's island with four
                packets needs 4+8+2+128+2 and the video preamble's 10)
out_v 0..623  : DE 50..593 (display lines 24..295: 40 of top border,
                the paper, 40 of bottom), VSYNC 600..605
```

1056x544 in a 1344x624 frame at 31.25 kHz and 50.08 Hz, pixel clock
42 MHz.  Not a CEA mode.  Korvet Nano's 1024x512 at 49.5 Hz was taken
by the sinks it met; whether a given one takes this is a board question,
and a black screen on a board is that before it is anything else.  The
OSD centres itself on the syncs and needs no change.

Aspect: the Spectrum's picture in this frame is about 5:4 by pixel
count (352 x 272 of square-ish pixels).  A 16:9 sink stretching the
1056x544 to full width shows it a third too wide; with the sink set to
4:3 it comes out about right.  The alternative - a 28 MHz pixel clock
with each machine pixel doubled - would have needed a second clock
domain or a second PLL, and the design has neither to spare.

## Audio in the HDMI stream

`hdmi_tx.v` resamples the mix to exactly 48 kHz with N = 6144 and
CTS = 42000 (42e6 x 6144 / (128 x 42000) = 48000) and sends the clock
regeneration packet at that ratio, so the rate the sink regenerates and
the rate delivered agree to the bit.  Four packets an island fit the
200-clock back porch; `DI_PKTS` is 4 as in Korvet Nano.
