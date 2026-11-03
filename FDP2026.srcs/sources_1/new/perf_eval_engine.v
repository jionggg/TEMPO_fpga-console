`timescale 1ns / 1ps
// Normalized song-millisecond / lane-code evaluator.
// C's expectation heads are LEVELS; each instrument/ID is cached ONCE.
// IDs 0..62 must be unique per instrument per session; 63 is reserved.
/**
perf_eval_engine: remembers C's head records once per ID, holds them after C's 
safety expiry, searches pending expectations over clock cycles, grades hits,
generates MISS results and duet decisions, serializes result outputs.
**/

module perf_eval_engine #(
    parameter integer PERFECT_MS=50,
    parameter integer GOOD_MS=150,
    parameter integer REPORT_DELAY_MS=250,
    parameter integer SYNC_MS=50
)(
    input clk, input reset, input enable,
    input [31:0] evaluation_time_ms,
    input note_valid, input [2:0] note_lane, input [31:0] note_time_ms,
    input drum_valid, input [2:0] drum_lane, input [31:0] drum_time_ms,
    input pno_exp_valid, input [5:0] pno_exp_id,
    input [2:0] pno_exp_lane, input [17:0] pno_exp_time_ms,
    input drm_exp_valid, input [5:0] drm_exp_id,
    input [2:0] drm_exp_lane, input [17:0] drm_exp_time_ms,
    output reg [5:0] pno_judged_id, output reg [5:0] drm_judged_id,
    output reg judge_pulse, output reg judge_player,
    output reg [2:0] judge_lane, output reg [1:0] judge_grade,
    output reg [7:0] judge_id,
    output reg sync_pulse, output reg sync_ok, output reg [7:0] sync_id,
    output reg det_overflow, output pending
);
    localparam [1:0] MISS=0, GOOD=1, PERFECT=2;
    localparam [1:0] IDLE=0, SCAN=1, COMMIT=2, EXPIRE=3;
    localparam [31:0] REPORT_WINDOW=GOOD_MS+REPORT_DELAY_MS;
    reg [127:0] seen, resolved, emitted;
    reg [63:0] sync_sent;
    reg [2:0] lanes [0:127];
    reg [17:0] targets [0:127];
    reg [1:0] grades [0:127];
    reg [31:0] hit_times [0:127];
    wire [6:0] pi={1'b0,pno_exp_id}, di={1'b1,drm_exp_id};
    reg [6:0] out_index, expire_index;
    wire [6:0] other={~out_index[6],out_index[5:0]};

    reg [1:0] state;
    reg prefer_drum, active_drum;
    reg [2:0] active_lane;
    reg [31:0] active_time;
    reg [5:0] scan;
    reg [6:0] best_index;
    reg best_found;
    reg [31:0] best_distance;
    wire [6:0] candidate={active_drum,scan};
    wire [31:0] candidate_time={14'd0,targets[candidate]};
    wire [31:0] distance=(active_time>=candidate_time) ?
        active_time-candidate_time : candidate_time-active_time;
    wire [31:0] pair_delta=(hit_times[out_index]>=hit_times[other]) ?
        hit_times[out_index]-hit_times[other] : hit_times[other]-hit_times[out_index];

    wire pn_empty, dr_empty, pn_ready, dr_ready;
    wire [34:0] pn_head, dr_head;
    wire choose_drum=!dr_empty && (pn_empty || prefer_drum);
    wire take=enable && state==IDLE && (!pn_empty || !dr_empty);
    event_fifo #(.WIDTH(35),.ADDR_BITS(4)) piano_queue(
        .clk(clk),.reset(reset),.push(note_valid && enable),
        .push_data({note_lane,note_time_ms}),.ready(pn_ready),
        .pop(take && !choose_drum),.head(pn_head),.empty(pn_empty));
    event_fifo #(.WIDTH(35),.ADDR_BITS(4)) drum_queue(
        .clk(clk),.reset(reset),.push(drum_valid && enable),
        .push_data({drum_lane,drum_time_ms}),.ready(dr_ready),
        .pop(take && choose_drum),.head(dr_head),.empty(dr_empty));
    assign pending=|(seen & ~emitted) || !pn_empty || !dr_empty ||
        state==SCAN || state==COMMIT;
    integer k;
    always @(posedge clk) begin
        judge_pulse<=0; sync_pulse<=0;
        pno_judged_id<=6'd63; drm_judged_id<=6'd63;
        if(reset) begin
            seen<=0; resolved<=0; emitted<=0; sync_sent<=0;
            out_index<=0; expire_index<=0; state<=IDLE;
            prefer_drum<=0; active_drum<=0; active_lane<=0; active_time<=0;
            scan<=0; best_index<=0; best_found<=0; best_distance<=0;
            judge_player<=0; judge_lane<=0; judge_grade<=MISS; judge_id<=0;
            sync_ok<=0; sync_id<=0; det_overflow<=0;
            for(k=0;k<128;k=k+1) begin
                lanes[k]<=0; targets[k]<=0; grades[k]<=MISS; hit_times[k]<=0;
            end
        end else begin
            // Capture even during countdown / pause. C holds head fields stable.
            if(pno_exp_valid && pno_exp_id!=63 && !seen[pi]) begin
                seen[pi]<=1; lanes[pi]<=pno_exp_lane; targets[pi]<=pno_exp_time_ms;
            end
            if(drm_exp_valid && drm_exp_id!=63 && !seen[di]) begin
                seen[di]<=1; lanes[di]<=drm_exp_lane; targets[di]<=drm_exp_time_ms;
            end
            if(enable) begin
                if((note_valid && !pn_ready) || (drum_valid && !dr_ready))
                    det_overflow<=1;
                // Serialize completed results. A separate stored bit prevents double scoring.
                if(!judge_pulse && seen[out_index] && resolved[out_index] && !emitted[out_index]) begin
                    emitted[out_index]<=1;
                    judge_pulse<=1; judge_player<=out_index[6];
                    judge_lane<=lanes[out_index]; judge_grade<=grades[out_index];
                    judge_id<={2'b00,out_index[5:0]};
                    if(out_index[6]) drm_judged_id<=out_index[5:0];
                    else pno_judged_id<=out_index[5:0];
                    if(seen[other] && emitted[other] &&
                       targets[other]==targets[out_index] && !sync_sent[out_index[5:0]]) begin
                        sync_sent[out_index[5:0]]<=1;
                        sync_pulse<=1; sync_id<={2'b00,out_index[5:0]};
                        sync_ok<=grades[out_index]!=MISS && grades[other]!=MISS && pair_delta<=SYNC_MS;
                    end
                end
                out_index<=out_index+1'b1;
                case(state)
                    IDLE: begin
                        if(take) begin
                            active_drum<=choose_drum; prefer_drum<=!choose_drum;
                            active_lane<=choose_drum ? dr_head[34:32] : pn_head[34:32];
                            active_time<=choose_drum ? dr_head[31:0] : pn_head[31:0];
                            best_found<=0; best_distance<=32'hffffffff; scan<=0; state<=SCAN;
                        end else state<=EXPIRE;
                    end
                    SCAN: begin
                        if(seen[candidate] && !resolved[candidate] &&
                           active_time<=evaluation_time_ms && distance<=GOOD_MS &&
                           (!active_drum || active_lane==lanes[candidate]) &&
                           (!best_found || distance<best_distance)) begin
                            best_found<=1; best_index<=candidate; best_distance<=distance;
                        end
                        if(scan==63) state<=COMMIT;
                        else scan<=scan+1'b1;
                    end
                    COMMIT: begin
                        if(best_found) begin
                            resolved[best_index]<=1; hit_times[best_index]<=active_time;
                            if(!active_drum && active_lane!=lanes[best_index]) grades[best_index]<=MISS;
                            else if(best_distance<=PERFECT_MS) grades[best_index]<=PERFECT;
                            else grades[best_index]<=GOOD;
                        end
                        state<=EXPIRE;
                    end
                    EXPIRE: begin
                        // Service buffered reports before expiring their instrument.
                        // The 250 ms default is a reporting allowance, not a wider hit window.
                        if(seen[expire_index] && !resolved[expire_index] &&
                           (expire_index[6] ? (dr_empty && !drum_valid) : (pn_empty && !note_valid)) &&
                           evaluation_time_ms>({14'd0,targets[expire_index]}+REPORT_WINDOW)) begin
                            resolved[expire_index]<=1; grades[expire_index]<=MISS;
                            hit_times[expire_index]<=0;
                        end
                        expire_index<=expire_index+1'b1; state<=IDLE;
                    end
                endcase
            end
        end
    end
endmodule
