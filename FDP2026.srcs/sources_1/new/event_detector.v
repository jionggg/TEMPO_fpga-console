// event_detector.v | v4 | 04 Nov 2026 22:30 SGT
// v4: timing fix only (results bit-identical to v3). The note jumps d1/d2 for all 8 notes are
//     now computed in a new state S_DIF and registered, so S_ARG only does one 44-bit compare
//     per clock (v3 did mux + compare + subtract + compare in one clock and failed timing
//     in the full team build).
`timescale 1ns / 1ps
// Decides drum hits and piano notes from the per-frame features (one frame every 16 ms).
// It keeps a short history of frames and judges an OLDER frame t once enough later frames
// have arrived. Rules and constants were tuned on the real MIC3 recordings (29 Oct 2026)
// with a bit-matched Python model.
//
// PIANO (judged for frame t = f-2, f = newest frame):
//   b  = loudest note in frame t;  b2 = loudest note in frame t+2
//   note onset if  S_b(t) > 4 * S_b(t-3)                 (that note's harmonics jumped)
//             and  4*max(E(t),E(t+1)) > 25 * E(t-3)      (a >= 8 dB hammer transient)
//             and  S_b2(t+2) > NOTE_ABS                  (loud enough)
//             and  >= 10 frames since the last note onset
//   C5 -> C4 correction: if b2 = C5 but 256*c4_odd > 3*c5_main, it is C4.
//
// DRUMS (judged for frame t = f-13):
//   trigger if  NF(t) > NF_ABS  and  NF(t) > 8 * NF(t-2)  and >= 8 frames since last trigger
//   pk = max(NF(t), NF(t+1));  late = NF(peak frame + 12)   (192 ms later)
//   (no note within +-2 frames):
//   kick  if late*794 < pk  (decayed more than 29 dB)
//   snare if late*36  < pk  (decayed more than 15.5 dB)
//   else hi-hat
//
// v2 (tuned on real drum+note recordings, 30 Oct): when a note starts within +-2 frames
//   of the drum, piano hammer noise is in the way, so a different test is used:
//   drum is real if  pk*400 >= note score   (loud burst: kick)
//                or  NF(peak+6)*50000 >= note score  (noise still there 96 ms later)
//   type: kick if NF(peak+6)*63 < pk, else snare if late*36 < pk, else hi-hat.
//
// Timestamps (in samples, 16 per ms) = end sample of frame t minus a measured offset.
// Every multiply is registered before it is compared (timing-safe at 100 MHz).
module event_detector #(
    parameter [43:0] NF_ABS      = 44'd98,
    parameter [43:0] NOTE_ABS    = 44'd292969,
    parameter [31:0] DRUM_OFFSET = 32'd311,
    parameter [31:0] NOTE_OFFSET = 32'd253
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         feat_valid,
    input  wire [43:0]  hf_energy,
    input  wire [43:0]  noise_floor,
    input  wire [351:0] note_score,
    input  wire [43:0]  c4_odd,
    input  wire [43:0]  c5_main,
    input  wire [31:0]  frame_end_tick,
    output reg  [2:0]   drum_type,       // 1 kick, 2 snare, 3 hi-hat
    output reg          drum_valid,
    output reg  [31:0]  drum_timestamp,
    output reg  [3:0]   note_code,       // 1 C4, 2 D4, 3 E4, 4 F4, 5 G4, 6 A4, 7 B4, 8 C5
    output reg          note_valid,
    output reg  [31:0]  note_timestamp
);
    // ---------------- history (index 0 = newest frame f) ----------------
    reg [43:0] E_h  [0:5];
    reg [43:0] NF_h [0:15];
    reg [43:0] SN_h [0:15];          // note score stored at the onset frame of each note
    reg [31:0] T_h  [0:15];          // frame end ticks
    reg [43:0] S_h  [0:5][0:7];      // note scores per frame
    reg [43:0] odd0, main0;
    reg [5:0]  frames_seen;          // saturates at 63
    reg [5:0]  note_age;             // frames since last note onset
    reg [5:0]  drum_age;             // frames since last drum trigger

    localparam S_IDLE=4'd0, S_ARG=4'd1, S_NP=4'd2, S_NC=4'd3, S_ND=4'd4,
               S_DA=4'd5, S_DB=4'd6, S_DP=4'd7, S_DC=4'd8, S_DD=4'd9,
               S_DIF=4'd10;
    reg [3:0]  st;
    reg [2:0]  idx;
    reg [2:0]  b1, b2;               // loudest note at t (index 2) and at t+2 (index 0)
    reg [43:0] best1, best2, bestd1, bestd2;
    reg [53:0] m_nf5;
    reg        c_jump;
    // registered products
    reg [53:0] m_rise, m_ehf_l, m_ehf_r, m_odd, m_main;
    reg [53:0] m_trig, m_kick, m_snare, m_cok;
    reg [63:0] m_copk, m_col6;
    reg        c_rise, c_hf, c_abs, c_c4;
    reg [43:0] pk, late, late6, sn_win;
    reg        d_trig, c_co, c_codet, c_cokick, c_kick, c_snare;

    // v4: how much each note JUMPED since 3 frames ago (0 if it fell), registered in S_DIF
    reg  [43:0] d1_r [0:7];          // frame t   (index 2) vs t-3 (index 5)
    reg  [43:0] d2_r [0:7];          // frame t+2 (index 0) vs t-3 (index 5)
    wire [43:0] s2_idx = S_h[2][idx];
    wire [43:0] s0_idx = S_h[0][idx];
    wire [43:0] d1_idx = d1_r[idx];
    wire [43:0] d2_idx = d2_r[idx];
    wire [43:0] nf_max = (NF_h[2] > NF_h[1]) ? NF_h[2] : NF_h[1];
    wire [43:0] e_max  = (E_h[2] > E_h[1]) ? E_h[2] : E_h[1];
    wire [43:0] sn_a   = (SN_h[11] > SN_h[12]) ? SN_h[11] : SN_h[12];
    wire [43:0] sn_b   = (SN_h[13] > SN_h[14]) ? SN_h[13] : SN_h[14];
    wire [43:0] sn_ab  = (sn_a > sn_b) ? sn_a : sn_b;

    integer i, n;
    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; idx <= 3'd0; frames_seen <= 6'd0;
            note_age <= 6'd63; drum_age <= 6'd63;
            drum_type <= 3'd0; drum_valid <= 1'b0; drum_timestamp <= 32'd0;
            note_code <= 4'd0; note_valid <= 1'b0; note_timestamp <= 32'd0;
            b1 <= 3'd0; b2 <= 3'd0; best1 <= 44'd0; best2 <= 44'd0;
            bestd1 <= 44'd0; bestd2 <= 44'd0; m_nf5 <= 54'd0; c_jump <= 1'b0;
            m_rise <= 54'd0; m_ehf_l <= 54'd0; m_ehf_r <= 54'd0; m_odd <= 54'd0; m_main <= 54'd0;
            m_trig <= 54'd0; m_kick <= 54'd0; m_snare <= 54'd0; m_cok <= 54'd0;
            m_copk <= 64'd0; m_col6 <= 64'd0;
            c_rise <= 1'b0; c_hf <= 1'b0; c_abs <= 1'b0; c_c4 <= 1'b0;
            pk <= 44'd0; late <= 44'd0; late6 <= 44'd0; sn_win <= 44'd0;
            d_trig <= 1'b0; c_co <= 1'b0; c_codet <= 1'b0; c_cokick <= 1'b0;
            c_kick <= 1'b0; c_snare <= 1'b0;
            odd0 <= 44'd0; main0 <= 44'd0;
            for (n = 0; n < 8; n = n + 1) begin d1_r[n] <= 44'd0; d2_r[n] <= 44'd0; end
            for (i = 0; i < 16; i = i + 1) begin
                NF_h[i] <= 44'd0; SN_h[i] <= 44'd0; T_h[i] <= 32'd0;
            end
            for (i = 0; i < 6; i = i + 1) begin
                E_h[i] <= 44'd0;
                for (n = 0; n < 8; n = n + 1) S_h[i][n] <= 44'd0;
            end
        end else begin
            drum_valid <= 1'b0;
            note_valid <= 1'b0;
            case (st)
                // ---- 1. store the new frame, shift history ----
                S_IDLE: if (feat_valid) begin
                    for (i = 15; i > 0; i = i - 1) begin
                        NF_h[i] <= NF_h[i-1]; SN_h[i] <= SN_h[i-1]; T_h[i] <= T_h[i-1];
                    end
                    NF_h[0] <= noise_floor; SN_h[0] <= 44'd0; T_h[0] <= frame_end_tick;
                    for (i = 5; i > 0; i = i - 1) begin
                        E_h[i] <= E_h[i-1];
                        for (n = 0; n < 8; n = n + 1) S_h[i][n] <= S_h[i-1][n];
                    end
                    E_h[0] <= hf_energy;
                    for (n = 0; n < 8; n = n + 1) S_h[0][n] <= note_score[44*n +: 44];
                    odd0  <= c4_odd;
                    main0 <= c5_main;
                    if (frames_seen != 6'd63) frames_seen <= frames_seen + 1'b1;
                    if (note_age    != 6'd63) note_age    <= note_age + 1'b1;
                    if (drum_age    != 6'd63) drum_age    <= drum_age + 1'b1;
                    idx <= 3'd0;
                    st  <= S_DIF;
                end
                // ---- 1b. (v4) note jumps for all 8 notes at once, registered ----
                S_DIF: begin
                    for (n = 0; n < 8; n = n + 1) begin
                        d1_r[n] <= (S_h[2][n] > S_h[5][n]) ? (S_h[2][n] - S_h[5][n]) : 44'd0;
                        d2_r[n] <= (S_h[0][n] > S_h[5][n]) ? (S_h[0][n] - S_h[5][n]) : 44'd0;
                    end
                    st <= S_ARG;
                end
                // ---- 2. loudest note in frame t and in frame t+2 (first maximum wins) ----
                S_ARG: begin
                    if (idx == 3'd0 || d1_idx > bestd1) begin bestd1 <= d1_idx; best1 <= s2_idx; b1 <= idx; end
                    if (idx == 3'd0 || d2_idx > bestd2) begin bestd2 <= d2_idx; best2 <= s0_idx; b2 <= idx; end
                    idx <= idx + 1'b1;
                    if (idx == 3'd7) st <= S_NP;
                end
                // ---- 3. note products ----
                S_NP: begin
                    m_rise  <= {10'd0, S_h[5][b1]} * 54'd2;      // v3: x2 (was x4)
                    m_nf5   <= {10'd0, NF_h[5]}    * 54'd4;
                    m_ehf_l <= {10'd0, e_max}      * 54'd4;
                    m_ehf_r <= {10'd0, E_h[5]}     * 54'd25;
                    m_odd   <= {10'd0, odd0}       * 54'd256;
                    m_main  <= {10'd0, main0}      * 54'd3;
                    st <= S_NC;
                end
                // ---- 4. note compares ----
                S_NC: begin
                    c_rise <= {10'd0, best1} > m_rise;
                    c_jump <= (bestd1 != 44'd0) && (bestd2 != 44'd0);
                    c_hf   <= (m_ehf_l > m_ehf_r) || ({10'd0, nf_max} > m_nf5);   // v3: or noise-floor click
                    c_abs  <= best2 > NOTE_ABS;
                    c_c4   <= m_odd > m_main;
                    st <= S_ND;
                end
                // ---- 5. note decision (onset frame t = index 2) ----
                S_ND: begin
                    if (frames_seen >= 6'd6 && note_age >= 6'd10 && c_jump && c_rise && c_hf && c_abs) begin
                        note_age       <= 6'd0;
                        SN_h[2]        <= best2;            // remembered for the drum check
                        note_code      <= ((b2 == 3'd7) && c_c4) ? 4'd1 : ({1'b0, b2} + 4'd1);
                        note_timestamp <= T_h[2] - NOTE_OFFSET;
                        note_valid     <= 1'b1;
                    end
                    st <= S_DA;
                end
                // ---- 6. drum: pick peak / late values for t = index 13 ----
                S_DA: begin
                    m_trig <= {10'd0, NF_h[15]} * 54'd8;
                    if (NF_h[13] >= NF_h[12]) begin pk <= NF_h[13]; late6 <= NF_h[7]; late <= NF_h[1]; end
                    else                      begin pk <= NF_h[12]; late6 <= NF_h[6]; late <= NF_h[0]; end
                    sn_win <= (sn_ab > SN_h[15]) ? sn_ab : SN_h[15];   // notes at t-2..t+2
                    st <= S_DB;
                end
                S_DB: begin
                    d_trig <= (frames_seen >= 6'd16) && (drum_age >= 6'd8) &&
                              (NF_h[13] > NF_ABS) && ({10'd0, NF_h[13]} > m_trig);
                    st <= S_DP;
                end
                // ---- 7. drum products ----
                S_DP: begin
                    m_copk  <= {20'd0, pk}    * 64'd400;
                    m_col6  <= {20'd0, late6} * 64'd50000;
                    m_cok   <= {10'd0, late6} * 54'd63;
                    m_kick  <= {10'd0, late}  * 54'd794;
                    m_snare <= {10'd0, late}  * 54'd36;
                    st <= S_DC;
                end
                // ---- 8. drum compares ----
                S_DC: begin
                    c_co     <= (sn_win != 44'd0);                       // a note started with it
                    c_codet  <= (m_copk >= {20'd0, sn_win}) || (m_col6 >= {20'd0, sn_win});
                    c_cokick <= m_cok   < {10'd0, pk};
                    c_kick   <= m_kick  < {10'd0, pk};
                    c_snare  <= m_snare < {10'd0, pk};
                    st <= S_DD;
                end
                // ---- 9. drum decision ----
                S_DD: begin
                    if (d_trig) begin
                        drum_age <= 6'd0;               // dead time counts even if vetoed
                        if (!c_co || c_codet) begin
                            if (c_co)
                                drum_type  <= c_cokick ? 3'd1 : (c_snare ? 3'd2 : 3'd3);
                            else
                                drum_type  <= c_kick ? 3'd1 : (c_snare ? 3'd2 : 3'd3);
                            drum_timestamp <= T_h[13] - DRUM_OFFSET;
                            drum_valid     <= 1'b1;
                        end
                    end
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule