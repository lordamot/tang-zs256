`timescale 1ns / 1ps
//========================================================================
// sys_pll.v - the system clock: 27 MHz in, 42 MHz out.
//
// Everything in this design runs on the one 42 MHz clock: the Z80's
// T-state is twelve of them (3.5 MHz exactly - the Scorpion's 14 MHz
// crystal divided by four), six in turbo (7 MHz), the machine's pixel is
// six (7 MHz), the HDMI pixel is one, the General Sound's Z80 is enabled
// every third (14 MHz, paced by its memory to about the 12 of the card),
// and the SDRAM takes the phase-shifted copy on its own pad.  42 is
// 27 x 14 / 9: IDIV 9 puts the phase detector at 3 MHz, the part's
// floor, FBDIV 14 multiplies it back up, and ODIV 16 puts the VCO at
// 672 MHz, inside its 400-1200.  It is the only multiple of 3.5 MHz an
// rPLL reaches from 27 between 31.5 and 63, and it lets the whole
// machine count in exact T-states, which a Spectrum's software expects
// (Korvet Nano's 40.5 would have been 1.25% off, and every tape loader,
// multicolour and tune with it).
//
// A hand-written instantiation of the rPLL primitive, like
// hdmi_serdes.v; stubbed in simulation by sim/stubs/gowin_ip_sim.v,
// which quotes these ratios.
//========================================================================
module sys_pll (
    input  clkin,       // 27 MHz, pin 4
    output clkout,      // 42 MHz
    output clkoutp,     // 42 MHz, 90 degrees later, for the SDRAM pad
    output lock
);

rPLL rpll_inst (
    .CLKOUT  (clkout ),
    .LOCK    (lock   ),
    .CLKOUTP (clkoutp),
    .CLKOUTD (       ),
    .CLKOUTD3(       ),
    .RESET   (1'b0   ),
    .RESET_P (1'b0   ),
    .CLKIN   (clkin  ),
    .CLKFB   (1'b0   ),
    .FBDSEL  (6'b000000),
    .IDSEL   (6'b000000),
    .ODSEL   (6'b000000),
    .PSDA    (4'b0000),
    .DUTYDA  (4'b0000),
    .FDLY    (4'b1111)
);

defparam rpll_inst.FCLKIN           = "27";
defparam rpll_inst.DEVICE           = "GW2AR-18C";
defparam rpll_inst.DYN_IDIV_SEL     = "false";
defparam rpll_inst.IDIV_SEL         = 8;        // divide by 9: 3 MHz at the phase detector
defparam rpll_inst.DYN_FBDIV_SEL    = "false";
defparam rpll_inst.FBDIV_SEL        = 13;       // multiply by 14
defparam rpll_inst.DYN_ODIV_SEL     = "false";
defparam rpll_inst.ODIV_SEL         = 16;       // VCO 672 MHz
defparam rpll_inst.PSDA_SEL         = "0100";   // clkoutp 90 degrees
defparam rpll_inst.DYN_DA_EN        = "false";
defparam rpll_inst.DUTYDA_SEL       = "1000";
defparam rpll_inst.CLKOUT_FT_DIR    = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR   = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP  = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL        = "internal";
defparam rpll_inst.CLKOUT_BYPASS    = "false";
defparam rpll_inst.CLKOUTP_BYPASS   = "false";
defparam rpll_inst.CLKOUTD_BYPASS   = "false";
defparam rpll_inst.DYN_SDIV_SEL     = 2;
defparam rpll_inst.CLKOUTD_SRC      = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC     = "CLKOUT";

endmodule
