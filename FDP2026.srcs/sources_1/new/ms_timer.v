`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.11.2026 13:13:07
// Design Name: 
// Module Name: ms_timer
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
// ms_timer - reusable millisecond up-counter (song timer, countdown phase timer)
//
// Runs on the 100 MHz system clock and advances only on `tick_1ms`
// (a clock ENABLE, not a separate clock).
//   clear : synchronous clear to 0 (wins over run)
//   run   : count up by 1 on every tick_1ms while high
//   both low : count is frozen
// ============================================================================
module ms_timer #(
    parameter integer WIDTH = 18
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             tick_1ms,
    input  wire             clear,
    input  wire             run,
    output reg  [WIDTH-1:0] count
);
    always @(posedge clk or posedge rst) begin
        if (rst)
            count <= {WIDTH{1'b0}};
        else if (clear)
            count <= {WIDTH{1'b0}};
        else if (run && tick_1ms)
            count <= count + 1'b1;
    end
endmodule
