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
//               font_rom.v (font_rom, char_cell), bin2bcd.v, fx_timers.v
//
// Revision:
// Revision 0.02 - ribbon (scores, buff), judgement words, pad glow, sync flash
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

// Each screen, top layer first:
//   ribbon (y 0-10): progress bar, teammate score | xN | my score, divider / buff fuse
//   judgement word (PERFECT / GOOD / MISS, 250 ms), falling tiles,
//   hit line (gold for 250 ms after a good sync pair), pads (judged lane glows),
//   lane dividers, black.
// sw[0] up = test mode: mock_feed and mock_judge stand in for Meiyi and Pei Ling.
//
// The colour logic is combinational in pixel_index: the OLED asks about a pixel and
// gets an answer straight away. Only bin2bcd, fx_timers and the mocks have clocks.
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
    input  [1:0]       difficulty,
    input  [3:0]       mult,            // proposed: team multiplier, 1 = no buff, max 9
    input  [11:0]      buff_ms_left,    // proposed: ms left on the buff, 0..3000
    // from Pei Ling
    input              judge_pulse,
    input              judge_player,
    input  [1:0]       judge_grade,
    input  [2:0]       judge_lane,
    input              sync_pulse,
    input              sync_ok,
    // OLED drivers
    input  [12:0]      pno_index,
    output [15:0]      pno_colour,
    input  [12:0]      drm_index,
    output [15:0]      drm_colour
    );


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
    wire [1:0]   mock_judge_grade;
    wire [2:0]   mock_judge_lane;
    wire [15:0]  mock_pno_score, mock_drm_score;
    wire [3:0]   mock_mult;
    wire [11:0]  mock_buff_ms_left;

    mock_judge mock_j (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .enable(sw_mock),
        .song_time_ms(mock_song_time_ms),
        .judge_pulse(mock_judge_pulse), .judge_player(mock_judge_player),
        .judge_grade(mock_judge_grade), .judge_lane(mock_judge_lane),
        .sync_pulse(mock_sync_pulse),   .sync_ok(mock_sync_ok),
        .pno_score(mock_pno_score),     .drm_score(mock_drm_score),
        .mult(mock_mult),               .buff_ms_left(mock_buff_ms_left)
    );

    // input_select: each "use_" signal is the mock one when sw[0] is up, else the real one
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
    wire         use_sync_pulse   = sw_mock ? mock_sync_pulse   : sync_pulse;
    wire         use_sync_ok      = sw_mock ? mock_sync_ok      : sync_ok;


    // ---- Scores as decimal digits (shared by both screens) ----
    wire [19:0] pno_digits, drm_digits;
    bin2bcd pno_bcd (.clk(clk), .value(use_pno_score), .digits(pno_digits));
    bin2bcd drm_bcd (.clk(clk), .value(use_drm_score), .digits(drm_digits));


    // ---- Stretch the 1-clock judgement pulses into 250 ms flashes ----
    wire       pno_fx_on, drm_fx_on, sync_fx_on;
    wire [1:0] pno_fx_grade, drm_fx_grade;
    wire [2:0] pno_fx_lane,  drm_fx_lane;

    fx_timers fx (
        .clk(clk), .rst(rst), .ms_tick(ms_tick),
        .judge_pulse(use_judge_pulse), .judge_player(use_judge_player),
        .judge_grade(use_judge_grade), .judge_lane(use_judge_lane),
        .sync_pulse(use_sync_pulse),   .sync_ok(use_sync_ok),
        .pno_fx_on(pno_fx_on), .pno_fx_grade(pno_fx_grade), .pno_fx_lane(pno_fx_lane),
        .drm_fx_on(drm_fx_on), .drm_fx_grade(drm_fx_grade), .drm_fx_lane(drm_fx_lane),
        .sync_fx_on(sync_fx_on)
    );


    // rotate 180 degrees by reversing px order
    localparam ROTATE_PNO = 0, ROTATE_DRM = 1;
    wire [12:0] pno_idx = ROTATE_PNO ? 13'd6143 - pno_index : pno_index;
    wire [12:0] drm_idx = ROTATE_DRM ? 13'd6143 - drm_index : drm_index;

    // piano screen: "my" score is the piano's, the teammate is the drummer
    screen_layout #(.SCREEN(0)) piano_screen (
        .pixel_index(pno_idx), .song_time_ms(use_song_time), .song_len_ms(use_song_len),
        .ev_valid(use_pno_valid), .ev_time(use_pno_time),
        .ev_lane(use_pno_lane),   .ev_sync(use_pno_sync),
        .my_digits(pno_digits),   .mate_digits(drm_digits),
        .mult(use_mult),          .buff_ms_left(use_buff),
        .fx_on(pno_fx_on), .fx_grade(pno_fx_grade), .fx_lane(pno_fx_lane),
        .sync_fx_on(sync_fx_on),
        .colour(pno_colour)
    );
    // drum screen: the other way round
    screen_layout #(.SCREEN(1)) drum_screen (
        .pixel_index(drm_idx), .song_time_ms(use_song_time), .song_len_ms(use_song_len),
        .ev_valid(use_drm_valid), .ev_time(use_drm_time),
        .ev_lane(use_drm_lane),   .ev_sync(use_drm_sync),
        .my_digits(drm_digits),   .mate_digits(pno_digits),
        .mult(use_mult),          .buff_ms_left(use_buff),
        .fx_on(drm_fx_on), .fx_grade(drm_fx_grade), .fx_lane(drm_fx_lane),
        .sync_fx_on(sync_fx_on),
        .colour(drm_colour)
    );

