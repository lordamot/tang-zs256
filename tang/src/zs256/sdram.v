`timescale 1ns / 1ps
//========================================================================
// sdram.v - the Scorpion's memories, in the Tang Nano 20K's SDRAM.
//
// One clock, 42 MHz, and a fixed timetable.  A T-state of the Z80 is
// twelve clocks (tphase 0..11, from top.v) and it is cut into two
// six-clock slots: phases 1-6 are slot A, the host processor's, phases
// 7-12 (7..11 and 0) slot B, the General Sound's Z80's, the ROM
// loader's and refresh's.  The slots start one clock after the Z80's
// enable at phase 0, which is when z80bus.v's request has just been
// registered: a request made in T1 is on slot A's first clock and
// served in the same T-state.  Each slot is one complete random access - ACTIVE, READ or
// WRITE with auto-precharge, data - and the slots never overlap, so the
// two processors never wait for each other and there is no arbiter to
// get wrong.  Korvet Nano's controller (../tang-korvet, sdram.v) with
// the slot shortened from eight clocks to six: the chip's row cycle is
// about 63 ns and a slot is 143.
//
//   slot clock  0: ACTIVE     (row)             if a request is up
//               1: READ/WRITE (column, A10=1)   write data driven now
//               2: -                            write data held
//               3: read data captured
//               4: (the late capture)
//               5: -
//
// Why clock 3: the chip is clocked by the PLL's copy 90 degrees behind
// ours, so it takes the READ a quarter period after we put it out (in
// clock 2) and, with CAS latency 2, has the word on the bus from tAC
// after its next edge - half way into our clock 3 - until tOH after the
// one following, a third into our clock 4.  The edge ending clock 3 is
// inside that window with margin both ways.  The self-test below moves
// the capture to clock 4 if the board says so.
//
// The word is 32 bits, four bytes a word, a byte picked by the DQM lanes
// on a write and by a mux on a read (membus.v, gs.v).  Word address
// a[20:0]: [20:19] the bank, [18:8] the row, [7:0] the column (2M x 32,
// 4 banks of 2048 rows of 256).  Who lives where is top.v's business:
// the host's RAM, the ROM, the General Sound's RAM and ROM.
//
// A port's request is a level: `req` is sampled on its slot's first
// clock and `take` says it was, one clock, at which moment the address,
// the data and the mask were read; `ack` comes one clock with `rdata`
// for a read.  A write is done when it is taken.
//
// Initialisation and the self-test are PK8000 Nano's through Korvet
// Nano: 65536 clocks of NOP after PLL lock, the JEDEC steps one a slot;
// then, with both processors still in reset, four words written
// through slot A and read back in the same order; if they do not come
// back the capture moves to slot clock 4 and the test runs again; a
// second failure raises bist_fail.  Both are on the LEDs.
//
// Refresh: 4096 rows in 64 ms is one every 15.6 us, 656 clocks; every
// 640 here, counted as due and taken in any slot nobody asks for - the
// host's slot is idle two thirds of the time even in turbo, and the
// General Sound's between its fetches.
//========================================================================
module sdram (
    input             clk,
    input             lock,         // the PLL has locked
    output            init,         // the memory is initialised

    input      [3:0]  tphase,       // 0..11

    // slot A: the host, phases 1..6
    input             a_req,
    input             a_we,
    input      [20:0] a_adr,        // word address
    input      [31:0] a_wdata,
    input      [3:0]  a_wmask,      // byte lanes written (1 = write)
    output            a_take,       // one clock: the request is in flight
    output reg [31:0] a_rdata,
    output reg        a_ack,        // one clock, with a_rdata

    // slot B: the General Sound and the loader, phases 7..12
    input             b_req,
    input             b_we,
    input      [20:0] b_adr,
    input      [31:0] b_wdata,
    input      [3:0]  b_wmask,
    output            b_take,
    output reg [31:0] b_rdata,
    output reg        b_ack,

    // the self-test's verdict (see the header)
    output reg        bist_done,
    output reg        bist_fail,
    output reg        cap_late,     // reads captured on slot clock 4, not 3

    // the chip
    output reg [10:0] SDRAM_A,
    output reg [1:0]  SDRAM_BA,
    inout      [31:0] SDRAM_DQ,
    output            SDRAM_nCS,
    output            SDRAM_nRAS,
    output            SDRAM_nCAS,
    output            SDRAM_nWE,
    output reg [3:0]  SDRAM_DQM
);

localparam [3:0] CMD_INHIBIT      = 4'b1111;
localparam [3:0] CMD_NOP          = 4'b0111;
localparam [3:0] CMD_ACTIVE       = 4'b0011;
localparam [3:0] CMD_READ         = 4'b0101;
localparam [3:0] CMD_WRITE        = 4'b0100;
localparam [3:0] CMD_PRECHARGE    = 4'b0010;
localparam [3:0] CMD_AUTO_REFRESH = 4'b0001;
localparam [3:0] CMD_LOAD_MODE    = 4'b0000;

// Mode register: CAS latency 2, burst length 1, sequential, single writes.
localparam [10:0] MODE = 11'b0_1_00_010_0_000;

reg  [3:0] cmd = CMD_INHIBIT;
assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = cmd;

reg  [31:0] dq_out = 32'd0;
reg         dq_oe  = 1'b0;
assign SDRAM_DQ = dq_oe ? dq_out : 32'hZZZZZZZZ;

// the slot clock 0..5 and which slot: slot A is phases 1..6, B 7..12
wire [3:0] ph     = (tphase == 4'd0) ? 4'd11 : tphase - 4'd1;
wire       slot_b = (ph >= 4'd6);
wire [2:0] sc     = slot_b ? ph[2:0] - 3'd6 : ph[2:0];

//------------------------------------------------------------------------
// Power-up
//------------------------------------------------------------------------
reg  [15:0] settle   = 16'd0;
reg  [4:0]  istep    = 5'd0;      // 0 = done
reg         started  = 1'b0;
assign init = started && (istep == 5'd0);

//------------------------------------------------------------------------
// Refresh, kept as a count of those due
//------------------------------------------------------------------------
reg  [9:0] ref_cnt = 10'd0;
reg  [2:0] ref_due = 3'd0;

//------------------------------------------------------------------------
// The self-test: eight accesses through slot A, one a T-state, advanced
// at phase 7 when the read data of the T-state's slot A is in a_rdata
// whichever clock captured it.  Four words at the top of the host RAM's
// first 64 KB (words 3FFCh..3FFFh), all four lanes.
//------------------------------------------------------------------------
reg         bist_run  = 1'b0;
reg         bist_rd   = 1'b0;     // 0 the write pass, 1 the read pass
reg  [1:0]  bist_i    = 2'd0;
reg         bist_bad  = 1'b0;
wire [20:0] bist_adr  = {7'd0, 12'h3FF, bist_i};
reg  [31:0] bist_pat;
always @(*) case (bist_i)
    2'd0: bist_pat = 32'h55AA_1234;
    2'd1: bist_pat = 32'hAA55_5678;
    2'd2: bist_pat = 32'h5A5A_9ABC;
    2'd3: bist_pat = 32'hA5A5_DEF0;
endcase

//------------------------------------------------------------------------
// Who gets the slot: decided on its first clock
//------------------------------------------------------------------------
wire running = init && (istep == 5'd0);
wire go_a    = running && !slot_b && sc == 3'd0 && (a_req || bist_run);
wire go_b    = running &&  slot_b && sc == 3'd0 && b_req;
wire go_ref  = running && sc == 3'd0 && ref_due != 3'd0 &&
               (slot_b ? !b_req : !(a_req || bist_run));
assign a_take = go_a && a_req && !bist_run;
assign b_take = go_b;

//------------------------------------------------------------------------
// The cycle in flight
//------------------------------------------------------------------------
reg         act      = 1'b0;
reg         act_we   = 1'b0;
reg         act_b    = 1'b0;
reg  [20:0] act_adr  = 21'd0;
reg  [31:0] act_data = 32'd0;
reg  [3:0]  act_mask = 4'd0;

always @(posedge clk) begin
    cmd       <= CMD_NOP;
    dq_oe     <= 1'b0;
    a_ack     <= 1'b0;
    b_ack     <= 1'b0;
    SDRAM_DQM <= 4'b1111;

    if (!lock) begin
        settle  <= 16'd0;
        istep   <= 5'd31;
        started <= 1'b0;
        cmd     <= CMD_INHIBIT;
        ref_due <= 3'd0;
        ref_cnt <= 10'd0;
        bist_run  <= 1'b0;  bist_rd  <= 1'b0; bist_i   <= 2'd0; bist_bad <= 1'b0;
        bist_done <= 1'b0;  bist_fail <= 1'b0; cap_late <= 1'b0;
        act <= 1'b0;
    end else if (!started) begin
        if (&settle) begin started <= 1'b1; istep <= 5'd31; end
        else settle <= settle + 16'd1;
        SDRAM_A  <= 11'd0;
        SDRAM_BA <= 2'd0;
    end else if (istep != 5'd0) begin
        // one step a slot, on the slot's first clock
        if (sc == 3'd0 && slot_b) begin
            istep <= istep - 5'd1;
            case (istep)
                5'd20: begin cmd <= CMD_PRECHARGE;    SDRAM_A <= 11'b100_0000_0000; end
                5'd16: cmd <= CMD_AUTO_REFRESH;
                5'd12: cmd <= CMD_AUTO_REFRESH;
                5'd8:  begin cmd <= CMD_LOAD_MODE;    SDRAM_A <= MODE; end
                default: ;
            endcase
        end
    end else begin
        //----------------------------------------------------------------
        // Running.
        //----------------------------------------------------------------
        if (!bist_done && !bist_run && tphase == 4'd7) bist_run <= 1'b1;
        if (bist_run && tphase == 4'd7) begin
            if (bist_rd && a_rdata != bist_pat) bist_bad <= 1'b1;
            bist_i <= bist_i + 2'd1;
            if (bist_i == 2'd3) begin
                if (!bist_rd)
                    bist_rd <= 1'b1;
                else begin
                    bist_rd <= 1'b0;
                    bist_bad <= 1'b0;
                    if (!(bist_bad || a_rdata != bist_pat)) begin
                        bist_run <= 1'b0; bist_done <= 1'b1;
                    end else if (!cap_late) begin
                        cap_late <= 1'b1;
                    end else begin
                        bist_run <= 1'b0; bist_done <= 1'b1;
                        bist_fail <= 1'b1; cap_late <= 1'b0;
                    end
                end
            end
        end

        if (ref_cnt == 10'd639) begin
            ref_cnt <= 10'd0;
            if (ref_due != 3'd7) ref_due <= ref_due + 3'd1;
        end else
            ref_cnt <= ref_cnt + 10'd1;

        case (sc)
        3'd0: begin
            act <= 1'b0;
            if (go_a) begin
                act      <= 1'b1;
                act_b    <= 1'b0;
                if (bist_run) begin
                    act_we   <= ~bist_rd;
                    act_adr  <= bist_adr;
                    act_data <= bist_pat;
                    act_mask <= 4'b1111;
                    SDRAM_BA <= bist_adr[20:19];
                    SDRAM_A  <= bist_adr[18:8];
                end else begin
                    act_we   <= a_we;
                    act_adr  <= a_adr;
                    act_data <= a_wdata;
                    act_mask <= a_wmask;
                    SDRAM_BA <= a_adr[20:19];
                    SDRAM_A  <= a_adr[18:8];
                end
                cmd      <= CMD_ACTIVE;
            end else if (go_b) begin
                act      <= 1'b1;
                act_b    <= 1'b1;
                act_we   <= b_we;
                act_adr  <= b_adr;
                act_data <= b_wdata;
                act_mask <= b_wmask;
                cmd      <= CMD_ACTIVE;
                SDRAM_BA <= b_adr[20:19];
                SDRAM_A  <= b_adr[18:8];
            end else if (go_ref) begin
                cmd     <= CMD_AUTO_REFRESH;
                ref_due <= ref_due - 3'd1;
            end
        end
        3'd1: if (act) begin
            // column with auto-precharge: A10 SET, written at its own
            // position (PK8000 Nano's lesson); the lanes by DQM
            SDRAM_A  <= {1'b1, 2'b00, act_adr[7:0]};
            SDRAM_BA <= act_adr[20:19];
            if (act_we) begin
                cmd       <= CMD_WRITE;
                dq_out    <= act_data;
                dq_oe     <= 1'b1;
                SDRAM_DQM <= ~act_mask;
            end else begin
                cmd       <= CMD_READ;
                SDRAM_DQM <= 4'b0000;
            end
        end
        3'd2: if (act && act_we) dq_oe <= 1'b1;
        3'd3: if (act && !act_we && !cap_late) begin
            if (act_b) begin b_rdata <= SDRAM_DQ; b_ack <= 1'b1; end
            else       begin a_rdata <= SDRAM_DQ; a_ack <= 1'b1; end
        end
        3'd4: if (act && !act_we && cap_late) begin
            if (act_b) begin b_rdata <= SDRAM_DQ; b_ack <= 1'b1; end
            else       begin a_rdata <= SDRAM_DQ; a_ack <= 1'b1; end
        end
        default: ;
        endcase
    end
end

endmodule
