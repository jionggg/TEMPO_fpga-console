`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// bin2bcd - turn a score (binary, 0..65535) into 5 decimal digits (Ji Yong)
//
// Works like counting out change: take away 10000s until less than 10000 is
// left, counting how many you took. Then 1000s, 100s, 10s. What is left is the
// ones digit. One subtraction per clock, so a whole number takes at most
// ~40 clocks (0.4 us at 100 MHz), far quicker than the eye can see.
// It never stops: as soon as it finishes, it starts again on the newest value.
//
//   digits[19:16] ten-thousands   digits[15:12] thousands   digits[11:8] hundreds
//   digits[7:4]   tens            digits[3:0]   ones
//////////////////////////////////////////////////////////////////////////////////

module bin2bcd (
    input             clk,          // 100 MHz
    input      [15:0] value,        // the number to show
    output reg [19:0] digits = 0    // its 5 decimal digits, 4 bits each
    );

    reg [15:0] rest  = 0;           // what is still left to count out
    reg [2:0]  place = 0;           // 0: 10000s, 1: 1000s, 2: 100s, 3: 10s, 4: done
    reg [3:0]  n4 = 0, n3 = 0, n2 = 0, n1 = 0;     // how many of each so far

    always @(posedge clk) begin
        case (place)
            3'd0: if (rest >= 10000) begin rest <= rest - 10000; n4 <= n4 + 1; end
                  else place <= 3'd1;
            3'd1: if (rest >= 1000)  begin rest <= rest - 1000;  n3 <= n3 + 1; end
                  else place <= 3'd2;
            3'd2: if (rest >= 100)   begin rest <= rest - 100;   n2 <= n2 + 1; end
                  else place <= 3'd3;
            3'd3: if (rest >= 10)    begin rest <= rest - 10;    n1 <= n1 + 1; end
                  else place <= 3'd4;
            default: begin
                digits <= {n4, n3, n2, n1, rest[3:0]};   // publish the finished answer
                rest   <= value;                           // start on the newest value
                n4 <= 0;  n3 <= 0;  n2 <= 0;  n1 <= 0;
                place  <= 3'd0;
            end
        endcase
    end

endmodule
