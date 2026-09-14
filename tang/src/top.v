`timescale 1ns / 1ps
//========================================================================
// top.v - ZS-256 Nano: the Scorpion ZS-256 Turbo+ on a Tang Nano 20K,
// with a BL616 (M0S Dock) beside it for USB, the SD card and the OSD.
//
// One clock.  sys_pll makes 42 MHz out of the board's 27, and every flop
// in the design runs on it: the Z80's T-state is twelve of them (tphase
// 0..11, counted here; six in turbo), the machine's pixel is six, the
// HDMI pixel is one, and the SDRAM takes the phase-shifted copy on its
// pad.  The only other clocks are the HDMI serial clock, made from this
// one inside hdmi_serdes.v, and the MCU's SPI clock, which mcu_spi.v
// takes through a handshake.  zs256.sdc names the two and the tool has
// the rest.  Korvet Nano's method (../tang-korvet), with this machine in
// it.
//
// The machine (tang/src/zs256/):
//   z80bus.v   a Z80 (tv80) on an enable, its bus as one request at a
//              time - the Scorpion's, and General Sound's
//   memmap.v   the paging: 7FFD, 1FFD, the DOS flip-flop, the ProfROM's
//              bank, the turbo flag
//   membus.v   the Scorpion's side of the SDRAM: RAM and ROM, the
//              screen's copy, the MCU's loader port
//   sdram.v    the SDRAM: slot A for the Scorpion, slot B for General
//              Sound, in every T-state
//   screen.v   the display's copy of pages 5 and 7
//   video.v    the display: 312 lines of 224 T-states, out as 1056x544
//   keyboard.v the matrix, filled from the MCU's key bytes
//   ports.v    the I/O bus: who answers which port
//   fdc.v      the Beta Disk (wd1793.sv) with four .trd images
//   ay.v       the AY-3-8912 (ym2149.sv)
//   gs.v       General Sound: its own Z80, RAM, DACs
//   smuc.v     SMUC: ide.v, rtc.v, nvram.v
//   poke.v     the MCU's bytes into the SDRAM
// and around it MiSTeryNano's MCU link (src/mister/), UKNC Nano's HDMI
// encoder with audio (src/hdmi/) and an I2S output (i2s_tx.v).
//========================================================================
module top(
    input         clk27,
    // buts[0] is S1 and forces a reset; buts[1] is S2, the Magic button.
    input  [ 1:0] buts,
    output [ 5:0] leds,

    output        uart_tx,        // tang-ultima's UART to the on-board BL616
    input         uart_rx,

    output        sdclk,
    inout         sdcmd,          // mosi
    inout         sddat0,         // miso
    inout         sddat1,         // not used
    inout         sddat2,         // not used
    inout         sddat3,         // cs

    output        O_tmds_clk_p,
    output        O_tmds_clk_n,
    output  [2:0] O_tmds_data_p,
    output  [2:0] O_tmds_data_n,

    // I2S to the dock's DAC
    output        HP_BCK,
    output        HP_WS,
    output        HP_DIN,
    output        PA_EN,

    output        O_sdram_clk,
    output        O_sdram_cke,
    output        O_sdram_cs_n,
    output        O_sdram_cas_n,
    output        O_sdram_ras_n,
    output        O_sdram_wen_n,
    output [ 3:0] O_sdram_dqm,
    output [10:0] O_sdram_addr,
    output [ 1:0] O_sdram_ba,
    inout  [31:0] IO_sdram_dq,

    // the MCU link, stock MiSTeryNano wiring: an external BL616 / M0S
    // Dock on 42/41/56/54/51 - 0 miso, 1 mosi, 2 csn, 3 sclk, 4 irqn
    inout  [ 4:0] m0s,

    // pin 48, wired on the board to TP1 = RECONFIG_N: low on SYS command 9
    // reloads the FPGA.  Dormant without that wire (tang-ultima).
    output        reconfig_n,

    // The configuration flash, on the MSPI pins that -use_mspi_as_gpio
    // hands to user logic after configuration (flashwr.v, SYS command
    // 10): tang-ultima's "Save to flash".
    output        mspi_clk,      // 59 MCLK
    output        mspi_cs_n,     // 60 MCS_N
    output        mspi_do,       // 61 MO, into the flash
    input         mspi_di        // 62 MI, out of it
);

assign O_sdram_cke = 1'b1;
assign PA_EN       = 1'b1;

//------------------------------------------------------------------------
// Clock
//------------------------------------------------------------------------
wire clk;          // 42 MHz, everything
wire locked;

sys_pll pll (
    .clkin  (clk27      ),
    .clkout (clk        ),
    .clkoutp(O_sdram_clk),
    .lock   (locked     )
);

//------------------------------------------------------------------------
// Resets.  `init` is the SDRAM's word that the memory exists; the
// MiSTeryNano side then waits 2^23 clocks (200 ms) as upstream does, for
// the MCU to come up.  The machine itself is reset by the OSD's 'R'
// (the MCU sends 3 at power-up and 0 when it has sent its settings and
// loaded the ROM), by S1, and until the memory is there.
//------------------------------------------------------------------------
wire init;
reg  [23:0] count_rst = 24'd0;
wire        n_all_rst = init & ~buts[0];
wire        por_done  = count_rst[23];
wire        mist_rst  = ~por_done;

always @(posedge clk or negedge n_all_rst)
    count_rst <= !n_all_rst ? 24'd0 : count_rst + {23'd0, !count_rst[23]};

wire [1:0] system_reset, system_volume, system_turbo, system_profrom, system_stereo;
wire       system_fdc, system_ay, system_gs, system_smuc, system_joy, system_mouse;
wire       system_ram1024, system_tape;
wire [3:0] system_wprot;
wire       magic_osd;

//------------------------------------------------------------------------
// The machine's raster and the T-state phase.  The line is 2688 clocks
// (224 T-states), the frame 312 lines (video.v).  They run from PLL
// lock; the SDRAM's initialisation steps are taken in slot B of the
// timetable, which is a phase of this counter.
//------------------------------------------------------------------------
reg  [11:0] hcnt   = 12'd0;
reg  [8:0]  vcnt   = 9'd0;
reg  [3:0]  tphase = 4'd0;

always @(posedge clk) begin
    if (!locked) begin
        hcnt <= 12'd0; vcnt <= 9'd0; tphase <= 4'd0;
    end else begin
        tphase <= (tphase == 4'd11) ? 4'd0 : tphase + 4'd1;
        if (hcnt == 12'd2687) begin
            hcnt <= 12'd0;
            vcnt <= (vcnt == 9'd311) ? 9'd0 : vcnt + 9'd1;
        end else
            hcnt <= hcnt + 12'd1;
    end
end

// the Z80's enable: phase 0, and phase 6 as well in turbo; the 3.5 MHz
// enable for the ВГ93 whatever the processor does
wire turbo;
wire cen_cpu = (tphase == 4'd0) || (turbo && tphase == 4'd6);
wire ce_35   = (tphase == 4'd0);

// the machine's reset: while the MCU says so (R bit 0), S1, no memory
// yet, and for 16 T-states after
reg  [7:0] cpu_rst_cnt = 8'hFF;
wire       cpu_rst_req = mist_rst | system_reset[0] | ~init;
always @(posedge clk) begin
    if (cpu_rst_req) cpu_rst_cnt <= 8'd16;
    else if (cpu_rst_cnt != 8'd0 && tphase == 4'd11) cpu_rst_cnt <= cpu_rst_cnt - 8'd1;
end
wire cpu_rst = (cpu_rst_cnt != 8'd0);

//------------------------------------------------------------------------
// The processor
//------------------------------------------------------------------------
wire [15:0] z_a;
wire [7:0]  z_dout, z_din;
wire        z_req, z_io, z_we, z_m1, z_ack, z_halt_n, z_iff1;
wire        nmi_n, int_n;
wire [15:0] z_pc_now;
wire        z_m1_now;

z80bus cpu (
    .clk(clk), .reset(cpu_rst), .cen(cen_cpu),
    .A(z_a), .dout(z_dout), .din(z_din), .req(z_req), .io(z_io), .we(z_we), .m1(z_m1), .ack(z_ack),
    .int_n(int_n), .nmi_n(nmi_n), .halt_n(z_halt_n), .rfsh_n(), .iff1(z_iff1),
    .pc_now(z_pc_now), .m1_now(z_m1_now)
);

//------------------------------------------------------------------------
// The memory map and the memory
//------------------------------------------------------------------------
wire        rom, screen7, dos;
wire [3:0]  rom_page;
wire [5:0]  ram_page;
wire [7:0]  p7FFD, p1FFD;
wire [1:0]  profrom_bank;
wire        mem_ack, mem_stb, io_stb, io_ack;
wire [7:0]  mem_rdata, io_rdata;

// the Magic button: S2, or the OSD's 'h' (held for a while, so that the
// RAM fetch it needs comes round)
reg [19:0] magic_hold = 20'd0;
always @(posedge clk) begin
    if (magic_osd) magic_hold <= 20'hFFFFF;
    else if (magic_hold != 20'd0) magic_hold <= magic_hold - 20'd1;
end
wire magic_n = !(buts[1] || magic_hold != 20'd0);

memmap map (
    .clk(clk), .reset(cpu_rst),
    .req(z_req), .A(z_a), .io(z_io), .m1(z_m1), .we(z_we), .wdata(z_dout),
    .io_wr_stb(io_stb && z_we), .io_rd_stb(io_stb && !z_we && !z_m1), .mem_stb(mem_stb),
    .profrom_mask(system_profrom), .ram1024(system_ram1024), .turbo_mode(system_turbo), .magic_n(magic_n),
    .rom(rom), .rom_page(rom_page), .ram_page(ram_page), .screen7(screen7),
    .dos(dos), .turbo(turbo), .nmi_n(nmi_n), .p7FFD(p7FFD), .p1FFD(p1FFD), .profrom_bank(profrom_bank)
);

wire        poke_stb, poke_req, poke_ack;
wire [23:0] poke_adr, poke_a;
wire [7:0]  poke_data, poke_d;
wire        scr_we;
wire [13:0] scr_wadr;
wire [7:0]  scr_wdata;
wire        a_req, a_we, a_take, a_ack;
wire [20:0] a_adr;
wire [31:0] a_wdata, a_rdata;
wire [3:0]  a_wmask;

membus mb (
    .clk(clk), .reset(mist_rst),
    .req(z_req && !z_io), .A(z_a), .we(z_we), .wdata(z_dout), .rdata(mem_rdata), .ack(mem_ack), .stb(mem_stb),
    .rom(rom), .rom_page(rom_page), .ram_page(ram_page),
    .ld_req(poke_req), .ld_adr(poke_a), .ld_data(poke_d), .ld_ack(poke_ack),
    .scr_we(scr_we), .scr_adr(scr_wadr), .scr_data(scr_wdata),
    .a_req(a_req), .a_we(a_we), .a_adr(a_adr), .a_wdata(a_wdata), .a_wmask(a_wmask),
    .a_take(a_take), .a_rdata(a_rdata), .a_ack(a_ack)
);

poke pk (
    .clk(clk), .reset(mist_rst),
    .stb(poke_stb), .adr(poke_adr), .data(poke_data),
    .ack(poke_ack), .req(poke_req), .req_adr(poke_a), .req_data(poke_d), .pending()
);

wire        b_req, b_we, b_take, b_ack;
wire [20:0] b_adr;
wire [31:0] b_wdata, b_rdata;
wire [3:0]  b_wmask;
wire        bist_done, bist_fail, cap_late;

sdram mem (
    .clk(clk), .lock(locked), .init(init), .tphase(tphase),
    .a_req(a_req), .a_we(a_we), .a_adr(a_adr), .a_wdata(a_wdata), .a_wmask(a_wmask),
    .a_take(a_take), .a_rdata(a_rdata), .a_ack(a_ack),
    .b_req(b_req), .b_we(b_we), .b_adr(b_adr), .b_wdata(b_wdata), .b_wmask(b_wmask),
    .b_take(b_take), .b_rdata(b_rdata), .b_ack(b_ack),
    .bist_done(bist_done), .bist_fail(bist_fail), .cap_late(cap_late),
    .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba), .SDRAM_DQ(IO_sdram_dq),
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
    .SDRAM_nWE(O_sdram_wen_n), .SDRAM_DQM(O_sdram_dqm)
);

//------------------------------------------------------------------------
// The display
//------------------------------------------------------------------------
wire [13:0] scr_radr;
wire [7:0]  scr_rdata;

screen scr (
    .clk(clk),
    .we(scr_we), .wadr(scr_wadr), .wdata(scr_wdata),
    .radr(scr_radr), .rdata(scr_rdata)
);

wire [7:0]  p_fe, attr_ff;
wire        paper, flash;
wire        hsync, vsync, visible;
wire [7:0]  red, green, blue;

video vid (
    .clk(clk), .hcnt(hcnt), .vcnt(vcnt),
    .screen7(screen7), .border(p_fe[2:0]),
    .scr_adr(scr_radr), .scr_data(scr_rdata),
    .int_n(int_n), .paper(paper), .attr_ff(attr_ff), .flash(flash),
    .hs(hsync), .vs(vsync), .de(visible), .r(red), .g(green), .b(blue)
);

//------------------------------------------------------------------------
// The I/O bus.  A request with `io` is strobed once, on its first clock;
// a write is done then, a read is answered four clocks later, by which
// time the ВГ93 and the SMUC have their bytes on the bus.
//------------------------------------------------------------------------
wire       io_req = z_req && z_io;
reg        io_served = 1'b0;
reg  [2:0] io_t = 3'd0;
assign io_stb = io_req && !io_served && (io_t == 3'd0);
assign io_ack = io_req && !io_served && ((io_stb && z_we) || io_t == 3'd4);
always @(posedge clk) begin
    if (!z_req) begin io_served <= 1'b0; io_t <= 3'd0; end
    else if (io_req && !io_served) begin
        if (io_ack) io_served <= 1'b1;
        else if (io_t != 3'd4) io_t <= io_t + 3'd1;
    end
end

assign z_ack = mem_ack | io_ack;
assign z_din = z_io ? io_rdata : mem_rdata;

wire [7:0]  kbd_byte;
wire        kbd_stb;
wire [4:0]  kbd_bits;
wire [7:0]  joystick0, joystick1;
wire [5:0]  mouse_bits;
wire        mouse_tgl;
wire [7:0]  mouse_dx, mouse_dy;

keyboard kbd (
    .clk(clk), .reset(mist_rst),
    .code(kbd_byte), .stb(kbd_stb),
    .rows_n(z_a[15:8]), .bits(kbd_bits)
);

// the Kempston mouse's counters: the USB reports summed, up is up
reg [7:0] mouse_x = 8'd0, mouse_y = 8'd0;
reg       mouse_tgl_d = 1'b0;
always @(posedge clk) begin
    mouse_tgl_d <= mouse_tgl;
    if (mouse_tgl != mouse_tgl_d) begin
        mouse_x <= mouse_x + mouse_dx;
        mouse_y <= mouse_y - mouse_dy;
    end
end

wire        smuc_sel, fe_wr, fdc_stb, ay_stb, gs_stb, smuc_stb;
wire [7:0]  smuc_rdata, gs_rdata, ay_rdata, fdc_rdata;
wire        fdc_drq, fdc_intrq;

ports io (
    .clk(clk), .reset(cpu_rst),
    .io_stb(io_stb), .A(z_a), .we(z_we), .wdata(z_dout), .m1(z_m1), .dos(dos),
    .en_smuc(system_smuc), .en_gs(system_gs), .en_mouse(system_mouse), .en_joy(system_joy),
    .smuc_sel(smuc_sel), .smuc_rdata(smuc_rdata), .gs_rdata(gs_rdata), .ay_rdata(ay_rdata),
    .fdc_rdata(fdc_rdata), .fdc_drq(fdc_drq), .fdc_intrq(fdc_intrq),
    .kbd_bits(kbd_bits), .tape_in(system_tape), .attr_ff(attr_ff), .paper(paper),
    .joystick(joystick0), .mouse_x(mouse_x), .mouse_y(mouse_y), .mouse_btn(mouse_bits[5:4]),
    .rdata(io_rdata),
    .fe_wr(fe_wr), .p_fe(p_fe), .fdc_stb(fdc_stb), .ay_stb(ay_stb), .gs_stb(gs_stb), .smuc_stb(smuc_stb)
);

//------------------------------------------------------------------------
// The sound chips
//------------------------------------------------------------------------
wire [7:0] ay_a, ay_b, ay_c;
ay psg (
    .clk(clk), .reset(cpu_rst), .en(system_ay),
    .io_stb(ay_stb), .a14(z_a[14]), .we(z_we), .wdata(z_dout), .rdata(ay_rdata),
    .ch_a(ay_a), .ch_b(ay_b), .ch_c(ay_c)
);

wire signed [15:0] gs_l, gs_r;
wire [15:0] gs_pc;
wire        gs_m1;
// the card's ROM copy is filled as the loader writes the image to its
// place in the SDRAM (400000h, mnano/romload.h): every byte membus.v
// takes from poke.v in that 32 KB goes to gs.v's BSRAM as well
wire        gs_ld_we = poke_ack && (poke_a[23:15] == 9'h080);
gs gsound (
    .clk(clk), .reset(cpu_rst || !system_gs),
    .io_stb(gs_stb), .a3(z_a[3]), .we(z_we), .wdata(z_dout), .rdata(gs_rdata),
    .ld_we(gs_ld_we), .ld_adr(poke_a[14:0]), .ld_data(poke_d),
    .b_req(b_req), .b_we(b_we), .b_adr(b_adr), .b_wdata(b_wdata), .b_wmask(b_wmask),
    .b_take(b_take), .b_rdata(b_rdata), .b_ack(b_ack),
    .out_l(gs_l), .out_r(gs_r), .dbg_pc(gs_pc), .dbg_m1(gs_m1)
);

//------------------------------------------------------------------------
// The SD card: the MCU's file system, and the five image slots through
// the arbiter - four floppies and the hard disk.
//------------------------------------------------------------------------
wire        mcu_sys_strobe, mcu_hid_strobe, mcu_osd_strobe, mcu_sdc_strobe;
wire        mcu_start;
wire  [7:0] mcu_sys_din, mcu_hid_din, mcu_sdc_din;
wire  [7:0] mcu_osd_din = 8'h55;
wire  [7:0] mcu_dout;
wire        hid_int, sdc_int;
wire  [7:0] int_ack;

wire [31:0] sd_img_size;
wire [ 4:0] sd_img_mounted;
wire [ 4:0] sd_rstart, sd_wstart;
wire [31:0] sd_rsector;
wire [ 7:0] sd_inbyte, sd_outbyte;
wire        sd_rbusy, sd_rdone, sd_outen;
wire [ 8:0] sd_outaddr;

sd_card #(.CLK_DIV(3'd1)) sd_card (
    .rstn(por_done), .clk(clk), .sdclk(sdclk), .sdcmd(sdcmd),
    .sddat({sddat3, sddat2, sddat1, sddat0}),
    .data_strobe(mcu_sdc_strobe), .data_start(mcu_start), .data_in(mcu_dout), .data_out(mcu_sdc_din),
    .image_size(sd_img_size), .image_mounted(sd_img_mounted),
    .irq(sdc_int), .iack(int_ack[3]),
    .rstart(sd_rstart), .wstart(sd_wstart), .rsector(sd_rsector),
    .rbusy(sd_rbusy), .rdone(sd_rdone), .inbyte(sd_inbyte),
    .outen(sd_outen), .outaddr(sd_outaddr), .outbyte(sd_outbyte)
);

reg [4:0] mounted = 5'd0;
integer   mi;
always @(posedge clk)
    for (mi = 0; mi < 5; mi = mi + 1)
        if (sd_img_mounted[mi]) mounted[mi] <= |sd_img_size;

wire [4:0]   c_rd, c_wr, c_ack, c_done, c_outen;
wire [159:0] c_sector;
wire [39:0]  c_inbyte;

sd_arbiter sdarb (
    .clk(clk), .reset(mist_rst),
    .c_rd(c_rd), .c_wr(c_wr), .c_sector(c_sector), .c_inbyte(c_inbyte),
    .c_ack(c_ack), .c_done(c_done), .c_outen(c_outen),
    .rstart(sd_rstart), .wstart(sd_wstart), .rsector(sd_rsector), .inbyte(sd_inbyte),
    .rbusy(sd_rbusy), .rdone(sd_rdone), .outen(sd_outen)
);

// slots 0..3: the floppies, one controller, the drive picks the slot
wire [1:0]  fdc_drive;
wire        fdc_sd_rd, fdc_sd_wr, fdc_busy;
wire [31:0] fdc_sector;
wire [7:0]  fdc_inbyte;
genvar gi;
generate for (gi = 0; gi < 4; gi = gi + 1) begin : fl
    assign c_rd[gi] = fdc_sd_rd && (fdc_drive == gi);
    assign c_wr[gi] = fdc_sd_wr && (fdc_drive == gi);
    assign c_sector[gi*32 +: 32] = fdc_sector;
    assign c_inbyte[gi*8 +: 8]   = fdc_inbyte;
end endgenerate
wire fdc_ack   = c_ack[{1'b0, fdc_drive}];
wire fdc_done  = c_done[{1'b0, fdc_drive}];
wire fdc_outen = c_outen[{1'b0, fdc_drive}];

fdc fd (
    .clk(clk), .reset(cpu_rst), .ce(ce_35), .en(system_fdc),
    .io_stb(fdc_stb), .a(z_a[7:0]), .we(z_we), .wdata(z_dout), .rdata(fdc_rdata),
    .drq(fdc_drq), .intrq(fdc_intrq),
    .mounted(sd_img_mounted[3:0]), .image_size(sd_img_size), .present(mounted[3:0]), .wprot(system_wprot),
    .drive(fdc_drive), .sd_rd(fdc_sd_rd), .sd_wr(fdc_sd_wr), .sd_sector(fdc_sector),
    .sd_ack(fdc_ack), .sd_done(fdc_done), .outen(fdc_outen), .outaddr(sd_outaddr), .outbyte(sd_outbyte),
    .inbyte(fdc_inbyte), .busy(fdc_busy)
);

// slot 4: the SMUC's hard disk
wire hd_present, hd_busy;
smuc smc (
    .clk(clk), .reset(cpu_rst), .en(system_smuc),
    .io_stb(io_stb), .A(z_a), .we(z_we), .wdata(z_dout), .sel(smuc_sel), .rdata(smuc_rdata),
    .hd_mounted(sd_img_mounted[4]), .hd_size(sd_img_size), .hd_present(hd_present),
    .hd_rd(c_rd[4]), .hd_wr(c_wr[4]), .hd_sector(c_sector[159:128]),
    .hd_ack(c_ack[4]), .hd_done(c_done[4]), .hd_outen(c_outen[4]), .hd_outaddr(sd_outaddr), .hd_outbyte(sd_outbyte),
    .hd_inbyte(c_inbyte[39:32]), .hd_busy(hd_busy)
);

//------------------------------------------------------------------------
// The MCU link (MiSTeryNano): SPI in, four targets out.
//------------------------------------------------------------------------
wire        spi_io_dout;
wire        int_out_n;

assign m0s[4:0] = { int_out_n, 3'bzzz, spi_io_dout };

wire spi_io_din = m0s[1];
wire spi_io_ss  = m0s[2];
wire spi_io_clk = m0s[3];

mcu_spi msp1 (
    .clk(clk), .reset(mist_rst),
    .spi_io_ss(spi_io_ss), .spi_io_clk(spi_io_clk), .spi_io_din(spi_io_din), .spi_io_dout(spi_io_dout),
    .mcu_sys_strobe(mcu_sys_strobe), .mcu_hid_strobe(mcu_hid_strobe),
    .mcu_osd_strobe(mcu_osd_strobe), .mcu_sdc_strobe(mcu_sdc_strobe),
    .mcu_start(mcu_start),
    .mcu_sys_din(mcu_sys_din), .mcu_hid_din(mcu_hid_din), .mcu_osd_din(mcu_osd_din), .mcu_sdc_din(mcu_sdc_din),
    .mcu_dout(mcu_dout)
);

// the debug window (CMD 7): what the processor is doing
reg [15:0] last_pc = 16'd0;
reg [7:0]  last_op = 8'd0;
reg [15:0] m1_count = 16'd0;
reg [7:0]  rst_count = 8'd0;
reg        cpu_rst_d = 1'b0;
always @(posedge clk) begin
    cpu_rst_d <= cpu_rst;
    if (cpu_rst && !cpu_rst_d) rst_count <= rst_count + 8'd1;
    if (mem_stb && z_m1) begin last_pc <= z_a; m1_count <= m1_count + 16'd1; end
    if (mem_ack && z_m1 && !z_io) last_op <= mem_rdata;
end
wire [255:0] dbg_bus = {
    64'd0,
    gs_pc, 8'd0, 8'd0,                                        // 23..20
    m1_count, rst_count, 8'd0,                                // 19..16
    p_fe, attr_ff, {6'd0, profrom_bank}, {7'd0, turbo},       // 15..12
    p7FFD, p1FFD, {7'd0, dos}, {5'd0, z_halt_n, z_iff1, 1'b0},// 11..8
    last_pc, last_op, 8'd0,                                    // 7..4
    {2'd0, hd_present, mounted[3:0], 1'b0},                   // 3
    {5'd0, cap_late, bist_fail, bist_done},                   // 2
    {6'd0, init, por_done},                                   // 1
    8'hA5 };                                                  // 0

wire sys_reconfig;
wire       flash_stb, flash_first;
wire [7:0] flash_din, flash_dout;
wire       cl_stb, cl_first;
wire [7:0] cl_din, cl_dout;
wire       cl_active, cl_tx;
sysctrl sctl1 (
    .clk(clk), .reset(mist_rst),
    .data_in_strobe(mcu_sys_strobe), .data_in_start(mcu_start), .data_in(mcu_dout), .data_out(mcu_sys_din),
    .int_out_n(int_out_n),
    .int_in({4'b0000, sdc_int, 1'b0, hid_int, 1'b0}),
    .int_ack(int_ack),
    .buttons(2'b00), .leds(), .color(),
    .system_reset(system_reset), .system_volume(system_volume), .system_turbo(system_turbo),
    .system_fdc(system_fdc), .system_ay(system_ay), .system_gs(system_gs), .system_smuc(system_smuc),
    .system_joy(system_joy), .system_mouse(system_mouse), .system_ram1024(system_ram1024),
    .system_profrom(system_profrom), .system_stereo(system_stereo), .system_tape(system_tape),
    .system_wprot(system_wprot), .magic(magic_osd),
    .poke_stb(poke_stb), .poke_adr(poke_adr), .poke_data(poke_data),
    .dbg(dbg_bus),
    .reconfig(sys_reconfig),
    .flash_stb(flash_stb), .flash_first(flash_first),
    .flash_din(flash_din), .flash_dout(flash_dout),
    .cl_stb(cl_stb), .cl_first(cl_first), .cl_din(cl_din), .cl_dout(cl_dout)
);

//------------------------------------------------------------------------
// tang-ultima: the configuration flash (SYS command 10), the UART to the
// board's own BL616 (SYS command 11), and RECONFIG_N (SYS command 9,
// dormant).  The same three blocks as in the three siblings.
//------------------------------------------------------------------------
flashwr fwr1(
    .clk(clk), .reset(mist_rst),
    .stb(flash_stb), .first(flash_first),
    .din(flash_din), .dout(flash_dout),
    .mspi_clk(mspi_clk), .mspi_cs_n(mspi_cs_n),
    .mspi_do(mspi_do),   .mspi_di(mspi_di)
);

coreload #(.CLK_HZ(42000000), .BAUD(2000000)) cl1(
    .clk(clk), .reset(mist_rst),
    .stb(cl_stb), .first(cl_first), .din(cl_din), .dout(cl_dout),
    .active(cl_active), .tx(cl_tx), .rx(uart_rx)
);
assign uart_tx = cl_tx;   // idles high

reg [7:0] reconfig_cnt = 8'd0;
always @(posedge clk) begin
    if(sys_reconfig)            reconfig_cnt <= 8'hff;
    else if(reconfig_cnt != 0)  reconfig_cnt <= reconfig_cnt - 8'd1;
end
assign reconfig_n = (reconfig_cnt == 8'd0);

hid hd1 (
    .clk(clk), .reset(mist_rst),
    .data_in_strobe(mcu_hid_strobe), .data_in_start(mcu_start), .data_in(mcu_dout), .data_out(mcu_hid_din),
    .db9_port(6'd0), .irq(hid_int), .iack(int_ack[1]),
    .mouse(mouse_bits), .keyboard(kbd_byte), .keyboard_stb(kbd_stb),
    .joystick0(joystick0), .joystick1(joystick1),
    .mouse_rep_tgl(mouse_tgl), .mouse_rep_dx(mouse_dx), .mouse_rep_dy(mouse_dy)
);

//------------------------------------------------------------------------
// The OSD over the picture, then the encoder.
//------------------------------------------------------------------------
wire [5:0] r_out, g_out, b_out;

osd_u8g2 osd1 (
    .clk(clk), .pclk(clk), .reset(mist_rst),
    .data_in_strobe(mcu_osd_strobe), .data_in_start(mcu_start), .data_in(mcu_dout),
    .hs(hsync), .vs(vsync),
    .r_in(red[7:2]), .g_in(green[7:2]), .b_in(blue[7:2]),
    .r_out(r_out), .g_out(g_out), .b_out(b_out)
);

reg        I_rgb_vs = 1'b0, I_rgb_hs = 1'b0, I_rgb_de = 1'b0;
reg  [7:0] I_rgb_r = 8'd0, I_rgb_g = 8'd0, I_rgb_b = 8'd0;

always @(posedge clk) begin
    I_rgb_vs <= vsync;
    I_rgb_hs <= hsync;
    I_rgb_de <= visible;
    I_rgb_r  <= {r_out, 2'd0};
    I_rgb_g  <= {g_out, 2'd0};
    I_rgb_b  <= {b_out, 2'd0};
end

wire [9:0]  tmds_ch0, tmds_ch1, tmds_ch2;
wire [15:0] audio_l, audio_r;

hdmi_tx hdmi1 (
    .I_rst_n(1'b1), .I_rgb_clk(clk),
    .I_rgb_vs(I_rgb_vs), .I_rgb_hs(I_rgb_hs), .I_rgb_de(I_rgb_de),
    .I_rgb_r(I_rgb_r), .I_rgb_g(I_rgb_g), .I_rgb_b(I_rgb_b),
    .I_audio_l(audio_l), .I_audio_r(audio_r),
    .O_tmds_ch0(tmds_ch0), .O_tmds_ch1(tmds_ch1), .O_tmds_ch2(tmds_ch2),
    .O_audio_ovf(), .O_audio_dropc(), .O_audio_pktc()
);

hdmi_serdes hdmi_ser (
    .clk_pixel(clk), .ref_locked(locked),
    .tmds_ch0(tmds_ch0), .tmds_ch1(tmds_ch1), .tmds_ch2(tmds_ch2),
    .O_tmds_clk_p(O_tmds_clk_p), .O_tmds_clk_n(O_tmds_clk_n),
    .O_tmds_data_p(O_tmds_data_p), .O_tmds_data_n(O_tmds_data_n)
);

//------------------------------------------------------------------------
// Sound.  The beeper (port FE bit 4) and the MIC output (bit 3, quieter,
// as the board's resistors make it), the AY's three channels placed
// ABC or ACB or all in the middle, and General Sound's two sides.
// Signed 16 bits a side, and the OSD's volume divides it down.
//------------------------------------------------------------------------
wire signed [15:0] beep = p_fe[4] ? 16'sd8000 : 16'sd0;
wire signed [15:0] mic  = p_fe[3] ? 16'sd2000 : 16'sd0;
wire [8:0] ay_ab = {1'b0, ay_a} + {2'd0, ay_b[7:1]};
wire [8:0] ay_cb = {1'b0, ay_c} + {2'd0, ay_b[7:1]};
wire [8:0] ay_ac = {1'b0, ay_a} + {2'd0, ay_c[7:1]};
wire [8:0] ay_bc = {1'b0, ay_b} + {2'd0, ay_c[7:1]};
wire [9:0] ay_mono = {2'd0, ay_a} + {2'd0, ay_b} + {2'd0, ay_c};
wire signed [15:0] ay_l = (system_stereo == 2'd0) ? {3'd0, ay_ab, 4'd0} :
                          (system_stereo == 2'd1) ? {3'd0, ay_ac, 4'd0} : {3'd0, ay_mono[9:1], 4'd0};
wire signed [15:0] ay_r = (system_stereo == 2'd0) ? {3'd0, ay_cb, 4'd0} :
                          (system_stereo == 2'd1) ? {3'd0, ay_bc, 4'd0} : {3'd0, ay_mono[9:1], 4'd0};
wire signed [15:0] mix_l = beep + mic + ay_l + (gs_l >>> 1);
wire signed [15:0] mix_r = beep + mic + ay_r + (gs_r >>> 1);

reg signed [15:0] vol_l = 16'sd0, vol_r = 16'sd0;
always @(posedge clk)
    case (system_volume)
        2'b00: begin vol_l <= 16'sd0;        vol_r <= 16'sd0;        end
        2'b01: begin vol_l <= mix_l >>> 2;   vol_r <= mix_r >>> 2;   end
        2'b10: begin vol_l <= mix_l >>> 1;   vol_r <= mix_r >>> 1;   end
        2'b11: begin vol_l <= mix_l;         vol_r <= mix_r;         end
    endcase

assign audio_l = vol_l;
assign audio_r = vol_r;

i2s_tx i2s (
    .clk(clk), .reset(mist_rst),
    .sample_l(vol_l), .sample_r(vol_r),
    .bck(HP_BCK), .ws(HP_WS), .din(HP_DIN)
);

//------------------------------------------------------------------------
// LEDs, active low on the board: lit is the signal true.
//------------------------------------------------------------------------
assign leds[0] = ~por_done;
assign leds[1] = ~p_fe[4];
assign leds[2] = ~(dos | cap_late);
assign leds[3] = ~(fdc_busy | hd_busy | sd_rbusy | bist_fail);
assign leds[4] = ~cpu_rst;
assign leds[5] = ~init;

endmodule
