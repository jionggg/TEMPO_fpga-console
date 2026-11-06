`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// hit_log.v - remembers recent hits so they can be painted under the white line (Ji Yong)
//
// The picture: a tile is a slice of song time, 8 rows = 256 ms tall. Its bottom edge
// is the moment the note is due (target). A hit is drawn as a second slice of the same
// height whose bottom edge is the moment the player actually hit. Both keep falling
// with the music, and below the white line:
//   - where the hit slice overlaps the tile  -> bright grade colour
//   - where the hit slice sticks out of it   -> dark shade of that colour (early / late)
//   - the part of the tile the hit missed    -> the tile's normal colour (tile_calc)
// Like a footprint in sand: the deeper print (overlap) is bright, the smudge around it
// (timing error) is faint.
//
// Three modules in this file:
//   hit_log   4 records per player, written on each judgement that had a real hit
//   hit_slot  one record (like one tile slot): valid, lane, target, hit, grade
//   hit_mark  for one record and one pixel: is this pixel painted, and in what colour?
//
// Needs Pei Ling's judge_target_ms / judge_hit_ms (perf_eval v4). judge_hit_ms = 0 means
// the note expired without a hit, so nothing is painted for it.
//////////////////////////////////////////////////////////////////////////////////

module hit_log #(parameter PLAYER = 0) (     // PLAYER: 0 = piano, 1 = drum
    input          clk,
    input          clear,                   // new game / reset: forget everything
    input  [17:0]  song_time_ms,
    input          judge_pulse,
    input          judge_player,
    input  [2:0]   judge_lane,
    input  [1:0]   judge_grade,
    input  [17:0]  judge_target_ms,
    input  [17:0]  judge_hit_ms,
    output [3:0]   rec_valid,               // record i = bit i
    output [11:0]  rec_lane,                // record i = [3i+2 : 3i]
    output [71:0]  rec_target,              // record i = [18i+17 : 18i]
    output [71:0]  rec_hit,
    output [7:0]   rec_grade                // record i = [2i+1 : 2i]
    );

    // A new record goes into the oldest slot: wr counts 0, 1, 2, 3, 0, ...
    wire write = judge_pulse && (judge_player == PLAYER) && (judge_hit_ms != 18'd0);
    reg  [1:0] wr = 2'd0;
    always @(posedge clk) begin
        if (clear)      wr <= 2'd0;
        else if (write) wr <= wr + 2'd1;
    end

    // If the song clock jumps backwards (restart), old records no longer make sense.
    reg  [17:0] last_time = 18'd0;
    always @(posedge clk) last_time <= song_time_ms;
    wire wipe = clear || (song_time_ms < last_time);

    hit_slot s0 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd0), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[0]), .lane(rec_lane[2:0]), .grade(rec_grade[1:0]),
        .target(rec_target[17:0]), .hit(rec_hit[17:0]));
    hit_slot s1 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd1), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[1]), .lane(rec_lane[5:3]), .grade(rec_grade[3:2]),
        .target(rec_target[35:18]), .hit(rec_hit[35:18]));
    hit_slot s2 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd2), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[2]), .lane(rec_lane[8:6]), .grade(rec_grade[5:4]),
        .target(rec_target[53:36]), .hit(rec_hit[53:36]));
    hit_slot s3 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd3), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[3]), .lane(rec_lane[11:9]), .grade(rec_grade[7:6]),
        .target(rec_target[71:54]), .hit(rec_hit[71:54]));

endmodule


//////////////////////////////////////////////////////////////////////////////////
// hit_slot - one remembered hit. Forgets itself once both slices have scrolled off
// the bottom of the screen (MARK_MS after the later of the two moments).
//////////////////////////////////////////////////////////////////////////////////

module hit_slot (
    input             clk,
    input             wipe,
    input             write,
    input      [17:0] song_time_ms,
    input      [2:0]  lane_in,
    input      [1:0]  grade_in,
    input      [17:0] target_in,
    input      [17:0] hit_in,
    output reg        valid  = 1'b0,
    output reg [2:0]  lane   = 3'd0,
    output reg [1:0]  grade  = 2'd0,
    output reg [17:0] target = 18'd0,
    output reg [17:0] hit    = 18'd0
    );

    `include "TEMPO_layout.vh"     // MARK_MS

    wire [17:0] later = (target > hit) ? target : hit;      // the later of the two moments
    wire [18:0] done_at = later + MARK_MS;                  // 19 bits: cannot overflow

    always @(posedge clk) begin
        if (wipe)
            valid <= 1'b0;
        else if (write) begin
            valid <= 1'b1;
            lane <= lane_in;  grade <= grade_in;  target <= target_in;  hit <= hit_in;
        end else if (valid && song_time_ms > done_at)
            valid <= 1'b0;                                  // scrolled off: forget it
    end

