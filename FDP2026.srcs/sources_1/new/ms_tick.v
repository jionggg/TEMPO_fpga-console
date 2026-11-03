`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.10.2026 02:06:50
// Design Name: 
// Module Name: ms_tick
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
// ms_tick - 1 kHz time base.
// Emits a one-clock `tick` pulse every CLKS_PER_MS clock cycles.
// 100 MHz clock -> CLKS_PER_MS = 100_000.
// ============================================================================
module ms_tick #(
    parameter integer CLKS_PER_MS = 100_000
)(
    input  wire clk,
    input  wire rst,
    output reg  tick
);
    localparam integer W = (CLKS_PER_MS > 1) ? $clog2(CLKS_PER_MS) : 1;
    reg [W-1:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt  <= {W{1'b0}};
            tick <= 1'b0;
        end
        else if (cnt == CLKS_PER_MS - 1) begin
            cnt  <= {W{1'b0}};
            tick <= 1'b1;
        end
        else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end
endmodule
