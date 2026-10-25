`timescale 1ns / 1ps

// Member A: Annanya - audio DSP (mic -> detected piano notes and drum hits)
//
// PLACEHOLDER: the ports are the team interface; replace the body with your design.
// Keep every port on clk (100 MHz). det_pulse is high for exactly one clk cycle.
//
// Proposed (not in the flowchart yet): stamp det_time_ms with Meiyi's
// song_time_ms, so your timestamps and her expected times use the same clock.
// Only detect while game_state == ST_PLAYING.
//
// Three drums: after drum_onset fires, classify the hit and put the drum in det_note:
//   DRUM_CRASH (0) crash cymbal, DRUM_SNARE (1) snare, DRUM_BASS (2) bass drum.
// Piano hits use NOTE_C..NOTE_G (0..4). det_is_drum says which table applies.


//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 16:22:37
// Design Name: 
// Module Name: audio_dsp
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


module audio_dsp (
    input         clk,
    input         rst,
    input  [2:0]  game_state,
    input  [17:0] song_time_ms,
    // Pmod MIC (JC pins 1, 3, 4) - change if your mic module needs different pins
    output        mic_cs,
    input         mic_miso,
    output        mic_sclk,
    // to Pei Ling
    output        det_pulse,
    output        det_is_drum,
    output [2:0]  det_note,       // piano 0..4 (C..G) or drum 0..2 (crash, snare, bass)
    output [17:0] det_time_ms
    );

    `include "tempo_defs.vh"

    assign mic_cs      = 1'b1;   // idle (deselected)
    assign mic_sclk    = 1'b0;
    assign det_pulse   = 1'b0;
    assign det_is_drum = 1'b0;
    assign det_note    = 3'd0;
    assign det_time_ms = 18'd0;

endmodule
