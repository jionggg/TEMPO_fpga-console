`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 11:03:58
// Design Name: 
// Module Name: score_keeper
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

