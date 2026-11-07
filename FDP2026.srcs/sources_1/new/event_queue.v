
`timescale 1ns / 1ps

// FIFO for expected events awaiting judgement.
module event_queue #(
    parameter integer DEPTH = 64
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,
    input  wire        push,
    input  wire [17:0] push_time_ms,
    input  wire [5:0]  push_id,
    input  wire        push_is_drum,
    input  wire [3:0]  push_note,
    input  wire        pop,

    output wire        head_valid,
    output wire [17:0] head_time_ms,
    output wire [5:0]  head_id,
    output wire        head_is_drum,
    output wire [3:0]  head_note,
    output wire        full
);
    reg [17:0] time_mem [0:DEPTH-1];
    reg [5:0]  id_mem   [0:DEPTH-1];
    reg        drum_mem [0:DEPTH-1];
    reg [3:0]  note_mem [0:DEPTH-1];

    reg [5:0] read_ptr;
    reg [5:0] write_ptr;
    reg [6:0] item_count;

    wire do_push = push && !full;
    wire do_pop  = pop && (item_count != 0);

    assign head_valid   = (item_count != 0);
    assign head_time_ms = time_mem[read_ptr];
    assign head_id      = id_mem[read_ptr];
    assign head_is_drum = drum_mem[read_ptr];
    assign head_note    = note_mem[read_ptr];
    assign full         = (item_count == DEPTH);

    // memories: written on a push, never reset (LUT RAM)
    always @(posedge clk) begin
        if (do_push && !rst && !clear) begin
            time_mem[write_ptr] <= push_time_ms;
            id_mem[write_ptr]   <= push_id;
            drum_mem[write_ptr] <= push_is_drum;
            note_mem[write_ptr] <= push_note;
        end
    end

    // pointers and count
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_ptr   <= 6'd0;
            write_ptr  <= 6'd0;
            item_count <= 7'd0;
        end
        else if (clear) begin
            read_ptr   <= 6'd0;
            write_ptr  <= 6'd0;
            item_count <= 7'd0;
        end
        else begin
            if (do_push)
                write_ptr <= write_ptr + 6'd1;

            if (do_pop)
                read_ptr <= read_ptr + 6'd1;

            case ({do_push, do_pop})
                2'b10: item_count <= item_count + 7'd1;
                2'b01: item_count <= item_count - 7'd1;
                default: item_count <= item_count;
            endcase
        end
    end
endmodule