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
// Wrong presses (v0.05): a key or drum that was played but did not hit a tile in its
// own lane (wrong key, extra hit, nothing due) leaves a burgundy slice of the same size,
// in the lane that was actually played, falling the same way.
//
// Modules in this file:
//   hit_log      4 records per player, written on each PERFECT / GOOD judgement
//   wrong_log    4 records per player, written on every press, crossed out again when
//                Pei Ling grades that press as a hit in the same lane
//   press_track  turns Annanya's raw note / drum reports into (lane, song ms), the way
//                Pei Ling's perf_eval does
//   hit_slot     one record (like one tile slot): valid, lane, target, hit, grade
//   hit_mark     for one record and one pixel: is this pixel painted, and in what colour?
//
// Needs Pei Ling's judge_target_ms / judge_hit_ms (perf_eval v4). A MISS paints nothing
// on its tile any more: on piano a wrong key comes back as a MISS for the tile that was
// due (with the wrong key's time), and that press is shown in its own lane instead.
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

    `include "TEMPO_defs.vh"       // GRADE_MISS

    // A new record goes into the oldest slot: wr counts 0, 1, 2, 3, 0, ...
    // Only real hits: a MISS (even one carrying a wrong key's time) paints nothing here.
    wire write = judge_pulse && (judge_player == PLAYER) && (judge_hit_ms != 18'd0) &&
                 (judge_grade != GRADE_MISS);
    reg  [1:0] wr = 2'd0;
    always @(posedge clk) begin
        if (clear)      wr <= 2'd0;
        else if (write) wr <= wr + 2'd1;
    end

    // If the song clock jumps backwards (restart), old records no longer make sense.
    reg  [17:0] last_time = 18'd0;
    always @(posedge clk) last_time <= song_time_ms;
    wire wipe = clear || (song_time_ms < last_time);

    hit_slot s0 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd0), .cancel(1'b0), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[0]), .lane(rec_lane[2:0]), .grade(rec_grade[1:0]),
        .target(rec_target[17:0]), .hit(rec_hit[17:0]));
    hit_slot s1 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd1), .cancel(1'b0), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[1]), .lane(rec_lane[5:3]), .grade(rec_grade[3:2]),
        .target(rec_target[35:18]), .hit(rec_hit[35:18]));
    hit_slot s2 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd2), .cancel(1'b0), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[2]), .lane(rec_lane[8:6]), .grade(rec_grade[5:4]),
        .target(rec_target[53:36]), .hit(rec_hit[53:36]));
    hit_slot s3 (.clk(clk), .wipe(wipe), .write(write && wr == 2'd3), .cancel(1'b0), .song_time_ms(song_time_ms),
        .lane_in(judge_lane), .grade_in(judge_grade), .target_in(judge_target_ms), .hit_in(judge_hit_ms),
        .valid(rec_valid[3]), .lane(rec_lane[11:9]), .grade(rec_grade[7:6]),
        .target(rec_target[71:54]), .hit(rec_hit[71:54]));

endmodule


//////////////////////////////////////////////////////////////////////////////////
// hit_slot - one remembered hit. Forgets itself once both slices have scrolled off
// the bottom of the screen (MARK_MS after the later of the two moments), or when
// cancel says so (wrong_log: the press turned out to be a real hit).
//////////////////////////////////////////////////////////////////////////////////

module hit_slot (
    input             clk,
    input             wipe,
    input             write,
    input             cancel,
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
        end else if (cancel)
            valid <= 1'b0;                                  // it was a real hit after all
        else if (valid && song_time_ms > done_at)
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

    // a wrong press (grade MARK_WRONG) is burgundy all over: there is no tile to compare with
    assign colour = (grade == MARK_WRONG) ? BURGUNDY :
                    in_tile               ? bright   : dark;

endmodule


//////////////////////////////////////////////////////////////////////////////////
// wrong_log - the last 4 presses of one player that did not hit a tile in their lane
//
// Every press is written straight away (as if it were wrong). Pei Ling needs about
// 1 microsecond to judge it; if she grades a PERFECT or GOOD in the same lane at the
// same moment, that record is crossed out again long before it could be seen. Like
// writing every footprint in the snow down, then rubbing out the ones that landed on
// a stepping stone: what is left are the missteps.
//////////////////////////////////////////////////////////////////////////////////

module wrong_log #(parameter PLAYER = 0) (     // PLAYER: 0 = piano, 1 = drum
    input          clk,
    input          clear,                   // new game / reset: forget everything
    input  [17:0]  song_time_ms,
    input          press,                   // 1 clk: this player played something
    input  [2:0]   press_lane,              // ... in this lane
    input  [17:0]  press_time,              // ... at this song time
    input          judge_pulse,             // Pei Ling's judgements
    input          judge_player,
    input  [2:0]   judge_lane,
    input  [1:0]   judge_grade,
    input  [17:0]  judge_hit_ms,
    output [3:0]   rec_valid,               // record i = bit i (same layout as hit_log)
    output [11:0]  rec_lane,
    output [71:0]  rec_target,
    output [71:0]  rec_hit,
    output [7:0]   rec_grade
    );

    `include "TEMPO_defs.vh"       // GRADE_MISS
    `include "TEMPO_layout.vh"     // MARK_WRONG

    // A new press goes into the oldest slot: wr counts 0, 1, 2, 3, 0, ...
    reg [1:0] wr = 2'd0;
    always @(posedge clk) begin
        if (clear)      wr <= 2'd0;
        else if (press) wr <= wr + 2'd1;
    end

    // If the song clock jumps backwards (restart), old records no longer make sense.
    reg  [17:0] last_time = 18'd0;
    always @(posedge clk) last_time <= song_time_ms;
    wire wipe = clear || (song_time_ms < last_time);

    // A real hit by this player. Pei Ling and this display turn Annanya's timestamps into
    // song ms on slightly different clocks, so "the same moment" means within 2 ms.
    wire good = judge_pulse && (judge_player == PLAYER) && (judge_grade != GRADE_MISS);

    wire [17:0] t0 = rec_target[17:0],  t1 = rec_target[35:18];
    wire [17:0] t2 = rec_target[53:36], t3 = rec_target[71:54];
    wire [17:0] e0 = (t0 > judge_hit_ms) ? t0 - judge_hit_ms : judge_hit_ms - t0;
    wire [17:0] e1 = (t1 > judge_hit_ms) ? t1 - judge_hit_ms : judge_hit_ms - t1;
    wire [17:0] e2 = (t2 > judge_hit_ms) ? t2 - judge_hit_ms : judge_hit_ms - t2;
    wire [17:0] e3 = (t3 > judge_hit_ms) ? t3 - judge_hit_ms : judge_hit_ms - t3;
    wire k0 = good && rec_valid[0] && (rec_lane[2:0]  == judge_lane) && (e0 <= 18'd2);
    wire k1 = good && rec_valid[1] && (rec_lane[5:3]  == judge_lane) && (e1 <= 18'd2);
    wire k2 = good && rec_valid[2] && (rec_lane[8:6]  == judge_lane) && (e2 <= 18'd2);
    wire k3 = good && rec_valid[3] && (rec_lane[11:9] == judge_lane) && (e3 <= 18'd2);

    // target = hit = the press time; grade MARK_WRONG makes hit_mark paint it burgundy
    hit_slot s0 (.clk(clk), .wipe(wipe), .write(press && wr == 2'd0), .cancel(k0), .song_time_ms(song_time_ms),
        .lane_in(press_lane), .grade_in(MARK_WRONG), .target_in(press_time), .hit_in(press_time),
        .valid(rec_valid[0]), .lane(rec_lane[2:0]), .grade(rec_grade[1:0]),
        .target(rec_target[17:0]), .hit(rec_hit[17:0]));
    hit_slot s1 (.clk(clk), .wipe(wipe), .write(press && wr == 2'd1), .cancel(k1), .song_time_ms(song_time_ms),
        .lane_in(press_lane), .grade_in(MARK_WRONG), .target_in(press_time), .hit_in(press_time),
        .valid(rec_valid[1]), .lane(rec_lane[5:3]), .grade(rec_grade[3:2]),
        .target(rec_target[35:18]), .hit(rec_hit[35:18]));
    hit_slot s2 (.clk(clk), .wipe(wipe), .write(press && wr == 2'd2), .cancel(k2), .song_time_ms(song_time_ms),
        .lane_in(press_lane), .grade_in(MARK_WRONG), .target_in(press_time), .hit_in(press_time),
        .valid(rec_valid[2]), .lane(rec_lane[8:6]), .grade(rec_grade[5:4]),
        .target(rec_target[53:36]), .hit(rec_hit[53:36]));
    hit_slot s3 (.clk(clk), .wipe(wipe), .write(press && wr == 2'd3), .cancel(k3), .song_time_ms(song_time_ms),
        .lane_in(press_lane), .grade_in(MARK_WRONG), .target_in(press_time), .hit_in(press_time),
        .valid(rec_valid[3]), .lane(rec_lane[11:9]), .grade(rec_grade[7:6]),
        .target(rec_target[71:54]), .hit(rec_hit[71:54]));

endmodule


//////////////////////////////////////////////////////////////////////////////////
// press_track - Annanya's raw reports -> (lane, song ms), copied from Pei Ling's
// perf_eval report stages R1 / R2 so both agree on when a press happened:
//   onset = song_time - (sample_tick - timestamp) / 16      (16 samples per ms)
// Piano: codes 1..5 (C4..G4) -> lanes 0..4; A4, B4, C5 have no lane and are skipped.
// Drums: 1 kick -> bass (2), 2 snare -> snare (1), 3 hi-hat -> hi-hat lane (0).
// Only while PLAYING, and only presses made after play started or resumed (like B).
//////////////////////////////////////////////////////////////////////////////////

module press_track (
    input             clk,
    input             playing,          // game_state == PLAYING (and not test mode)
    input      [17:0] song_time_ms,
    input             note_valid,       // from Annanya
    input      [3:0]  note_code,
    input      [31:0] note_timestamp,
    input             drum_valid,
    input      [2:0]  drum_type,
    input      [31:0] drum_timestamp,
    input      [31:0] sample_tick,
    output reg        pno_press = 1'b0, // 1 clk per piano press with a lane
    output reg [2:0]  pno_lane  = 3'd0,
    output reg [17:0] pno_time  = 18'd0,
    output reg        drm_press = 1'b0, // 1 clk per drum press
    output reg [2:0]  drm_lane  = 3'd0,
    output reg [17:0] drm_time  = 18'd0
    );

    // the sample number when play started or resumed; reports from before it are ignored
    reg        was_playing  = 1'b0;
    reg [31:0] start_sample = 32'd0;
    always @(posedge clk) begin
        was_playing <= playing;
        if (playing && !was_playing) start_sample <= sample_tick;
    end
    wire starting = playing && !was_playing;     // B drops reports on this clock too

    // stage 1: how old each report is, in samples (like B's R1)
    reg        p1_valid = 1'b0, d1_valid = 1'b0;
    reg [3:0]  p1_code  = 4'd0;
    reg [2:0]  d1_type  = 3'd0;
    reg [31:0] p1_age   = 32'd0, d1_age   = 32'd0;
    reg [31:0] p1_since = 32'd0, d1_since = 32'd0;
    reg [17:0] now1     = 18'd0;
    always @(posedge clk) begin
        p1_valid <= note_valid && playing && !starting;
        d1_valid <= drum_valid && playing && !starting;
        p1_code  <= note_code;
        d1_type  <= drum_type;
        p1_age   <= sample_tick - note_timestamp;
        d1_age   <= sample_tick - drum_timestamp;
        p1_since <= note_timestamp - start_sample;
        d1_since <= drum_timestamp - start_sample;
        now1     <= song_time_ms;
    end

    // stage 2: onset in song ms and lane (like B's R2). bit 31 set = "negative".
    wire [31:0] p_age_ms = p1_age >> 4;
    wire [31:0] d_age_ms = d1_age >> 4;
    wire p_ok = !p1_age[31] && !p1_since[31] && (p_age_ms <= {14'd0, now1}) &&
                (p1_code >= 4'd1) && (p1_code <= 4'd5);
    wire d_ok = !d1_age[31] && !d1_since[31] && (d_age_ms <= {14'd0, now1}) &&
                (d1_type >= 3'd1) && (d1_type <= 3'd3);
    always @(posedge clk) begin
        pno_press <= p1_valid && p_ok && playing;
        pno_lane  <= p1_code[2:0] - 3'd1;
        pno_time  <= now1 - p_age_ms[17:0];
        drm_press <= d1_valid && d_ok && playing;
        drm_lane  <= (d1_type == 3'd1) ? 3'd2 : (d1_type == 3'd2) ? 3'd1 : 3'd0;
        drm_time  <= now1 - d_age_ms[17:0];
    end

endmodule
