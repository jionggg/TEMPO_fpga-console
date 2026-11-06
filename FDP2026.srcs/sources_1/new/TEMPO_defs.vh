// TEMPO_defs.vh | v2 | 04 Nov 2026 18:00 SGT
// v2_Annanya: fixed TEMPO_DRUM_LANE_BASS (was DRUM_KICK, which does not exist -> compile error).
//     A's hi-hat class is judged on the DRUM_CRASH lane (team decision 04 Nov).
// tempo_defs.vh - str codes every module agrees on

// to call this header file INSIDE a module, after the port list:
//     `include "TEMPO_defs.vh"

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
// (A detects kick -> DRUM_BASS, snare -> DRUM_SNARE, hi-hat/cymbal -> DRUM_CRASH)
// left to right on the drum OLED
localparam [2:0] DRUM_CRASH = 3'd0,
                 DRUM_SNARE = 3'd1,   
                 DRUM_BASS  = 3'd2,   
                 DRUM_NONE = 3'd3; 
localparam       DRUM_LANES = 3;




// ---------------------------------------------------------------------------
// Clock, countdown, and gameplay timing
// ---------------------------------------------------------------------------

localparam integer CLK_FREQ_HZ         = 100_000_000;
localparam integer COUNTDOWN_SECONDS   = 3;
localparam integer COUNTDOWN_STEP_MS   = 1000;
localparam integer GO_DISPLAY_MS       = 500;
localparam integer LOOKAHEAD_MS        = 1500;
localparam integer HIT_WINDOW_MS       = 150;
localparam integer SONG_END_PADDING_MS = 200;

// ---------------------------------------------------------------------------
// Song chart timing
// ---------------------------------------------------------------------------

localparam integer TOTAL_NOTES           = 62;
localparam integer START_TIME_MS         = 1000;
localparam integer BEAT_INTERVAL_MS     = 400;
localparam integer LAST_NOTE_BEAT_OFFSET = 62;
localparam integer LAST_NOTE_TIME_MS    = START_TIME_MS +
                                           (LAST_NOTE_BEAT_OFFSET *
                                            BEAT_INTERVAL_MS);

// Derived fractional beat values used by song_rom.
localparam integer HALF_BEAT_MS  = BEAT_INTERVAL_MS / 2;
localparam integer FOURTH_BEAT_MS = BEAT_INTERVAL_MS / 4;

// ---------------------------------------------------------------------------
// Song ROM event fields
// ---------------------------------------------------------------------------

// event_type [1:0]
localparam [1:0] EVENT_NONE  = 2'b00,
                 EVENT_PIANO = 2'b01,
                 EVENT_DRUM  = 2'b10,
                 EVENT_DUET  = 2'b11;

// Drum codes stored inside the ROM event word [9:6]. These are not OLED lane
// codes: ROM code 1 maps to DRUM_BASS and ROM code 2 maps to DRUM_SNARE.
localparam [3:0] ROM_DRUM_NONE  = 4'd0,
                 ROM_DRUM_KICK  = 4'd1,
                 ROM_DRUM_SNARE = 4'd2,
                 ROM_DRUM_CRASH = 4'd3;

// ROM piano notes are stored as 1..5 and converted to lanes 0..4.
localparam [3:0] ROM_PIANO_FIRST_NOTE  = 4'd1;
localparam [3:0] ROM_PIANO_NOTE_OFFSET = 4'd1;

// Expected-event queue special value.
localparam [5:0] NO_JUDGEMENT_ID = 6'd63;

// ---------------------------------------------------------------------------
// Compatibility aliases for the earlier TEMPO module versions
// ---------------------------------------------------------------------------

localparam [2:0] TEMPO_STATE_MENU      = ST_MENU;
localparam [2:0] TEMPO_STATE_COUNTDOWN = ST_COUNTDOWN;
localparam [2:0] TEMPO_STATE_PLAYING   = ST_PLAYING;
localparam [2:0] TEMPO_STATE_PAUSED    = ST_PAUSED;
localparam [2:0] TEMPO_STATE_RESULTS   = ST_RESULTS;

localparam [1:0] TEMPO_EVENT_NONE  = EVENT_NONE;
localparam [1:0] TEMPO_EVENT_PIANO = EVENT_PIANO;
localparam [1:0] TEMPO_EVENT_DRUM  = EVENT_DRUM;
localparam [1:0] TEMPO_EVENT_DUET  = EVENT_DUET;

localparam [3:0] TEMPO_DRUM_NONE  = ROM_DRUM_NONE;
localparam [3:0] TEMPO_DRUM_KICK  = ROM_DRUM_KICK;
localparam [3:0] TEMPO_DRUM_SNARE = ROM_DRUM_SNARE;

localparam [3:0] TEMPO_PIANO_FIRST_NOTE  = ROM_PIANO_FIRST_NOTE;
localparam [3:0] TEMPO_PIANO_NOTE_OFFSET = ROM_PIANO_NOTE_OFFSET;

localparam [2:0] TEMPO_DRUM_LANE_SNARE = DRUM_SNARE;
localparam [2:0] TEMPO_DRUM_LANE_BASS  = DRUM_BASS;