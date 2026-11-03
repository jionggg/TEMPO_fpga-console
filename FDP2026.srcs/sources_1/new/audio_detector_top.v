// audio_detector_top.v | v1 | 29 Oct 2026 21:00 SGT
`timescale 1ns / 1ps
// Person A subsystem: Pmod MIC3 -> continuous FFT (every 16 ms) -> drum + piano events.
// Replaces drum_recognition_top. This is the module teammates instantiate.
//
// Teammate interface (all on the 100 MHz clock):
//   drum_type[2:0]       1 kick, 2 snare, 3 hi-hat (holds last value)
//   drum_valid           1-clock pulse per drum hit (only real hits)
//   drum_timestamp[31:0] sample number when the drum was hit (16 = 1 ms)
//   note_code[3:0]       1 C4 2 D4 3 E4 4 F4 5 G4 6 A4 7 B4 8 C5 (holds last value)
//   note_valid           1-clock pulse per piano note
//   note_timestamp[31:0] sample number when the note was played
//   sample_tick[31:0]    current sample number (+1 every 1/16000 s) - same time base
// The valid pulses arrive later than the hit (notes ~60 ms, drums ~230 ms): judge timing
// by the timestamps, not by when the pulse arrives.
module audio_detector_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        mic_miso,
    output wire        mic_sck,
    output wire        mic_cs,
    output wire [2:0]  drum_type,
    output wire        drum_valid,
    output wire [31:0] drum_timestamp,
    output wire [3:0]  note_code,
    output wire        note_valid,
    output wire [31:0] note_timestamp,
    output wire [31:0] sample_tick,
    // debug / display
    output wire signed [15:0] dbg_audio_sample,
    output wire        dbg_sample_ready,
    output wire        dbg_frame_start
);
    wire signed [15:0] audio_sample;
    wire               sample_ready;
    wire [11:0]        mic_raw;

    wire [9:0]         rd_index;
    wire signed [15:0] rd_data;
    wire               frame_start;
    wire [31:0]        frame_end_tick;

    wire [23:0] config_data;
    wire        config_valid, config_ready;
    wire [31:0] fft_input_data, fft_output_data;
    wire        fft_input_valid, fft_input_ready, fft_input_last;
    wire [15:0] fft_output_user;
    wire        fft_output_valid, fft_output_last;
    wire        ctrl_busy;

    wire         feat_valid;
    wire [43:0]  hf_energy, noise_floor, c4_odd, c5_main;
    wire [351:0] note_score;

    assign dbg_audio_sample = audio_sample;
    assign dbg_sample_ready = sample_ready;
    assign dbg_frame_start  = frame_start;

    mic3_reader u_mic (
        .clk(clk), .mic_miso(mic_miso),
        .mic_sck(mic_sck), .mic_cs(mic_cs),
        .mic_sample(mic_raw),
        .audio_sample(audio_sample), .sample_ready(sample_ready)
    );

    frame_buffer u_buf (
        .clk(clk), .rst(rst),
        .audio_sample(audio_sample), .sample_ready(sample_ready),
        .rd_index(rd_index), .rd_data(rd_data),
        .frame_start(frame_start), .frame_end_tick(frame_end_tick),
        .sample_tick(sample_tick)
    );

    fft_controller u_ctrl (
        .clk(clk), .rst(rst), .frame_start(frame_start),
        .rd_index(rd_index), .rd_data(rd_data),
        .config_data(config_data), .config_valid(config_valid), .config_ready(config_ready),
        .fft_input_data(fft_input_data), .fft_input_valid(fft_input_valid),
        .fft_input_ready(fft_input_ready), .fft_input_last(fft_input_last),
        .fft_output_valid(fft_output_valid), .fft_output_last(fft_output_last),
        .busy(ctrl_busy)
    );

    xfft_0 u_fft (
        .aclk(clk), .aresetn(~rst),
        .s_axis_config_tdata(config_data),
        .s_axis_config_tvalid(config_valid),
        .s_axis_config_tready(config_ready),
        .s_axis_data_tdata(fft_input_data),
        .s_axis_data_tvalid(fft_input_valid),
        .s_axis_data_tready(fft_input_ready),
        .s_axis_data_tlast(fft_input_last),
        .m_axis_data_tdata(fft_output_data),
        .m_axis_data_tuser(fft_output_user),
        .m_axis_data_tvalid(fft_output_valid),
        .m_axis_data_tready(1'b1),
        .m_axis_data_tlast(fft_output_last)
    );

    spectrum_features u_feat (
        .clk(clk), .rst(rst),
        .fft_data(fft_output_data), .fft_bin(fft_output_user[9:0]),
        .fft_valid(fft_output_valid), .fft_last(fft_output_last),
        .feat_valid(feat_valid),
        .hf_energy(hf_energy), .noise_floor(noise_floor), .note_score(note_score),
        .c4_odd(c4_odd), .c5_main(c5_main)
    );

    // frame_end_tick only changes at the next frame_start (16 ms later), long after
    // this frame's features are finished, so it still belongs to this frame here.
    event_detector u_det (
        .clk(clk), .rst(rst),
        .feat_valid(feat_valid),
        .hf_energy(hf_energy), .noise_floor(noise_floor), .note_score(note_score),
        .c4_odd(c4_odd), .c5_main(c5_main),
        .frame_end_tick(frame_end_tick),
        .drum_type(drum_type), .drum_valid(drum_valid), .drum_timestamp(drum_timestamp),
        .note_code(note_code), .note_valid(note_valid), .note_timestamp(note_timestamp)
    );
endmodule
