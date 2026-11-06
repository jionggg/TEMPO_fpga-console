`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 25.10.2026 12:07:34
// Design Name:
// Module Name: display_top
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Member D (Ji Yong) graphics for both OLEDs
//
// Dependencies: mock_feed.v (mock_feed, mock_judge), tile_calc.v, ui_renderer.v,
//               font_rom.v (font_rom, char_cell), bin2bcd.v, fx_timers.v,
//               scene_text.v, sprite_rom.v, hit_log.v
//
// Revision:
// Revision 0.04 - song menu (song_select), lane labels under the white line, bass sprite
//                 for every drum lane, 3 px progress bar, SYNC'D line + results count,
//                 drummer score left / pianist right on both screens with a green flash
// Revision 0.03 - scene per game state (menu, countdown, pause, results), hit sprites
//                 and dragging hit colour under the white line (replaces pad glow)
// Revision 0.02 - ribbon (scores, buff), judgement words, pad glow, sync flash
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

// One scene per game state (Meiyi's game_state):
//   MENU       TEMPO title, PIANO / DRUMS, EASY / NORMAL / HARD (song_select), PRESS START
//   COUNTDOWN  empty field + ribbon, big outlined 3, 2, 1, GO; no tiles yet
//   PLAYING    top layer first: ribbon, judgement word and SYNC'D, hit sprite (under the
//              white line), hit colour (under the line), falling tiles, hit line (gold
//              after a good sync), lane labels, pads, lane dividers, black
//   PAUSED     the PLAYING picture at half brightness, PAUSED / U RESUME / D QUIT on top
//   RESULTS    ribbon (final scores) + RESULTS, SYNC'D nn/tt, my PERFECT / GOOD / MISS, PRESS C
// sw[0] up = test mode: the mocks stand in for Meiyi and Pei Ling and the PLAYING
// scene is always shown.
//
// The colour logic is combinational in pixel_index: the OLED asks about a pixel and
// gets an answer straight away. Only the counters, timers and mocks have clocks.
//////////////////////////////////////////////////////////////////////////////////

module display_top (
    input              clk,
    input              rst,
    input              ms_tick,
    input              sw_mock,
    // from Meiyi
    input  [2:0]       game_state,
    input  [1:0]       countdown_num,
    input  [17:0]      song_time_ms,
    input  [17:0]      song_len_ms,
    input  [7:0]       pno_ev_valid,
    input  [8*18-1:0]  pno_ev_time,
    input  [8*3-1:0]   pno_ev_lane,
    input  [7:0]       pno_ev_sync,
    input  [7:0]       drm_ev_valid,
    input  [8*18-1:0]  drm_ev_time,
    input  [8*3-1:0]   drm_ev_lane,
    input  [7:0]       drm_ev_sync,
    input  [15:0]      pno_score,
    input  [15:0]      drm_score,
    input  [7:0]       pno_combo,
    input  [7:0]       drm_combo,
    input  [1:0]       song_select,     // menu choice 0..2 (EASY, NORMAL, HARD)
    input  [3:0]       mult,            // proposed: team multiplier, 1 = no buff, max 9
    input  [11:0]      buff_ms_left,    // proposed: ms left on the buff, 0..3000
    // from Pei Ling
    input              judge_pulse,
    input              judge_player,
    input  [1:0]       judge_grade,
    input  [2:0]       judge_lane,
    input  [17:0]      judge_target_ms, // when the judged note was due
    input  [17:0]      judge_hit_ms,    // when it was actually hit (0 = not hit)
    input  [7:0]       judge_id,        // which event was judged (a duet's two halves share it)
    input              sync_pulse,
    input              sync_ok,
    input  [7:0]       sync_id,         // which duet the sync result is for
    // OLED drivers
    input  [12:0]      pno_index,
    output [15:0]      pno_colour,
    input  [12:0]      drm_index,
    output [15:0]      drm_colour
    );

    `include "TEMPO_defs.vh"       // ST_*, GRADE_*


    // ---- Test mode: sw[0] up = show the mocks' fake song and judgements ----

    wire [17:0]  mock_song_time_ms;
    wire [7:0]   mock_pno_valid, mock_pno_sync, mock_drm_valid, mock_drm_sync;
    wire [143:0] mock_pno_time,  mock_drm_time;
    wire [23:0]  mock_pno_lane,  mock_drm_lane;

    mock_feed mock (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .enable(sw_mock),
        .song_time_ms(mock_song_time_ms),
        .pno_ev_valid(mock_pno_valid), .pno_ev_time(mock_pno_time),
        .pno_ev_lane(mock_pno_lane),   .pno_ev_sync(mock_pno_sync),
        .drm_ev_valid(mock_drm_valid), .drm_ev_time(mock_drm_time),
        .drm_ev_lane(mock_drm_lane),   .drm_ev_sync(mock_drm_sync)
    );

    wire         mock_judge_pulse, mock_judge_player, mock_sync_pulse, mock_sync_ok;
    wire [7:0]   mock_judge_id, mock_sync_id;
    wire [1:0]   mock_judge_grade;
    wire [2:0]   mock_judge_lane;
    wire [17:0]  mock_judge_target, mock_judge_hit;
    wire [15:0]  mock_pno_score, mock_drm_score;
    wire [3:0]   mock_mult;
    wire [11:0]  mock_buff_ms_left;

    mock_judge mock_j (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .enable(sw_mock),
        .song_time_ms(mock_song_time_ms),
        .judge_pulse(mock_judge_pulse), .judge_player(mock_judge_player),
        .judge_grade(mock_judge_grade), .judge_lane(mock_judge_lane),
        .judge_target_ms(mock_judge_target), .judge_hit_ms(mock_judge_hit),
        .judge_id(mock_judge_id),       .sync_id(mock_sync_id),
        .sync_pulse(mock_sync_pulse),   .sync_ok(mock_sync_ok),
        .pno_score(mock_pno_score),     .drm_score(mock_drm_score),
        .mult(mock_mult),               .buff_ms_left(mock_buff_ms_left)
    );

    // input_select: each "use_" signal is the mock one when sw[0] is up, else the real one
    wire [2:0]   use_state     = sw_mock ? ST_PLAYING        : game_state;
    wire [17:0]  use_song_time = sw_mock ? mock_song_time_ms : song_time_ms;
    wire [17:0]  use_song_len  = sw_mock ? 18'd30000         : song_len_ms;   // fake 30 s song
    wire [7:0]   use_pno_valid = sw_mock ? mock_pno_valid    : pno_ev_valid;
    wire [143:0] use_pno_time  = sw_mock ? mock_pno_time     : pno_ev_time;
    wire [23:0]  use_pno_lane  = sw_mock ? mock_pno_lane     : pno_ev_lane;
    wire [7:0]   use_pno_sync  = sw_mock ? mock_pno_sync     : pno_ev_sync;
    wire [7:0]   use_drm_valid = sw_mock ? mock_drm_valid    : drm_ev_valid;
    wire [143:0] use_drm_time  = sw_mock ? mock_drm_time     : drm_ev_time;
    wire [23:0]  use_drm_lane  = sw_mock ? mock_drm_lane     : drm_ev_lane;
    wire [7:0]   use_drm_sync  = sw_mock ? mock_drm_sync     : drm_ev_sync;

    wire [15:0]  use_pno_score = sw_mock ? mock_pno_score    : pno_score;
    wire [15:0]  use_drm_score = sw_mock ? mock_drm_score    : drm_score;
    wire [3:0]   use_mult      = sw_mock ? mock_mult         : mult;
    wire [11:0]  use_buff      = sw_mock ? mock_buff_ms_left : buff_ms_left;

    wire         use_judge_pulse  = sw_mock ? mock_judge_pulse  : judge_pulse;
    wire         use_judge_player = sw_mock ? mock_judge_player : judge_player;
    wire [1:0]   use_judge_grade  = sw_mock ? mock_judge_grade  : judge_grade;
    wire [2:0]   use_judge_lane   = sw_mock ? mock_judge_lane   : judge_lane;
    wire [17:0]  use_judge_target = sw_mock ? mock_judge_target : judge_target_ms;
    wire [17:0]  use_judge_hit    = sw_mock ? mock_judge_hit    : judge_hit_ms;
    wire [7:0]   use_judge_id     = sw_mock ? mock_judge_id     : judge_id;
    wire         use_sync_pulse   = sw_mock ? mock_sync_pulse   : sync_pulse;
    wire         use_sync_ok      = sw_mock ? mock_sync_ok      : sync_ok;
    wire [7:0]   use_sync_id      = sw_mock ? mock_sync_id      : sync_id;

    // a new game is starting (or no game): forget the last game's tallies and hits
    wire new_round = rst || (use_state == ST_MENU) || (use_state == ST_COUNTDOWN);


    // ---- Scores as decimal digits (shared by both screens) ----
    wire [19:0] pno_digits, drm_digits;
    bin2bcd pno_bcd (.clk(clk), .value(use_pno_score), .digits(pno_digits));
    bin2bcd drm_bcd (.clk(clk), .value(use_drm_score), .digits(drm_digits));


    // ---- Was a good sync PERFECT + PERFECT? (green SYNC'D) or not (orange) ----
    // Pei Ling sends the sync result on the same clock as the duet's second judgement,
    // so remember every judgement's grade by its ID, like a coat check: the first
    // player's grade waits on its peg until the partner's result arrives.
    reg [1:0] pno_grade_of [0:63];
    reg [1:0] drm_grade_of [0:63];
    always @(posedge clk) begin
        if (use_judge_pulse) begin
            if (use_judge_player == 1'b0) pno_grade_of[use_judge_id[5:0]] <= use_judge_grade;
            else                          drm_grade_of[use_judge_id[5:0]] <= use_judge_grade;
        end
    end
    // a grade arriving on this very clock has not reached its peg yet: take it directly
    wire [1:0] sync_pno_grade = (use_judge_pulse && use_judge_player == 1'b0) ? use_judge_grade
                                                                         : pno_grade_of[use_sync_id[5:0]];
    wire [1:0] sync_drm_grade = (use_judge_pulse && use_judge_player == 1'b1) ? use_judge_grade
                                                                         : drm_grade_of[use_sync_id[5:0]];
    wire sync_perfect = (sync_pno_grade == GRADE_PERFECT) && (sync_drm_grade == GRADE_PERFECT);

    // ---- A score just went up? (it only drops when a new game clears it) ----
    reg  [15:0] last_pno_score = 0, last_drm_score = 0;
    always @(posedge clk) begin
        last_pno_score <= use_pno_score;
        last_drm_score <= use_drm_score;
    end
    wire pno_up = (use_pno_score > last_pno_score);
    wire drm_up = (use_drm_score > last_drm_score);


    // ---- Stretch the 1-clock judgement pulses into 250 ms flashes ----
    wire       pno_fx_on, drm_fx_on, sync_fx_on, sync_fx_perfect;
    wire       pno_flash, drm_flash;
    wire [1:0] pno_fx_grade, drm_fx_grade;
    wire [2:0] pno_fx_lane,  drm_fx_lane;
    wire [4:0] pno_spr_on;
    wire [2:0] drm_spr_on;

    fx_timers fx (
        .clk(clk), .rst(rst), .ms_tick(ms_tick),
        .judge_pulse(use_judge_pulse), .judge_player(use_judge_player),
        .judge_grade(use_judge_grade), .judge_lane(use_judge_lane),
        .sync_pulse(use_sync_pulse),   .sync_ok(use_sync_ok), .sync_perfect(sync_perfect),
        .pno_up(pno_up), .drm_up(drm_up),
        .pno_fx_on(pno_fx_on), .pno_fx_grade(pno_fx_grade), .pno_fx_lane(pno_fx_lane),
        .drm_fx_on(drm_fx_on), .drm_fx_grade(drm_fx_grade), .drm_fx_lane(drm_fx_lane),
        .sync_fx_on(sync_fx_on), .sync_fx_perfect(sync_fx_perfect),
        .pno_spr_on(pno_spr_on), .drm_spr_on(drm_spr_on),
        .pno_flash(pno_flash), .drm_flash(drm_flash)
    );


    // ---- Blink for "PRESS START" / "PRESS C": toggles every 500 ms ----
    reg [8:0] blink_ms = 0;
    reg       blink    = 1;
    always @(posedge clk) begin
        if (ms_tick) begin
            if (blink_ms == 9'd499) begin blink_ms <= 0; blink <= ~blink; end
            else                          blink_ms <= blink_ms + 1;
        end
    end


    // ---- Results: count each player's PERFECT / GOOD / MISS, and the team's SYNC'Ds ----
    // Cleared when a new game starts; held through RESULTS. Stops at 99 (2 digits).
    reg [7:0] p_perf = 0, p_good = 0, p_miss = 0;
    reg [7:0] d_perf = 0, d_good = 0, d_miss = 0;
    // syncs = duets played in sync; duets = every duet Pei Ling judged, in sync or not.
    // She judges every duet of the song (a missed one too, once its time runs out), so
    // by the RESULTS screen duets = the number of duets (sync tiles) in the song.
    reg [7:0] syncs  = 0;
    reg [7:0] duets  = 0;
    always @(posedge clk) begin
        if (new_round) begin
            syncs <= 0;
            duets <= 0;
        end else if (use_sync_pulse) begin
            if (use_sync_ok && syncs != 99) syncs <= syncs + 1;
            if (duets != 99)                duets <= duets + 1;
        end
    end
    always @(posedge clk) begin
        if (new_round) begin
            p_perf <= 0; p_good <= 0; p_miss <= 0;
            d_perf <= 0; d_good <= 0; d_miss <= 0;
        end else if (use_judge_pulse) begin
            if (use_judge_player == 1'b0) begin
                if      (use_judge_grade == GRADE_PERFECT) begin if (p_perf != 99) p_perf <= p_perf + 1; end
                else if (use_judge_grade == GRADE_GOOD)    begin if (p_good != 99) p_good <= p_good + 1; end
                else                                       begin if (p_miss != 99) p_miss <= p_miss + 1; end
            end else begin
                if      (use_judge_grade == GRADE_PERFECT) begin if (d_perf != 99) d_perf <= d_perf + 1; end
                else if (use_judge_grade == GRADE_GOOD)    begin if (d_good != 99) d_good <= d_good + 1; end
                else                                       begin if (d_miss != 99) d_miss <= d_miss + 1; end
            end
        end
    end

    // two decimal digits each: digits[7:4] tens, [3:0] ones
    wire [19:0] p_perf_d, p_good_d, p_miss_d, d_perf_d, d_good_d, d_miss_d;
    bin2bcd bcd_pp (.clk(clk), .value({8'd0, p_perf}), .digits(p_perf_d));
    bin2bcd bcd_pg (.clk(clk), .value({8'd0, p_good}), .digits(p_good_d));
    bin2bcd bcd_pm (.clk(clk), .value({8'd0, p_miss}), .digits(p_miss_d));
    bin2bcd bcd_dp (.clk(clk), .value({8'd0, d_perf}), .digits(d_perf_d));
    bin2bcd bcd_dg (.clk(clk), .value({8'd0, d_good}), .digits(d_good_d));
    bin2bcd bcd_dm (.clk(clk), .value({8'd0, d_miss}), .digits(d_miss_d));
    wire [19:0] sync_d, duets_d;
    bin2bcd bcd_sy (.clk(clk), .value({8'd0, syncs}),  .digits(sync_d));
    bin2bcd bcd_du (.clk(clk), .value({8'd0, duets}),  .digits(duets_d));


    // ---- Recent hits per player, for the dragging colour under the white line ----
    wire [3:0]  p_rec_valid, d_rec_valid;
    wire [11:0] p_rec_lane,  d_rec_lane;
    wire [71:0] p_rec_target, d_rec_target, p_rec_hit, d_rec_hit;
    wire [7:0]  p_rec_grade, d_rec_grade;

    hit_log #(.PLAYER(0)) pno_hits (
        .clk(clk), .clear(new_round), .song_time_ms(use_song_time),
        .judge_pulse(use_judge_pulse), .judge_player(use_judge_player),
        .judge_lane(use_judge_lane), .judge_grade(use_judge_grade),
        .judge_target_ms(use_judge_target), .judge_hit_ms(use_judge_hit),
        .rec_valid(p_rec_valid), .rec_lane(p_rec_lane), .rec_target(p_rec_target),
        .rec_hit(p_rec_hit), .rec_grade(p_rec_grade)
    );
    hit_log #(.PLAYER(1)) drm_hits (
        .clk(clk), .clear(new_round), .song_time_ms(use_song_time),
        .judge_pulse(use_judge_pulse), .judge_player(use_judge_player),
        .judge_lane(use_judge_lane), .judge_grade(use_judge_grade),
        .judge_target_ms(use_judge_target), .judge_hit_ms(use_judge_hit),
        .rec_valid(d_rec_valid), .rec_lane(d_rec_lane), .rec_target(d_rec_target),
        .rec_hit(d_rec_hit), .rec_grade(d_rec_grade)
    );


    // rotate 180 degrees by reversing px order
    localparam ROTATE_PNO = 0, ROTATE_DRM = 1;
    wire [12:0] pno_idx = ROTATE_PNO ? 13'd6143 - pno_index : pno_index;
    wire [12:0] drm_idx = ROTATE_DRM ? 13'd6143 - drm_index : drm_index;

    // piano screen (both screens show the drummer's score left, the pianist's right)
    screen_layout #(.SCREEN(0)) piano_screen (
        .pixel_index(pno_idx), .state(use_state), .countdown_num(countdown_num), .blink(blink),
        .song_select(song_select),
        .song_time_ms(use_song_time), .song_len_ms(use_song_len),
        .ev_valid(use_pno_valid), .ev_time(use_pno_time),
        .ev_lane(use_pno_lane),   .ev_sync(use_pno_sync),
        .drm_digits(drm_digits),  .pno_digits(pno_digits),
        .drm_flash(drm_flash),    .pno_flash(pno_flash),
        .mult(use_mult),          .buff_ms_left(use_buff),
        .fx_on(pno_fx_on), .fx_grade(pno_fx_grade),
        .sync_fx_on(sync_fx_on), .sync_fx_perfect(sync_fx_perfect),
        .spr_on(pno_spr_on),
        .rec_valid(p_rec_valid), .rec_lane(p_rec_lane), .rec_target(p_rec_target),
        .rec_hit(p_rec_hit), .rec_grade(p_rec_grade),
        .perfect_d(p_perf_d[7:0]), .good_d(p_good_d[7:0]), .miss_d(p_miss_d[7:0]),
        .sync_d(sync_d[7:0]), .sync_total_d(duets_d[7:0]),
        .colour(pno_colour)
    );
    // drum screen: its own judgements, hits and tallies
    screen_layout #(.SCREEN(1)) drum_screen (
        .pixel_index(drm_idx), .state(use_state), .countdown_num(countdown_num), .blink(blink),
        .song_select(song_select),
        .song_time_ms(use_song_time), .song_len_ms(use_song_len),
        .ev_valid(use_drm_valid), .ev_time(use_drm_time),
        .ev_lane(use_drm_lane),   .ev_sync(use_drm_sync),
        .drm_digits(drm_digits),  .pno_digits(pno_digits),
        .drm_flash(drm_flash),    .pno_flash(pno_flash),
        .mult(use_mult),          .buff_ms_left(use_buff),
        .fx_on(drm_fx_on), .fx_grade(drm_fx_grade),
        .sync_fx_on(sync_fx_on), .sync_fx_perfect(sync_fx_perfect),
        .spr_on({2'b00, drm_spr_on}),
        .rec_valid(d_rec_valid), .rec_lane(d_rec_lane), .rec_target(d_rec_target),
        .rec_hit(d_rec_hit), .rec_grade(d_rec_grade),
        .perfect_d(d_perf_d[7:0]), .good_d(d_good_d[7:0]), .miss_d(d_miss_d[7:0]),
        .sync_d(sync_d[7:0]), .sync_total_d(duets_d[7:0]),
        .colour(drm_colour)
    );

endmodule


// One copy per screen. SCREEN = 0 piano (5 lanes), 1 drum (3 lanes).
module screen_layout #(parameter SCREEN = 0) (
    input      [12:0]     pixel_index,
    input      [2:0]      state,          // which scene (game_state)
    input      [1:0]      countdown_num,
    input                 blink,
    input      [1:0]      song_select,    // menu choice 0..2
    input      [17:0]     song_time_ms,
    input      [17:0]     song_len_ms,
    input      [7:0]      ev_valid,
    input      [8*18-1:0] ev_time,
    input      [8*3-1:0]  ev_lane,
    input      [7:0]      ev_sync,
    input      [19:0]     drm_digits,     // drummer's score, 5 digits (ribbon, left)
    input      [19:0]     pno_digits,     // pianist's score (ribbon, right)
    input                 drm_flash,      // drummer's score just went up
    input                 pno_flash,      // pianist's score just went up
    input      [3:0]      mult,
    input      [11:0]     buff_ms_left,
    input                 fx_on,          // this player's judgement word is showing
    input      [1:0]      fx_grade,
    input                 sync_fx_on,     // gold hit line and SYNC'D are showing
    input                 sync_fx_perfect,// ... and the duet was PERFECT + PERFECT
    input      [4:0]      spr_on,         // bit L = lane L's hit sprite is showing
    input      [3:0]      rec_valid,      // this player's 4 recent hits (hit_log)
    input      [11:0]     rec_lane,
    input      [71:0]     rec_target,
    input      [71:0]     rec_hit,
    input      [7:0]      rec_grade,
    input      [7:0]      perfect_d,      // results: 2 decimal digits each
    input      [7:0]      good_d,
    input      [7:0]      miss_d,
    input      [7:0]      sync_d,         // results: the team's SYNC'D count
    input      [7:0]      sync_total_d,   // results: how many duets the song had
    output reg [15:0]     colour
    );

    `include "TEMPO_defs.vh"
    `include "TEMPO_layout.vh"

    // 7'd96, not plain 96: a plain number counts as 32 bits wide, which makes the
    // tools build a 32-bit divider. Sized to 7 bits, the divider is 13 bits wide.
    wire [6:0] x = pixel_index % 7'd96;   // 0..95, left to right
    wire [5:0] y = pixel_index / 7'd96;   // 0..63, top to bottom

    // which lane is this pixel's column in? (tile area only, not the divider)
    reg       in_lane;
    reg [2:0] lane;
    always @(*) begin
        in_lane = 1'b0;
        lane    = 3'd0;
        if (SCREEN == 0) begin
            // 5 piano lanes, 19 px each: C | D | E | F | G
            if      (x >=  1 && x <= 17) begin in_lane = 1'b1; lane = NOTE_C; end
            else if (x >= 20 && x <= 36) begin in_lane = 1'b1; lane = NOTE_D; end
            else if (x >= 39 && x <= 55) begin in_lane = 1'b1; lane = NOTE_E; end
            else if (x >= 58 && x <= 74) begin in_lane = 1'b1; lane = NOTE_F; end
            else if (x >= 77 && x <= 93) begin in_lane = 1'b1; lane = NOTE_G; end
        end else begin
            // 3 drum lanes, 32 px each: hi-hat | snare | bass
            // (lane 0 is DRUM_CRASH in TEMPO_defs.vh; on screen it is the hi-hat)
            if      (x >=  2 && x <= 29) begin in_lane = 1'b1; lane = DRUM_CRASH; end
            else if (x >= 34 && x <= 61) begin in_lane = 1'b1; lane = DRUM_SNARE; end
            else if (x >= 66 && x <= 93) begin in_lane = 1'b1; lane = DRUM_BASS;  end
        end
    end

    wire is_divider = (SCREEN == 0) ? (x == 19 || x == 38 || x == 57 || x == 76)
                                    : (x == 32 || x == 64);

    // tiles and the hit effects only exist once the song is running
    wire show_play = (state == ST_PLAYING) || (state == ST_PAUSED);


    // falling tiles: one tile_calc per screen, same SCREEN setting as this copy
    wire        on_tile;
    wire [15:0] tile_colour;
    tile_calc #(.SCREEN(SCREEN)) tiles (
        .x(x), .y(y), .song_time_ms(song_time_ms),
        .ev_valid(ev_valid), .ev_time(ev_time), .ev_lane(ev_lane), .ev_sync(ev_sync),
        .on_tile(on_tile), .tile_colour(tile_colour)
    );

    // ribbon and judgement word: one ui_renderer per screen
    wire [15:0] ribbon_colour, word_colour, fx_colour;
    wire        word_on;
    ui_renderer #(.SCREEN(SCREEN)) ui (
        .x(x), .y(y), .song_time_ms(song_time_ms), .song_len_ms(song_len_ms),
        .drm_digits(drm_digits), .pno_digits(pno_digits),
        .drm_flash(drm_flash),   .pno_flash(pno_flash),
        .mult(mult), .buff_ms_left(buff_ms_left),
        .fx_on(fx_on), .fx_grade(fx_grade),
        .sync_on(sync_fx_on), .sync_perfect(sync_fx_perfect),
        .ribbon_colour(ribbon_colour), .word_on(word_on),
        .word_colour(word_colour), .fx_colour(fx_colour)
    );

    // menu / countdown / pause / results words
    wire        text_on, big_on;
    wire [15:0] text_colour, big_colour;
    scene_text #(.SCREEN(SCREEN)) words (
        .x(x), .y(y), .state(state), .countdown_num(countdown_num), .blink(blink),
        .perfect_d(perfect_d), .good_d(good_d), .miss_d(miss_d),
        .sync_d(sync_d), .sync_total_d(sync_total_d), .song_select(song_select),
        .text_on(text_on), .text_colour(text_colour),
        .big_on(big_on), .big_colour(big_colour)
    );

    // ---- under the white line: the dragging hit colour (4 recent hits) ----
    wire        m0, m1, m2, m3;
    wire [15:0] c0, c1, c2, c3;
    hit_mark #(.SCREEN(SCREEN)) hm0 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(rec_valid[0]), .lane(rec_lane[2:0]),  .grade(rec_grade[1:0]),
        .target(rec_target[17:0]),  .hit(rec_hit[17:0]),  .on(m0), .colour(c0));
    hit_mark #(.SCREEN(SCREEN)) hm1 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(rec_valid[1]), .lane(rec_lane[5:3]),  .grade(rec_grade[3:2]),
        .target(rec_target[35:18]), .hit(rec_hit[35:18]), .on(m1), .colour(c1));
    hit_mark #(.SCREEN(SCREEN)) hm2 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(rec_valid[2]), .lane(rec_lane[8:6]),  .grade(rec_grade[5:4]),
        .target(rec_target[53:36]), .hit(rec_hit[53:36]), .on(m2), .colour(c2));
    hit_mark #(.SCREEN(SCREEN)) hm3 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(rec_valid[3]), .lane(rec_lane[11:9]), .grade(rec_grade[7:6]),
        .target(rec_target[71:54]), .hit(rec_hit[71:54]), .on(m3), .colour(c3));
    wire        mark_on     = m0 | m1 | m2 | m3;
    wire [15:0] mark_colour = m0 ? c0 : m1 ? c1 : m2 ? c2 : c3;

    // ---- under the white line: the hit sprite of a lane that was just hit ----
    // piano: an eighth note in every lane; drums: the bass drum in every lane
    // (the lane label underneath says which drum it was)
    wire [1:0]  spr_id  = (SCREEN == 0) ? 2'd0 : 2'd3;     // SPR_NOTE or SPR_KICK
    wire [6:0]  spr_x0  = (SCREEN == 0) ? lane * 19 + 1 : lane * 32 + 8;  // sprite's left column
    wire [6:0]  spr_col = x - spr_x0;                                     // 0..15 inside it
    wire [5:0]  spr_row = y - SPRITE_Y0;                                  // 0..7 inside it
    wire [15:0] spr_bits;
    sprite_rom sprites (.sprite(spr_id), .row(spr_row[2:0]), .bits(spr_bits));
    wire spr_px = in_lane && spr_on[lane] && (y >= SPRITE_Y0) &&
                  (x >= spr_x0) && (spr_col < 16) && spr_bits[15 - spr_col];

    // ---- under the white line: the lane names, hidden while that lane's sprite shows ----
    wire label_on;
    lane_label #(.SCREEN(SCREEN)) labels (.x(x), .y(y), .hide(spr_on), .on(label_on));

    // ---- the playing field, top layer first ----
    reg [15:0] field;
    always @(*) begin
        if      (y < RIBBON_H)                  field = ribbon_colour;
        else if (state == ST_PLAYING && word_on) field = word_colour;   // not behind PAUSED
        else if (show_play && spr_px)           field = WHITE;
        else if (show_play && mark_on)          field = mark_colour;
        else if (show_play && on_tile)          field = tile_colour;
        else if (y == HIT_Y)                    field = sync_fx_on ? GOLD : WHITE;
        else if (label_on)                      field = LABEL;
        else if (y >= PAD_Y0 && in_lane)        field = PAD;
        else if (is_divider)                    field = DIVIDER;
        else                                    field = BLACK;
    end

    // half brightness for the pause screen: halve red, green and blue
    wire [15:0] dim_field = {1'b0, field[15:12], 1'b0, field[10:6], 1'b0, field[4:1]};

    // ---- the scene for this game state ----
    always @(*) begin
        case (state)
            ST_MENU:      colour = text_on ? text_colour : BLACK;
            ST_COUNTDOWN: colour = big_on  ? big_colour  : field;
            ST_PLAYING:   colour = field;
            ST_PAUSED:    colour = text_on ? text_colour : dim_field;
            ST_RESULTS:   colour = (y < RIBBON_H) ? ribbon_colour :
                                   text_on        ? text_colour   : BLACK;
            default:      colour = field;
        endcase
    end

endmodule
