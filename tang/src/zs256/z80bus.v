`timescale 1ns / 1ps
//========================================================================
// z80bus.v - a Z80 (tv80) on an enable, with its bus as a request.
//
// Two of these run the machine: the Scorpion's own Z80 (3.5 MHz, or 7 in
// turbo) and the General Sound's (14 MHz, paced by its memory).  Both
// are tv80 (Guy Hutchison's Verilog of Daniel Wallner's T80, MIT,
// verbatim) clocked by the one 42 MHz clock with a T-state enable `cen`
// from top.v, and this wrapper turns the core's cycle signals into one
// request at a time that the rest of the design answers when it can:
//
//   req      a level from the start of T2 until the cycle is served
//   io       the cycle is an I/O cycle (else memory)
//   we       a write; `dout` holds the byte from the request on (the
//            core's own register, steady until its next T1)
//   m1       an opcode fetch (memory), or an interrupt acknowledge (I/O)
//   A        the address, standing from T1 to the end of the cycle
//   ack      one clock from outside: a read's byte is on `din` now and
//            stays until the next ack; a write has been taken
//
// WAIT is held from the request until the ack, and tv80 samples it at
// the end of T2 as the chip does, so a cycle served inside T2 costs
// nothing and one served later costs whole T-states.  Where the answer
// comes from in each T-state is top.v's business (the SDRAM's slots are
// one clock after the enable, so a memory cycle that begins on the
// slot's T-state is served in the same T-state - membus.v).  tv80 takes
// the byte at the END of T2, not in T3 as the chip does; the difference
// is invisible from outside.
//
// The bus signals are tv80s.v's (rd_n/wr_n/mreq_n/iorq_n registered on
// the enable, WR/ from T2 - its T2Write = 1), folded into the request;
// IOWait = 1 gives an I/O cycle the chip's automatic wait state.
//========================================================================
module z80bus (
    input             clk,
    input             reset,        // active high
    input             cen,          // the T-state enable

    output reg [15:0] A,
    output     [7:0]  dout,
    input      [7:0]  din,
    output reg        req,
    output reg        io,
    output reg        we,
    output reg        m1,
    input             ack,

    input             int_n,
    input             nmi_n,
    output            halt_n,
    output            rfsh_n,
    output            iff1,         // interrupts enabled (for the OSD's debug)

    // the core's view, for the testbench
    output     [15:0] pc_now,       // the address bus as the core drives it
    output            m1_now
);

wire        m1_n, iorq, no_read, write, intcycle_n;
wire [15:0] core_a;
wire [7:0]  core_dout;
wire [6:0]  mcycle, tstate;
reg  [7:0]  di_reg = 8'd0;
reg  [7:0]  dreg   = 8'hFF;      // the last byte read
wire        wait_n = !req;       // served = the request is gone

tv80_core #(.Mode(0), .IOWait(1)) core (
    .cen       (cen        ),
    .m1_n      (m1_n       ),
    .iorq      (iorq       ),
    .no_read   (no_read    ),
    .write     (write      ),
    .rfsh_n    (rfsh_n     ),
    .halt_n    (halt_n     ),
    .wait_n    (wait_n     ),
    .int_n     (int_n      ),
    .nmi_n     (nmi_n      ),
    .reset_n   (~reset     ),
    .busrq_n   (1'b1       ),
    .busak_n   (           ),
    .clk       (clk        ),
    .IntE      (iff1       ),
    .stop      (           ),
    .A         (core_a     ),
    .dinst     (dreg       ),
    .di        (di_reg     ),
    .dout      (core_dout  ),
    .mc        (mcycle     ),
    .ts        (tstate     ),
    .intcycle_n(intcycle_n )
);

// the core sets dout on the enable that ends T1 - the one this latches
// the request on - so the byte is taken live: it stands until the next T1
assign dout   = core_dout;
assign pc_now = core_a;
assign m1_now = !m1_n;

// The request: raised on the enable that ends T1 (tv80s.v raises rd_n
// or wr_n there), for an M1 fetch, an interrupt acknowledge (M1 with
// IORQ), a read or a write; held through the wait states; dropped by
// the ack.  A cycle with neither read nor write (no_read: the second
// half of a refresh, an internal cycle) asks nothing.  The core holds
// T1 for an extra enable in an I/O cycle and two in an interrupt
// acknowledge (its IOWait: tstate does not advance while Auto_Wait_t1
// is clear), so a request is raised once an M-cycle - `armed` from the
// request until T1 is over - or an IN would read its port twice.
wire t1  = tstate[1];
wire m1c = mcycle[0];
wire ask_m1  = m1c;                                  // opcode fetch, or INTA
wire ask_rd  = !m1c && !no_read && !write;
wire ask_wr  = !m1c && write;
reg  armed = 1'b0;

always @(posedge clk) begin
    if (reset) begin
        req <= 1'b0; io <= 1'b0; we <= 1'b0; m1 <= 1'b0; A <= 16'd0;
        di_reg <= 8'd0; dreg <= 8'hFF; armed <= 1'b0;
    end else begin
        if (ack) begin
            req  <= 1'b0;
            if (!we) dreg <= din;
        end
        if (cen) begin
            if (!t1) armed <= 1'b0;
            if (t1 && !armed && (ask_m1 || ask_rd || ask_wr)) begin
                req  <= 1'b1;
                armed <= 1'b1;
                A    <= core_a;
                m1   <= ask_m1;
                io   <= ask_m1 ? !intcycle_n : iorq;
                we   <= ask_wr;
            end
            // the byte for the core's data path, as tv80s.v latches it
            if (tstate[2] && wait_n) di_reg <= dreg;
        end
    end
end

endmodule