endmodule


//////////////////////////////////////////////////////////////////////////////////
// hit_mark - one record, one pixel: is it painted under the white line, and how?
//
// Same row maths as tile_slot: a moment `m` sits at row  BASE_Y - (m + OFFSET - now) / 32.
// OFFSET is 640 ms here (20 rows) so moments up to 640 ms in the past stay positive,
// which covers everything down to the bottom of the screen.
//////////////////////////////////////////////////////////////////////////////////

module hit_mark #(parameter SCREEN = 0) (     // SCREEN: 0 = piano, 1 = drum
    input  [6:0]  x,
    input  [5:0]  y,
    input  [17:0] song_time_ms,
    input         valid,
    input  [2:0]  lane,
    input  [1:0]  grade,
    input  [17:0] target,
    input  [17:0] hit,
    output        on,               // this pixel is painted by this hit
    output [15:0] colour
    );

    `include "TEMPO_defs.vh"       // GRADE_*
    `include "TEMPO_layout.vh"     // HIT_Y, TILE_H, SHIFT, colours

    localparam OFFSET_MS = 640;                              // keeps the numbers positive
    localparam BASE_Y    = HIT_Y + (OFFSET_MS >> SHIFT);     // 55 + 20 = 75

    // ms until each moment, plus 640. Far past wraps round to a huge number; far future
    // is also huge. Either way the "_vis" check below throws it away.
    wire [18:0] t_ahead = target + OFFSET_MS - song_time_ms;
    wire [18:0] h_ahead = hit    + OFFSET_MS - song_time_ms;
    wire t_vis = (t_ahead < 1280);                            // bottom edge within rows 35..75
    wire h_vis = (h_ahead < 1280);

    // bottom row of each slice (8 bits: can be below the screen, up to 75)
    wire [7:0] t_ybot = BASE_Y - (t_ahead >> SHIFT);
    wire [7:0] h_ybot = BASE_Y - (h_ahead >> SHIFT);

    // the lane's columns (same as tile_slot)
    wire [6:0] x0 = (SCREEN == 0) ? lane * 19 + 1  : lane * 32 + 2;
    wire [6:0] x1 = (SCREEN == 0) ? lane * 19 + 17 : lane * 32 + 29;
    wire in_x = (x >= x0) && (x <= x1);

    // inside each slice? rows ybot-7 .. ybot, written so nothing goes negative
    wire in_tile = t_vis && (y <= t_ybot) && (y + TILE_H > t_ybot);
    wire in_hit  = h_vis && (y <= h_ybot) && (y + TILE_H > h_ybot);

    assign on = valid && (y > HIT_Y) && in_x && in_hit;

    wire [15:0] bright = (grade == GRADE_PERFECT) ? GREEN    :
                         (grade == GRADE_GOOD)    ? YELLOW   : RED;
    wire [15:0] dark   = (grade == GRADE_PERFECT) ? DK_GREEN :
                         (grade == GRADE_GOOD)    ? DK_YELLOW : DK_RED;

    assign colour = in_tile ? bright : dark;

endmodule
