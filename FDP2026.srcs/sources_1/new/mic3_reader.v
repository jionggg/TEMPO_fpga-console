// mic3_reader.v | v2 | 29 Oct 2026 17:00 SGT
`timescale 1ns / 1ps
// v2: ADC read at 80 kS/s (every 1250 clocks) -> average of 5 reads (anti-alias +
//     decimate) -> DC removal (high-pass, about 2.5 Hz) -> clamp to +-2047 -> 16 kS/s.
//     SPI bit timing identical to v1 (SCLK 2.5 MHz, frame of 4 zeros + 12 data bits).
//     Ports unchanged. 5 reads x 1250 clocks = 6250 clocks -> exactly 16 kS/s.
module mic3_reader (
    input wire clk,
    input wire mic_miso,
    output reg mic_sck = 1'b0,
    output reg mic_cs = 1'b1,
    output reg [11:0] mic_sample = 0,            // latest RAW ADC code (80 kS/s)
    output reg signed [15:0] audio_sample = 0,   // filtered, DC-removed, 16 kS/s
    output reg sample_ready = 1'b0               // 1-cycle pulse at 16 kHz
);
    // ---------------- SPI read engine (80 kS/s) ----------------
    localparam [10:0] READ_PERIOD = 11'd1250;    // 100 MHz / 1250 = 80 kS/s
    reg [10:0] read_timer = 0;
    reg [4:0]  clk_count = 0;
    reg [4:0]  bit_count = 0;
    reg [15:0] shift_reg = 0;
    localparam IDLE=2'd0, RISING=2'd1, FALLING=2'd2, FINISH=2'd3;
    reg [1:0]  state = IDLE;

    // ---------------- Decimation by 5 ----------------
    reg [2:0]         dec_count = 0;              // counts reads 0..4
    reg signed [15:0] dec_sum   = 0;              // running sum, max +-10240
    reg signed [15:0] avg_sum   = 0;              // completed sum of 5
    reg               avg_ready = 1'b0;

    wire signed [15:0] centred = $signed({4'b0000, shift_reg[11:0]}) - 16'sd2048;
    wire signed [15:0] new_sum = dec_sum + centred;

    // average = sum * 13 / 64  (13/64 = 1/4.92, close to 1/5, no divider needed)
    wire signed [20:0] sum21   = avg_sum;         // sign-extended
    wire signed [20:0] sum_x13 = sum21 * 21'sd13; // max +-133120
    wire signed [15:0] avg     = sum_x13 >>> 6;   // max +-2080

    // ---------------- DC removal ----------------
    // dc_acc holds the DC estimate x 1024. Time constant 1024 samples (64 ms),
    // so cutoff = 16000 / (2*pi*1024) = about 2.5 Hz, far below the 47 Hz low band.
    reg  signed [25:0] dc_acc = 0;
    wire signed [15:0] dc_est = dc_acc >>> 10;
    wire signed [16:0] hp     = avg - dc_est;
    wire signed [15:0] hp_sat = (hp >  17'sd2047) ? 16'sd2047  :
                                (hp < -17'sd2047) ? -16'sd2047 : hp[15:0];

    always @(posedge clk) begin
        sample_ready <= 1'b0;
        avg_ready    <= 1'b0;

        if (read_timer == READ_PERIOD - 1'b1)
            read_timer <= 0;
        else
            read_timer <= read_timer + 1'b1;

        if (state == IDLE) begin
            mic_cs <= 1'b1;
            mic_sck <= 1'b0;
            clk_count <= 0;
            if (read_timer == 0) begin
                mic_cs <= 1'b0;
                bit_count <= 0;
                state <= RISING;
            end
        end else if (clk_count == 5'd19) begin
            clk_count <= 0;
            case (state)
                RISING: begin
                    mic_sck <= 1'b1;
                    shift_reg <= {shift_reg[14:0], mic_miso};
                    state <= FALLING;
                end
                FALLING: begin
                    mic_sck <= 1'b0;
                    if (bit_count == 5'd15)
                        state <= FINISH;
                    else begin
                        bit_count <= bit_count + 1'b1;
                        state <= RISING;
                    end
                end
                FINISH: begin
                    mic_cs <= 1'b1;
                    mic_sck <= 1'b0;
                    mic_sample <= shift_reg[11:0];
                    if (dec_count == 3'd4) begin
                        avg_sum   <= new_sum;   // 5th read completes the group
                        dec_sum   <= 0;
                        dec_count <= 0;
                        avg_ready <= 1'b1;
                    end else begin
                        dec_sum   <= new_sum;
                        dec_count <= dec_count + 1'b1;
                    end
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end else begin
            clk_count <= clk_count + 1'b1;
        end

        // One clock after each group of 5: output a filtered 16 kHz sample.
        if (avg_ready) begin
            audio_sample <= hp_sat;
            sample_ready <= 1'b1;
            dc_acc       <= dc_acc + hp;   // DC estimate tracks slowly
        end
    end
endmodule
