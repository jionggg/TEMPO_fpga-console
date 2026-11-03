`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.11.2026 13:06:15
// Design Name: 
// Module Name: btn_debounce
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


`timescale 1ns / 1ps
// ============================================================================
// btn_debounce - push-button debouncer.
//   1. two-flop synchroniser (button is asynchronous to clk)
//   2. debounce: the synchronised input must differ from the current stable
//      level for DEBOUNCE_MS consecutive milliseconds before it is accepted
//   3. `pressed` is a ONE-clock pulse on each debounced press (rising edge)
// `level` is the debounced button level, if anyone needs it.
// ============================================================================
module btn_debounce #(
    parameter integer DEBOUNCE_MS = 10
)(
    input  wire clk,
    input  wire rst,
    input  wire tick_1ms,
    input  wire btn_in,
    output reg  pressed,
    output reg  level
);
    reg        s0, s1;
    reg [15:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s0      <= 1'b0;
            s1      <= 1'b0;
            level   <= 1'b0;
            cnt     <= 16'd0;
            pressed <= 1'b0;
        end
        else begin
            s0      <= btn_in;
            s1      <= s0;
            pressed <= 1'b0;

            if (s1 == level)
                cnt <= 16'd0;                  // input agrees, nothing pending
            else if (tick_1ms) begin
                if (cnt == DEBOUNCE_MS - 1) begin
                    level   <= s1;
                    pressed <= s1;             // pulse only on press, not release
                    cnt     <= 16'd0;
                end
                else
                    cnt <= cnt + 16'd1;
            end
        end
    end
endmodule
