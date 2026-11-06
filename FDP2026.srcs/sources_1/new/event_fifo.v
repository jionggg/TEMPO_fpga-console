`timescale 1ns / 1ps
// Single-clock, first-word-fall-through FIFO. Reset is synchronous.
// A full FIFO accepts a new record when an old record is popped on the same edge.
/**
event_fifo: two independent 16-record detected-hit queues inside the engine;
simultaneous piano and drum reports are both retained. Full queues set sticky
det_overflow instead of silently overwriting a record.
**/

module event_fifo #(
    parameter integer WIDTH = 35,
    parameter integer ADDR_BITS = 4
)(
    input clk, input reset,
    input push, input [WIDTH-1:0] push_data, output ready,
    input pop, output [WIDTH-1:0] head, output empty
);
    localparam integer DEPTH = 1 << ADDR_BITS;
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_BITS-1:0] rd, wr;
    reg [ADDR_BITS:0] count;
    wire take = pop && !empty;
    wire put = push && ready;
    assign empty = count == 0;
    assign ready = (count < DEPTH) || take;
    assign head = mem[rd];
    // Memory has no reset, allowing distributed RAM inference.
    always @(posedge clk) begin
        if (!reset && put) mem[wr] <= push_data;
    end
    always @(posedge clk) begin
        if (reset) begin rd <= 0; wr <= 0; count <= 0; end
        else begin
            if (put) wr <= wr + 1'b1;
            if (take) rd <= rd + 1'b1;
            case ({put,take})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

