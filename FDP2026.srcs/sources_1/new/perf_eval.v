`timescale 1ns / 1ps

// Member B: Pei Ling - performance evaluation (match hits, grade, sync judge)
// perf_eval: public ports, audio-code conversion, sample-count timestamps to song milliseconds, session clearing, pause/resume boundaries, final-report drain timer.


module perf_eval #(
    parameter integer PERFECT_MS=50,
    parameter integer GOOD_MS=150,
    parameter integer REPORT_DELAY_MS=250,
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
    wire [31:0] now_ms={14'd0,song_time_ms}+(game_state==RESULTS ? drain_ms : 32'd0);

    // Current sample clock and reported onset are in the same 16 kHz domain.
    // Mapping via report age removes reset/countdown offsets without changing A.
    wire [31:0] pn_age=sample_tick-note_timestamp;
    wire [31:0] dr_age=sample_tick-drum_timestamp;
    wire [31:0] pn_since=note_timestamp-play_start_sample;
    wire [31:0] dr_since=drum_timestamp-play_start_sample;
    wire signed [32:0] pn_onset_signed=$signed({1'b0,now_ms})-$signed({1'b0,(pn_age>>4)});
    wire signed [32:0] dr_onset_signed=$signed({1'b0,now_ms})-$signed({1'b0,(dr_age>>4)});
    wire [31:0] pn_time=RAW_AUDIO_INPUT ? pn_onset_signed[31:0] : note_timestamp;
    wire [31:0] dr_time=RAW_AUDIO_INPUT ? dr_onset_signed[31:0] : drum_timestamp;
    wire pn_time_ok=RAW_AUDIO_INPUT ?
        (!pn_age[31] && !pn_since[31] && !pn_onset_signed[32]) :
        (note_timestamp>={14'd0,play_start_song_ms} && note_timestamp<=now_ms);
    wire dr_time_ok=RAW_AUDIO_INPUT ?
        (!dr_age[31] && !dr_since[31] && !dr_onset_signed[32]) :
        (drum_timestamp>={14'd0,play_start_song_ms} && drum_timestamp<=now_ms);

    // A: C4..G4=1..5 -> game lanes 0..4. A4/B4/C5 remain wrong notes.
    wire [2:0] pn_lane=RAW_AUDIO_INPUT ?
        ((note_code>=1 && note_code<=5) ? note_code[2:0]-3'd1 : 3'd7) :
        (note_code<=4 ? note_code[2:0] : 3'd7);
    wire pn_code_ok=RAW_AUDIO_INPUT ? (note_code>=1 && note_code<=8) : 1'b1;
    // A: kick=1 -> bass=2, snare=2 -> snare=1.
    // Hi-hat=3 is not crash; ignore until the team agrees on a third instrument.
    wire [2:0] dr_lane=RAW_AUDIO_INPUT ?
        (drum_type==1 ? 3'd2 : drum_type==2 ? 3'd1 : 3'd3) : drum_type;
    wire dr_code_ok=RAW_AUDIO_INPUT ? (drum_type==1 || drum_type==2) : drum_type<=2;
    // Drop reports on the PLAY-entry edge; the new resume boundary is registered then.
    wire boundary_ok=!(game_state==PLAY && previous_state!=PLAY);
    wire accept_pn=enable && boundary_ok && note_valid && pn_code_ok && pn_time_ok &&
        (game_state!=RESULTS || pn_time<={14'd0,song_time_ms});
    wire accept_dr=enable && boundary_ok && drum_valid && dr_code_ok && dr_time_ok &&
        (game_state!=RESULTS || dr_time<={14'd0,song_time_ms});

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
        .clk(clk),.reset(clear),.enable(enable),.evaluation_time_ms(now_ms),
        .note_valid(accept_pn),.note_lane(pn_lane),.note_time_ms(pn_time),
        .drum_valid(accept_dr),.drum_lane(dr_lane),.drum_time_ms(dr_time),
        .pno_exp_valid(pno_exp_valid),.pno_exp_id(pno_exp_id),
        .pno_exp_lane(pno_exp_lane),.pno_exp_time_ms(pno_exp_time_ms),
        .drm_exp_valid(drm_exp_valid),.drm_exp_id(drm_exp_id),
        .drm_exp_lane(drm_exp_lane),.drm_exp_time_ms(drm_exp_time_ms),
        .pno_judged_id(pno_judged_id),.drm_judged_id(drm_judged_id),
        .judge_pulse(judge_pulse),.judge_player(judge_player),.judge_lane(judge_lane),
        .judge_grade(judge_grade),.judge_id(judge_id),
        .sync_pulse(sync_pulse),.sync_ok(sync_ok),.sync_id(sync_id),
        .det_overflow(det_overflow),.pending(pending));
endmodule

