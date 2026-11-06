// perf_eval.v | v4 | 06 Nov 2026 SGT
// v4 (added by D, Ji Yong, for B to review; judging behaviour unchanged): two extra
//   outputs, judge_target_ms and judge_hit_ms, valid with each judge_pulse, so D can draw
//   how early / late a hit was. judge_hit_ms = 0 when nothing was hit (expired MISS).
// v3 (timing fix by A for B to review; judging behaviour unchanged):
//   - A's reports go through 2 register stages before the engine's queues:
//     R1 = age and since-play-start subtractions, R2 = onset time in song ms + lane/ok flags.
//     Reports reach the engine 2 clocks (20 ns) later; timestamps are unchanged.
//   - C's expected-event heads are registered once (C holds them as levels).
//   - now_ms and the engine reset are registered (1 clock later).
//   v2 failed timing at 100 MHz in the full team build (paths into the engine's
//   hit queues and targets/lanes tables).
// v2 (04 Nov): A's hi-hat (drum_type 3) maps to the crash lane (0) instead of being ignored.
`timescale 1ns / 1ps

// Member B: Pei Ling - performance evaluation (match hits, grade, sync judge)
// perf_eval: public ports, audio-code conversion, sample-count timestamps to song milliseconds, session clearing, pause/resume boundaries, final-report drain timer.


module perf_eval #(
    parameter integer PERFECT_MS=50,
    parameter integer GOOD_MS=150,
    parameter integer REPORT_DELAY_MS=300,
    parameter integer SYNC_MS=50,
    parameter integer CLKS_PER_MS=100_000,
    parameter integer RAW_AUDIO_INPUT=1
)(
    input clk, input rst, input session_clear,
    input [2:0] game_state, input [17:0] song_time_ms,
    input note_valid, input [3:0] note_code, input [31:0] note_timestamp,
    input drum_valid, input [2:0] drum_type, input [31:0] drum_timestamp,
    input [31:0] sample_tick,
    input pno_exp_valid, input [5:0] pno_exp_id,
    input [2:0] pno_exp_lane, input [17:0] pno_exp_time_ms,
    input drm_exp_valid, input [5:0] drm_exp_id,
    input [2:0] drm_exp_lane, input [17:0] drm_exp_time_ms,
    output [5:0] pno_judged_id, output [5:0] drm_judged_id,
    output judge_pulse, output judge_player, output [2:0] judge_lane,
    output [1:0] judge_grade, output [7:0] judge_id,
    output [17:0] judge_target_ms,       // v4: when the judged note was due (song ms)
    output [17:0] judge_hit_ms,          // v4: when it was actually hit, 0 = not hit
    output sync_pulse, output sync_ok, output [7:0] sync_id,
    output det_overflow, output pending
);
    localparam [2:0] MENU=0, PLAY=2, RESULTS=4;
    localparam [31:0] DRAIN_LIMIT=GOOD_MS+REPORT_DELAY_MS+2;
    reg [2:0] previous_state;
    reg [17:0] previous_song_time;
    reg [31:0] play_start_sample;
    reg [17:0] play_start_song_ms;
    reg [31:0] drain_clocks, drain_ms;
    wire rewound=song_time_ms<previous_song_time;
    wire clear=rst || session_clear || game_state==MENU || rewound;
    wire enable=game_state==PLAY || game_state==RESULTS;
    wire boundary_ok=!(game_state==PLAY && previous_state!=PLAY);
    wire [31:0] now_ms={14'd0,song_time_ms}+(game_state==RESULTS ? drain_ms : 32'd0);

    // v3: registered copies (1 clock later)
    reg        eng_reset = 1'b1;
    reg [31:0] now_ms_q  = 32'd0;
    reg        pno_exp_valid_q = 1'b0, drm_exp_valid_q = 1'b0;
    reg [5:0]  pno_exp_id_q = 6'd63,   drm_exp_id_q = 6'd63;
    reg [2:0]  pno_exp_lane_q = 3'd0,  drm_exp_lane_q = 3'd0;
    reg [17:0] pno_exp_time_q = 18'd0, drm_exp_time_q = 18'd0;
    always @(posedge clk) begin
        eng_reset <= clear;
        now_ms_q  <= now_ms;
        pno_exp_valid_q <= pno_exp_valid; pno_exp_id_q <= pno_exp_id;
        pno_exp_lane_q  <= pno_exp_lane;  pno_exp_time_q <= pno_exp_time_ms;
        drm_exp_valid_q <= drm_exp_valid; drm_exp_id_q <= drm_exp_id;
        drm_exp_lane_q  <= drm_exp_lane;  drm_exp_time_q <= drm_exp_time_ms;
    end

    // ---------------- report stage R1: subtractions in the 16 kHz sample domain ----------------
    // Current sample clock and reported onset are in the same 16 kHz domain.
    // Mapping via report age removes reset/countdown offsets without changing A.
    reg        r1_pn_valid = 1'b0, r1_dr_valid = 1'b0;
    reg [3:0]  r1_pn_code = 4'd0;
    reg [2:0]  r1_dr_type = 3'd0;
    reg [31:0] r1_pn_ts = 32'd0, r1_dr_ts = 32'd0;
    reg [31:0] r1_pn_age = 32'd0, r1_dr_age = 32'd0;
    reg [31:0] r1_pn_since = 32'd0, r1_dr_since = 32'd0;
    always @(posedge clk) begin
        if (clear || !enable || !boundary_ok) begin
            r1_pn_valid <= 1'b0; r1_dr_valid <= 1'b0;
        end else begin
            r1_pn_valid <= note_valid;  r1_dr_valid <= drum_valid;
        end
        r1_pn_code  <= note_code;                       r1_dr_type  <= drum_type;
        r1_pn_ts    <= note_timestamp;                  r1_dr_ts    <= drum_timestamp;
        r1_pn_age   <= sample_tick - note_timestamp;    r1_dr_age   <= sample_tick - drum_timestamp;
        r1_pn_since <= note_timestamp - play_start_sample;
        r1_dr_since <= drum_timestamp - play_start_sample;
    end

    // ---------------- report stage R2: onset in song ms, lane codes, checks ----------------
    wire signed [32:0] pn_onset_signed=$signed({1'b0,now_ms_q})-$signed({1'b0,(r1_pn_age>>4)});
    wire signed [32:0] dr_onset_signed=$signed({1'b0,now_ms_q})-$signed({1'b0,(r1_dr_age>>4)});
    wire [31:0] pn_time=RAW_AUDIO_INPUT ? pn_onset_signed[31:0] : r1_pn_ts;
    wire [31:0] dr_time=RAW_AUDIO_INPUT ? dr_onset_signed[31:0] : r1_dr_ts;
    wire pn_time_ok=RAW_AUDIO_INPUT ?
        (!r1_pn_age[31] && !r1_pn_since[31] && !pn_onset_signed[32]) :
        (r1_pn_ts>={14'd0,play_start_song_ms} && r1_pn_ts<=now_ms_q);
    wire dr_time_ok=RAW_AUDIO_INPUT ?
        (!r1_dr_age[31] && !r1_dr_since[31] && !dr_onset_signed[32]) :
        (r1_dr_ts>={14'd0,play_start_song_ms} && r1_dr_ts<=now_ms_q);

    // A: C4..G4=1..5 -> game lanes 0..4. A4/B4/C5 remain wrong notes.
    wire [2:0] pn_lane=RAW_AUDIO_INPUT ?
        ((r1_pn_code>=1 && r1_pn_code<=5) ? r1_pn_code[2:0]-3'd1 : 3'd7) :
        (r1_pn_code<=4 ? r1_pn_code[2:0] : 3'd7);
    wire pn_code_ok=RAW_AUDIO_INPUT ? (r1_pn_code>=1 && r1_pn_code<=8) : 1'b1;
    // A: kick=1 -> bass=2, snare=2 -> snare=1, hi-hat/cymbal=3 -> crash=0
    // (team decision 04 Nov: A's hi-hat class is judged on the crash lane).
    wire [2:0] dr_lane=RAW_AUDIO_INPUT ?
        (r1_dr_type==1 ? 3'd2 : r1_dr_type==2 ? 3'd1 : r1_dr_type==3 ? 3'd0 : 3'd3) : r1_dr_type;
    wire dr_code_ok=RAW_AUDIO_INPUT ? (r1_dr_type>=1 && r1_dr_type<=3) : r1_dr_type<=2;

    reg        r2_pn_valid = 1'b0, r2_dr_valid = 1'b0;
    reg        r2_pn_ok = 1'b0,    r2_dr_ok = 1'b0;
    reg [2:0]  r2_pn_lane = 3'd0,  r2_dr_lane = 3'd0;
    reg [31:0] r2_pn_time = 32'd0, r2_dr_time = 32'd0;
    always @(posedge clk) begin
        if (clear || !enable || !boundary_ok) begin
            r2_pn_valid <= 1'b0; r2_dr_valid <= 1'b0;
        end else begin
            r2_pn_valid <= r1_pn_valid; r2_dr_valid <= r1_dr_valid;
        end
        r2_pn_ok   <= pn_code_ok && pn_time_ok;  r2_dr_ok   <= dr_code_ok && dr_time_ok;
        r2_pn_lane <= pn_lane;                   r2_dr_lane <= dr_lane;
        r2_pn_time <= pn_time;                   r2_dr_time <= dr_time;
    end

    // ---------------- accept into the engine ----------------
    // Drop reports on the PLAY-entry edge; the new resume boundary is registered then.
    wire accept_pn=enable && boundary_ok && r2_pn_valid && r2_pn_ok &&
        (game_state!=RESULTS || r2_pn_time<={14'd0,song_time_ms});
    wire accept_dr=enable && boundary_ok && r2_dr_valid && r2_dr_ok &&
        (game_state!=RESULTS || r2_dr_time<={14'd0,song_time_ms});

    always @(posedge clk) begin
        previous_state<=game_state; previous_song_time<=song_time_ms;
        if(clear) begin
            play_start_sample<=sample_tick; play_start_song_ms<=song_time_ms;
            drain_clocks<=0; drain_ms<=0;
        end else begin
            if(game_state==PLAY && previous_state!=PLAY) begin
                play_start_sample<=sample_tick; play_start_song_ms<=song_time_ms;
            end
            if(game_state!=RESULTS || previous_state!=RESULTS) begin
                drain_clocks<=0; drain_ms<=0;
            end else if(drain_ms<DRAIN_LIMIT) begin
                if(drain_clocks==CLKS_PER_MS-1) begin drain_clocks<=0; drain_ms<=drain_ms+1'b1; end
                else drain_clocks<=drain_clocks+1'b1;
            end
        end
    end
    perf_eval_engine #(.PERFECT_MS(PERFECT_MS),.GOOD_MS(GOOD_MS),
        .REPORT_DELAY_MS(REPORT_DELAY_MS),.SYNC_MS(SYNC_MS)) engine(
        .clk(clk),.reset(eng_reset),.enable(enable),.evaluation_time_ms(now_ms_q),
        .note_valid(accept_pn),.note_lane(r2_pn_lane),.note_time_ms(r2_pn_time),
        .drum_valid(accept_dr),.drum_lane(r2_dr_lane),.drum_time_ms(r2_dr_time),
        .pno_exp_valid(pno_exp_valid_q),.pno_exp_id(pno_exp_id_q),
        .pno_exp_lane(pno_exp_lane_q),.pno_exp_time_ms(pno_exp_time_q),
        .drm_exp_valid(drm_exp_valid_q),.drm_exp_id(drm_exp_id_q),
        .drm_exp_lane(drm_exp_lane_q),.drm_exp_time_ms(drm_exp_time_q),
        .pno_judged_id(pno_judged_id),.drm_judged_id(drm_judged_id),
        .judge_pulse(judge_pulse),.judge_player(judge_player),.judge_lane(judge_lane),
        .judge_grade(judge_grade),.judge_id(judge_id),
        .judge_target_ms(judge_target_ms),.judge_hit_ms(judge_hit_ms),
        .sync_pulse(sync_pulse),.sync_ok(sync_ok),.sync_id(sync_id),
        .det_overflow(det_overflow),.pending(pending));
endmodule

