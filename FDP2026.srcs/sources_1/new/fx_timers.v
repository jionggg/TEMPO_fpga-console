`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// fx_timers - keep each judgement visible long enough to see (Ji Yong)
//
// Pei Ling's judge_pulse lasts one 100 MHz clock: 10 ns, far too short for an eye.
// This works like a stairwell light on a timer: the pulse presses the button,
// and the light stays on for FX_MS (250 ms), then goes off by itself. A new
// pulse restarts the timer. The grade and lane are remembered while it is on.
//
// Three timers: piano judgement, drum judgement, and the sync flash (gold hit line and
// the SYNC'D word, which also remembers whether the duet was PERFECT + PERFECT).
// Plus one small timer per lane (5 piano + 3 drum) for the hit sprites, started only
// by a real hit (PERFECT or GOOD), so two quick hits in different lanes both show.
// Plus one per score: the score turns green for 250 ms each time it goes up.
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
    input             sync_perfect,     // with sync_pulse: both halves were PERFECT
    // from display_top: a score just went up (1 clk)
    input             pno_up,
    input             drm_up,
    // what to show
    output            pno_fx_on,        // piano judgement is showing
    output reg [1:0]  pno_fx_grade = 0,
    output reg [2:0]  pno_fx_lane  = 0,
    output            drm_fx_on,        // drum judgement is showing
    output reg [1:0]  drm_fx_grade = 0,
    output reg [2:0]  drm_fx_lane  = 0,
    output            sync_fx_on,       // gold hit line and SYNC'D are showing
    output reg        sync_fx_perfect = 0,  // ... green SYNC'D (1) or orange (0)
    output     [4:0]  pno_spr_on,       // bit L = piano lane L's hit sprite is showing
    output     [2:0]  drm_spr_on,       // bit L = drum lane L's hit sprite is showing
    output            pno_flash,        // pianist's score is green
    output            drm_flash         // drummer's score is green
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
            if (sync_pulse && sync_ok) begin
                sync_left       <= FX_MS;
                sync_fx_perfect <= sync_perfect;
            end else if (ms_tick && sync_left != 0)
                sync_left <= sync_left - 1;
        end
    end

    assign pno_fx_on  = (pno_left  != 0);
    assign drm_fx_on  = (drm_left  != 0);
    assign sync_fx_on = (sync_left != 0);

    // ---- hit sprites: one stairwell light per lane ----
    `include "TEMPO_defs.vh"       // GRADE_MISS
    wire hit   = judge_pulse && (judge_grade != GRADE_MISS);   // a real hit
    wire p_hit = hit && (judge_player == 1'b0);
    wire d_hit = hit && (judge_player == 1'b1);

    lane_timer p0 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(p_hit && judge_lane == 3'd0), .on(pno_spr_on[0]));
    lane_timer p1 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(p_hit && judge_lane == 3'd1), .on(pno_spr_on[1]));
    lane_timer p2 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(p_hit && judge_lane == 3'd2), .on(pno_spr_on[2]));
    lane_timer p3 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(p_hit && judge_lane == 3'd3), .on(pno_spr_on[3]));
    lane_timer p4 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(p_hit && judge_lane == 3'd4), .on(pno_spr_on[4]));
    lane_timer d0 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(d_hit && judge_lane == 3'd0), .on(drm_spr_on[0]));
    lane_timer d1 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(d_hit && judge_lane == 3'd1), .on(drm_spr_on[1]));
    lane_timer d2 (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(d_hit && judge_lane == 3'd2), .on(drm_spr_on[2]));

    // ---- score flashes: the same kind of stairwell light, one per score ----
    lane_timer fp (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(pno_up), .on(pno_flash));
    lane_timer fd (.clk(clk), .rst(rst), .ms_tick(ms_tick), .start(drm_up), .on(drm_flash));

endmodule


//////////////////////////////////////////////////////////////////////////////////
// lane_timer - one stairwell light: on for FX_MS after `start`, restarted by a new start
//////////////////////////////////////////////////////////////////////////////////

module lane_timer (
    input  clk,
    input  rst,
    input  ms_tick,
    input  start,
    output on
    );

    `include "TEMPO_layout.vh"     // FX_MS

    reg [7:0] left = 0;            // ms left (250 fits in 8 bits)

    always @(posedge clk) begin
        if (rst)                         left <= 0;
        else if (start)                  left <= FX_MS;
        else if (ms_tick && left != 0)   left <= left - 1;
    end

    assign on = (left != 0);

endmodule
