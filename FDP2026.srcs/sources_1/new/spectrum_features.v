// spectrum_features.v | v1 | 29 Oct 2026 21:00 SGT
`timescale 1ns / 1ps
// Turns each FFT output frame into 12 numbers (all sums of P[k] = Re^2 + Im^2):
//   hf_energy  E    : sum of P over bins 192..511  (3 kHz - 8 kHz)
//   noise_floor NF  : bins 192..511 split into 20 groups of 16; sum of each group's MINIMUM.
//                     Piano harmonics are narrow lines and do not lift a group's minimum;
//                     drum noise fills every bin, so NF tracks drum noise only.
//   note_score S[n] : for the 8 notes C4..C5, sum of P at harmonics 1..4
//   c4_odd / c5_main: P at 262 Hz + 785 Hz bins (16,17,50) and at 523 Hz bins (33,34),
//                     used to tell C4 (weak fundamental on this speaker) from C5.
// Bin width = 16000/1024 = 15.625 Hz. Only bins 0..511 are used.
// Fully pipelined: accepts one FFT output per clock (m_axis tready can stay 1).
module spectrum_features (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] fft_data,     // [15:0] real, [31:16] imaginary
    input  wire [9:0]  fft_bin,      // XK_INDEX from tuser
    input  wire        fft_valid,
    input  wire        fft_last,
    output reg         feat_valid,   // 1-clock pulse after each frame
    output reg  [43:0] hf_energy,
    output reg  [43:0] noise_floor,
    output reg  [351:0] note_score,  // 8 x 44 bits, note n at [44*n +: 44]
    output reg  [43:0] c4_odd,
    output reg  [43:0] c5_main
);
    // ---- bin -> note mask (generated from round(h * f0 / 15.625), h = 1..4) ----
    function [7:0] note_mask;
        input [9:0] b;
        begin
            case (b)
                10'd17:  note_mask = 8'b00000001;
                10'd19:  note_mask = 8'b00000010;
                10'd21:  note_mask = 8'b00000100;
                10'd22:  note_mask = 8'b00001000;
                10'd25:  note_mask = 8'b00010000;
                10'd28:  note_mask = 8'b00100000;
                10'd32:  note_mask = 8'b01000000;
                10'd33:  note_mask = 8'b10000001;
                10'd38:  note_mask = 8'b00000010;
                10'd42:  note_mask = 8'b00000100;
                10'd45:  note_mask = 8'b00001000;
                10'd50:  note_mask = 8'b00010001;
                10'd56:  note_mask = 8'b00100010;
                10'd63:  note_mask = 8'b01000100;
                10'd67:  note_mask = 8'b10001001;
                10'd75:  note_mask = 8'b00010010;
                10'd84:  note_mask = 8'b00100100;
                10'd89:  note_mask = 8'b00001000;
                10'd95:  note_mask = 8'b01000000;
                10'd100: note_mask = 8'b10010000;
                10'd113: note_mask = 8'b00100000;
                10'd126: note_mask = 8'b01000000;
                10'd134: note_mask = 8'b10000000;
                default: note_mask = 8'b00000000;
            endcase
        end
    endfunction

    // ---- Stage 1: register input ----
    reg signed [15:0] re1, im1;
    reg [9:0] bin1;
    reg v1, l1;
    // ---- Stage 2: squares + bin flags ----
    reg [31:0] re_sq2, im_sq2;
    reg [9:0]  bin2;
    reg v2, l2;
    // ---- Stage 3: power + lookups ----
    reg [32:0] p3;
    reg [7:0]  mask3;
    reg        hf3, grp_first3, grp_last3, odd3, main3, use3;
    reg        v3, l3;

    wire signed [31:0] re_sq = re1 * re1;
    wire signed [31:0] im_sq = im1 * im1;

    // ---- accumulators ----
    reg [43:0] e_acc, nf_acc, odd_acc, main_acc;
    reg [43:0] s_acc [0:7];
    reg [32:0] gmin;                       // running minimum of the current 16-bin group
    wire [32:0] gmin_next = grp_first3 ? p3 : ((p3 < gmin) ? p3 : gmin);
    wire [43:0] p3x = {11'd0, p3};

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            v1 <= 1'b0; l1 <= 1'b0; v2 <= 1'b0; l2 <= 1'b0; v3 <= 1'b0; l3 <= 1'b0;
            re1 <= 16'sd0; im1 <= 16'sd0; bin1 <= 10'd0;
            re_sq2 <= 32'd0; im_sq2 <= 32'd0; bin2 <= 10'd0;
            p3 <= 33'd0; mask3 <= 8'd0;
            hf3 <= 1'b0; grp_first3 <= 1'b0; grp_last3 <= 1'b0;
            odd3 <= 1'b0; main3 <= 1'b0; use3 <= 1'b0;
            e_acc <= 44'd0; nf_acc <= 44'd0; odd_acc <= 44'd0; main_acc <= 44'd0;
            gmin <= 33'd0;
            for (i = 0; i < 8; i = i + 1) s_acc[i] <= 44'd0;
            feat_valid <= 1'b0;
            hf_energy <= 44'd0; noise_floor <= 44'd0; note_score <= 352'd0;
            c4_odd <= 44'd0; c5_main <= 44'd0;
        end else begin
            // Stage 1
            re1  <= fft_data[15:0];
            im1  <= fft_data[31:16];
            bin1 <= fft_bin;
            v1   <= fft_valid;
            l1   <= fft_valid & fft_last;
            // Stage 2
            re_sq2 <= re_sq;
            im_sq2 <= im_sq;
            bin2   <= bin1;
            v2     <= v1;
            l2     <= l1;
            // Stage 3
            p3         <= {1'b0, re_sq2} + {1'b0, im_sq2};
            mask3      <= note_mask(bin2);
            use3       <= (bin2 < 10'd512);
            hf3        <= (bin2 >= 10'd192) && (bin2 <= 10'd511);
            grp_first3 <= (bin2[3:0] == 4'd0);
            grp_last3  <= (bin2[3:0] == 4'd15);
            odd3       <= (bin2 == 10'd16) || (bin2 == 10'd17) || (bin2 == 10'd50);
            main3      <= (bin2 == 10'd33) || (bin2 == 10'd34);
            v3         <= v2;
            l3         <= l2;

            // Stage 4: accumulate
            feat_valid <= 1'b0;
            if (v3) begin
                if (use3) begin
                    if (hf3) begin
                        e_acc <= e_acc + p3x;
                        gmin  <= gmin_next;
                        if (grp_last3)
                            nf_acc <= nf_acc + {11'd0, gmin_next};
                    end
                    for (i = 0; i < 8; i = i + 1)
                        if (mask3[i]) s_acc[i] <= s_acc[i] + p3x;
                    if (odd3)  odd_acc  <= odd_acc + p3x;
                    if (main3) main_acc <= main_acc + p3x;
                end
                if (l3) begin
                    // bins 512..1023 are never added, so the sums are complete here
                    hf_energy   <= e_acc;
                    noise_floor <= nf_acc;
                    c4_odd      <= odd_acc;
                    c5_main     <= main_acc;
                    for (i = 0; i < 8; i = i + 1)
                        note_score[44*i +: 44] <= s_acc[i];
                    e_acc <= 44'd0; nf_acc <= 44'd0; odd_acc <= 44'd0; main_acc <= 44'd0;
                    for (i = 0; i < 8; i = i + 1) s_acc[i] <= 44'd0;
                    feat_valid <= 1'b1;
                end
            end
        end
    end
endmodule
