`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.10.2026 11:30:37
// Design Name: 
// Module Name: oled_coordinates
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


module oled_coordinates (
    input wire basys_clk,
    input wire reset,
    input wire [12:0] pixel_number, 
    output reg [5:0] x_coord        
    );

    always @(posedge basys_clk or posedge reset) begin
        if (reset) begin
            x_coord <= 6'd0;
        end else begin
            x_coord <= pixel_number[5:0]; 
        end
    end

endmodule
