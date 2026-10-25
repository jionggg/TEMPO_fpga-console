`timescale 1ns / 1ps

// Member C: Meiyi - game intelligence
//   (game FSM + the one song clock, song ROM / LFSR, event queue, scoring, difficulty)
//
// PLACEHOLDER: the ports are the team interface; replace the body with your design.
// Inside, you can split it into game_fsm, pattern_gen and score_keeper as on the
// Miro UML. Keep every port on clk (100 MHz); use ms_tick to count milliseconds:
//     always @(posedge clk) if (ms_tick && game_state == 2) song_time_ms <= song_time_ms + 1;
// Buttons arrive raw (not debounced).

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 16:23:03
// Design Name: 
// Module Name: game_intel
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

module game_intel (
    input              clk,
    input              rst,
    input              ms_tick,
    input              btn_start,      // btnC
    input              btn_pause,      // btnU
    input              btn_quit,       // btnD
    // from Pei Ling
    input              judge_pulse,
    input              judge_player,
    input  [1:0]       judge_grade,
    input  [7:0]       judge_id,
    input              sync_pulse,
    input              sync_ok,
    // to everyone
    output [2:0]       game_state,     // 0 MENU, 1 COUNTDOWN, 2 PLAYING, 3 PAUSED, 4 RESULTS
    output [1:0]       countdown_num,  // 3, 2, 1, then 0 = GO
    output [17:0]      song_time_ms,
    output [17:0]      song_len_ms,
    // to Pei Ling: next expected event
    output             exp_valid,
    output [7:0]       exp_id,
    output             exp_is_drum,
    output [2:0]       exp_note,       // piano 0..4 or drum 0..2, see tempo_defs.vh
    output [17:0]      exp_time_ms,
    // to Ji Yong: next 8 events per screen, slot 0 = soonest
    output [7:0]       pno_ev_valid,
    output [8*18-1:0]  pno_ev_time,
    output [8*3-1:0]   pno_ev_lane,
    output [7:0]       pno_ev_sync,
    output [7:0]       drm_ev_valid,
    output [8*18-1:0]  drm_ev_time,
    output [8*3-1:0]   drm_ev_lane,    // 0 crash, 1 snare, 2 bass
    output [7:0]       drm_ev_sync,
    // to Ji Yong: scores
    output [15:0]      pno_score,
    output [15:0]      drm_score,
    output [7:0]       pno_combo,
    output [7:0]       drm_combo,
    output [1:0]       difficulty
    );

    `include "tempo_defs.vh"
    // Three drums: drum events now carry a lane (DRUM_CRASH / SNARE / BASS) in
    // drm_ev_lane and exp_note, chosen by your song ROM / LFSR patterns.

    assign game_state    = 3'd0;      // MENU
    assign countdown_num = 2'd0;
    assign song_time_ms  = 18'd0;
    assign song_len_ms   = 18'd0;

    assign exp_valid     = 1'b0;
    assign exp_id        = 8'd0;
    assign exp_is_drum   = 1'b0;
    assign exp_note      = 3'd0;
    assign exp_time_ms   = 18'd0;

    assign pno_ev_valid  = 8'd0;
    assign pno_ev_time   = {8*18{1'b0}};
    assign pno_ev_lane   = {8*3{1'b0}};
    assign pno_ev_sync   = 8'd0;
    assign drm_ev_valid  = 8'd0;
    assign drm_ev_time   = {8*18{1'b0}};
    assign drm_ev_lane   = {8*3{1'b0}};
    assign drm_ev_sync   = 8'd0;

    assign pno_score     = 16'd0;
    assign drm_score     = 16'd0;
    assign pno_combo     = 8'd0;
    assign drm_combo     = 8'd0;
    assign difficulty    = 2'd0;

endmodule