endmodule


// One copy per screen. SCREEN = 0 piano (5 lanes), 1 drum (3 lanes).
module screen_layout #(parameter SCREEN = 0) (
    input      [12:0]     pixel_index,
    input      [17:0]     song_time_ms,
    input      [17:0]     song_len_ms,
    input      [7:0]      ev_valid,
    input      [8*18-1:0] ev_time,
    input      [8*3-1:0]  ev_lane,
    input      [7:0]      ev_sync,
    input      [19:0]     my_digits,      // this screen's player's score, 5 digits
    input      [19:0]     mate_digits,    // the other player's score
    input      [3:0]      mult,
    input      [11:0]     buff_ms_left,
    input                 fx_on,          // this player's judgement is showing
    input      [1:0]      fx_grade,
    input      [2:0]      fx_lane,
    input                 sync_fx_on,     // gold hit line
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
            // 3 drum lanes, 32 px each: crash | snare | bass
            if      (x >=  2 && x <= 29) begin in_lane = 1'b1; lane = DRUM_CRASH; end
            else if (x >= 34 && x <= 61) begin in_lane = 1'b1; lane = DRUM_SNARE; end
            else if (x >= 66 && x <= 93) begin in_lane = 1'b1; lane = DRUM_BASS;  end
        end
    end

    wire is_divider = (SCREEN == 0) ? (x == 19 || x == 38 || x == 57 || x == 76)
                                    : (x == 32 || x == 64);


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
        .my_digits(my_digits), .mate_digits(mate_digits),
        .mult(mult), .buff_ms_left(buff_ms_left),
        .fx_on(fx_on), .fx_grade(fx_grade),
        .ribbon_colour(ribbon_colour), .word_on(word_on),
        .word_colour(word_colour), .fx_colour(fx_colour)
    );

    // the judged lane's pad glows in the grade colour while the flash is on
    wire pad_glow = fx_on && (lane == fx_lane);

    // top layer first; the first test that says yes paints the pixel
    always @(*) begin
        if      (y < RIBBON_H)              colour = ribbon_colour;
        else if (word_on)                   colour = word_colour;
        else if (on_tile)                   colour = tile_colour;
        else if (y == HIT_Y)                colour = sync_fx_on ? GOLD : WHITE;
        else if (y >= PAD_Y0 && in_lane)    colour = pad_glow ? fx_colour : PAD;
        else if (is_divider)                colour = DIVIDER;
        else                                colour = BLACK;
    end

endmodule
