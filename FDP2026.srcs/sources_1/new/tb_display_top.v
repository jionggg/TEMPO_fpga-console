`timescale 1ns / 1ps
// tb_display_top - fast testbench for display_top ALONE 

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 16:04:09
// Design Name: 
// Module Name: tb_display_top
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

// No Oled_Display and no 150 ms power-up: this testbench plays the part of the two
// OLEDs. It asks display_top about every pixel (pixel_index 0..6143), collects the
// colours, and writes each screen to a .ppm image. The whole run takes ~1 ms of
// simulated time, so it finishes in seconds.
//
// The mock inputs below stand in for C (events, song clock) and B (judgements)
// Today display_top draws a static layout, so every frame looks the same.
// Once you add falling tiles, the frames at 0 / 250 / 500 ms will show the
// tiles sliding down, and slot 0 should touch the hit line in the 500 ms frame.

// note to self; set this as top, run Behavioral Simulation, then type run all
// in the Tcl console. Images land in  <project>.sim/sim_1/behav/xsim/
// open .ppm with GIMP or IrfanView on Windows
//////////////////////////////////////////////////////////////////////////////////

module tb_display_top;

    `include "tempo_defs.vh"

    reg clk = 0;
    always #5 clk = ~clk;                         // 100 MHz

    // ---- mock inputs (Meiyi) ----
    reg  [2:0]      game_state    = ST_PLAYING;
    reg  [1:0]      countdown_num = 2'd0;
    reg  [17:0]     song_time_ms  = 18'd0;
    reg  [17:0]     song_len_ms   = 18'd30000;    // 30 s song
    reg  [7:0]      pno_ev_valid  = 8'b0000_0111; // slots 0..2 hold events
    reg  [8*18-1:0] pno_ev_time   = 0;
    reg  [8*3-1:0]  pno_ev_lane   = 0;
    reg  [7:0]      pno_ev_sync   = 8'b0000_0001;
    reg  [7:0]      drm_ev_valid  = 8'b0000_0111;
    reg  [8*18-1:0] drm_ev_time   = 0;
    reg  [8*3-1:0]  drm_ev_lane   = 0;
    reg  [7:0]      drm_ev_sync   = 8'b0000_0001;
    reg  [15:0]     pno_score = 16'd1200, drm_score = 16'd900;
    reg  [7:0]      pno_combo = 8'd12,    drm_combo = 8'd7;
    reg  [1:0]      difficulty = 2'd1;

    // ---- mock inputs (Pei Ling) ----
    reg             judge_pulse = 0, judge_player = 0, sync_pulse = 0, sync_ok = 0;
    reg  [1:0]      judge_grade = GRADE_PERFECT;
    reg  [2:0]      judge_lane  = 3'd0;

    // ---- the "OLEDs" ----
    reg  [12:0] pno_index = 0, drm_index = 0;
    wire [15:0] pno_colour, drm_colour;

    display_top dut (
        .clk(clk), .rst(1'b0), .ms_tick(1'b0), .sw_mock(1'b0),
        .game_state(game_state), .countdown_num(countdown_num),
        .song_time_ms(song_time_ms), .song_len_ms(song_len_ms),
        .pno_ev_valid(pno_ev_valid), .pno_ev_time(pno_ev_time),
        .pno_ev_lane(pno_ev_lane), .pno_ev_sync(pno_ev_sync),
        .drm_ev_valid(drm_ev_valid), .drm_ev_time(drm_ev_time),
        .drm_ev_lane(drm_ev_lane), .drm_ev_sync(drm_ev_sync),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade), .judge_lane(judge_lane),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok),
        .pno_score(pno_score), .drm_score(drm_score),
        .pno_combo(pno_combo), .drm_combo(drm_combo),
        .difficulty(difficulty),
        .pno_index(pno_index), .pno_colour(pno_colour),
        .drm_index(drm_index), .drm_colour(drm_colour)
    );

    // ---- ask about every pixel of both screens, write two .ppm files ----
    task dump_frames(input integer t_ms);
        integer fp, fd, i;
        reg [8*40-1:0] name;
        begin
            $sformat(name, "piano_t%0d.ppm", t_ms); fp = $fopen(name, "w");
            $sformat(name, "drum_t%0d.ppm",  t_ms); fd = $fopen(name, "w");
            $fwrite(fp, "P3\n96 64\n255\n");
            $fwrite(fd, "P3\n96 64\n255\n");
            for (i = 0; i < 6144; i = i + 1) begin
                pno_index = i; drm_index = i;
                #1;                               // let the combinational logic settle
                $fwrite(fp, "%0d %0d %0d\n", pno_colour[15:11]*255/31, pno_colour[10:5]*255/63, pno_colour[4:0]*255/31);
                $fwrite(fd, "%0d %0d %0d\n", drm_colour[15:11]*255/31, drm_colour[10:5]*255/63, drm_colour[4:0]*255/31);
            end
            $fclose(fp); $fclose(fd);
            $display("wrote piano_t%0d.ppm and drum_t%0d.ppm", t_ms, t_ms);
        end
    endtask

    initial begin
        // piano: slot 0 hits at 500 ms in lane C, slot 1 at 900 ms in E, slot 2 at 1300 ms in G
        pno_ev_time[0*18 +: 18] = 18'd500;   pno_ev_lane[0*3 +: 3] = NOTE_C;
        pno_ev_time[1*18 +: 18] = 18'd900;   pno_ev_lane[1*3 +: 3] = NOTE_E;
        pno_ev_time[2*18 +: 18] = 18'd1300;  pno_ev_lane[2*3 +: 3] = NOTE_G;
        // drums: bass at 500 ms (in sync with the piano C), snare at 750 ms, crash at 1000 ms
        drm_ev_time[0*18 +: 18] = 18'd500;   drm_ev_lane[0*3 +: 3] = DRUM_BASS;
        drm_ev_time[1*18 +: 18] = 18'd750;   drm_ev_lane[1*3 +: 3] = DRUM_SNARE;
        drm_ev_time[2*18 +: 18] = 18'd1000;  drm_ev_lane[2*3 +: 3] = DRUM_CRASH;

        song_time_ms = 18'd0;   dump_frames(0);
        song_time_ms = 18'd250; dump_frames(250);
        song_time_ms = 18'd500; dump_frames(500);
        $finish;
    end

endmodule

