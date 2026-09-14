/*
    sysctrl.v

    The system control target of the MCU link: the status the firmware
    checks at start (CMD 0, with the core id), the LEDs and colour it may
    set (1, 2), the buttons (3), the OSD's values (4), the interrupt
    control (5).  MiSTeryNano's, with this core's letters in CMD 4.

    The letters are the OSD's (mnano/menu.c, variables_zs256), and a
    menu value needs three edits: the letter in the form string, an entry
    in variables_zs256[], and a line here.

    CMD 6 is a write into the SDRAM: THREE address bytes (high first: the
    byte address of the whole chip, membus.v's loader port - the ROM
    image goes in this way at start), then any number of data bytes,
    each a strobe on poke_stb with the address stepping.  Korvet Nano's
    CMD 6 has two address bytes; the firmware knows which core it talks
    to.
    CMD 7 is the debug window: an offset, then bytes (top.v's dbg bus).
    CMD 9, 10, 11 are tang-ultima's, the same in every core.
    As everywhere on this link the core answers one strobe behind: the
    byte set at a strobe is what the MCU clocks in during its next byte.
*/

module sysctrl (
  input             clk,
  input             reset,

  input             data_in_strobe,
  input             data_in_start,
  input [7:0]       data_in,
  output reg [7:0]  data_out,

  // interrupt interface
  output            int_out_n,
  input [7:0]       int_in,
  output reg [7:0]  int_ack,

  input [1:0]       buttons, // S0 and S1 buttons on Tang Nano 20k

  output reg [1:0]  leds, // two leds can be controlled from the MCU
  output reg [23:0] color, // a 24bit color to e.g. be used to drive the ws2812

  // values that can be configured by the user
  output reg [1:0]  system_reset,     // 'R' coldboot(3), reset(1), run(0)
  output reg [1:0]  system_volume,    // 'A' mute(0), 33%(1), 66%(2), 100%(3)
  output reg [1:0]  system_turbo,     // 'T' 0 as the ports say, 1 always 7 MHz, 2 always 3.5
  output reg        system_fdc,       // 'f' the Beta Disk is in
  output reg        system_ay,        // 'y' the AY is in
  output reg        system_gs,        // 'g' General Sound is on the bus
  output reg        system_smuc,      // 'u' the SMUC is on the bus
  output reg        system_joy,       // 'j' the Kempston joystick
  output reg        system_mouse,     // 'M' the Kempston mouse
  output reg        system_ram1024,   // 'm' 1 = 1024 KB (1FFD bits 7:6), 0 = 256
  output reg [1:0]  system_profrom,   // 'P' the ProfROM's bank mask: 0 a 64 KB image, 1 128, 3 256
  output reg [1:0]  system_stereo,    // 's' the AY's placing: 0 ABC, 1 ACB, 2 mono
  output reg        system_tape,      // 't' 0 tape input low, 1 high (until a tape exists)
  output reg [3:0]  system_wprot,     // 'p' 'q' 'k' 'l' floppies A..D write-protected
  output reg        magic,            // 'h' one clock: the Magic button

  // CMD 6: a byte into the SDRAM
  output reg        poke_stb,
  output reg [23:0] poke_adr,
  output reg [7:0]  poke_data,

  // CMD 7: the debug window, 32 bytes
  input [255:0]     dbg,

  // CMD 9: reload the FPGA from the next image in the SPI flash (tang-ultima)
  output reg        reconfig,

  // CMD 10: the configuration flash (tang-ultima).  The payload is passed
  // through to flashwr.v byte for byte - the sub-commands are its, not
  // this module's - and its answers come back the same way.
  output            flash_stb,
  output            flash_first,
  output      [7:0] flash_din,
  input       [7:0] flash_dout,
  // CMD 11: the UART to the board's own BL616 (tang-ultima, coreload.v),
  // passed through the same way; a core switch into the FPGA's SRAM
  output            cl_stb,
  output            cl_first,
  output      [7:0] cl_din,
  input       [7:0] cl_dout
);

