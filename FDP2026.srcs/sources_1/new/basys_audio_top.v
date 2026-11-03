// basys_audio_top.v | v2 | 02 Nov 2026 23:00 SGT
`timescale 1ns / 1ps
// Board-level wrapper for testing the audio detector on its own (Person A).
//   LED0 kick, LED1 snare, LED2 hi-hat      : last drum detected (stays on)
//   LED3..LED10 = C4 D4 E4 F4 G4 A4 B4 C5   : last note detected (stays on)
//   LED11..LED15                            : microphone level meter (LED15 = near clipping)
//   7-segment: [note letter][octave][blank][drum]   drum: b = kick, 5 = snare, H = hi-hat
//   A decimal point flashes for 0.15 s on every new note (digit 2) / drum (digit 0).
//   BTNC = reset (a power-on reset also happens automatically after programming).
module basys_audio_top (
    input  wire        clk,        // 100 MHz, W5
    input  wire        btnC,       // U18
    input  wire        mic_miso,   // JA3, J2
    output wire        mic_cs,     // JA1, J1
    output wire        mic_sck,    // JA4, G2
    output wire        RsTx,       // USB-UART to PC, A18
    output reg  [15:0] led,
    output reg  [6:0]  seg,        // seg[0]=CA ... seg[6]=CG, active low
    output reg         dp,         // active low
    output reg  [3:0]  an          // active low
);
    // ---------------- reset: power-on (about 10 ms) or BTNC ----------------
    reg [19:0] por_cnt = 20'd0;
    reg        por_done = 1'b0;
    reg [2:0]  btn_sync = 3'b000;
    reg        rst = 1'b1;
    always @(posedge clk) begin
        btn_sync <= {btn_sync[1:0], btnC};
        if (!por_done) begin
            por_cnt <= por_cnt + 1'b1;
            if (por_cnt == 20'hFFFFF) por_done <= 1'b1;
        end
        rst <= (~por_done) | btn_sync[2];
    end

    // ---------------- detector ----------------
    wire [2:0]  drum_type;
    wire        drum_valid;
    wire [31:0] drum_timestamp;
    wire [3:0]  note_code;
    wire        note_valid;
    wire [31:0] note_timestamp;
    wire [31:0] sample_tick;
    wire signed [15:0] audio_sample;
    wire        sample_ready, frame_start;

    audio_detector_top u_audio (
        .clk(clk), .rst(rst),
        .mic_miso(mic_miso), .mic_sck(mic_sck), .mic_cs(mic_cs),
        .drum_type(drum_type), .drum_valid(drum_valid), .drum_timestamp(drum_timestamp),
        .note_code(note_code), .note_valid(note_valid), .note_timestamp(note_timestamp),
        .sample_tick(sample_tick),
        .dbg_audio_sample(audio_sample), .dbg_sample_ready(sample_ready),
        .dbg_frame_start(frame_start)
    );

    // ---------------- latched results ----------------
    reg [2:0]  last_drum = 3'd0;
    reg [3:0]  last_note = 4'd0;
    reg [23:0] drum_flash = 24'd0;    // counts down 0.15 s after a drum
    reg [23:0] note_flash = 24'd0;
    always @(posedge clk) begin
        if (rst) begin
            last_drum <= 3'd0; last_note <= 4'd0; drum_flash <= 24'd0; note_flash <= 24'd0;
        end else begin
            if (drum_valid) begin last_drum <= drum_type; drum_flash <= 24'd15_000_000; end
            else if (drum_flash != 24'd0) drum_flash <= drum_flash - 1'b1;
            if (note_valid) begin last_note <= note_code; note_flash <= 24'd15_000_000; end
            else if (note_flash != 24'd0) note_flash <= note_flash - 1'b1;
        end
    end
    
        // ---------------- UART link to the laptop (TEST ONLY - not in the team build) ----------------
    // 11-byte packets at 460800 baud: 0xA5, kind, code, timestamp[31:0], sample_tick[31:0]
    //   kind 1 = drum (code = drum_type), kind 2 = note (code = note_code),
    //   kind 3 = clock heartbeat every 100 ms (code 0) so the laptop always knows sample_tick.
    reg        d_pend = 1'b0, n_pend = 1'b0, hb_pend = 1'b0;
    reg [2:0]  d_code = 3'd0;
    reg [3:0]  n_code = 4'd0;
    reg [31:0] d_ts = 32'd0, d_tick = 32'd0, n_ts = 32'd0, n_tick = 32'd0;
    reg [23:0] hb_cnt = 24'd0;        // 10,000,000 clocks = 100 ms

    reg [87:0] pkt = 88'd0;           // 11 bytes, sent from pkt[87:80] down
    reg [3:0]  pkt_left = 4'd0;       // bytes still to send
    reg        tx_busy = 1'b0;
    reg [9:0]  tx_shift = 10'h3FF;    // {stop, data, start}, idles high
    reg [3:0]  tx_bits = 4'd0;
    reg [7:0]  baud_cnt = 8'd0;
    localparam [7:0] BAUD_DIV = 8'd217;   // 100 MHz / 460800

    assign RsTx = tx_shift[0];

    always @(posedge clk) begin
        if (rst) begin
            d_pend <= 1'b0; n_pend <= 1'b0; hb_pend <= 1'b0; hb_cnt <= 24'd0; pkt_left <= 4'd0;
            tx_busy <= 1'b0; tx_shift <= 10'h3FF; tx_bits <= 4'd0; baud_cnt <= 8'd0;
        end else begin
            // heartbeat every 100 ms
            if (hb_cnt == 24'd9_999_999) begin hb_cnt <= 24'd0; hb_pend <= 1'b1; end
            else hb_cnt <= hb_cnt + 1'b1;
            // capture events
            if (drum_valid) begin
                d_pend <= 1'b1; d_code <= drum_type; d_ts <= drum_timestamp; d_tick <= sample_tick;
            end
            if (note_valid) begin
                n_pend <= 1'b1; n_code <= note_code; n_ts <= note_timestamp; n_tick <= sample_tick;
            end
            // byte transmitter (8N1); events go before heartbeats
            if (tx_busy) begin
                if (baud_cnt == BAUD_DIV - 1'b1) begin
                    baud_cnt <= 8'd0;
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    if (tx_bits == 4'd9) tx_busy <= 1'b0;
                    else                 tx_bits <= tx_bits + 1'b1;
                end else
                    baud_cnt <= baud_cnt + 1'b1;
            end else if (pkt_left != 4'd0) begin
                tx_shift <= {1'b1, pkt[87:80], 1'b0};
                pkt      <= {pkt[79:0], 8'd0};
                pkt_left <= pkt_left - 1'b1;
                tx_bits  <= 4'd0;
                baud_cnt <= 8'd0;
                tx_busy  <= 1'b1;
            end else if (d_pend && !drum_valid) begin
                pkt      <= {8'hA5, 8'd1, 5'd0, d_code, d_ts, d_tick};
                pkt_left <= 4'd11;
                d_pend   <= 1'b0;
            end else if (n_pend && !note_valid) begin
                pkt      <= {8'hA5, 8'd2, 4'd0, n_code, n_ts, n_tick};
                pkt_left <= 4'd11;
                n_pend   <= 1'b0;
            end else if (hb_pend) begin
                pkt      <= {8'hA5, 8'd3, 8'd0, sample_tick, sample_tick};
                pkt_left <= 4'd11;
                hb_pend  <= 1'b0;
            end
        end
    end

    // ---------------- level meter: peak |sample| over ~100 ms ----------------
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
        led <= 16'd0;
        led[0] <= (last_drum == 3'd1);
        led[1] <= (last_drum == 3'd2);
        led[2] <= (last_drum == 3'd3);
        for (k = 1; k <= 8; k = k + 1)
            led[2 + k] <= (last_note == k);
        led[11] <= (peak_show >= 11'd100);
        led[12] <= (peak_show >= 11'd200);
        led[13] <= (peak_show >= 11'd400);
        led[14] <= (peak_show >= 11'd800);
        led[15] <= (peak_show >= 11'd1600);
    end

    // ---------------- 7-segment display ----------------
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
