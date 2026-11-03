`timescale 1ns / 1ps

// Member B: Pei Ling - performance evaluation (match hits, grade, sync judge)
//
// PLACEHOLDER: the ports are the team interface; replace the body with your design.
// Keep every port on clk (100 MHz). judge_pulse and sync_pulse are high for
// exactly one clk cycle per judgement.
//
// Proposed (not in the flowchart yet): song_time_ms lets you call a MISS when an
// expected event's window passes with no hit.


//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 16:22:51
// Design Name: 
// Module Name: perf_eval
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module perf_eval #(
    parameter [31:0] PERFECT_MS=32'd50,
    parameter [31:0] GOOD_MS=32'd150,
    parameter [31:0] MAX_REPORT_DELAY_MS=32'd120
)(
    input clk, input reset, input session_clear,
    input [2:0] game_state, input [17:0] song_time_ms,
    input note_valid, input [3:0] note_code, input [31:0] note_timestamp,
    input drum_valid, input [2:0] drum_type, input [31:0] drum_timestamp,
    input exp_valid, output exp_ready, input [7:0] exp_id,
    input exp_is_drum, input [3:0] exp_note, input [17:0] exp_time_ms,
    input [2:0] exp_drum, input [7:0] sync_lim_ms,
    output judge_pulse, output judge_player, output [2:0] judge_lane,
    output [1:0] judge_grade, output [7:0] judge_id,
    output sync_pulse, output sync_ok,
    // Diagnostic extensions: optional for teammates, useful during integration.
    output det_overflow, output protocol_error, output [15:0] stray_count,
    output table_full, output pending,
    output signed [32:0] judge_error_ms,
    output judge_wrong_note, output judge_timeout,
    output [7:0] sync_id, output sync_delta_valid, output [31:0] sync_delta_ms
);
    wire clear=reset || session_clear;
    wire play=game_state==3'd2;
    wire pn_empty,dr_empty,pn_ready,dr_ready,engine_ready;
    wire [35:0] pn_head;
    wire [34:0] dr_head;
    reg prefer_drum;
    reg input_overflow;
    wire choose_drum=!dr_empty && (pn_empty || prefer_drum);
    wire send=play && engine_ready && (!pn_empty || !dr_empty);
    event_fifo #(.WIDTH(36),.ADDR_BITS(4)) piano_queue(
        .clk(clk),.reset(clear),.push(note_valid && play),
        .push_data({note_code,note_timestamp}),.ready(pn_ready),
        .pop(send && !choose_drum),.head(pn_head),.empty(pn_empty));
    event_fifo #(.WIDTH(35),.ADDR_BITS(4)) drum_queue(
        .clk(clk),.reset(clear),.push(drum_valid && play),
        .push_data({drum_type,drum_timestamp}),.ready(dr_ready),
        .pop(send && choose_drum),.head(dr_head),.empty(dr_empty));
    always @(posedge clk) begin
        if(clear) begin prefer_drum<=0;input_overflow<=0;end
        else begin
            if(send) prefer_drum<=!choose_drum;
            if(play && ((note_valid && !pn_ready) || (drum_valid && !dr_ready)))
                input_overflow<=1;
        end
    end
    wire engine_overflow,engine_pending;
    assign det_overflow=input_overflow || engine_overflow;
    assign pending=engine_pending || !pn_empty || !dr_empty;
    perf_eval_engine #(.TIME_BITS(32),.AUTO_PAIR(1),.PERFECT_MS(PERFECT_MS),
        .GOOD_MS(GOOD_MS),.MAX_REPORT_DELAY_MS(MAX_REPORT_DELAY_MS)) engine(
        .clk(clk),.reset(reset),.session_clear(session_clear),
        .sync_lim_ms(sync_lim_ms),.game_state(game_state),.song_time_ms({14'd0,song_time_ms}),
        .det_pulse(send),.det_is_drum(choose_drum),
        .det_note(choose_drum ? {5'd0,dr_head[34:32]} : {4'd0,pn_head[35:32]}),
        .det_time_ms(choose_drum ? dr_head[31:0] : pn_head[31:0]),
        .det_ready_out(engine_ready),
        .exp_valid(exp_valid),.exp_ready(exp_ready),.exp_id(exp_id),
        .exp_is_drum(exp_is_drum),.exp_note(exp_is_drum ? {5'd0,exp_drum} : {4'd0,exp_note}),
        .exp_time_ms({14'd0,exp_time_ms}),
        .exp_lane(exp_is_drum ? exp_drum : exp_note[2:0]),.exp_sync(1'b1),
        .judge_pulse(judge_pulse),.judge_player(judge_player),.judge_lane(judge_lane),
        .judge_grade(judge_grade),.judge_id(judge_id),.judge_error_ms(judge_error_ms),
        .judge_wrong_note(judge_wrong_note),.judge_timeout(judge_timeout),
        .sync_pulse(sync_pulse),.sync_ok(sync_ok),.sync_id(sync_id),
        .sync_delta_valid(sync_delta_valid),.sync_delta_ms(sync_delta_ms),
        .det_overflow(engine_overflow),.protocol_error(protocol_error),
        .stray_count(stray_count),.table_full(table_full),.pending(engine_pending));
endmodule

