// tempo_defs.vh - the codes every TEMPO module agrees on.

// to call this header file INSIDE a module, after the port list:
//     `include "tempo_defs.vh"

// each module that includes it gets its own copy of these localparams, so there is
// no clash when one file's hardcode is edited. 
// use the names (eg DRUM_SNARE), not the raw numbers (3'd1), so tht changes
// here reaches everyone's modules

// game_state [2:0] - written only by Meiyi's game_fsm
localparam [2:0] ST_MENU      = 3'd0,     
                 ST_COUNTDOWN = 3'd1,
                 ST_PLAYING   = 3'd2,
                 ST_PAUSED    = 3'd3,
                 ST_RESULTS   = 3'd4;

// judge_grade [1:0] - written only by Pei Ling's perf_eval
localparam [1:0] GRADE_MISS    = 2'd0,
                 GRADE_GOOD    = 2'd1,
                 GRADE_PERFECT = 2'd2;

// lane codes [2:0] is shared by det_note, exp_note, judge_lane, pno_ev_lane, drm_ev_lane
// the is_drum / player bit says which table applies

// Piano (det_is_drum = 0, exp_is_drum = 0, judge_player = 0): one lane per note
localparam [2:0] NOTE_C = 3'd0,
                 NOTE_D = 3'd1,
                 NOTE_E = 3'd2,
                 NOTE_F = 3'd3,
                 NOTE_G = 3'd4;
localparam       PIANO_LANES = 5;

// Drums (det_is_drum = 1, exp_is_drum = 1, judge_player = 1): one lane per drum
// left to right on the drum OLED
localparam [2:0] DRUM_CRASH = 3'd0,    // crash cymbal
                 DRUM_SNARE = 3'd1,    // snare drum
                 DRUM_BASS  = 3'd2;    // bass (kick) drum
localparam       DRUM_LANES = 3;
