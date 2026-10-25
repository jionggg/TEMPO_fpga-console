`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 15:48:39
// Design Name: 
// Module Name: tick_gen
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

// A "tick" is a clock-enable, not a clock: 
//      tick is high for exactly ONE 100 MHz cycle out of every N. 
// Logic that should act once per ms stays on the 100 MHz clock, for eg:
//     always @(posedge clk) if (ms_tick) song_time_ms <= song_time_ms + 1;

// Everyone sees the same tick on the same clock, so modules never drift apart.

//   N = 100_000 -> one tick per 1 ms   (made once in My_Top_Module: ms_tick)
//////////////////////////////////////////////////////////////////////////////////

module tick_gen #(parameter N = 100_000) (
    input      clk,
    output reg tick = 0
    );

    reg [31:0] count = 0;

    always @(posedge clk) begin
        tick  <= (count == N - 1);
        count <= (count == N - 1) ? 0 : count + 1;
    end

endmodule

