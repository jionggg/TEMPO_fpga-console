// audio_dsp.v | v2 | 04 Nov 2026 23:15 SGT
// v2: adds the same on-board audio debug as the standalone basys_audio_top test:
//     dbg_led (shown on the LEDs when sw[1] is up) and the 7-segment display (always on).
//     Detector outputs to Pei Ling are unchanged from v1.
`timescale 1ns / 1ps
// Member A: Vishwanath Annanya - audio DSP (Pmod MIC3 -> detected piano notes and drum hits)
//
// Thin team wrapper around audio_detector_top. Outputs are exactly the 7 signals that
// Pei Ling's perf_eval reads (RAW_AUDIO_INPUT = 1); she converts codes to lanes and
// sample counts to song milliseconds, and ignores reports outside PLAYING.
//
//   drum_type[2:0]       1 kick, 2 snare, 3 hi-hat/cymbal (holds last value)
//   drum_valid           1-clk pulse per drum hit
//   drum_timestamp[31:0] sample number of the hit (16 samples = 1 ms)
//   note_code[3:0]       1 C4, 2 D4, 3 E4, 4 F4, 5 G4, 6 A4, 7 B4, 8 C5 (holds last value)
//   note_valid           1-clk pulse per piano note
//   note_timestamp[31:0] sample number of the note
//   sample_tick[31:0]    current sample number (same time base as the timestamps)
//
// Debug (same layout as basys_audio_top):
//   dbg_led[0..2]   last drum: kick, snare, hi-hat (stays on)
//   dbg_led[3..10]  last note: C4 D4 E4 F4 G4 A4 B4 C5 (stays on)
//   dbg_led[11..15] mic level meter, peak over 100 ms (LED15 = near clipping)
//   7-segment       [note letter][octave][blank][drum]   drum: b = kick, 5 = snare, H = hi-hat
//                   a decimal point flashes for 0.15 s on every new note (digit 2) / drum (digit 0)
//   The detector runs in every game state, so this works in MENU too.
//
// Reset: ~10 ms power-on reset after programming (the FFT core needs a clean reset),
// plus btnR (rst from the top), synchronised to clk first.
// Everything runs on clk (100 MHz). Mic pins: JC1 = mic_cs, JC3 = mic_miso, JC4 = mic_sclk.
module audio_dsp (
    input  wire        clk,
    input  wire        rst,            // btnR from the top (raw)
    // Pmod MIC3
    output wire        mic_cs,
    input  wire        mic_miso,
    output wire        mic_sclk,
    // to Pei Ling (perf_eval)
    output wire        note_valid,
    output wire [3:0]  note_code,
    output wire [31:0] note_timestamp,
    output wire        drum_valid,
    output wire [2:0]  drum_type,
    output wire [31:0] drum_timestamp,
    output wire [31:0] sample_tick,
    // board debug
    output reg  [15:0] dbg_led = 16'd0,
    output reg  [6:0]  seg     = 7'b1111111,   // seg[0]=CA ... seg[6]=CG, active low
    output reg         dp      = 1'b1,         // active low
    output reg  [3:0]  an      = 4'b1111       // active low
    );

    // ---------------- reset: power-on (2^20 clocks = 10.5 ms) or btnR ----------------
    reg [19:0] por_cnt  = 20'd0;
    reg        por_done = 1'b0;
    reg [1:0]  rst_sync = 2'b00;
    reg        rst_dsp  = 1'b1;

    always @(posedge clk) begin
        rst_sync <= {rst_sync[0], rst};
        if (!por_done) begin
            por_cnt <= por_cnt + 1'b1;
            if (por_cnt == 20'hFFFFF) por_done <= 1'b1;
        end
        rst_dsp <= (~por_done) | rst_sync[1];
    end

    // ---------------- detector ----------------
    wire signed [15:0] audio_sample;
    wire               sample_ready;

    audio_detector_top u_audio (
        .clk(clk),
        .rst(rst_dsp),
        .mic_miso(mic_miso),
        .mic_sck(mic_sclk),
        .mic_cs(mic_cs),
        .drum_type(drum_type),
        .drum_valid(drum_valid),
        .drum_timestamp(drum_timestamp),
        .note_code(note_code),
        .note_valid(note_valid),
        .note_timestamp(note_timestamp),
        .sample_tick(sample_tick),
        .dbg_audio_sample(audio_sample),
        .dbg_sample_ready(sample_ready),
        .dbg_frame_start()
    );

    // ---------------- debug: latched last results ----------------
    reg [2:0]  last_drum  = 3'd0;
    reg [3:0]  last_note  = 4'd0;
    reg [23:0] drum_flash = 24'd0;    // counts down 0.15 s after a drum
    reg [23:0] note_flash = 24'd0;
    always @(posedge clk) begin
        if (rst_dsp) begin
            last_drum <= 3'd0; last_note <= 4'd0; drum_flash <= 24'd0; note_flash <= 24'd0;
        end else begin
            if (drum_valid) begin last_drum <= drum_type; drum_flash <= 24'd15_000_000; end
            else if (drum_flash != 24'd0) drum_flash <= drum_flash - 1'b1;
            if (note_valid) begin last_note <= note_code; note_flash <= 24'd15_000_000; end
            else if (note_flash != 24'd0) note_flash <= note_flash - 1'b1;
        end
    end

    // ---------------- debug: level meter, peak |sample| over ~100 ms ----------------
    reg [10:0] peak_now = 11'd0, peak_show = 11'd0;
    reg [10:0] win_cnt  = 11'd0;      // 1600 samples = 100 ms
    wire [15:0] abs_s = audio_sample[15] ? (~audio_sample + 16'd1) : audio_sample;
    always @(posedge clk) begin
        if (sample_ready) begin
            if (win_cnt == 11'd1599) begin
                win_cnt   <= 11'd0;
                peak_show <= peak_now;
                peak_now  <= 11'd0;
            end else begin
                win_cnt <= win_cnt + 1'b1;
                if (abs_s[10:0] > peak_now) peak_now <= abs_s[10:0];
            end
        end
    end

    integer k;
    always @(posedge clk) begin
        dbg_led <= 16'd0;
        dbg_led[0] <= (last_drum == 3'd1);
        dbg_led[1] <= (last_drum == 3'd2);
        dbg_led[2] <= (last_drum == 3'd3);
        for (k = 1; k <= 8; k = k + 1)
            dbg_led[2 + k] <= (last_note == k);
        dbg_led[11] <= (peak_show >= 11'd100);
        dbg_led[12] <= (peak_show >= 11'd200);
        dbg_led[13] <= (peak_show >= 11'd400);
        dbg_led[14] <= (peak_show >= 11'd800);
        dbg_led[15] <= (peak_show >= 11'd1600);
    end

    // ---------------- debug: 7-segment display ----------------
    // patterns are {g,f,e,d,c,b,a}, active low
    localparam [6:0] P_BLANK = 7'b1111111, P_DASH = 7'b0111111,
                     P_C = 7'b1000110, P_D = 7'b0100001, P_E = 7'b0000110, P_F = 7'b0001110,
                     P_G = 7'b1000010, P_A = 7'b0001000, P_B = 7'b0000011,
                     P_4 = 7'b0011001, P_5 = 7'b0010010, P_H = 7'b0001001;
    reg [6:0] note_letter, note_oct, drum_letter;
    always @(*) begin
        case (last_note)
            4'd1: begin note_letter = P_C; note_oct = P_4; end
            4'd2: begin note_letter = P_D; note_oct = P_4; end
            4'd3: begin note_letter = P_E; note_oct = P_4; end
            4'd4: begin note_letter = P_F; note_oct = P_4; end
            4'd5: begin note_letter = P_G; note_oct = P_4; end
            4'd6: begin note_letter = P_A; note_oct = P_4; end
            4'd7: begin note_letter = P_B; note_oct = P_4; end
            4'd8: begin note_letter = P_C; note_oct = P_5; end
            default: begin note_letter = P_DASH; note_oct = P_DASH; end
        endcase
        case (last_drum)
            3'd1:    drum_letter = P_B;
            3'd2:    drum_letter = P_5;
            3'd3:    drum_letter = P_H;
            default: drum_letter = P_DASH;
        endcase
    end

    reg [17:0] scan_cnt = 18'd0;       // digit changes every ~0.65 ms
    always @(posedge clk) begin
        scan_cnt <= scan_cnt + 1'b1;
        case (scan_cnt[17:16])
            2'd0: begin an <= 4'b1110; seg <= drum_letter; dp <= ~(drum_flash != 24'd0); end
            2'd1: begin an <= 4'b1101; seg <= P_BLANK;     dp <= 1'b1; end
            2'd2: begin an <= 4'b1011; seg <= note_oct;    dp <= ~(note_flash != 24'd0); end
            2'd3: begin an <= 4'b0111; seg <= note_letter; dp <= 1'b1; end
        endcase
    end

endmodule