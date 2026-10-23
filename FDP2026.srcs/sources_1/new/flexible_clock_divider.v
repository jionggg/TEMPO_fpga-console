`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.10.2026 10:15:17
// Design Name: 
// Module Name: flexible_clock_divider
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

module flexible_clock_divider(
    input basys_clock,
    output reg slower_clock = 0,
    output [31:0] my_m_value
    );
    
    reg [31:0] count = 0;
    
    always @ (posedge basys_clock)
    begin 
        count <= (count == my_m_value) ? 0 : count+1;
        slower_clock <= (count == 0) ? ~slower_clock : slower_clock;
    end
    
endmodule