`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// fx_timers - keep each judgement visible long enough to see (Ji Yong)
//
// Pei Ling's judge_pulse lasts one 100 MHz clock: 10 ns, far too short for an eye.
// This works like a stairwell light on a timer: the pulse presses the button,
// and the light stays on for FX_MS (250 ms), then goes off by itself. A new
// pulse restarts the timer. The grade and lane are remembered while it is on.
//
// Three timers: piano judgement, drum judgement, and the sync flash.
//////////////////////////////////////////////////////////////////////////////////

module fx_timers (
    input             clk,              // 100 MHz
    input             rst,
    input             ms_tick,          // 1-cycle pulse every 1 ms
    // from Pei Ling (or mock_feed)
    input             judge_pulse,      // 1 clk per judgement
    input             judge_player,     // 0 piano, 1 drum
    input      [1:0]  judge_grade,      // GRADE_MISS / GOOD / PERFECT
    input      [2:0]  judge_lane,
    input             sync_pulse,       // 1 clk per sync pair judged
    input             sync_ok,          // 1 = the pair was in sync
    // what to show
    output            pno_fx_on,        // piano judgement is showing
    output reg [1:0]  pno_fx_grade = 0,
    output reg [2:0]  pno_fx_lane  = 0,
    output            drm_fx_on,        // drum judgement is showing
    output reg [1:0]  drm_fx_grade = 0,
    output reg [2:0]  drm_fx_lane  = 0,
    output            sync_fx_on        // gold hit line is showing
    );

    `include "TEMPO_layout.vh"     // FX_MS

    reg [7:0] pno_left  = 0;        // ms left on each timer (250 fits in 8 bits)
    reg [7:0] drm_left  = 0;
    reg [7:0] sync_left = 0;

    always @(posedge clk) begin
        if (rst) begin
            pno_left  <= 0;
            drm_left  <= 0;
            sync_left <= 0;
        end else begin
            // piano: a new judgement restarts the timer, otherwise count down each ms
            if (judge_pulse && judge_player == 1'b0) begin
                pno_left     <= FX_MS;
                pno_fx_grade <= judge_grade;
                pno_fx_lane  <= judge_lane;
            end else if (ms_tick && pno_left != 0)
                pno_left <= pno_left - 1;

            // drum: the same
            if (judge_pulse && judge_player == 1'b1) begin
                drm_left     <= FX_MS;
                drm_fx_grade <= judge_grade;
                drm_fx_lane  <= judge_lane;
            end else if (ms_tick && drm_left != 0)
                drm_left <= drm_left - 1;

            // sync: only a successful pair lights the hit lines
            if (sync_pulse && sync_ok)
                sync_left <= FX_MS;
            else if (ms_tick && sync_left != 0)
                sync_left <= sync_left - 1;
        end
    end

    assign pno_fx_on  = (pno_left  != 0);
    assign drm_fx_on  = (drm_left  != 0);
    assign sync_fx_on = (sync_left != 0);

endmodule
