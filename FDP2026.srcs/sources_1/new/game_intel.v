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
//   to all game_state, countdown_num, song_time_ms, song_len_ms, song_select, new_game
//
// Scoring: PERFECT 100, GOOD 50, MISS 0 and combo back to 0; +50 to both players for
// every duet judged in sync (sync_ok). Scores and combos clear when a new game starts
// and stay visible on the RESULTS screen. The selected song is chosen in MENU.
module game_intel (
    input              clk,
    input              rst,
    input              btn_start,      // btnC (raw)
    input              btn_pause,      // btnU (pause/resume; menu next song)
    input              btn_quit,       // btnD (quit; menu previous song)
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
    output [1:0]       song_select,     // 0..2; D uses this to highlight the menu choice
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
    output [7:0]       drm_combo
    );

    `include "TEMPO_defs.vh"

    // ---------------------------------------------------------------- game FSM
    game_fsm u_fsm (
        .clk(clk), .rst(rst),
        .btnC(btn_start), .btnU(btn_pause), .btnD(btn_quit),
        .song_len_ms(song_len_ms),
        .game_state(game_state),
        .song_select(song_select),
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
        .new_game(new_game),
        .play_enable(game_state == ST_PLAYING),
        .song_select(song_select),
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

endmodule

