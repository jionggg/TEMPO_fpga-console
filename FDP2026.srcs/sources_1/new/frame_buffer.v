// frame_buffer.v | v1 | 29 Oct 2026 21:00 SGT
`timescale 1ns / 1ps
// Continuous 1024-sample circular buffer (one block RAM).
// Every 256 new samples (16 ms) it announces a new analysis frame = the latest 1024 samples.
//   frame_start     : 1-clock pulse when a new frame is complete
//   frame_end_tick  : sample number of the NEWEST sample in that frame
//   sample_tick     : free-running count of samples received (16 per ms)
// Read side: rd_index 0 = oldest sample of the frame, 1023 = newest. rd_data is valid
// one clock after rd_index changes (synchronous block-RAM read).
// Safe to read while recording: the next write (6250 clocks later) only overwrites
// index 0, which the FFT controller reads first.
module frame_buffer (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] audio_sample,
    input  wire               sample_ready,
    input  wire [9:0]         rd_index,
    output reg  signed [15:0] rd_data,
    output reg                frame_start,
    output reg  [31:0]        frame_end_tick,
    output reg  [31:0]        sample_tick
);
    reg signed [15:0] mem [0:1023];
    reg [9:0]  wr_ptr;
    reg [9:0]  frame_base;     // physical address of the oldest sample of the current frame
    reg [10:0] fill;           // samples stored so far, saturates at 1024

    // Control
    always @(posedge clk) begin
        frame_start <= 1'b0;
        if (rst) begin
            wr_ptr         <= 10'd0;
            fill           <= 11'd0;
            sample_tick    <= 32'd0;
            frame_base     <= 10'd0;
            frame_end_tick <= 32'd0;
        end else if (sample_ready) begin
            wr_ptr      <= wr_ptr + 1'b1;
            sample_tick <= sample_tick + 1'b1;
            if (fill != 11'd1024)
                fill <= fill + 1'b1;
            // This sample completes a frame when its number ends in ...255 (every 256)
            // and the buffer already holds the 1023 samples before it.
            if (sample_tick[7:0] == 8'd255 && fill >= 11'd1023) begin
                frame_base     <= wr_ptr + 1'b1;   // next slot to be overwritten = oldest
                frame_end_tick <= sample_tick;     // number of this (newest) sample
                frame_start    <= 1'b1;
            end
        end
    end

    // Block RAM write port
    always @(posedge clk) begin
        if (sample_ready)
            mem[wr_ptr] <= audio_sample;
    end

    // Block RAM read port (1-clock latency)
    wire [9:0] rd_addr = frame_base + rd_index;
    always @(posedge clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule
