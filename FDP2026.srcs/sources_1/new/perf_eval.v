`timescale 1ns / 1ps

// Member B: Pei Ling - performance evaluation (match hits, grade, sync judge)
//
// PLACEHOLDER: the ports are the team interface; replace the body with your design.
// Keep every port on clk (100 MHz). judge_pulse and sync_pulse are high for
// exactly one clk cycle per judgement.
//
// Proposed (not in the flowchart yet): song_time_ms lets you call a MISS when an
// expected event's window passes with no hit.


//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 16:22:51
// Design Name: 
// Module Name: perf_eval
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


module perf_eval (
    input         clk,
    input         rst,
    input  [2:0]  game_state,
    input  [17:0] song_time_ms,
    // from Annanya
    input         det_pulse,
    input         det_is_drum,
    input  [2:0]  det_note,
    input  [17:0] det_time_ms,
    // from Meiyi
    input         exp_valid,
    input  [7:0]  exp_id,
    input         exp_is_drum,
    input  [2:0]  exp_note,
    input  [17:0] exp_time_ms,
    // to Meiyi and Ji Yong
    output        judge_pulse,
    output        judge_player,   // 0 piano, 1 drum
    output [1:0]  judge_grade,    // 0 MISS, 1 GOOD, 2 PERFECT
    output [2:0]  judge_lane,     // piano 0..4, drum 0..2 (crash, snare, bass)
    output [7:0]  judge_id,
    output        sync_pulse,
    output        sync_ok
    );

    `include "tempo_defs.vh"
    // Three drums: a drum hit only matches an expected drum event if det_note == exp_note
    // (a snare hit on a bass-drum tile is a wrong note, just like a wrong piano key).

    assign judge_pulse  = 1'b0;
    assign judge_player = 1'b0;
    assign judge_grade  = 2'd0;
    assign judge_lane   = 3'd0;
    assign judge_id     = 8'd0;
    assign sync_pulse   = 1'b0;
    assign sync_ok      = 1'b0;

endmodule
