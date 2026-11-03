`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.10.2026 02:02:52
// Design Name: 
// Module Name: countdown_timer
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
// countdown_timer - 3, 2, 1, GO
//
// While `enable` is low it parks at the start value (3) and does nothing.
// While `enable` is high it shows 3, 2, 1 for COUNTDOWN_STEP_MS each, then GO
// for GO_DISPLAY_MS (GO_DISPLAY_MS must be >= 1), then pulses `done` once.
//
//   num[1:0] : 3, 2, 1, or 0 = GO        (sent to the OLED via game_fsm)
//   go       : high while GO is shown (num == 0)
//   done     : ONE-clock pulse when the GO display has finished
//
// Runs on the 100 MHz clock; time advances on the shared 1 kHz tick_1ms.
// ============================================================================
module countdown_timer (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_1ms,
    input  wire       enable,

    output reg  [1:0] num,
    output wire       go,
    output reg        done
);
    `include "TEMPO_defs.vh"

    assign go = (num == 2'd0);

    // ms spent on the current number / on GO (reuses the generic timer)
    wire [15:0] phase_ms;
    wire step_end = go ? (phase_ms == GO_DISPLAY_MS      - 1)
                       : (phase_ms == COUNTDOWN_STEP_MS  - 1);
    wire advance  = enable && tick_1ms && step_end;

    ms_timer #(.WIDTH(16)) u_phase_timer (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms),
        .clear(!enable || advance),
        .run(enable),
        .count(phase_ms)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            num  <= COUNTDOWN_SECONDS;
            done <= 1'b0;
        end
        else begin
            done <= 1'b0;
            if (!enable)
                num <= COUNTDOWN_SECONDS;          // park at 3
            else if (advance) begin
                if (go)
                    done <= 1'b1;                  // GO finished
                else
                    num <= num - 2'd1;
            end
        end
    end
endmodule

