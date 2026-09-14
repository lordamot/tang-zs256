`timescale 1ns / 1ps
//========================================================================
// ide.v - an ATA disk, one drive, on an image file from the card.
//
// The SMUC's IDE port is the standard ATA register file (smuc.v says
// how the Scorpion reaches it); this is the drive on it: an image file
// on the SD card (sd_card.v's slot 4) read and written a sector at a
// time through the same path as the floppies.  What it does:
//
//   ECh IDENTIFY DEVICE     256 words: the geometry below, LBA, PIO
//   20h/21h READ SECTORS    one at a time: the sector into the buffer,
//                           DRQ, 256 words out, the next
//   30h/31h WRITE SECTORS   DRQ, 256 words in, the sector to the card
//   C4h/C5h read/write multiple  the same (IDENTIFY says one a block)
//   40h/41h VERIFY, 91h INITIALIZE PARAMETERS, 1xh RECALIBRATE, 70h SEEK,
//   E0h-E7h power and flush, EFh SET FEATURES   accepted, nothing done
//   anything else           ERR with ABRT
//
// CHS and LBA both work; the geometry is 16 heads x 32 sectors, so a
// cylinder is 512 sectors and the cylinder count is the image's sector
// count shifted, no division.  A drive of the second kind (slave) is
// not there: its registers read as if absent.
//
// The data register is 16 bits wide and the buffer is kept as words;
// the SD path fills and drains it a byte at a time.
//========================================================================
module ide (
    input             clk,
    input             reset,

    // the register file: a strobe with the request, reg = A10..A8
    input             stb,
    input      [2:0]  reg_a,        // 0 data .. 7 status/command
    input             ctrl,         // 1: the control block (alt status / device control)
    input             we,
    input      [15:0] wdata,
    output reg [15:0] rdata,

    // the image
    input             mounted,      // one clock: the slot's image changed
    input      [31:0] image_size,
    output            present,

    // the SD path (sd_arbiter.v client 4)
    output reg        sd_rd,
    output reg        sd_wr,
    output reg [31:0] sd_sector,
    input             sd_ack,
    input             sd_done,
    input             outen,
    input      [8:0]  outaddr,
    input      [7:0]  outbyte,
    output     [7:0]  inbyte,

    output            busy
);

//------------------------------------------------------------------------
// The image
//------------------------------------------------------------------------
reg  [31:0] sectors = 32'd0;
assign present = (sectors != 32'd0);
wire [15:0] cyls = sectors[24:9];          // 16 heads x 32 sectors a cylinder
always @(posedge clk) if (mounted) sectors <= {9'd0, image_size[31:9]};

//------------------------------------------------------------------------
// The registers
//------------------------------------------------------------------------
reg  [7:0] r_error = 8'h01, r_features = 8'd0, r_count = 8'd1, r_sector = 8'd1;
reg  [7:0] r_cyl_l = 8'd0, r_cyl_h = 8'd0, r_drive = 8'hA0;
reg        s_bsy = 1'b0, s_drq = 1'b0, s_err = 1'b0;
wire [7:0] status = {s_bsy, present, 1'b0, present, s_drq, 1'b0, 1'b0, s_err};
wire       slave  = r_drive[4];
wire       lba    = r_drive[6];
assign busy = s_bsy;

// the sector addressed: LBA, or CHS with 16 x 32
wire [27:0] lba_adr = {r_drive[3:0], r_cyl_h, r_cyl_l, r_sector};
wire [31:0] chs_adr = {7'd0, r_cyl_h, r_cyl_l, r_drive[3:0], 5'd0} + {24'd0, r_sector} - 32'd1;
wire [31:0] cur_adr = lba ? {4'd0, lba_adr} : chs_adr;

// the address stepped after a sector
wire [7:0]  n_sector = lba ? r_sector + 8'd1 : ((r_sector == 8'd32) ? 8'd1 : r_sector + 8'd1);
wire        s_wrap   = !lba && (r_sector == 8'd32);
wire [3:0]  n_head   = s_wrap ? ((r_drive[3:0] == 4'd15) ? 4'd0 : r_drive[3:0] + 4'd1) : r_drive[3:0];
wire        h_wrap   = s_wrap && (r_drive[3:0] == 4'd15);
wire [15:0] n_cyl    = h_wrap ? {r_cyl_h, r_cyl_l} + 16'd1 : {r_cyl_h, r_cyl_l};
wire [27:0] n_lba    = lba_adr + 28'd1;

localparam [3:0] S_IDLE = 4'd0, S_ID = 4'd1, S_RD_FETCH = 4'd2, S_RD_DATA = 4'd3,
                 S_WR_DATA = 4'd4, S_WR_STORE = 4'd5, S_NEXT = 4'd6;
reg [3:0] state = S_IDLE;

//------------------------------------------------------------------------
// The buffer: 256 words in two byte-wide BSRAMs, one write port and one
// read port each.  The SD side and the host never use it at once (BSY
// for one, DRQ for the other), so the read address is the SD side's
// while a sector moves and the host's word index otherwise; both read
// a clock behind.  The write comes from one of three sources - the SD
// side a byte at a time, IDENTIFY's generator, the host's data register
// - one at a time by the same argument.
//------------------------------------------------------------------------
reg [7:0] buf_lo [0:255];
reg [7:0] buf_hi [0:255];
reg [8:0] widx = 9'd0;              // the host's word index
reg       is_write = 1'b0;
reg       id_fill = 1'b0;
reg [8:0] id_i = 9'd0;
reg       xfer = 1'b0;              // a sector is moving on the SD side

wire        host_wr = stb && !ctrl && we && !slave && (reg_a == 3'd0) && s_drq && (state == S_WR_DATA);
wire        sd_in   = outen && sd_ack && !is_write;
wire [7:0]  w_adr   = id_fill ? id_i[7:0] : sd_in ? outaddr[8:1] : widx[7:0];
wire [15:0] w_data  = id_fill ? id_word : sd_in ? {outbyte, outbyte} : wdata;
wire        w_lo    = id_fill || host_wr || (sd_in && !outaddr[0]);
wire        w_hi    = id_fill || host_wr || (sd_in &&  outaddr[0]);
wire [7:0]  r_adr   = xfer ? outaddr[8:1] : widx[7:0];
reg  [7:0]  q_lo = 8'd0, q_hi = 8'd0;
always @(posedge clk) begin
    if (w_lo) buf_lo[w_adr] <= w_data[7:0];
    if (w_hi) buf_hi[w_adr] <= w_data[15:8];
    q_lo <= buf_lo[r_adr];
    q_hi <= buf_hi[r_adr];
end
assign inbyte = outaddr[0] ? q_hi : q_lo;
wire [15:0] buf_word = {q_hi, q_lo};

// IDENTIFY's words, generated into the buffer
reg  [15:0] id_word;
function [15:0] ascii2(input [7:0] a, input [7:0] b); ascii2 = {a, b}; endfunction
always @(*) begin
    case (id_i[7:0])
        8'd0:  id_word = 16'h0040;          // fixed disk
        8'd1:  id_word = cyls;
        8'd3:  id_word = 16'd16;
        8'd6:  id_word = 16'd32;
        8'd10: id_word = ascii2("Z", "S"); 8'd11: id_word = ascii2("2", "5"); 8'd12: id_word = ascii2("6", " ");
        8'd13, 8'd14, 8'd15, 8'd16, 8'd17, 8'd18, 8'd19: id_word = ascii2(" ", " ");
        8'd23: id_word = ascii2("1", ".");  8'd24: id_word = ascii2("0", " ");
        8'd25, 8'd26: id_word = ascii2(" ", " ");
        8'd27: id_word = ascii2("T", "a"); 8'd28: id_word = ascii2("n", "g"); 8'd29: id_word = ascii2(" ", "Z");
        8'd30: id_word = ascii2("S", "2"); 8'd31: id_word = ascii2("5", "6"); 8'd32: id_word = ascii2(" ", "S");
        8'd33: id_word = ascii2("M", "U"); 8'd34: id_word = ascii2("C", " "); 8'd35: id_word = ascii2("d", "i");
        8'd36: id_word = ascii2("s", "k");
        8'd37, 8'd38, 8'd39, 8'd40, 8'd41, 8'd42, 8'd43, 8'd44, 8'd45, 8'd46: id_word = ascii2(" ", " ");
        8'd47: id_word = 16'h8001;          // one sector a block
        8'd49: id_word = 16'h0200;          // LBA
        8'd51: id_word = 16'h0200;          // PIO 2
        8'd53: id_word = 16'h0001;          // words 54-58 valid
        8'd54: id_word = cyls;
        8'd55: id_word = 16'd16;
        8'd56: id_word = 16'd32;
        8'd57: id_word = sectors[15:0];
        8'd58: id_word = sectors[31:16];
        8'd59: id_word = 16'h0101;
        8'd60: id_word = sectors[15:0];
        8'd61: id_word = sectors[31:16];
        default: id_word = 16'h0000;
    endcase
end

task step_address;
    begin
        if (lba) {r_drive[3:0], r_cyl_h, r_cyl_l, r_sector} <= n_lba;
        else begin r_sector <= n_sector; r_drive[3:0] <= n_head; {r_cyl_h, r_cyl_l} <= n_cyl; end
    end
endtask

always @(posedge clk) begin
    if (id_fill) begin
        id_i <= id_i + 9'd1;
        if (id_i == 9'd255) begin id_fill <= 1'b0; s_bsy <= 1'b0; s_drq <= 1'b1; state <= S_RD_DATA; widx <= 9'd0; end
    end

    if (reset) begin
        state <= S_IDLE; s_bsy <= 1'b0; s_drq <= 1'b0; s_err <= 1'b0; r_error <= 8'h01;
        r_count <= 8'd1; r_sector <= 8'd1; r_cyl_l <= 8'd0; r_cyl_h <= 8'd0; r_drive <= 8'hA0;
        sd_rd <= 1'b0; sd_wr <= 1'b0; id_fill <= 1'b0; widx <= 9'd0; is_write <= 1'b0; xfer <= 1'b0;
    end else begin
        if (sd_ack) begin sd_rd <= 1'b0; sd_wr <= 1'b0; end
        if (sd_rd || sd_wr) xfer <= 1'b1;
        if (sd_done) xfer <= 1'b0;

        // the register file
        if (stb && !ctrl && we && !slave) begin
            case (reg_a)
                3'd0: if (s_drq && state == S_WR_DATA) begin
                    widx <= widx + 9'd1;
                    if (widx == 9'd255) begin
                        s_drq <= 1'b0; s_bsy <= 1'b1; state <= S_WR_STORE;
                        sd_sector <= cur_adr; sd_wr <= 1'b1;
                    end
                end
                3'd1: r_features <= wdata[7:0];
                3'd2: r_count    <= wdata[7:0];
                3'd3: r_sector   <= wdata[7:0];
                3'd4: r_cyl_l    <= wdata[7:0];
                3'd5: r_cyl_h    <= wdata[7:0];
                3'd6: r_drive    <= wdata[7:0];
                3'd7: if (!s_bsy) begin
                    s_err <= 1'b0; r_error <= 8'd0; s_drq <= 1'b0;
                    case (wdata[7:0])
                        8'hEC: begin s_bsy <= 1'b1; id_fill <= 1'b1; id_i <= 9'd0; state <= S_ID; is_write <= 1'b0; end
                        8'h20, 8'h21, 8'hC4: begin
                            s_bsy <= 1'b1; is_write <= 1'b0; state <= S_RD_FETCH;
                            sd_sector <= cur_adr; sd_rd <= 1'b1;
                        end
                        8'h30, 8'h31, 8'hC5: begin
                            is_write <= 1'b1; widx <= 9'd0; s_drq <= 1'b1; state <= S_WR_DATA;
                        end
                        8'h40, 8'h41, 8'h91, 8'h70, 8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE5, 8'hE6, 8'hE7, 8'hEA, 8'hEF, 8'hC6,
                        8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
                        8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F: ;
                        default: begin s_err <= 1'b1; r_error <= 8'h04; end
                    endcase
                end
            endcase
        end
        if (stb && ctrl && we && wdata[2]) begin       // SRST
            state <= S_IDLE; s_bsy <= 1'b0; s_drq <= 1'b0; s_err <= 1'b0; r_error <= 8'h01;
            r_count <= 8'd1; r_sector <= 8'd1; r_cyl_l <= 8'd0; r_cyl_h <= 8'd0; r_drive <= 8'hA0;
        end
        if (stb && !ctrl && !we && reg_a == 3'd0 && s_drq && state == S_RD_DATA) begin
            widx <= widx + 9'd1;
            if (widx == 9'd255) begin
                s_drq <= 1'b0;
                if (r_count == 8'd1 || id_i != 9'd0) begin state <= S_IDLE; id_i <= 9'd0; end
                else begin
                    r_count <= r_count - 8'd1; step_address; s_bsy <= 1'b1;
                    state <= S_NEXT;
                end
            end
        end

        case (state)
            S_NEXT: begin sd_sector <= cur_adr; sd_rd <= 1'b1; state <= S_RD_FETCH; end
            S_RD_FETCH: if (sd_done) begin s_bsy <= 1'b0; s_drq <= 1'b1; widx <= 9'd0; state <= S_RD_DATA; end
            S_WR_STORE: if (sd_done) begin
                s_bsy <= 1'b0;
                if (r_count == 8'd1) state <= S_IDLE;
                else begin r_count <= r_count - 8'd1; step_address; widx <= 9'd0; s_drq <= 1'b1; state <= S_WR_DATA; end
            end
            default: ;
        endcase
        if (!present && state != S_IDLE && !id_fill) begin state <= S_IDLE; s_bsy <= 1'b0; s_drq <= 1'b0; end
    end
end

// the readback (the data word a clock behind the strobe, as the buffer reads)
always @(*) begin
    if (slave) rdata = 16'h0000;
    else if (ctrl) rdata = reg_a[0] ? 16'h00FF : {8'd0, status};
    else case (reg_a)
        3'd0: rdata = buf_word;
        3'd1: rdata = {8'd0, r_error};
        3'd2: rdata = {8'd0, r_count};
        3'd3: rdata = {8'd0, r_sector};
        3'd4: rdata = {8'd0, r_cyl_l};
        3'd5: rdata = {8'd0, r_cyl_h};
        3'd6: rdata = {8'd0, r_drive};
        default: rdata = {8'd0, status};
    endcase
end

endmodule
