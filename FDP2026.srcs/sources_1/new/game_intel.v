// game_intel.v | v1 | 04 Nov 2026 18:50 SGT
`timescale 1ns / 1ps
// Member C: Li Meiyi - game intelligence (drafted by A for C to review)
//
// Wraps Meiyi's finished modules and adds the two missing pieces:
//   game_fsm        states, countdown, song clock, debounced buttons, new_game pulse
//   pattern_gen     song ROM -> piano / drum expected-event heads (to B) + tile spawn pulses
//   upcoming_slots  NEW: turns the spawn pulses into the next 8 events per screen (to D)
//   score_keeper    NEW: scores and combos per player from B's judgements (to D)
//
// Interfaces (all on clk, 100 MHz; pulses are 1 clk):
//   to B   pno_exp_* / drm_exp_*   oldest unjudged piano / drum event (levels)
//   from B pno_judged_id / drm_judged_id (63 = none), judge_*, sync_*
//   to D   pno_ev_* / drm_ev_*     8 slots each: slot i = [i*18 +: 18] time, [i*3 +: 3] lane,
//                                  slot 0 = soonest. A tile stays in its slot until
//                                  300 ms after its hit time (D's LATE_MS), then drops out.
//          *_ev_sync[i] = 1 when piano and drum land together (duet entry in the song).
//   to all game_state, countdown_num, song_time_ms, song_len_ms, new_game
//
// Scoring: PERFECT 100, GOOD 50, MISS 0 and combo back to 0; +50 to both players for
// every duet judged in sync (sync_ok). Scores and combos clear when a new game starts
// and stay visible on the RESULTS screen. difficulty is fixed at 0 (one song for now).
module game_intel (
    input              clk,
    input              rst,
    input              btn_start,      // btnC (raw)
    input              btn_pause,      // btnU (raw)
    input              btn_quit,       // btnD (raw)
    // from Pei Ling
    input              judge_pulse,
    input              judge_player,   // 0 piano, 1 drum
    input  [1:0]       judge_grade,
    input              sync_pulse,
    input              sync_ok,
    input  [5:0]       pno_judged_id,
    input  [5:0]       drm_judged_id,
    // to everyone
    output [2:0]       game_state,
    output [1:0]       countdown_num,
    output [17:0]      song_time_ms,
    output [17:0]      song_len_ms,
    output             new_game,
    // to Pei Ling: expected-event heads
    output             pno_exp_valid,
    output [5:0]       pno_exp_id,
    output [2:0]       pno_exp_lane,
    output [17:0]      pno_exp_time_ms,
    output             drm_exp_valid,
    output [5:0]       drm_exp_id,
    output [2:0]       drm_exp_lane,
    output [17:0]      drm_exp_time_ms,
    // to Ji Yong: next 8 events per screen
    output [7:0]       pno_ev_valid,
    output [8*18-1:0]  pno_ev_time,
    output [8*3-1:0]   pno_ev_lane,
    output [7:0]       pno_ev_sync,
    output [7:0]       drm_ev_valid,
    output [8*18-1:0]  drm_ev_time,
    output [8*3-1:0]   drm_ev_lane,
    output [7:0]       drm_ev_sync,
    // to Ji Yong: scores
    output [15:0]      pno_score,
    output [15:0]      drm_score,
    output [7:0]       pno_combo,
    output [7:0]       drm_combo,
    output [1:0]       difficulty
    );

    `include "TEMPO_defs.vh"

    // ---------------------------------------------------------------- game FSM
    game_fsm u_fsm (
        .clk(clk), .rst(rst),
        .btnC(btn_start), .btnU(btn_pause), .btnD(btn_quit),
        .song_len_ms(song_len_ms),
        .game_state(game_state),
        .song_time_ms(song_time_ms),
        .countdown_num(countdown_num),
        .countdown_go(),
        .new_game(new_game)
    );

    // ---------------------------------------------------------------- song + queues
    wire        spn_pno_valid, spn_drm_valid;      // 1-clk tile spawn pulses
    wire [5:0]  spn_pno_id,    spn_drm_id;
    wire [2:0]  spn_pno_lane,  spn_drm_lane;
    wire [17:0] spn_pno_time,  spn_drm_time;      // hit time of the spawned tile

    pattern_gen u_pattern (
        .clk(clk), .rst(rst),
        .song_time_ms(song_time_ms),
        .pno_judged_id(pno_judged_id),
        .drm_judged_id(drm_judged_id),
        .pno_exp_valid(pno_exp_valid), .pno_exp_id(pno_exp_id),
        .pno_exp_lane(pno_exp_lane),   .pno_exp_time_ms(pno_exp_time_ms),
        .drm_exp_valid(drm_exp_valid), .drm_exp_id(drm_exp_id),
        .drm_exp_lane(drm_exp_lane),   .drm_exp_time_ms(drm_exp_time_ms),
        .pno_ev_valid(spn_pno_valid),  .pno_ev_id(spn_pno_id),
        .pno_ev_lane(spn_pno_lane),    .pno_ev_time_ms(spn_pno_time),
        .drm_ev_valid(spn_drm_valid),  .drm_ev_id(spn_drm_id),
        .drm_ev_lane(spn_drm_lane),    .drm_ev_time_ms(spn_drm_time),
        .song_len_ms(song_len_ms)
    );

    // A duet ROM entry spawns its piano and drum tile in the same clock.
    wire spawn_sync = spn_pno_valid && spn_drm_valid;

    // ---------------------------------------------------------------- 8-slot lists for D
    // Emptied in MENU (song clock back at 0) and on reset.
    wire slots_clear = rst || (game_state == ST_MENU);

    upcoming_slots #(.KEEP_MS(300)) u_pno_slots (
        .clk(clk), .clear(slots_clear), .song_time_ms(song_time_ms),
        .spawn(spn_pno_valid), .spawn_time(spn_pno_time),
        .spawn_lane(spn_pno_lane), .spawn_sync(spawn_sync),
        .ev_valid(pno_ev_valid), .ev_time(pno_ev_time),
        .ev_lane(pno_ev_lane),   .ev_sync(pno_ev_sync)
    );

    upcoming_slots #(.KEEP_MS(300)) u_drm_slots (
        .clk(clk), .clear(slots_clear), .song_time_ms(song_time_ms),
        .spawn(spn_drm_valid), .spawn_time(spn_drm_time),
        .spawn_lane(spn_drm_lane), .spawn_sync(spawn_sync),
        .ev_valid(drm_ev_valid), .ev_time(drm_ev_time),
        .ev_lane(drm_ev_lane),   .ev_sync(drm_ev_sync)
    );

    // ---------------------------------------------------------------- scores
    score_keeper u_score (
        .clk(clk), .clear(rst || new_game),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok),
        .pno_score(pno_score), .drm_score(drm_score),
        .pno_combo(pno_combo), .drm_combo(drm_combo)
    );

    assign difficulty = 2'd0;

