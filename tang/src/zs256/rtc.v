`timescale 1ns / 1ps
//========================================================================
// rtc.v - the SMUC's clock chip, a DS12887 (MC146818): the time in BCD,
// a calendar, and 114 bytes of RAM.
//
// The chip's registers: 0 seconds, 2 minutes, 4 hours, 6 the day of the
// week (1..7), 7 the date, 8 the month, 9 the year (two digits), 1/3/5
// the alarm, 10 A, 11 B, 12 C, 13 D, 14..127 RAM.  What is here: the
// clock runs from the 42 MHz (a second is 42 000 000 clocks) in BCD
// with the calendar's month lengths and leap years, 24-hour, and can be
// set by writing the registers; A reads 20h (no update in progress,
// the 32 kHz divider), B what was written with bit 1 (24-hour) forced
// and bit 2 (binary) cleared, C the update-ended flag (bit 4) and
// clears it, D 80h (the battery is fine).  The RAM is 114 bytes in
// registers.  Nothing keeps time across a power cycle: the board has
// no battery and no clock, so it starts at 00:00:00 on 1 January 2000,
// a Saturday, until the software sets it - or the OSD does.
//========================================================================
module rtc (
    input             clk,
    input             reset,

    input             stb,          // one clock with the request
    input             we,
    input             sel_adr,      // 1: the address register, 0: the data
    input      [7:0]  wdata,
    output reg [7:0]  rdata
);

reg [6:0] adr = 7'd0;

// the time, BCD
reg [7:0] sec = 8'h00, min = 8'h00, hour = 8'h00, wday = 8'h07, date = 8'h01, month = 8'h01, year = 8'h00;
reg [7:0] alarm_s = 8'h00, alarm_m = 8'h00, alarm_h = 8'h00;
reg [7:0] reg_b = 8'h02;
reg       uf = 1'b0;
reg [7:0] ram [0:113];
integer i;
initial for (i = 0; i < 114; i = i + 1) ram[i] = 8'h00;

// a second
reg [25:0] tick = 26'd0;
wire       second = (tick == 26'd41999999);
always @(posedge clk) tick <= second ? 26'd0 : tick + 26'd1;

function [7:0] bcd_inc(input [7:0] v);
    bcd_inc = (v[3:0] == 4'd9) ? {v[7:4] + 4'd1, 4'd0} : v + 8'd1;
endfunction

// the month's last day, BCD
// 2000..2099: a year divisible by four (10 is 2 mod 4, so tens * 2 + ones)
wire [4:0] y4   = {year[7:4], 1'b0} + {1'b0, year[3:0]};
wire       leap = (y4[1:0] == 2'd0);
reg [7:0] last_day;
always @(*) case (month)
    8'h02: last_day = leap ? 8'h29 : 8'h28;
    8'h04, 8'h06, 8'h09, 8'h11: last_day = 8'h30;
    default: last_day = 8'h31;
endcase

always @(posedge clk) begin
    if (reset) begin
        adr <= 7'd0; uf <= 1'b0;
    end else begin
        if (second) begin
            uf <= 1'b1;
            if (sec == 8'h59) begin
                sec <= 8'h00;
                if (min == 8'h59) begin
                    min <= 8'h00;
                    if (hour == 8'h23) begin
                        hour <= 8'h00;
                        wday <= (wday == 8'h07) ? 8'h01 : wday + 8'd1;
                        if (date == last_day) begin
                            date <= 8'h01;
                            if (month == 8'h12) begin month <= 8'h01; year <= (year == 8'h99) ? 8'h00 : bcd_inc(year); end
                            else month <= bcd_inc(month);
                        end else date <= bcd_inc(date);
                    end else hour <= bcd_inc(hour);
                end else min <= bcd_inc(min);
            end else sec <= bcd_inc(sec);
        end
        if (stb && we) begin
            if (sel_adr) adr <= wdata[6:0];
            else case (adr)
                7'd0:  sec     <= wdata;
                7'd1:  alarm_s <= wdata;
                7'd2:  min     <= wdata;
                7'd3:  alarm_m <= wdata;
                7'd4:  hour    <= wdata;
                7'd5:  alarm_h <= wdata;
                7'd6:  wday    <= wdata;
                7'd7:  date    <= wdata;
                7'd8:  month   <= wdata;
                7'd9:  year    <= wdata;
                7'd11: reg_b   <= wdata;
                7'd10, 7'd12, 7'd13: ;
                default: ram[adr - 7'd14] <= wdata;
            endcase
        end
        if (stb && !we && !sel_adr && adr == 7'd12) uf <= 1'b0;
    end
end

always @(*) begin
    case (adr)
        7'd0:  rdata = sec;
        7'd1:  rdata = alarm_s;
        7'd2:  rdata = min;
        7'd3:  rdata = alarm_m;
        7'd4:  rdata = hour;
        7'd5:  rdata = alarm_h;
        7'd6:  rdata = wday;
        7'd7:  rdata = date;
        7'd8:  rdata = month;
        7'd9:  rdata = year;
        7'd10: rdata = 8'h20;
        7'd11: rdata = (reg_b & 8'hFB) | 8'h02;
        7'd12: rdata = {3'd0, uf, 4'd0};
        7'd13: rdata = 8'h80;
        default: rdata = ram[adr - 7'd14];
    endcase
end

endmodule
