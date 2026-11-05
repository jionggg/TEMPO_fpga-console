// My_Top_Module.v | v3 | 04 Nov 2026 23:15 SGT
// v3: audio debug from A on the board: 7-segment (seg/dp/an, always) and LEDs when sw[1] is up.
`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: VISHWANATH ANNANYA
//  STUDENT B NAME: LEE PEI LING
//  STUDENT C NAME: LI MEIYI
//  STUDENT D NAME: LIM JI YONG
//////////////////////////////////////////////////////////////////////////////////

// TEMPO top level. WIRING ONLY: no game logic lives here.
// v2 (drafted by A for D to review): rewired to the real A / B / C interfaces.
//   A -> B : the 7 raw audio signals (note_*, drum_*, sample_tick); B converts them
//   C -> B : separate piano / drum expected-event heads (pno_exp_*, drm_exp_*)
//   B -> C : pno_judged_id / drm_judged_id, judge_*, sync_*
//   C -> B : new_game -> session_clear
//   C -> D : 8-slot event lists, scores (unchanged from v1)
//   B's REPORT_DELAY_MS raised 250 -> 300: A's drum reports arrive ~230 ms after the hit.
//
//   1. Shared clocks, made once:  clk (100 MHz), clk_6p25M (OLEDs), ms_tick (1 ms)
//   2. Board controls
//   3. Wires between members
//   4. One module per member
//   5. Two OLED drivers           (5-lane piano on JA, 3-lane drum on JB)
//
// Team clock rule: every signal passed between members is on clk (100 MHz)
// and a "pulse" is high for exactly one clk cycle.
//////////////////////////////////////////////////////////////////////////////////

module My_Top_Module (
    input         clk,        // 100 MHz board clock (W5)
    input         btnC,       // start / confirm
    input         btnU,       // pause / resume
    input         btnD,       // quit to menu
    input         btnR,       // reset everything
    input  [15:0] sw,         // sw[0] = use mock_feed (D's test inputs), sw[1] = audio debug LEDs
    output [15:0] led,
    output [7:0]  JA,         // Pmod OLED, piano screen
    output [7:0]  JB,         // Pmod OLED, drum screen
    output        mic_cs,     // Pmod MIC3 on JC pin 1
    input         mic_miso,   // Pmod MIC3 on JC pin 3
    output        mic_sclk,   // Pmod MIC3 on JC pin 4
    output [6:0]  seg,        // 7-segment: A's audio debug (last note, last drum)
    output        dp,
    output [3:0]  an
    );

    // ---------------------------------------------------------------- 1. clocks
    wire clk_6p25M;                       // only for the two Oled_Display drivers
    flexible_clock_divider div_oled (
        .basys_clock (clk),
        .my_m_value  (32'd7),             // 100 MHz / (2 * 8) = 6.25 MHz
        .slower_clock(clk_6p25M)
    );

    wire ms_tick;                         // one clk-long pulse every 1 ms
    tick_gen #(.N(100_000)) tick_1ms (
        .clk (clk),
        .tick(ms_tick)
    );

    // ---------------------------------------------------------------- 2. controls
    wire rst     = btnR;
    wire sw_mock = sw[0];
    wire sw_audio_dbg = sw[1];

    // ---------------------------------------------------------------- 3. wires
    // A (Annanya) -> B (Pei Ling): raw detector outputs
    wire        note_valid;           // 1 clk per piano note
    wire [3:0]  note_code;            // 1..8 = C4 D4 E4 F4 G4 A4 B4 C5
    wire [31:0] note_timestamp;       // sample number of the note (16 per ms)
    wire        drum_valid;           // 1 clk per drum hit
    wire [2:0]  drum_type;            // 1 kick, 2 snare, 3 hi-hat/cymbal
    wire [31:0] drum_timestamp;
    wire [31:0] sample_tick;          // current sample number

    // C (Meiyi) -> everyone: game state and the one song clock
    wire [2:0]  game_state;           // 0 MENU, 1 COUNTDOWN, 2 PLAYING, 3 PAUSED, 4 RESULTS
    wire [1:0]  countdown_num;
    wire [17:0] song_time_ms;
    wire [17:0] song_len_ms;
    wire        new_game;             // 1 clk when a game starts (leaving MENU)

    // C -> B: expected-event heads, one per instrument
    wire        pno_exp_valid,   drm_exp_valid;
    wire [5:0]  pno_exp_id,      drm_exp_id;
    wire [2:0]  pno_exp_lane,    drm_exp_lane;
    wire [17:0] pno_exp_time_ms, drm_exp_time_ms;

    // B -> C: which event was just judged (63 = none)
    wire [5:0]  pno_judged_id, drm_judged_id;

    // C -> D: next 8 upcoming events per screen (slot 0 = soonest)
    wire [7:0]      pno_ev_valid, pno_ev_sync;
    wire [8*18-1:0] pno_ev_time;          // slot i = pno_ev_time[i*18 +: 18]
    wire [8*3-1:0]  pno_ev_lane;          // slot i = pno_ev_lane[i*3 +: 3]; 0..4 = C..G
    wire [7:0]      drm_ev_valid, drm_ev_sync;
    wire [8*18-1:0] drm_ev_time;
    wire [8*3-1:0]  drm_ev_lane;          // 0 crash, 1 snare, 2 bass

    // C -> D: scores
    wire [15:0] pno_score, drm_score;
    wire [7:0]  pno_combo, drm_combo;
    wire [1:0]  difficulty;

    // C -> D: sync buff (PROPOSED by D, not in game_intel). Tied to "no buff" so D's
    // ribbon hides the xN and the fuse. If Meiyi adds these outputs, delete the "= ..."
    // parts and connect them in member_c below.
    wire [3:0]  mult         = 4'd1;      // team multiplier: 1 = no buff, max 9
    wire [11:0] buff_ms_left = 12'd0;     // ms left on the buff, 0..3000

    // B -> C and D: judgements
    wire        judge_pulse;          // 1 clk per judgement
    wire        judge_player;         // 0 piano, 1 drum
    wire [1:0]  judge_grade;          // 0 MISS, 1 GOOD, 2 PERFECT
    wire [2:0]  judge_lane;           // piano 0..4; drum 0, 1, 2 (crash, snare, bass)
    wire [7:0]  judge_id;
    wire        sync_pulse, sync_ok;
    wire [7:0]  sync_id;
    wire        det_overflow;         // sticky: B's hit queue overflowed (debug)
    wire        eval_pending;

    // A -> board: audio debug
    wire [15:0] audio_dbg_led;

    // D <-> OLED drivers
    wire [12:0] pno_index, drm_index;     // pixel the OLED is asking about (0..6143)
    wire [15:0] pno_colour, drm_colour;   // RGB565 answer

    // ---------------------------------------------------------------- 4. members
    audio_dsp member_a (                  // Annanya
        .clk(clk), .rst(rst),
        .mic_cs(mic_cs), .mic_miso(mic_miso), .mic_sclk(mic_sclk),
        .note_valid(note_valid), .note_code(note_code), .note_timestamp(note_timestamp),
        .drum_valid(drum_valid), .drum_type(drum_type), .drum_timestamp(drum_timestamp),
        .sample_tick(sample_tick),
        .dbg_led(audio_dbg_led), .seg(seg), .dp(dp), .an(an)
    );

    perf_eval #(.REPORT_DELAY_MS(300)) member_b (   // Pei Ling
        .clk(clk), .rst(rst), .session_clear(new_game),
        .game_state(game_state), .song_time_ms(song_time_ms),
        .note_valid(note_valid), .note_code(note_code), .note_timestamp(note_timestamp),
        .drum_valid(drum_valid), .drum_type(drum_type), .drum_timestamp(drum_timestamp),
        .sample_tick(sample_tick),
        .pno_exp_valid(pno_exp_valid), .pno_exp_id(pno_exp_id),
        .pno_exp_lane(pno_exp_lane),   .pno_exp_time_ms(pno_exp_time_ms),
        .drm_exp_valid(drm_exp_valid), .drm_exp_id(drm_exp_id),
        .drm_exp_lane(drm_exp_lane),   .drm_exp_time_ms(drm_exp_time_ms),
        .pno_judged_id(pno_judged_id), .drm_judged_id(drm_judged_id),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_lane(judge_lane), .judge_grade(judge_grade), .judge_id(judge_id),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok), .sync_id(sync_id),
        .det_overflow(det_overflow), .pending(eval_pending)
    );

    game_intel member_c (                 // Meiyi
        .clk(clk), .rst(rst),
        .btn_start(btnC), .btn_pause(btnU), .btn_quit(btnD),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok),
        .pno_judged_id(pno_judged_id), .drm_judged_id(drm_judged_id),
        .game_state(game_state), .countdown_num(countdown_num),
        .song_time_ms(song_time_ms), .song_len_ms(song_len_ms),
        .new_game(new_game),
        .pno_exp_valid(pno_exp_valid), .pno_exp_id(pno_exp_id),
        .pno_exp_lane(pno_exp_lane),   .pno_exp_time_ms(pno_exp_time_ms),
        .drm_exp_valid(drm_exp_valid), .drm_exp_id(drm_exp_id),
        .drm_exp_lane(drm_exp_lane),   .drm_exp_time_ms(drm_exp_time_ms),
        .pno_ev_valid(pno_ev_valid), .pno_ev_time(pno_ev_time),
        .pno_ev_lane(pno_ev_lane),   .pno_ev_sync(pno_ev_sync),
        .drm_ev_valid(drm_ev_valid), .drm_ev_time(drm_ev_time),
        .drm_ev_lane(drm_ev_lane),   .drm_ev_sync(drm_ev_sync),
        .pno_score(pno_score), .drm_score(drm_score),
        .pno_combo(pno_combo), .drm_combo(drm_combo),
        .difficulty(difficulty)
    );

    display_top member_d (                // Ji Yong
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .sw_mock(sw_mock),
        .game_state(game_state), .countdown_num(countdown_num),
        .song_time_ms(song_time_ms), .song_len_ms(song_len_ms),
        .pno_ev_valid(pno_ev_valid), .pno_ev_time(pno_ev_time),
        .pno_ev_lane(pno_ev_lane), .pno_ev_sync(pno_ev_sync),
        .drm_ev_valid(drm_ev_valid), .drm_ev_time(drm_ev_time),
        .drm_ev_lane(drm_ev_lane), .drm_ev_sync(drm_ev_sync),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade), .judge_lane(judge_lane),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok),
        .pno_score(pno_score), .drm_score(drm_score),
        .pno_combo(pno_combo), .drm_combo(drm_combo),
        .difficulty(difficulty),
        .mult(mult), .buff_ms_left(buff_ms_left),
        .pno_index(pno_index), .pno_colour(pno_colour),
        .drm_index(drm_index), .drm_colour(drm_colour)
    );

    // ---------------------------------------------------------------- 5. OLEDs
    // Pmod OLED pins: 1 cs, 2 sdin, 3 (unused), 4 sclk, 7 d_cn, 8 resn, 9 vccen, 10 pmoden
    // reset must stay 0: the driver powers the screen with pmoden = !reset.
    Oled_Display oled_piano (
        .clk(clk_6p25M), .reset(1'b0),
        .frame_begin(), .sending_pixels(), .sample_pixel(),
        .pixel_index(pno_index), .pixel_data(pno_colour),
        .cs(JA[0]), .sdin(JA[1]), .sclk(JA[3]), .d_cn(JA[4]),
        .resn(JA[5]), .vccen(JA[6]), .pmoden(JA[7])
    );
    assign JA[2] = 1'b0;

    Oled_Display oled_drum (
        .clk(clk_6p25M), .reset(1'b0),
        .frame_begin(), .sending_pixels(), .sample_pixel(),
        .pixel_index(drm_index), .pixel_data(drm_colour),
        .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]), .d_cn(JB[4]),
        .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JB[2] = 1'b0;

    // ---------------------------------------------------------------- 6. debug
    // sw[1] down: led[2:0] = game_state, led[3] = B's hit queue overflowed (should stay off),
    //            led[15] = mock inputs on
    // sw[1] up:  A's audio debug - led[0..2] last drum (kick, snare, hi-hat),
    //            led[3..10] last note (C4..C5), led[11..15] mic level meter
    assign led = sw_audio_dbg ? audio_dbg_led
                              : {sw_mock, 11'd0, det_overflow, game_state};

endmodule