endmodule


// ============================================================================
// upcoming_slots: the next 8 tiles for one screen, oldest (soonest) in slot 0.
// Tiles arrive from pattern_gen in time order, so the list is a shift queue:
//   spawn  -> written into the first empty slot (if all 8 are full, the oldest
//             slot is dropped first; it is already past the hit line)
//   expire -> slot 0 leaves KEEP_MS after its hit time; the rest shift down
// ============================================================================
module upcoming_slots #(
    parameter integer KEEP_MS = 300          // = D's LATE_MS: missed tile keeps falling
)(
    input              clk,
    input              clear,
    input  [17:0]      song_time_ms,
    input              spawn,
    input  [17:0]      spawn_time,
    input  [2:0]       spawn_lane,
    input              spawn_sync,
    output [7:0]       ev_valid,
    output [8*18-1:0]  ev_time,
    output [8*3-1:0]   ev_lane,
    output [7:0]       ev_sync
    );

    reg [17:0] t  [0:7];
    reg [2:0]  ln [0:7];
    reg        sy [0:7];
    reg [3:0]  count = 4'd0;                 // slots in use, 0..8

    wire expire = (count != 4'd0) &&
                  ({14'd0, song_time_ms} > ({14'd0, t[0]} + KEEP_MS));
    wire shift  = expire || (spawn && (count == 4'd8));
    wire [3:0] count_kept = shift ? (count - 4'd1) : count;   // after dropping slot 0

    integer i;
    always @(posedge clk) begin
        if (clear) begin
            count <= 4'd0;
        end else begin
            if (shift) begin
                for (i = 0; i < 7; i = i + 1) begin
                    t[i]  <= t[i+1];
                    ln[i] <= ln[i+1];
                    sy[i] <= sy[i+1];
                end
            end
            if (spawn) begin                  // written after the shift (last write wins)
                t[count_kept[2:0]]  <= spawn_time;
                ln[count_kept[2:0]] <= spawn_lane;
                sy[count_kept[2:0]] <= spawn_sync;
            end
            count <= count_kept + (spawn ? 4'd1 : 4'd0);
        end
    end

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : pack
            assign ev_valid[g]          = (count > g);
            assign ev_time[g*18 +: 18]  = t[g];
            assign ev_lane[g*3 +: 3]    = ln[g];
            assign ev_sync[g]           = sy[g];
        end
    endgenerate

endmodule


// ============================================================================
// score_keeper: score and combo per player from B's judgements.
// judge_pulse and sync_pulse come from B in the same clock for a duet.
// ============================================================================
module score_keeper (
    input              clk,
    input              clear,
    input              judge_pulse,
    input              judge_player,     // 0 piano, 1 drum
    input  [1:0]       judge_grade,
    input              sync_pulse,
    input              sync_ok,
    output reg [15:0]  pno_score,
    output reg [15:0]  drm_score,
    output reg [7:0]   pno_combo,
    output reg [7:0]   drm_combo
    );

    `include "TEMPO_defs.vh"

    localparam [15:0] PTS_PERFECT = 16'd100,
                      PTS_GOOD    = 16'd50,
                      SYNC_BONUS  = 16'd50;

    wire        is_hit = (judge_grade == GRADE_PERFECT) || (judge_grade == GRADE_GOOD);
    wire [15:0] pts    = (judge_grade == GRADE_PERFECT) ? PTS_PERFECT :
                         (judge_grade == GRADE_GOOD)    ? PTS_GOOD    : 16'd0;
    wire [15:0] bonus  = (sync_pulse && sync_ok) ? SYNC_BONUS : 16'd0;

    wire [15:0] pno_add = ((judge_pulse && !judge_player) ? pts : 16'd0) + bonus;
    wire [15:0] drm_add = ((judge_pulse &&  judge_player) ? pts : 16'd0) + bonus;

    // 17-bit sums so the score stops at 65535 instead of wrapping
    wire [16:0] pno_sum = {1'b0, pno_score} + {1'b0, pno_add};
    wire [16:0] drm_sum = {1'b0, drm_score} + {1'b0, drm_add};

    always @(posedge clk) begin
        if (clear) begin
            pno_score <= 16'd0;  drm_score <= 16'd0;
            pno_combo <= 8'd0;   drm_combo <= 8'd0;
        end else begin
            pno_score <= pno_sum[16] ? 16'hFFFF : pno_sum[15:0];
            drm_score <= drm_sum[16] ? 16'hFFFF : drm_sum[15:0];
            if (judge_pulse && !judge_player)
                pno_combo <= !is_hit ? 8'd0 : (pno_combo == 8'hFF) ? 8'hFF : pno_combo + 8'd1;
            if (judge_pulse && judge_player)
                drm_combo <= !is_hit ? 8'd0 : (drm_combo == 8'hFF) ? 8'hFF : drm_combo + 8'd1;
        end
    end

endmodule