assign flash_stb   = data_in_strobe && !data_in_start && (command == 8'd10);
assign flash_first = (state == 4'd1);
assign flash_din   = data_in;
assign cl_stb      = data_in_strobe && !data_in_start && (command == 8'd11);
assign cl_first    = (state == 4'd1);
assign cl_din      = data_in;

reg [3:0] state;
reg [7:0] command;
reg [7:0] id;

// reverse data byte for rgb
wire [7:0] data_in_rev = { data_in[0], data_in[1], data_in[2], data_in[3],
                           data_in[4], data_in[5], data_in[6], data_in[7] };

reg coldboot = 1'b1;

// CMD 7's byte index: the offset plus the strobes since it, wrapping
wire [4:0] dbg_ix = id[4:0] + {1'b0, state} - 5'd1;

assign int_out_n = (int_in != 8'h00 || coldboot)?1'b0:1'b1;

always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;
      leds <= 2'b00;        // after reset leds are off
      color <= 24'h000000;  // color black -> rgb led off

      int_ack <= 8'h00;
      coldboot = 1'b1;      // reset is actually the power-on-reset
      reconfig <= 1'b0;

      // the OSD's defaults (menu.c, variables_zs256), until the MCU says
      system_reset   <= 2'b00;
      system_volume  <= 2'b01;
      system_turbo   <= 2'b00;
      system_fdc     <= 1'b1;
      system_ay      <= 1'b1;
      system_gs      <= 1'b1;
      system_smuc    <= 1'b1;
      system_joy     <= 1'b1;
      system_mouse   <= 1'b1;
      system_ram1024 <= 1'b0;
      system_profrom <= 2'b00;
      system_stereo  <= 2'b00;
      system_tape    <= 1'b1;
      system_wprot   <= 4'b0000;
      magic <= 1'b0;
      poke_stb <= 1'b0;
      poke_adr <= 24'd0;
   end else begin
      int_ack <= 8'h00;
      reconfig <= 1'b0;
      poke_stb <= 1'b0;
      magic <= 1'b0;
      if(poke_stb) poke_adr <= poke_adr + 24'd1;   // the clock after a byte

      // CMD 10's answers are flashwr.v's, tracked a cycle behind it -
      // which is a dozen cycles before the MCU clocks the next byte out
      if(command == 8'd10) data_out <= flash_dout;
      if(command == 8'd11) data_out <= cl_dout;

      // iack bit 0 acknowledges the coldboot notification
      if(int_ack[0]) coldboot <= 1'b0;

      if(data_in_strobe) begin
        if(data_in_start) begin
            state <= 4'd1;
            command <= data_in;
        end else if(state != 4'd0) begin
            if(state != 4'd15) state <= state + 4'd1;

            // CMD 0: status data
            if(command == 8'd0) begin
                if(state == 4'd1) data_out <= 8'h5c;
                if(state == 4'd2) data_out <= 8'h42;
                if(state == 4'd3) data_out <= 8'h09;   // core id 9 = Scorpion ZS-256 (mnano/sysctrl.h)
            end

            // CMD 1: there are two MCU controlled LEDs
            if(command == 8'd1) begin
                if(state == 4'd1) leds <= data_in[1:0];
            end

            // CMD 2: a 24 color value to be mapped e.g. onto the ws2812
            if(command == 8'd2) begin
                if(state == 4'd1) color[15: 8] <= data_in_rev;
                if(state == 4'd2) color[ 7: 0] <= data_in_rev;
                if(state == 4'd3) color[23:16] <= data_in_rev;
            end

            // CMD 3: return button state
            if(command == 8'd3) begin
                data_out <= { 6'b000000, buttons };
            end

            // CMD 4: config values (e.g. set by user via OSD)
            if(command == 8'd4) begin
                if(state == 4'd1) id <= data_in;

                if(state == 4'd2) begin
                    if(id == "R") system_reset   <= data_in[1:0];
                    if(id == "A") system_volume  <= data_in[1:0];
                    if(id == "T") system_turbo   <= data_in[1:0];
                    if(id == "f") system_fdc     <= data_in[0];
                    if(id == "y") system_ay      <= data_in[0];
                    if(id == "g") system_gs      <= data_in[0];
                    if(id == "u") system_smuc    <= data_in[0];
                    if(id == "j") system_joy     <= data_in[0];
                    if(id == "M") system_mouse   <= data_in[0];
                    if(id == "m") system_ram1024 <= data_in[0];
                    if(id == "P") system_profrom <= data_in[1:0];
                    if(id == "s") system_stereo  <= data_in[1:0];
                    if(id == "t") system_tape    <= data_in[0];
                    if(id == "p") system_wprot[0] <= data_in[0];
                    if(id == "q") system_wprot[1] <= data_in[0];
                    if(id == "k") system_wprot[2] <= data_in[0];
                    if(id == "l") system_wprot[3] <= data_in[0];
                    if(id == "h") magic <= 1'b1;
                end
            end

            // CMD 6: a write into the SDRAM - three address bytes, then the bytes
            if(command == 8'd6) begin
                if(state == 4'd1) poke_adr[23:16] <= data_in;
                if(state == 4'd2) poke_adr[15:8]  <= data_in;
                if(state == 4'd3) poke_adr[7:0]   <= data_in;
                if(state >= 4'd4) begin poke_data <= data_in; poke_stb <= 1'b1; end
            end

            // CMD 7: the debug window - the offset, then the bytes
            if(command == 8'd7) begin
                if(state == 4'd1) begin
                    id <= data_in;
                    data_out <= dbg[8*data_in[4:0] +: 8];
                end else
                    data_out <= dbg[8*dbg_ix +: 8];
            end

            // CMD 5: interrupt control
            if(command == 8'd5) begin
                if(state == 4'd1) int_ack <= data_in;
                data_out <= { int_in[7:1], coldboot };
            end

            // CMD 9: reconfigure (tang-ultima's core switch).  The byte
            // after the command must be A5h, so that a stray byte on the
            // link cannot reload the FPGA; the pulse reaches top.v, which
            // drives RECONFIG_N low, and the FPGA loads the image whose
            // flash address this bitstream's header names (Gowin
            // MultiBoot, UG290 7.5.4) - itself, for a standalone build.
            // Nothing here survives it.
            if(command == 8'd9) begin
                if(state == 4'd1 && data_in == 8'hA5) reconfig <= 1'b1;
            end
         end
      end
   end
end

endmodule
