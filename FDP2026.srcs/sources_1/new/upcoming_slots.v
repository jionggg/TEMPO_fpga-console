`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 11:03:26
// Design Name: 
// Module Name: upcoming_slots
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// ============================================================================
// upcoming_slots: the next 8 tiles for one screen, oldest (soonest) in slot 0.
// Tiles arrive from pattern_gen in time order, so the list is a shift queue:
//   spawn  -> written into the first empty slot (if all 8 are full, the oldest
//             slot is dropped first; it is already past the hit line)
//   expire -> slot 0 leaves KEEP_MS after its hit time; the rest shift down
// ============================================================================
module upcoming_slots #(
    parameter integer KEEP_MS = 300          // = D's LATE_MS: missed tile keeps falling
)(
    input              clk,
    input              clear,
    input  [17:0]      song_time_ms,
    input              spawn,
    input  [17:0]      spawn_time,
    input  [2:0]       spawn_lane,
    input              spawn_sync,
    output [7:0]       ev_valid,
    output [8*18-1:0]  ev_time,
    output [8*3-1:0]   ev_lane,
    output [7:0]       ev_sync
    );

    reg [17:0] t  [0:7];
    reg [2:0]  ln [0:7];
    reg        sy [0:7];
    reg [3:0]  count = 4'd0;                 // slots in use, 0..8

    wire expire = (count != 4'd0) &&
                  ({14'd0, song_time_ms} > ({14'd0, t[0]} + KEEP_MS));
    wire shift  = expire || (spawn && (count == 4'd8));
    wire [3:0] count_kept = shift ? (count - 4'd1) : count;   // after dropping slot 0

    integer i;
    always @(posedge clk) begin
        if (clear) begin
            count <= 4'd0;
        end else begin
            if (shift) begin
                for (i = 0; i < 7; i = i + 1) begin
                    t[i]  <= t[i+1];
                    ln[i] <= ln[i+1];
                    sy[i] <= sy[i+1];
                end
            end
            if (spawn) begin                  // written after the shift (last write wins)
                t[count_kept[2:0]]  <= spawn_time;
                ln[count_kept[2:0]] <= spawn_lane;
                sy[count_kept[2:0]] <= spawn_sync;
            end
            count <= count_kept + (spawn ? 4'd1 : 4'd0);
        end
    end

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : pack
            assign ev_valid[g]          = (count > g);
            assign ev_time[g*18 +: 18]  = t[g];
            assign ev_lane[g*3 +: 3]    = ln[g];
            assign ev_sync[g]           = sy[g];
        end
    endgenerate

endmodule

