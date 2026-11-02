`timescale 1ns / 1ps

// While enable (sw[0]) is up, this makes its own song clock and a looping song,
// and sends them in exactly the same format as Meiyi's real outputs. display_top
// shows these instead of hers. Drop the switch and the song restarts from 0.
//
// The song: one beat every 512 ms (about 117 beats per minute).
//   piano: a note on every beat, melody C E G E F D E C, repeating every 8 beats
//   drums: crash, -, snare, -, bass, bass, snare, -   (repeating every 8 beats)
//   every 4th beat is a sync beat: piano and drum land together (white rim)
// The first 4 beats are left empty, so the first tiles fall in from the top.
//
// Two modules in this file:
//   mock_feed  the song clock, and the 8 upcoming beats for each screen
//   mock_beat  given a beat number, which piano note and which drum it is

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.10.2026 17:30:03
// Design Name: 
// Module Name: mock_feed
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


module mock_feed (
    input              clk,             // 100 MHz
    input              rst,
    input              ms_tick,         // 1-cycle pulse every 1 ms
    input              enable,          // sw[0]: 1 = run the fake song
    output reg [17:0]  song_time_ms = 0,
    output     [7:0]   pno_ev_valid,
    output     [143:0] pno_ev_time,     // slot 0 = [17:0], ...
    output     [23:0]  pno_ev_lane,     // slot 0 = [2:0], slot 1 = [5:3], ...
    output     [7:0]   pno_ev_sync,
    output     [7:0]   drm_ev_valid,
    output     [143:0] drm_ev_time,
    output     [23:0]  drm_ev_lane,
    output     [7:0]   drm_ev_sync
    );

    // ---- 1. The song clock: count milliseconds while enabled ----
    always @(posedge clk) begin
        if (rst || !enable)
            song_time_ms <= 0;                      // switch down: back to the start
        else if (ms_tick)
            song_time_ms <= song_time_ms + 1;       // one more millisecond
    end

    // ---- 2. Which beats are the next 8 on screen? ----
    // Beat n is due at n * 512 ms. tile_calc keeps a tile until it is 300 ms late,
    // so the first beat still on screen is the first one due after (now - 300).
    // Adding 212 (= 512 - 300) and dividing by 512 finds it without going negative.
    // Dividing by 512 is a right shift by 9 (512 = 2^9).
    wire [18:0] shifted    = song_time_ms + 212;    // 19 bits so it can't overflow
    wire [9:0]  first_beat = shifted >> 9;

    wire [9:0] b0 = first_beat;                     // the 8 upcoming beats, in order
    wire [9:0] b1 = first_beat + 1;
    wire [9:0] b2 = first_beat + 2;
    wire [9:0] b3 = first_beat + 3;
    wire [9:0] b4 = first_beat + 4;
    wire [9:0] b5 = first_beat + 5;
    wire [9:0] b6 = first_beat + 6;
    wire [9:0] b7 = first_beat + 7;

    // ---- 3. When is each one due? beat * 512 ms ----
    // Piano and drums share the same beat grid, so they share the times.
    assign pno_ev_time[17:0]    = b0 * 512;
    assign pno_ev_time[35:18]   = b1 * 512;
    assign pno_ev_time[53:36]   = b2 * 512;
    assign pno_ev_time[71:54]   = b3 * 512;
    assign pno_ev_time[89:72]   = b4 * 512;
    assign pno_ev_time[107:90]  = b5 * 512;
    assign pno_ev_time[125:108] = b6 * 512;
    assign pno_ev_time[143:126] = b7 * 512;
    assign drm_ev_time = pno_ev_time;

    // ---- 4. What is played on each beat? One mock_beat per slot ----
    wire [2:0] pl0, pl1, pl2, pl3, pl4, pl5, pl6, pl7;     // piano lane
    wire [2:0] dl0, dl1, dl2, dl3, dl4, dl5, dl6, dl7;     // drum lane
    wire       dv0, dv1, dv2, dv3, dv4, dv5, dv6, dv7;     // drum plays on this beat
    wire       sy0, sy1, sy2, sy3, sy4, sy5, sy6, sy7;     // sync beat

    mock_beat m0 (.beat(b0), .pno_lane(pl0), .drm_lane(dl0), .drm_plays(dv0), .sync(sy0));
    mock_beat m1 (.beat(b1), .pno_lane(pl1), .drm_lane(dl1), .drm_plays(dv1), .sync(sy1));
    mock_beat m2 (.beat(b2), .pno_lane(pl2), .drm_lane(dl2), .drm_plays(dv2), .sync(sy2));
    mock_beat m3 (.beat(b3), .pno_lane(pl3), .drm_lane(dl3), .drm_plays(dv3), .sync(sy3));
    mock_beat m4 (.beat(b4), .pno_lane(pl4), .drm_lane(dl4), .drm_plays(dv4), .sync(sy4));
    mock_beat m5 (.beat(b5), .pno_lane(pl5), .drm_lane(dl5), .drm_plays(dv5), .sync(sy5));
    mock_beat m6 (.beat(b6), .pno_lane(pl6), .drm_lane(dl6), .drm_plays(dv6), .sync(sy6));
    mock_beat m7 (.beat(b7), .pno_lane(pl7), .drm_lane(dl7), .drm_plays(dv7), .sync(sy7));

    // ---- 5. Pack the answers into the buses, slot 0 in the lowest bits ----
    // A beat is only real once the song has started (beat 4 onwards).
    wire st0 = (b0 >= 4), st1 = (b1 >= 4), st2 = (b2 >= 4), st3 = (b3 >= 4);
    wire st4 = (b4 >= 4), st5 = (b5 >= 4), st6 = (b6 >= 4), st7 = (b7 >= 4);

    assign pno_ev_valid[0] = st0;  assign pno_ev_valid[1] = st1;
    assign pno_ev_valid[2] = st2;  assign pno_ev_valid[3] = st3;
    assign pno_ev_valid[4] = st4;  assign pno_ev_valid[5] = st5;
    assign pno_ev_valid[6] = st6;  assign pno_ev_valid[7] = st7;

    assign drm_ev_valid[0] = st0 && dv0;  assign drm_ev_valid[1] = st1 && dv1;
    assign drm_ev_valid[2] = st2 && dv2;  assign drm_ev_valid[3] = st3 && dv3;
    assign drm_ev_valid[4] = st4 && dv4;  assign drm_ev_valid[5] = st5 && dv5;
    assign drm_ev_valid[6] = st6 && dv6;  assign drm_ev_valid[7] = st7 && dv7;

    assign pno_ev_lane[2:0]   = pl0;  assign drm_ev_lane[2:0]   = dl0;
    assign pno_ev_lane[5:3]   = pl1;  assign drm_ev_lane[5:3]   = dl1;
    assign pno_ev_lane[8:6]   = pl2;  assign drm_ev_lane[8:6]   = dl2;
    assign pno_ev_lane[11:9]  = pl3;  assign drm_ev_lane[11:9]  = dl3;
    assign pno_ev_lane[14:12] = pl4;  assign drm_ev_lane[14:12] = dl4;
    assign pno_ev_lane[17:15] = pl5;  assign drm_ev_lane[17:15] = dl5;
    assign pno_ev_lane[20:18] = pl6;  assign drm_ev_lane[20:18] = dl6;
    assign pno_ev_lane[23:21] = pl7;  assign drm_ev_lane[23:21] = dl7;

    assign pno_ev_sync[0] = sy0;  assign pno_ev_sync[1] = sy1;
    assign pno_ev_sync[2] = sy2;  assign pno_ev_sync[3] = sy3;
    assign pno_ev_sync[4] = sy4;  assign pno_ev_sync[5] = sy5;
    assign pno_ev_sync[6] = sy6;  assign pno_ev_sync[7] = sy7;
    assign drm_ev_sync = pno_ev_sync;

endmodule


//////////////////////////////////////////////////////////////////////////////////
// mock_beat - the fake song's score: for beat number `beat`, which piano note and
// which drum? Only the last 3 bits matter, so the pattern repeats every 8 beats.
//////////////////////////////////////////////////////////////////////////////////

module mock_beat (
    input      [9:0] beat,
    output reg [2:0] pno_lane,
    output reg [2:0] drm_lane,
    output reg       drm_plays,
    output           sync
    );

    `include "TEMPO_defs.vh"       // NOTE_C .. NOTE_G, DRUM_CRASH / SNARE / BASS

    always @(*) begin
        case (beat[2:0])            // position inside the 8-beat bar pair
            3'd0: begin pno_lane = NOTE_C; drm_lane = DRUM_CRASH; drm_plays = 1; end
            3'd1: begin pno_lane = NOTE_E; drm_lane = DRUM_CRASH; drm_plays = 0; end
            3'd2: begin pno_lane = NOTE_G; drm_lane = DRUM_SNARE; drm_plays = 1; end
            3'd3: begin pno_lane = NOTE_E; drm_lane = DRUM_SNARE; drm_plays = 0; end
            3'd4: begin pno_lane = NOTE_F; drm_lane = DRUM_BASS;  drm_plays = 1; end
            3'd5: begin pno_lane = NOTE_D; drm_lane = DRUM_BASS;  drm_plays = 1; end
            3'd6: begin pno_lane = NOTE_E; drm_lane = DRUM_SNARE; drm_plays = 1; end
            3'd7: begin pno_lane = NOTE_C; drm_lane = DRUM_SNARE; drm_plays = 0; end
        endcase
    end

    assign sync = (beat[1:0] == 2'd0);     // beats 0, 4, 8, ... land together

endmodule

