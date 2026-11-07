`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 11:00:24
// Design Name: 
// Module Name: song_rom_3
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

// Ode to Joy song event table.

module song_rom_3 (
    input  wire [5:0]  addr,
    output reg  [31:0] event_data
);
    `include "TEMPO_defs.vh"

    // Keeping event construction in one function prevents timestamp-width
    // mistakes when arithmetic is used in the chart below.
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

    always @* begin
        case (addr)
            6'd0: event_data = make_event(START_TIME_MS,
                                               EVENT_DUET, NOTE_E, DRUM_BASS, 6'd0);
            6'd1: event_data = make_event(START_TIME_MS + (1 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_NONE, 6'd1);
            6'd2: event_data = make_event(START_TIME_MS + (2 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_F, DRUM_SNARE, 6'd2);
            6'd3: event_data = make_event(START_TIME_MS + (3 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_G, DRUM_NONE, 6'd3);
            6'd4: event_data = make_event(START_TIME_MS + (4 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_G, DRUM_BASS, 6'd4);
            6'd5: event_data = make_event(START_TIME_MS + (5 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_F, DRUM_NONE, 6'd5);
            6'd6: event_data = make_event(START_TIME_MS + (6 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_SNARE, 6'd6);
            6'd7: event_data = make_event(START_TIME_MS + (7 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd7);
            6'd8: event_data = make_event(START_TIME_MS + (8 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_C, DRUM_BASS, 6'd8);
            6'd9: event_data = make_event(START_TIME_MS + (9 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_C, DRUM_NONE, 6'd9);
            6'd10:event_data = make_event(START_TIME_MS + (10 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_SNARE, 6'd10);
            6'd11:event_data = make_event(START_TIME_MS + (11 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_NONE, 6'd11);
            6'd12:event_data = make_event(START_TIME_MS + (12 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_BASS, 6'd12);
            6'd13:event_data = make_event(START_TIME_MS + (13 * BEAT_INTERVAL_MS) + HALF_BEAT_MS,
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd13);
            6'd14:event_data = make_event(START_TIME_MS + (14 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_SNARE, 6'd14);
            6'd15:event_data = make_event(START_TIME_MS + (16 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_CRASH, 6'd15);
            6'd16:event_data = make_event(START_TIME_MS + (17 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_NONE, 6'd16);
            6'd17:event_data = make_event(START_TIME_MS + (18 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_F, DRUM_SNARE, 6'd17);
            6'd18:event_data = make_event(START_TIME_MS + (19 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_G, DRUM_NONE, 6'd18);
            6'd19:event_data = make_event(START_TIME_MS + (20 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_G, DRUM_BASS, 6'd19);
            6'd20:event_data = make_event(START_TIME_MS + (21 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_F, DRUM_NONE, 6'd20);
            6'd21:event_data = make_event(START_TIME_MS + (22 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_SNARE, 6'd21);
            6'd22:event_data = make_event(START_TIME_MS + (23 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd22);
            6'd23:event_data = make_event(START_TIME_MS + (24 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_C, DRUM_BASS, 6'd23);
            6'd24:event_data = make_event(START_TIME_MS + (25 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_C, DRUM_NONE, 6'd24);
            6'd25:event_data = make_event(START_TIME_MS + (26 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_SNARE, 6'd25);
            6'd26:event_data = make_event(START_TIME_MS + (27 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_NONE, 6'd26);
            6'd27:event_data = make_event(START_TIME_MS + (28 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_BASS, 6'd27);
            6'd28:event_data = make_event(START_TIME_MS + (29 * BEAT_INTERVAL_MS) + HALF_BEAT_MS,
                                               EVENT_PIANO, NOTE_C, DRUM_NONE, 6'd28);
            6'd29:event_data = make_event(START_TIME_MS + (30 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_C, DRUM_SNARE, 6'd29);
            6'd30:event_data = make_event(START_TIME_MS + (32 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_CRASH, 6'd30);
            6'd31:event_data = make_event(START_TIME_MS + (33 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd31);
            6'd32:event_data = make_event(START_TIME_MS + (34 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_SNARE, 6'd32);
            6'd33:event_data = make_event(START_TIME_MS + (35 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_C, DRUM_SNARE, 6'd33);
            6'd34:event_data = make_event(START_TIME_MS + (36 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_BASS, 6'd34);
            6'd35:event_data = make_event(START_TIME_MS + (37 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_SNARE, 6'd35);
            6'd36:event_data = make_event(START_TIME_MS + (37 * BEAT_INTERVAL_MS) + HALF_BEAT_MS,
                                               EVENT_PIANO, NOTE_F, DRUM_NONE, 6'd36);
            6'd37:event_data = make_event(START_TIME_MS + (38 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_SNARE, 6'd37);
            6'd38:event_data = make_event(START_TIME_MS + (39 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_C, DRUM_NONE, 6'd38);
            6'd39:event_data = make_event(START_TIME_MS + (40 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_BASS, 6'd39);
            6'd40:event_data = make_event(START_TIME_MS + (41 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_SNARE, 6'd40);
            6'd41:event_data = make_event(START_TIME_MS + (41 * BEAT_INTERVAL_MS) + HALF_BEAT_MS,
                                               EVENT_PIANO, NOTE_F, DRUM_CRASH, 6'd41);
            6'd42:event_data = make_event(START_TIME_MS + (42 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_SNARE, 6'd42);
            6'd43:event_data = make_event(START_TIME_MS + (43 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd43);
            6'd44:event_data = make_event(START_TIME_MS + (44 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_C, DRUM_BASS, 6'd44);
            6'd45:event_data = make_event(START_TIME_MS + (45 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd45);
            6'd46:event_data = make_event(START_TIME_MS + (46 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_G, DRUM_CRASH, 6'd46);
            6'd47:event_data = make_event(START_TIME_MS + (48 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_BASS, 6'd47);
            6'd48:event_data = make_event(START_TIME_MS + (49 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_BASS, 6'd48);
            6'd49:event_data = make_event(START_TIME_MS + (50 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_F, DRUM_SNARE, 6'd49);
            6'd50:event_data = make_event(START_TIME_MS + (51 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_G, DRUM_NONE, 6'd50);
            6'd51:event_data = make_event(START_TIME_MS + (52 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_G, DRUM_BASS, 6'd51);
            6'd52:event_data = make_event(START_TIME_MS + (53 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_F, DRUM_BASS, 6'd52);
            6'd53:event_data = make_event(START_TIME_MS + (54 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_E, DRUM_SNARE, 6'd53);
            6'd54:event_data = make_event(START_TIME_MS + (55 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_D, DRUM_NONE, 6'd54);
            6'd55:event_data = make_event(START_TIME_MS + (56 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_C, DRUM_BASS, 6'd55);
            6'd56:event_data = make_event(START_TIME_MS + (57 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_C, DRUM_NONE, 6'd56);
            6'd57:event_data = make_event(START_TIME_MS + (58 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_SNARE, 6'd57);
            6'd58:event_data = make_event(START_TIME_MS + (59 * BEAT_INTERVAL_MS),
                                               EVENT_PIANO, NOTE_E, DRUM_SNARE, 6'd58);
            6'd59:event_data = make_event(START_TIME_MS + (60 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_D, DRUM_BASS, 6'd59);
            6'd60:event_data = make_event(START_TIME_MS + (61 * BEAT_INTERVAL_MS) + HALF_BEAT_MS,
                                               EVENT_PIANO, NOTE_C, DRUM_SNARE, 6'd60);
            6'd61:event_data = make_event(START_TIME_MS + (62 * BEAT_INTERVAL_MS),
                                               EVENT_DUET, NOTE_C, DRUM_CRASH, 6'd61);
            default: event_data = 32'd0;
        endcase
    end
endmodule
