//========================================================================
// Top-level testbench: the whole machine, with the SDRAM modelled and a
// minimal stand-in for the BL616.
//========================================================================
// Plusargs:
//   +VCD          dump sim/out/tb_top.vcd (large)
//   +VIDEO_PPM    write each decoded frame as a .ppm
//   +RUN_MS=<n>   how long to run, in simulated milliseconds (default 40)
//   +NOFASTBOOT   do not shortcut the 200 ms power-on reset counter
//   +ROM=<file>   the ROM image, straight into the SDRAM model (64 KB, or
//                 a 256 KB ProfROM; default soft/rom/scorp294.rom)
//   +ROMSPI=<file>  the same, but sent the firmware's way, SYS CMD 6 over SPI
//   +GSROM=<file> General Sound's ROM into the model (default soft/rom/gs105a.rom)
//   +CPUTRACE     every opcode fetch: address and opcode
//   +IOTRACE      every I/O read and write
//   +MEMTRACE     every request on the SDRAM's two ports
//   +GSTRACE      General Sound's opcode fetches
//   +TRACE_MS=<n> hold the traces off until n ms
//   +TRACE_INT=<n> trace from the n-th interrupt taken, 1 ms, then stop
//   +SPITRACE     every byte the MCU stand-in gets into sysctrl
//   +PPM_MAX=<n>  cap how many .ppm frames are written (default 4)
//   +PPM_EVERY=<n>  write every n-th frame only (default 1)
//   +PPM_FROM=<n> skip the frames before n ms
//   +NOMEMCHECK   turn off the read-after-write check on the SDRAM
//   +HDMIDBG      print every data island packet the decoder sees
//   +TURBO=<n>    the OSD's turbo switch: 0 as the ports say (default), 1 on, 2 off
//   +NOFDC +NOAY +NOGS +NOSMUC   the OSD's switches off
//   +PROFROM=<n>  the ProfROM bank mask (0 for a 64 KB image, 3 for 256 KB;
//                 set from the +ROM file's size if not given)
//   +TYPE_STR=<text>  type the text ('_' for a space) and Enter at +TYPE_MS=<n> (default 2500)
//   +KEYS=<codes>     press and release these key codes in turn (hex pairs) at +TYPE_MS
//   +TRDA= +TRDB= +TRDC= +TRDD= +HDD=<file>   images (sim/stubs/sd_card_sim.v)
//   +SDFAST       the card answers in microseconds, not a millisecond
//   +MAGIC=<ms>   press the Magic button at n ms
//   +SCRDUMP      write the screen (page 5 or 7 of the model) to sim/out/screen.scr at the end
//   +RAMDUMP      write the SDRAM's words to sim/out/ram.hex at the end
//
// Every delay in milliseconds is `ms * 64'd1000000`: a 32-bit product
// wraps past 4294 ms.
//
// The SPI master, the HDMI decoder and the .ppm writer are UKNC Nano's
// through Korvet Nano's, the checks around them are this machine's.
//========================================================================
`timescale 1ns / 1ps

module tb_top;

    //--------------------------------------------------------------------
    // Clock and board inputs
    //--------------------------------------------------------------------
    reg clk27 = 1'b0;
    always #18.518 clk27 = ~clk27;      // 27 MHz

    reg  [1:0] buts = 2'b00;
    wire [5:0] leds;

    wire uart_tx;
    reg  uart_rx = 1'b1;

    wire sdclk;
    wire sdcmd, sddat0, sddat1, sddat2, sddat3;
    pullup (sdcmd); pullup (sddat0); pullup (sddat1);
    pullup (sddat2); pullup (sddat3);

    wire       O_tmds_clk_p, O_tmds_clk_n;
    wire [2:0] O_tmds_data_p, O_tmds_data_n;

    wire HP_BCK, HP_WS, HP_DIN, PA_EN;

    wire        O_sdram_clk, O_sdram_cke, O_sdram_cs_n;
    wire        O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [3:0]  O_sdram_dqm;
    wire [10:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba;
    wire [31:0] IO_sdram_dq;

    reg  spi_io_ss  = 1'b1;
    reg  spi_io_clk = 1'b0;
    reg  spi_io_din = 1'b0;

    wire [4:0] m0s;
    assign m0s[1] = spi_io_din ;
    assign m0s[2] = spi_io_ss  ;
    assign m0s[3] = spi_io_clk ;
    wire spi_io_dout = m0s[0];
    wire mcu_intn    = m0s[4];

    //--------------------------------------------------------------------
    // The design
    //--------------------------------------------------------------------
    wire reconfig_n;
    wire mspi_clk, mspi_cs_n, mspi_do;
    wire mspi_di = 1'b1;
    top uut (
        .clk27(clk27), .buts(buts), .leds(leds),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .sdclk(sdclk), .sdcmd(sdcmd),
        .sddat0(sddat0), .sddat1(sddat1), .sddat2(sddat2), .sddat3(sddat3),
        .O_tmds_clk_p(O_tmds_clk_p),   .O_tmds_clk_n(O_tmds_clk_n),
        .O_tmds_data_p(O_tmds_data_p), .O_tmds_data_n(O_tmds_data_n),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN), .PA_EN(PA_EN),
        .O_sdram_clk(O_sdram_clk),     .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),   .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_dqm(O_sdram_dqm),     .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),       .IO_sdram_dq(IO_sdram_dq),
        .m0s(m0s),
        .reconfig_n(reconfig_n),
        .mspi_clk(mspi_clk), .mspi_cs_n(mspi_cs_n),
        .mspi_do(mspi_do),   .mspi_di(mspi_di)
    );

    //--------------------------------------------------------------------
    // Memory.  sdram.v uses single-word reads (BL1), CAS 2, 32 bits.
    //--------------------------------------------------------------------
    sdram_model #(.BURST(1)) ram (
        .clk(O_sdram_clk), .cke(O_sdram_cke),
        .cs_n(O_sdram_cs_n), .ras_n(O_sdram_ras_n),
        .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n),
        .ba(O_sdram_ba), .a(O_sdram_addr),
        .dqm(O_sdram_dqm), .dq(IO_sdram_dq)
    );

    // a file into the model, a byte at a time into the word/lane layout
    // membus.v uses: word = byte address / 4, lane = its bits 1:0
    task load_image(input [1023:0] name, input integer base, output integer n);
        integer fd, c, w;
        reg [31:0] v;
        begin
            n = 0;
            fd = $fopen(name, "rb");
            if (fd == 0) $display("[tb] cannot open %0s", name);
            else begin
                c = $fgetc(fd);
                while (c != -1) begin
                    w = base + n;
                    v = ram.mem[w >> 2];
                    case (w & 3)
                        0: v[7:0]   = c[7:0];
                        1: v[15:8]  = c[7:0];
                        2: v[23:16] = c[7:0];
                        3: v[31:24] = c[7:0];
                    endcase
                    ram.mem[w >> 2] = v;
                    // the General Sound ROM's BSRAM copy, as the loader would fill it
                    if (base == 24'h400000 && n < 32768) uut.gsound.rom[n] = c[7:0];
                    n = n + 1;
                    c = $fgetc(fd);
                end
                $fclose(fd);
                $display("[tb] %0s: %0d bytes into the SDRAM model at %06x", name, n, base);
            end
        end
    endtask

    //--------------------------------------------------------------------
    // A minimal BL616: SPI master, mode 1, MSB first.
    //--------------------------------------------------------------------
    localparam SPI_HALF = 25;           // ns; 20 MHz like the real firmware
    localparam SPI_HOLD = 5;

    reg [7:0] spi_rx;

    task spi_byte(input [7:0] tx);
        integer b;
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                spi_io_din  = tx[b];
                #SPI_HALF spi_io_clk = 1'b1;
                #SPI_HALF spi_io_clk = 1'b0;
                #SPI_HOLD;
                spi_rx = {spi_rx[6:0], spi_io_dout};
            end
            #(SPI_HALF * 20);
        end
    endtask

    task spi_begin; begin spi_io_ss = 1'b0; #SPI_HALF; end endtask
    task spi_end;   begin #SPI_HALF spi_io_ss = 1'b1; #(SPI_HALF*4); end endtask

    // SYS command 4: set a configuration value
    task sys_set_val(input [7:0] id, input [7:0] val);
        begin
            spi_begin;
            spi_byte(8'd0);     // target SYS
            spi_byte(8'd4);     // command "set value"
            spi_byte(id);
            spi_byte(val);
            spi_end;
        end
    endtask

    // SYS command 6: a file into the SDRAM, the firmware's way
    task sys_load(input [1023:0] name, input [23:0] base);
        integer fd, c, n;
        begin
            fd = $fopen(name, "rb");
            if (fd == 0) $display("[tb] cannot open %0s", name);
            else begin
                n = 0;
                c = $fgetc(fd);
                while (c != -1) begin
                    if (n % 256 == 0) begin
                        if (n != 0) spi_end;
                        spi_begin;
                        spi_byte(8'd0); spi_byte(8'd6);
                        spi_byte(base[23:16] + n[23:16]); spi_byte(n[15:8]); spi_byte(n[7:0]);
                    end
                    spi_byte(c[7:0]);
                    n = n + 1;
                    c = $fgetc(fd);
                end
                spi_end;
                $fclose(fd);
                $display("[tb] %0t %0s: %0d bytes sent over CMD 6 to %06x", $time, name, n, base);
            end
        end
    endtask

    // HID command 1: one keyboard byte, as usb_host.c's kbd_tx sends it
    task hid_key(input [7:0] code);
        begin
            spi_begin;
            spi_byte(8'd1);     // target HID
            spi_byte(8'd1);     // keyboard
            spi_byte(code);
            spi_end;
        end
    endtask

    // press and release a key: the code as keyboard.v takes it.  The
    // ROM scans the keyboard in its frame interrupt, so a key is held
    // for three frames.
    localparam KEY_HOLD = 70000000;   // 70 ms
    task key(input [7:0] code);
        begin
            hid_key(code);
            #KEY_HOLD;
            hid_key(8'h80 | code);
            #KEY_HOLD;
        end
    endtask

    // the matrix (keyboard.v): code = row * 5 + col + 1; +40 with Caps
    // Shift, +80 with Symbol Shift
    function [7:0] kcode(input [2:0] row, input [2:0] col);
        kcode = row * 8'd5 + {5'd0, col} + 8'd1;
    endfunction
    localparam [7:0] K_ENTER = 8'd31;   // row 6 col 0
    localparam [7:0] K_SPACE = 8'd36;   // row 7 col 0

    // a character on the machine's keyboard
    task type_char(input [7:0] ch);
        reg [7:0] code; reg ok;
        begin
            ok = 1'b1; code = 8'd0;
            if (ch >= "A" && ch <= "Z") ch = ch + 8'h20;
            case (ch)
                "z": code = kcode(0,1); "x": code = kcode(0,2); "c": code = kcode(0,3); "v": code = kcode(0,4);
                "a": code = kcode(1,0); "s": code = kcode(1,1); "d": code = kcode(1,2); "f": code = kcode(1,3); "g": code = kcode(1,4);
                "q": code = kcode(2,0); "w": code = kcode(2,1); "e": code = kcode(2,2); "r": code = kcode(2,3); "t": code = kcode(2,4);
                "1": code = kcode(3,0); "2": code = kcode(3,1); "3": code = kcode(3,2); "4": code = kcode(3,3); "5": code = kcode(3,4);
                "0": code = kcode(4,0); "9": code = kcode(4,1); "8": code = kcode(4,2); "7": code = kcode(4,3); "6": code = kcode(4,4);
                "p": code = kcode(5,0); "o": code = kcode(5,1); "i": code = kcode(5,2); "u": code = kcode(5,3); "y": code = kcode(5,4);
                "l": code = kcode(6,1); "k": code = kcode(6,2); "j": code = kcode(6,3); "h": code = kcode(6,4);
                "m": code = kcode(7,2); "n": code = kcode(7,3); "b": code = kcode(7,4);
                "_", " ": code = K_SPACE;
                "\"": code = 8'd80 + kcode(5,0);   // SS + P
                ":":  code = 8'd80 + kcode(0,1);   // SS + Z
                ".":  code = 8'd80 + kcode(7,2);   // SS + M
                ",":  code = 8'd80 + kcode(7,3);   // SS + N
                "-":  code = 8'd80 + kcode(6,3);   // SS + J
                "=":  code = 8'd80 + kcode(6,1);   // SS + L
                default: begin ok = 1'b0; $display("[tb] type_char: no key for %c (%02x)", ch, ch); end
            endcase
            if (ok) key(code);
        end
    endtask

    task type_string(input [8*255:1] str);
        integer n, i;
        reg [7:0] c;
        begin
            n = 0;
            for (i = 0; i < 255; i = i + 1) if (str[8*(i+1) -: 8] != 8'd0) n = i + 1;
            for (i = n - 1; i >= 0; i = i - 1) begin
                c = str[8*(i+1) -: 8];
                type_char(c);
            end
        end
    endtask

    reg [7:0] st0, st1, st2, st3;

    // Exactly what sys_status_is_valid() in mnano/sysctrl.c does.
    task sys_status;
        begin
            spi_begin;
            spi_byte(8'd0);
            spi_byte(8'd0);
            spi_byte(8'h00);
            spi_byte(8'h00);  st0 = spi_rx;
            spi_byte(8'h00);  st1 = spi_rx;
            spi_byte(8'h00);  st2 = spi_rx;
            spi_byte(8'h00);  st3 = spi_rx;
            spi_end;
        end
    endtask

    // SYS command 7: the debug window
    reg [7:0] dbgb [0:31];
    integer dbg_i, dbg_o;
    task sys_debug;
        begin
            for (dbg_o = 0; dbg_o < 32; dbg_o = dbg_o + 8) begin
                spi_begin;
                spi_byte(8'd0);
                spi_byte(8'd7);
                spi_byte(dbg_o[7:0]);
                for (dbg_i = 0; dbg_i < 8; dbg_i = dbg_i + 1) begin
                    spi_byte(8'h00);
                    dbgb[dbg_o + dbg_i] = spi_rx;
                end
                spi_end;
            end
        end
    endtask

    //--------------------------------------------------------------------
    // Run
    //--------------------------------------------------------------------
    integer run_ms, type_ms, turbo_n, prof_n, magic_ms, rom_n, gsrom_n;
    reg [8*255:1] type_str, keys_str;
    reg [1023:0]  rom_file, gsrom_file;
    integer tries, ki, kn;
    reg     fastboot;
    integer cfg_errs = 0;

    initial begin
        if (!$value$plusargs("RUN_MS=%d", run_ms)) run_ms = 40;
        fastboot = !$test$plusargs("NOFASTBOOT");

        if ($test$plusargs("VCD")) begin
            $dumpfile("sim/out/tb_top.vcd");
            $dumpvars(0, tb_top);
        end

        // the ROMs into the model before anything runs
        rom_n = 0; gsrom_n = 0;
        if (!$test$plusargs("ROMSPI=")) begin
            if (!$value$plusargs("ROM=%s", rom_file)) rom_file = "soft/rom/scorp294.rom";
            load_image(rom_file, 24'h100000, rom_n);
        end
        if (!$value$plusargs("GSROM=%s", gsrom_file)) gsrom_file = "soft/rom/gs105a.rom";
        load_image(gsrom_file, 24'h400000, gsrom_n);

        if (fastboot) begin
            wait (uut.init);
            #20000;
            force uut.count_rst = 24'h7FFFF0;
            #20000;
            release uut.count_rst;
            $display("[tb] %0t fastboot: count_rst forced", $time);
        end

        tries = 0;
        st0 = 0; st1 = 0; st2 = 0;
        while (tries < 200 && !(st0 == 8'h5c && st1 == 8'h42)) begin
            #100000;
            sys_status;
            tries = tries + 1;
        end

        if (st0 == 8'h5c && st1 == 8'h42)
            $display("[tb] %0t FPGA ready, core id 0x%02x (expect 09 = ZS-256)", $time, st2);
        else begin
            $display("[tb] %0t FPGA never answered (got %02x %02x %02x)", $time, st0, st1, st2);
            cfg_errs = cfg_errs + 1;
        end
        if (st2 !== 8'h09) cfg_errs = cfg_errs + 1;

        sys_set_val("R", 8'd3);
        #50000;
        if ($value$plusargs("ROMSPI=%s", rom_file)) begin
            sys_load(rom_file, 24'h100000);
            rom_n = 65536;
        end
        // the OSD's defaults (mnano/menu.c, variables_zs256), and the plusargs
        if (!$value$plusargs("TURBO=%d", turbo_n)) turbo_n = 0;
        if (!$value$plusargs("PROFROM=%d", prof_n)) prof_n = (rom_n > 65536) ? 3 : 0;
        sys_set_val("A", 8'd1);
        sys_set_val("T", turbo_n[7:0]);
        sys_set_val("f", {7'd0, !$test$plusargs("NOFDC")});
        sys_set_val("y", {7'd0, !$test$plusargs("NOAY")});
        sys_set_val("g", {7'd0, !$test$plusargs("NOGS")});
        sys_set_val("u", {7'd0, !$test$plusargs("NOSMUC")});
        sys_set_val("j", 8'd1);
        sys_set_val("M", 8'd1);
        sys_set_val("m", 8'd0);
        sys_set_val("P", prof_n[7:0]);
        sys_set_val("s", 8'd0);
        sys_set_val("t", 8'd1);
        sys_set_val("p", 8'd0); sys_set_val("q", 8'd0); sys_set_val("k", 8'd0); sys_set_val("l", 8'd0);
        sys_set_val("R", 8'd0);
        $display("[tb] %0t released reset (turbo %0d, profrom mask %0d)", $time, turbo_n, prof_n);
        #2000;
        if (uut.system_volume !== 2'd1 || uut.system_turbo !== turbo_n[1:0] ||
            uut.system_profrom !== prof_n[1:0] || uut.system_mouse !== 1'b1) begin
            $display("[tb] *** OSD VALUES WRONG after the defaults");
            cfg_errs = cfg_errs + 1;
        end

        if ($value$plusargs("MAGIC=%d", magic_ms)) begin
            #(magic_ms * 64'd1000000);
            $display("[tb] %0t Magic pressed", $time);
            buts[1] = 1'b1; #20000000; buts[1] = 1'b0;
        end

        if ($value$plusargs("TYPE_STR=%s", type_str)) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2500;
            #(type_ms * 64'd1000000);
            $display("[tb] %0t typing %0s", $time, type_str);
            type_string(type_str);
            key(K_ENTER);
        end
        if ($value$plusargs("KEYS=%s", keys_str)) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2500;
            if (!$test$plusargs("TYPE_STR=")) #(type_ms * 64'd1000000);
            kn = 0;
            for (ki = 0; ki < 255; ki = ki + 1) if (keys_str[8*(ki+1) -: 8] != 8'd0) kn = ki + 1;
            for (ki = kn - 1; ki >= 1; ki = ki - 2) begin
                $display("[tb] %0t key %0d", $time, hexpair(keys_str[8*(ki+1) -: 8], keys_str[8*ki -: 8]));
                key(hexpair(keys_str[8*(ki+1) -: 8], keys_str[8*ki -: 8]));
            end
        end

        // a second batch of keys at its own time (from the run's start, as
        // TYPE_MS): +KEYS2=<hex pairs, zz a second's pause> +TYPE2_MS=<ms>
        if ($value$plusargs("KEYS2=%s", keys_str)) begin
            if (!$value$plusargs("TYPE2_MS=%d", type_ms)) type_ms = 5000;
            wait ($time >= type_ms * 64'd1000000);
            kn = 0;
            for (ki = 0; ki < 255; ki = ki + 1) if (keys_str[8*(ki+1) -: 8] != 8'd0) kn = ki + 1;
            for (ki = kn - 1; ki >= 1; ki = ki - 2) begin
                if (keys_str[8*(ki+1) -: 8] == "z") #(64'd1000000000);   // "zz": a second's pause
                else begin
                    $display("[tb] %0t key %0d", $time, hexpair(keys_str[8*(ki+1) -: 8], keys_str[8*ki -: 8]));
                    key(hexpair(keys_str[8*(ki+1) -: 8], keys_str[8*ki -: 8]));
                end
            end
        end

        #(run_ms * 64'd1000000);
        $display("[tb] %0t done: %0d video frames, leds=%b", $time, rx_frames, leds);
        $display("[tb] config checks: %0d wrong", cfg_errs);
        $display("[tb] cpu: %0d opcode fetches, %0d I/O reads, %0d I/O writes, %0d interrupts taken, %0d T2 samples with a request up, %0d in DOS",
                 m1_count, io_rd, io_wr, int_count, wait_count, dos_fetches);
        $display("[tb] ports: 7FFD %02x (%0d writes), 1FFD %02x (%0d writes), FE %02x (%0d writes), dos %b, turbo %b, profrom bank %0d",
                 uut.p7FFD, w7ffd, uut.p1FFD, w1ffd, uut.p_fe, wfe, uut.dos, uut.turbo, uut.profrom_bank);
        if (!$test$plusargs("NOMEMCHECK"))
            $display("[tb] read-after-write: %0d checked, %0d wrong", mem_checks, mem_errs);
        $display("[tb] sdram self-test: done %b, fail %b, late capture %b  (expect 1 0 0 against the model)",
                 uut.bist_done, uut.bist_fail, uut.cap_late);
        // the card's last byte to the host: after its RAM test, the page count (3Fh for 2 MB)
        $display("[tb] sd transfers %0d; screen writes %0d; gs: %0d fetches, %0d ints, %0d status polls, pc %04x, last byte out %02x",
                 sd_xfers, scr_writes, gs_m1s, gs_ints, gs_polls, uut.gs_pc, uut.gsound.to_zx);
        sys_debug;
        $display("[tb] debug (CMD 7): flags %02x %02x, disks %02x, pc %02x%02x op %02x, 7FFD %02x 1FFD %02x dos %02x cpu %02x, fe %02x attr %02x prof %02x turbo %02x, m1 %02x%02x resets %02x, gs pc %02x%02x",
                 dbgb[1], dbgb[2], dbgb[3], dbgb[7], dbgb[6], dbgb[5], dbgb[11], dbgb[10], dbgb[9], dbgb[8],
                 dbgb[15], dbgb[14], dbgb[13], dbgb[12], dbgb[19], dbgb[18], dbgb[17], dbgb[23], dbgb[22]);
        $display("[tb] i2s: %0d frames, %0d with sound", i2s_frames, i2s_nonzero);
        $display("[tb] hdmi: %0d packets, %0d ecc errors  (acr %0d, avi %0d, ai %0d, gcp %0d, audio %0d, null %0d)",
                 rx_packets, rx_ecc_errs, rx_acr, rx_avi, rx_ai, rx_gcp, rx_audio, rx_null);
        $display("[tb] hdmi frame: %0d x %0d, %0d bad guard bands", rx_w, rx_h_last, rx_bad_gb);
        if ($test$plusargs("SCRDUMP")) scr_dump;
        $finish;
    end

    function [7:0] hexpair(input [7:0] a, input [7:0] b);
        hexpair = {hexdig(a), hexdig(b)};
    endfunction
    function [3:0] hexdig(input [7:0] c);
        hexdig = (c >= "a") ? c - "a" + 8'd10 : (c >= "A") ? c - "A" + 8'd10 : c - "0";
    endfunction

    // the screen as a .scr: the 6912 bytes of the page 7FFD shows, out
    // of the SDRAM model (page 5 at byte 14000h, page 7 at 1C000h)
    task scr_dump;
        integer fh, i, base; reg [31:0] v;
        begin
            base = uut.p7FFD[3] ? 'h1C000 : 'h14000;
            fh = $fopen("sim/out/screen.scr", "wb");
            for (i = 0; i < 6912; i = i + 1) begin
                v = ram.mem[(base + i) >> 2];
                case (i & 3)
                    0: $fwrite(fh, "%c", v[7:0]);
                    1: $fwrite(fh, "%c", v[15:8]);
                    2: $fwrite(fh, "%c", v[23:16]);
                    3: $fwrite(fh, "%c", v[31:24]);
                endcase
            end
            $fclose(fh);
            $display("[tb] sim/out/screen.scr written (page %0d)", uut.p7FFD[3] ? 7 : 5);
        end
    endtask

    //--------------------------------------------------------------------
    // Watching the processor
    //--------------------------------------------------------------------
    integer trace_ms, trace_int;
    reg     tracing = 1'b0;
    initial begin
        if (!$value$plusargs("TRACE_MS=%d", trace_ms)) trace_ms = 0;
        if (!$value$plusargs("TRACE_INT=%d", trace_int)) trace_int = 0;
        if (trace_int > 0) begin
            wait (int_count >= trace_int);
            $display("[tb] %0t interrupt %0d taken: tracing for 1 ms, then stop", $time, trace_int);
            tracing = 1'b1;
            #(64'd1000000);
            $display("[tb] %0t TRACE_INT: stop", $time);
            $finish;
        end
        if (trace_ms > 0) #(trace_ms * 64'd1000000);
        tracing = 1'b1;
    end

    integer m1_count = 0, io_rd = 0, io_wr = 0, int_count = 0, wait_count = 0, dos_fetches = 0;
    integer w7ffd = 0, w1ffd = 0, wfe = 0, scr_writes = 0, gs_m1s = 0, gs_ints = 0, gs_polls = 0;
    reg     first_seen = 1'b0;
    reg [15:0] m1_adr, io_adr;
    reg        m1_pend = 1'b0, io_pend = 1'b0;
    reg        gs_int_d = 1'b1;
    reg        iff1_d = 1'b0;

    always @(posedge uut.clk) begin
        if (uut.mem_stb && uut.z_m1) begin
            m1_count = m1_count + 1;
            m1_adr   = uut.z_a;
            m1_pend  = 1'b1;
            if (uut.dos) dos_fetches = dos_fetches + 1;
            if (!first_seen) begin
                first_seen = 1'b1;
                $display("[tb] %0t CPU first fetch at %04x", $time, uut.z_a);
            end
        end
        if (m1_pend && uut.mem_ack) begin
            m1_pend = 1'b0;
            if ($test$plusargs("CPUTRACE") && tracing)
                $display("[cpu] %0t %04x: %02x%s", $time, m1_adr, uut.mem_rdata, uut.dos ? " dos" : "");
        end
        if (uut.io_stb && uut.z_m1 && uut.z_io) begin
            int_count = int_count + 1;
            if (int_count <= 3) $display("[tb] %0t interrupt %0d taken", $time, int_count);
            if ($test$plusargs("IFFTRACE")) $display("[iff] %0t inta %0d at %04x dos %b", $time, int_count, m1_adr, uut.dos);
        end
        // +IFFTRACE: every change of IFF1 with the last opcode fetched
        iff1_d <= uut.z_iff1;
        if ($test$plusargs("IFFTRACE") && iff1_d != uut.z_iff1)
            $display("[iff] %0t iff1 %b at %04x dos %b", $time, uut.z_iff1, m1_adr, uut.dos);
        if (uut.io_stb && !uut.z_m1) begin
            if (uut.z_we) begin
                io_wr = io_wr + 1;
                if ($test$plusargs("IOTRACE") && tracing) $display("[io]  %0t out %04x <= %02x", $time, uut.z_a, uut.z_dout);
                if (uut.z_a[15:14] == 2'b01 && uut.z_a[0] && !uut.z_a[1] && uut.z_a[5]) w7ffd = w7ffd + 1;
                if (uut.z_a[15:14] == 2'b00 && uut.z_a[0] && !uut.z_a[1] && uut.z_a[5]) w1ffd = w1ffd + 1;
                if (!uut.z_a[0] && uut.z_a[1] && uut.z_a[5]) wfe = wfe + 1;
            end else begin
                io_rd = io_rd + 1; io_adr = uut.z_a; io_pend = 1'b1;
            end
        end
        if (io_pend && uut.io_ack) begin
            io_pend = 1'b0;
            if ($test$plusargs("IOTRACE") && tracing) $display("[io]  %0t in  %04x -> %02x", $time, io_adr, uut.io_rdata);
        end
        if (uut.cen_cpu && uut.z_req && uut.cpu.tstate[2]) wait_count = wait_count + 1;
        if (uut.scr_we) scr_writes = scr_writes + 1;
        if ((uut.gsound.fast_go || uut.gsound.b_take) && uut.gsound.m1) begin
            gs_m1s = gs_m1s + 1;
            if ($test$plusargs("GSTRACE") && tracing) $display("[gs]  %0t %04x", $time, uut.gsound.A);
        end
        // the firmware's command loop reads its status register (port 4)
        if (uut.gsound.io_want && !uut.gsound.inta && !uut.gsound.we_z && uut.gsound.A[3:0] == 4'h4)
            gs_polls = gs_polls + 1;
        gs_int_d <= uut.gsound.int_n;
        if (gs_int_d && !uut.gsound.int_n) gs_ints = gs_ints + 1;
    end

    // +SPITRACE
    always @(posedge uut.clk)
        if ($test$plusargs("SPITRACE") && uut.mcu_sys_strobe)
            $display("[spi] %0t sys byte %02x start=%b state=%0d cmd=%02x id=%02x",
                     $time, uut.mcu_dout, uut.mcu_start,
                     uut.sctl1.state, uut.sctl1.command, uut.sctl1.id);

    //--------------------------------------------------------------------
    // Read-after-write check on the SDRAM's two ports: a shadow of every
    // word written, lane by lane, compared against what is read back.
    // 21 address bits: the RAM, the ROM and General Sound's memory.
    //--------------------------------------------------------------------
    reg [31:0] shadow [0:2097151];
    reg [3:0]  known  [0:2097151];
    integer    mem_errs = 0, mem_checks = 0;
    integer    si;
    initial for (si = 0; si < 2097152; si = si + 1) known[si] = 4'd0;

    reg        rd_pend_a = 1'b0, rd_pend_b = 1'b0;
    reg [20:0] rd_wa, rd_wb;
    task note_write(input [20:0] w, input [31:0] d, input [3:0] m);
        begin
            for (si = 0; si < 4; si = si + 1)
                if (m[si]) begin shadow[w][si*8 +: 8] = d[si*8 +: 8]; known[w][si] = 1'b1; end
        end
    endtask
    task check_read(input [20:0] w, input [31:0] d, input [7:0] port);
        begin
            if (known[w] != 4'd0 && !$test$plusargs("NOMEMCHECK")) begin
                mem_checks = mem_checks + 1;
                for (si = 0; si < 4; si = si + 1)
                    if (known[w][si] && d[si*8 +: 8] !== shadow[w][si*8 +: 8]) begin
                        mem_errs = mem_errs + 1;
                        if (mem_errs <= 10)
                            $display("[mem] %0t port %c read %08x at word %06x, lane %0d wrote %02x",
                                     $time, port, d, w, si, shadow[w][si*8 +: 8]);
                    end
            end
        end
    endtask
    always @(posedge uut.clk) begin
        if (uut.a_take) begin
            if (uut.a_we) note_write(uut.a_adr, uut.a_wdata, uut.a_wmask);
            else begin rd_pend_a = 1'b1; rd_wa = uut.a_adr; end
            if ($test$plusargs("MEMTRACE") && tracing)
                $display("[ram] %0t A %s word %06x mask %b %08x", $time, uut.a_we ? "wr" : "rd", uut.a_adr, uut.a_wmask, uut.a_wdata);
        end
        if (uut.a_ack && rd_pend_a) begin rd_pend_a = 1'b0; check_read(rd_wa, uut.a_rdata, "A"); end
        if (uut.b_take) begin
            if (uut.b_we) note_write(uut.b_adr, uut.b_wdata, uut.b_wmask);
            else begin rd_pend_b = 1'b1; rd_wb = uut.b_adr; end
            if ($test$plusargs("MEMTRACE") && tracing)
                $display("[ram] %0t B %s word %06x mask %b %08x", $time, uut.b_we ? "wr" : "rd", uut.b_adr, uut.b_wmask, uut.b_wdata);
        end
        if (uut.b_ack && rd_pend_b) begin rd_pend_b = 1'b0; check_read(rd_wb, uut.b_rdata, "B"); end
    end

    final if ($test$plusargs("RAMDUMP")) $writememh("sim/out/ram.hex", ram.mem, 0, 1048575);

    integer sd_xfers = 0;
    always @(posedge uut.clk) if (uut.sd_rdone) sd_xfers = sd_xfers + 1;

    //--------------------------------------------------------------------
    // I2S monitor
    //--------------------------------------------------------------------
    reg [15:0] i2s_sr = 16'd0;
    reg [15:0] i2s_l  = 16'd0;
    reg        ws_d   = 1'b0;
    integer    i2s_frames = 0, i2s_nonzero = 0;
    always @(posedge HP_BCK) begin
        i2s_sr <= {i2s_sr[14:0], HP_DIN};
        ws_d   <= HP_WS;
        if (HP_WS && !ws_d) i2s_l <= i2s_sr;
        if (!HP_WS && ws_d) begin
            i2s_frames = i2s_frames + 1;
            if (i2s_l !== 16'd0 || i2s_sr !== 16'd0) i2s_nonzero = i2s_nonzero + 1;
        end
    end

    //--------------------------------------------------------------------
    // The HDMI receiver: hdmi_serdes is stubbed, so what leaves the
    // design is three ten-bit TMDS words a pixel clock.  This decodes
    // them as a sink does and rebuilds the picture for `make frames`.
    //--------------------------------------------------------------------
    wire        px_clk = uut.clk;
    wire [9:0]  t0 = uut.tmds_ch0;
    wire [9:0]  t1 = uut.tmds_ch1;
    wire [9:0]  t2 = uut.tmds_ch2;

    localparam [9:0] CTL00 = 10'b1101010100, CTL01 = 10'b0010101011,
                     CTL10 = 10'b0101010100, CTL11 = 10'b1010101011;
    localparam [9:0] VGB_02 = 10'b1011001100, VGB_1 = 10'b0100110011;

    function is_ctl(input [9:0] w);
        is_ctl = (w == CTL00) || (w == CTL01) || (w == CTL10) || (w == CTL11);
    endfunction

    function [1:0] ctl_of(input [9:0] w);
        ctl_of = (w == CTL00) ? 2'b00 : (w == CTL01) ? 2'b01 :
                 (w == CTL10) ? 2'b10 : 2'b11;
    endfunction

    function [7:0] tmds_dec(input [9:0] w);
        reg [7:0] qm, d;
        integer   i;
        begin
            qm = w[9] ? ~w[7:0] : w[7:0];
            d[0] = qm[0];
            for (i = 1; i < 8; i = i + 1)
                d[i] = w[8] ? (qm[i] ^ qm[i-1]) : (qm[i] ~^ qm[i-1]);
            tmds_dec = d;
        end
    endfunction

    function [4:0] terc4_dec(input [9:0] w);
        case (w)
            10'b1010011100: terc4_dec = 5'h00;
            10'b1001100011: terc4_dec = 5'h01;
            10'b1011100100: terc4_dec = 5'h02;
            10'b1011100010: terc4_dec = 5'h03;
            10'b0101110001: terc4_dec = 5'h04;
            10'b0100011110: terc4_dec = 5'h05;
            10'b0110001110: terc4_dec = 5'h06;
            10'b0100111100: terc4_dec = 5'h07;
            10'b1011001100: terc4_dec = 5'h08;
            10'b0100111001: terc4_dec = 5'h09;
            10'b0110011100: terc4_dec = 5'h0a;
            10'b1011000110: terc4_dec = 5'h0b;
            10'b1010001110: terc4_dec = 5'h0c;
            10'b1001110001: terc4_dec = 5'h0d;
            10'b0101100011: terc4_dec = 5'h0e;
            10'b1011000011: terc4_dec = 5'h0f;
            default:        terc4_dec = 5'h10;
        endcase
    endfunction

    function [7:0] ecc_step(input [7:0] ecc, input b);
        ecc_step = (ecc >> 1) ^ ((ecc[0] ^ b) ? 8'b10000011 : 8'd0);
    endfunction

    localparam RX_CTL = 0, RX_VGB = 1, RX_VID = 2,
               RX_DGB = 3, RX_DI  = 4, RX_DGBT = 5;

    integer rx_state   = RX_CTL;
    integer rx_gb      = 0;
    integer rx_frames  = 0;
    integer rx_packets = 0, rx_ecc_errs = 0;
    integer rx_acr = 0, rx_avi = 0, rx_ai = 0, rx_audio = 0, rx_null = 0, rx_gcp = 0;
    integer rx_bad_gb = 0;

    reg        rx_vs = 1'b0, rx_vs_d = 1'b0;
    integer    rx_x = 0, rx_y = 0, rx_w = 0, rx_h_last = 0;

    parameter MAXW = 1056;
    parameter MAXH = 640;
    reg [23:0] fb [0:MAXW*MAXH-1];

    reg [4:0]  pk_cnt = 5'd0;
    reg [23:0] pk_hdr;
    reg [55:0] pk_sub [0:3];
    reg [7:0]  pk_par [0:4];
    reg [7:0]  pk_ecc [0:4];
    integer    gi;

    integer fh, fi, fj, fh_h;
    integer written = 0, ppm_max;
    reg     want_ppm = 0;
    reg [255:0] fname;
    integer ppm_from, ppm_every;
    reg     ppm_armed = 1'b0;
    initial begin
        want_ppm = $test$plusargs("VIDEO_PPM");
        if (!$value$plusargs("PPM_MAX=%d", ppm_max)) ppm_max = 4;
        if (!$value$plusargs("PPM_FROM=%d", ppm_from)) ppm_from = 0;
        if (!$value$plusargs("PPM_EVERY=%d", ppm_every)) ppm_every = 1;
        if (ppm_from > 0) #(ppm_from * 64'd1000000);
        ppm_armed = 1'b1;
    end

    task write_ppm;
        begin
            written = written + 1;
            fh_h = (rx_y > MAXH) ? MAXH : rx_y;
            $sformat(fname, "sim/out/frame_%04d.ppm", rx_frames);
            fh = $fopen(fname, "wb");
            if (fh) begin
                $fwrite(fh, "P6\n%0d %0d\n255\n", rx_w, fh_h);
                for (fj = 0; fj < fh_h; fj = fj + 1)
                    for (fi = 0; fi < rx_w; fi = fi + 1)
                        $fwrite(fh, "%c%c%c",
                                fb[fj*MAXW+fi][23:16],
                                fb[fj*MAXW+fi][15:8],
                                fb[fj*MAXW+fi][7:0]);
                $fclose(fh);
                $display("[hdmi] %0t wrote %0s (%0dx%0d)", $time, fname, rx_w, fh_h);
            end
        end
    endtask

    task finish_packet;
        reg [7:0] ptype;
        begin
            rx_packets = rx_packets + 1;
            for (gi = 0; gi < 5; gi = gi + 1)
                if (pk_par[gi] !== pk_ecc[gi]) rx_ecc_errs = rx_ecc_errs + 1;
            ptype = pk_hdr[7:0];
            case (ptype)
                8'h00: rx_null  = rx_null  + 1;
                8'h01: rx_acr   = rx_acr   + 1;
                8'h02: rx_audio = rx_audio + 1;
                8'h03: rx_gcp   = rx_gcp   + 1;
                8'h82: rx_avi   = rx_avi   + 1;
                8'h84: rx_ai    = rx_ai    + 1;
                default: ;
            endcase
            if ($test$plusargs("HDMIDBG"))
                $display("[hdmi] %0t packet type %02x hdr %06x sub0 %014x",
                         $time, ptype, pk_hdr, pk_sub[0]);
        end
    endtask

    always @(posedge px_clk) begin : rx
        reg [1:0] c0, c1, c2;
        reg [4:0] n0, n1, n2;
        reg [7:0] dr, dg, db;
        c0 = ctl_of(t0); c1 = ctl_of(t1); c2 = ctl_of(t2);

        case (rx_state)
        RX_CTL: begin
            if (is_ctl(t0)) begin
                rx_vs_d = rx_vs;
                rx_vs   = c0[1];
                if (rx_vs && !rx_vs_d) begin
                    if (rx_frames > 0 && want_ppm && ppm_armed &&
                        written < ppm_max && (rx_frames % ppm_every) == 0) write_ppm;
                    rx_frames = rx_frames + 1;
                    rx_h_last = rx_y;
                    rx_x = 0; rx_y = 0;
                end
            end
            if (is_ctl(t1) && c1 == 2'b01) begin
                if (is_ctl(t2) && c2 == 2'b01) rx_state = RX_DGB;
                else                           rx_state = RX_VGB;
                rx_gb = 0;
            end
        end

        RX_VGB: begin
            if (is_ctl(t1) && ctl_of(t1) == 2'b01) begin
            end else begin
                if (t0 !== VGB_02 || t1 !== VGB_1 || t2 !== VGB_02)
                    rx_bad_gb = rx_bad_gb + 1;
                rx_gb = rx_gb + 1;
                if (rx_gb == 2) begin rx_state = RX_VID; rx_x = 0; end
            end
        end

        RX_VID: begin
            if (is_ctl(t0)) begin
                if (rx_x > rx_w) rx_w = rx_x;
                rx_x = 0;
                rx_y = rx_y + 1;
                rx_state = RX_CTL;
            end else begin
                db = tmds_dec(t0); dg = tmds_dec(t1); dr = tmds_dec(t2);
                if (rx_x < MAXW && rx_y < MAXH)
                    fb[rx_y*MAXW+rx_x] = {dr, dg, db};
                rx_x = rx_x + 1;
            end
        end

        RX_DGB: begin
            if (is_ctl(t1) && ctl_of(t1) == 2'b01 &&
                is_ctl(t2) && ctl_of(t2) == 2'b01) begin
            end else begin
                if (t1 !== VGB_1 || t2 !== VGB_1) rx_bad_gb = rx_bad_gb + 1;
                rx_gb = rx_gb + 1;
                if (rx_gb == 2) begin
                    rx_state = RX_DI;
                    pk_cnt = 5'd0;
                    for (gi = 0; gi < 5; gi = gi + 1) pk_par[gi] = 8'd0;
                end
            end
        end

        RX_DI: begin
            n0 = terc4_dec(t0); n1 = terc4_dec(t1); n2 = terc4_dec(t2);
            if (n0[4] || n1[4] || n2[4]) begin
                rx_gb = 0;
                rx_state = RX_DGBT;
            end else begin
                if (pk_cnt < 5'd24) pk_hdr[pk_cnt] = n0[2];
                for (gi = 0; gi < 4; gi = gi + 1) begin
                    pk_sub[gi][{pk_cnt, 1'b0}] = n1[gi];
                    pk_sub[gi][{pk_cnt, 1'b1}] = n2[gi];
                end
                if (pk_cnt >= 5'd28) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        pk_ecc[gi][{pk_cnt[1:0], 1'b0}] = n1[gi];
                        pk_ecc[gi][{pk_cnt[1:0], 1'b1}] = n2[gi];
                    end
                end
                if (pk_cnt >= 5'd24) pk_ecc[4][pk_cnt[2:0]] = n0[2];
                if (pk_cnt < 5'd28) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        pk_par[gi] = ecc_step(pk_par[gi], n1[gi]);
                        pk_par[gi] = ecc_step(pk_par[gi], n2[gi]);
                    end
                    if (pk_cnt < 5'd24)
                        pk_par[4] = ecc_step(pk_par[4], n0[2]);
                end
                if (pk_cnt == 5'd31) begin
                    finish_packet;
                    for (gi = 0; gi < 5; gi = gi + 1) pk_par[gi] = 8'd0;
                end
                pk_cnt = pk_cnt + 5'd1;
            end
        end

        RX_DGBT: begin
            rx_gb = rx_gb + 1;
            if (rx_gb == 2) rx_state = RX_CTL;
        end
        endcase
    end

endmodule
