// fft_controller.v | v3 | 29 Oct 2026 21:00 SGT
`timescale 1ns / 1ps
// v3: continuous analysis. On every frame_start it windows the 1024 samples of the frame
//     and streams them into xfft_0, then waits for the FFT output to finish.
// Window (no ROM needed): w[n] = (4 n (1024-n) / 2^20)^2 in Q15 - smooth, Hann-like.
// FFT input = sample * w * 8 / 32768  (max +-16376, fits signed 16-bit).
// FFT scaling: total 2^9 (stages 0..8 shift 1 bit, stage 9 none). No overflow is possible
// for inputs within +-16384: each scaled stage keeps |value| <= input max, the last <= 2x.
// Config word layout (PG109, radix-2 burst, N=1024): {3'b0, SCALE_SCH[19:0], FWD_INV}.
module fft_controller (
    input  wire               clk,
    input  wire               rst,
    input  wire               frame_start,
    output reg  [9:0]         rd_index,
    input  wire signed [15:0] rd_data,
    output wire [23:0]        config_data,
    output wire               config_valid,
    input  wire               config_ready,
    output wire [31:0]        fft_input_data,
    output wire               fft_input_valid,
    input  wire               fft_input_ready,
    output wire               fft_input_last,
    input  wire               fft_output_valid,
    input  wire               fft_output_last,
    output wire               busy
);
    localparam IDLE=3'd0, CONFIG=3'd1, ADDR=3'd2, WAIT=3'd3, LATCH=3'd4,
               MUL=3'd5, SEND=3'd6, WAIT_OUT=3'd7;
    reg [2:0] state;

    // SCALE_SCH = 00 01 01 01 01 01 01 01 01 01 (stage9..stage0) = 20'h15555, FWD = 1
    assign config_data  = 24'h02AAAB;
    assign config_valid = (state == CONFIG);
    assign busy         = (state != IDLE);

    // ---- window generator, pipelined alongside the RAM read ----
    reg  [20:0] win_a;                  // n * (1024 - n), max 262144
    reg  [15:0] win_q;                  // win_a >> 3, clamped to 32767
    reg  [15:0] win_w;                  // win_q^2 >> 15  (Q15 window value)
    wire [31:0] win_q_sq = win_q * win_q;

    reg  signed [15:0] x_hold;
    reg  signed [32:0] prod;            // sample * window (written in MUL, stable in SEND)
    wire signed [32:0] prod_sh = prod >>> 12;

    assign fft_input_data  = {16'd0, prod_sh[15:0]};   // imag = 0, real = windowed sample
    assign fft_input_valid = (state == SEND);
    assign fft_input_last  = (state == SEND) && (rd_index == 10'd1023);

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            rd_index <= 10'd0;
            win_a    <= 21'd0;
            win_q    <= 16'd0;
            win_w    <= 16'd0;
            x_hold   <= 16'sd0;
            prod     <= 33'sd0;
        end else begin
            case (state)
                IDLE: if (frame_start) state <= CONFIG;
                CONFIG: if (config_ready) begin
                    rd_index <= 10'd0;
                    state    <= ADDR;
                end
                ADDR: begin             // RAM samples rd_index at the end of this cycle
                    win_a <= rd_index * (11'd1024 - {1'b0, rd_index});
                    state <= WAIT;
                end
                WAIT: begin             // RAM data valid from the next cycle
                    win_q <= (win_a[20:3] > 18'd32767) ? 16'd32767 : win_a[18:3];
                    state <= LATCH;
                end
                LATCH: begin
                    x_hold <= rd_data;
                    win_w  <= win_q_sq[30:15];
                    state  <= MUL;
                end
                MUL: begin
                    prod  <= x_hold * $signed({1'b0, win_w});
                    state <= SEND;
                end
                SEND: if (fft_input_ready) begin
                    if (rd_index == 10'd1023)
                        state <= WAIT_OUT;
                    else begin
                        rd_index <= rd_index + 1'b1;
                        state    <= ADDR;
                    end
                end
                WAIT_OUT: if (fft_output_valid && fft_output_last) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
