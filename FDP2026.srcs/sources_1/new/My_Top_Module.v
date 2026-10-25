`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: VISHWANATH ANNANYA
//  STUDENT B NAME: LEE PEI LING
//  STUDENT C NAME: LI MEIYI
//  STUDENT D NAME: LIM JI YONG
//////////////////////////////////////////////////////////////////////////////////

// TEMPO top level. WIRING ONLY: no game logic lives here.
//
//   1. Shared clocks, made once:  clk (100 MHz), clk_6p25M (OLEDs), ms_tick (1 ms)
//   2. Board controls
//   3. Wires between members      (names match the Miro UML)
//   4. One module per member      (each member edits only their OWN top_module file)
//   5. Two OLED drivers           (5lane piano on JA, 3lane drum on JB)
//
// Team clock rule: every signal passed between members is on clk (100 MHz)
// and a "pulse" is high for exactly one clk cycle. 
// Do not make a divided clock inside your module for anything a teammate reads.
//////////////////////////////////////////////////////////////////////////////////

module My_Top_Module (
    input         clk,        // 100 MHz board clock (W5)
    input         btnC,       // start / confirm   (to Meiyi's FSM)
    input         btnU,       // pause / resume
    input         btnD,       // quit to menu
    input         btnR,       // reset everything
    input  [15:0] sw,         // sw[0] = use mock_feed (jy's test inputs)
    output [15:0] led,
    output [7:0]  JA,         // Pmod OLED, piano screen
    output [7:0]  JB,         // Pmod OLED, drum screen
    output        mic_cs,     // Pmod MIC on JC pin 1 (JC[0])  - Annanya to confirm
    input         mic_miso,   // Pmod MIC on JC pin 3 (JC[2])
    output        mic_sclk    // Pmod MIC on JC pin 4 (JC[3])
    );

    // ---------------------------------------------------------------- 1. clocks
    wire clk_6p25M;                       // only for the two Oled_Display drivers
    flexible_clock_divider div_oled (
        .basys_clock (clk),
        .my_m_value  (32'd7),             // 100 MHz / (2 * 8) = 6.25 MHz
        .slower_clock(clk_6p25M)
    );

    wire ms_tick;                         // every 1 ms+
    tick_gen #(.N(100_000)) tick_1ms (      // count N = 100k means one tick per 1 ms 
        .clk (clk),
        .tick(ms_tick)
    );

    // ---------------------------------------------------------------- 2. controls
    wire rst     = btnR;
    wire sw_mock = sw[0];

    // ---------------------------------------------------------------- 3. wires
    // A (Annanya) -> B (Pei Ling): detected hits
    wire        det_pulse;      // detected hit is temporally bound by one clk cycle (so 100 MHz)
    wire        det_is_drum;
    wire [2:0]  det_note;       // piano NOTE_C..NOTE_G, or DRUM_CRASH/SNARE/BASS
    wire [17:0] det_time_ms;      // (all lane codes live in tempo_defs.vh)
    
    // C (Meiyi) -> everyone: game state and the one song clock
    wire [2:0]  game_state;    // 0 MENU, 1 COUNTDOWN, 2 PLAYING, 3 PAUSED, 4 RESULTS
    wire [1:0]  countdown_num;
    wire [17:0] song_time_ms;
    wire [17:0] song_len_ms;

    // C -> B: next expected event
    wire        exp_valid;
    wire [7:0]  exp_id;
    wire        exp_is_drum;
    wire [2:0]  exp_note;         // same lane codes as det_note in ln61
    wire [17:0] exp_time_ms;

    // C -> D: next 8 upcoming events per screen (slot 0 = soonest)
    wire [7:0]      pno_ev_valid, pno_ev_sync;
    wire [8*18-1:0] pno_ev_time;          // slot i = pno_ev_time[i*18 +: 18]
    wire [8*3-1:0]  pno_ev_lane;          // slot i = pno_ev_lane[i*3 +: 3]     ; 0,1,2,3,4 = C,D,E,F,G
    wire [7:0]      drm_ev_valid, drm_ev_sync;
    wire [8*18-1:0] drm_ev_time;
    wire [8*3-1:0]  drm_ev_lane;          // 0 crash, 1 snare, 2 bass

    // C -> D: scores
    wire [15:0] pno_score, drm_score;
    wire [7:0]  pno_combo, drm_combo;
    wire [1:0]  difficulty;

    // B -> C and D: judgements
    wire        judge_pulse;         // 1 clk per judgement
    wire        judge_player;        // 0 piano, 1 drum
    wire [1:0]  judge_grade;         // 0 MISS, 1 GOOD, 2 PERFECT
    wire [2:0]  judge_lane;         // piano: 0, ..., 4; drum 0, 1, 2 (crash, snare, bass)
    wire [7:0]  judge_id;
    wire        sync_pulse, sync_ok;

    // D <-> OLED drivers
    wire [12:0] pno_index, drm_index;     // pixel the OLED is asking about (0..6143)
    wire [15:0] pno_colour, drm_colour;   // RGB565 answer

    // ---------------------------------------------------------------- 4. members
    audio_dsp member_a (                  // Annanya
        .clk(clk), .rst(rst),
        .game_state(game_state), .song_time_ms(song_time_ms),
        .mic_cs(mic_cs), .mic_miso(mic_miso), .mic_sclk(mic_sclk),
        .det_pulse(det_pulse), .det_is_drum(det_is_drum),
        .det_note(det_note), .det_time_ms(det_time_ms)
    );

    perf_eval member_b (                  // Pei Ling
        .clk(clk), .rst(rst),
        .game_state(game_state), .song_time_ms(song_time_ms),
        .det_pulse(det_pulse), .det_is_drum(det_is_drum),
        .det_note(det_note), .det_time_ms(det_time_ms),
        .exp_valid(exp_valid), .exp_id(exp_id), .exp_is_drum(exp_is_drum),
        .exp_note(exp_note), .exp_time_ms(exp_time_ms),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade), .judge_lane(judge_lane), .judge_id(judge_id),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok)
    );

    game_intel member_c (                 // Meiyi
        .clk(clk), .rst(rst), .ms_tick(ms_tick),
        .btn_start(btnC), .btn_pause(btnU), .btn_quit(btnD),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade), .judge_id(judge_id),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok),
        .game_state(game_state), .countdown_num(countdown_num),
        .song_time_ms(song_time_ms), .song_len_ms(song_len_ms),
        .exp_valid(exp_valid), .exp_id(exp_id), .exp_is_drum(exp_is_drum),
        .exp_note(exp_note), .exp_time_ms(exp_time_ms),
        .pno_ev_valid(pno_ev_valid), .pno_ev_time(pno_ev_time),
        .pno_ev_lane(pno_ev_lane), .pno_ev_sync(pno_ev_sync),
        .drm_ev_valid(drm_ev_valid), .drm_ev_time(drm_ev_time),
        .drm_ev_lane(drm_ev_lane), .drm_ev_sync(drm_ev_sync),
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
    assign led = {sw_mock, 12'd0, game_state};   // led[2:0] = game_state, led[15] = mock on

endmodule
