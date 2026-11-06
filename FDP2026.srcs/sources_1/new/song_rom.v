`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.10.2026 02:26:49
// Design Name: 
// Module Name: song_rom
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

// Hot Cross Buns event table for TEMPO (song_select == 0).
//
// Event word format:
//   [31:16] hit timestamp in ms
//   [15:14] event type
//   [13:10] piano lane
//   [9:6]   drum lane (shared lane codes)
//   [5:0]   event ID
module song_rom (
    input  wire [5:0]  addr,
    output reg  [31:0] event_data
);
    `include "TEMPO_defs.vh"

    function [31:0] make_event;
        input [15:0] timestamp_ms;
        input [1:0]  event_type;
        input [3:0]  piano_lane;
        input [3:0]  drum_lane;
        input [5:0]  event_id;
        begin
            make_event = {timestamp_ms, event_type, piano_lane,
                          drum_lane, event_id};
        end
    endfunction

    // 17-note melody: E D C | E D C | C C C C | D D D D | E D C.
    // A simple bass/snare pulse is paired with every second piano note.
    always @* begin
        case (addr)
            6'd0:  event_data = make_event(START_TIME_MS + (0  * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_E, DRUM_BASS,  6'd0);
            6'd1:  event_data = make_event(START_TIME_MS + (1  * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_D, DRUM_NONE,  6'd1);
            6'd2:  event_data = make_event(START_TIME_MS + (2  * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_C, DRUM_SNARE, 6'd2);
            6'd3:  event_data = make_event(START_TIME_MS + (4  * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_E, DRUM_BASS,  6'd3);
            6'd4:  event_data = make_event(START_TIME_MS + (5  * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_D, DRUM_NONE,  6'd4);
            6'd5:  event_data = make_event(START_TIME_MS + (6  * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_C, DRUM_SNARE,  6'd5);
            6'd6:  event_data = make_event(START_TIME_MS + (8  * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_C, DRUM_BASS, 6'd6);
            6'd7:  event_data = make_event(START_TIME_MS + (9  * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_C, DRUM_NONE,  6'd7);
            6'd8:  event_data = make_event(START_TIME_MS + (10  * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_C, DRUM_BASS,  6'd8);
            6'd9:  event_data = make_event(START_TIME_MS + (11  * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_C, DRUM_NONE,  6'd9);
            6'd10: event_data = make_event(START_TIME_MS + (12 * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_D, DRUM_BASS, 6'd10);
            6'd11: event_data = make_event(START_TIME_MS + (13 * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_D, DRUM_NONE,  6'd11);
            6'd12: event_data = make_event(START_TIME_MS + (14 * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_D, DRUM_BASS,  6'd12);
            6'd13: event_data = make_event(START_TIME_MS + (15 * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_D, DRUM_NONE,  6'd13);
            6'd14: event_data = make_event(START_TIME_MS + (16 * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_E, DRUM_BASS, 6'd14);
            6'd15: event_data = make_event(START_TIME_MS + (17 * BEAT_INTERVAL_MS), EVENT_PIANO, NOTE_D, DRUM_NONE,  6'd15);
            6'd16: event_data = make_event(START_TIME_MS + (18 * BEAT_INTERVAL_MS), EVENT_DUET,  NOTE_C, DRUM_SNARE,  6'd16);
            default: event_data = 32'd0;
        endcase
    end
endmodule

