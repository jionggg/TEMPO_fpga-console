`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_scenes - one picture of every scene, both screens (Ji Yong)
//
// Drives display_top's real inputs (sw[0] down) the way Meiyi and Pei Ling would:
//   MENU, COUNTDOWN 3 / 2 / 1 / GO, PLAYING with hits (sprites + hit colour),
//   PAUSED, RESULTS. Each frame is saved as scene_<name>_piano.ppm / _drum.ppm in the
//   way the board shows them. ms_tick stays 0, so flashes stay on for the pictures.
// Vivado: simulation source, Set as Top, Run Behavioral Simulation, "run all".
//////////////////////////////////////////////////////////////////////////////////

module tb_scenes;

    `include "TEMPO_defs.vh"

    reg clk = 0;
    always #5 clk = ~clk;

    reg  [2:0]   game_state = ST_MENU;
    reg  [1:0]   countdown_num = 2'd3;
    reg  [17:0]  song_time_ms = 0;
    reg  [7:0]   pno_ev_valid = 0, drm_ev_valid = 0, pno_ev_sync = 0, drm_ev_sync = 0;
    reg  [143:0] pno_ev_time = 0, drm_ev_time = 0;
    reg  [23:0]  pno_ev_lane = 0, drm_ev_lane = 0;
    reg  [15:0]  pno_score = 0, drm_score = 0;
    reg          judge_pulse = 0, judge_player = 0, sync_pulse = 0, sync_ok = 0;
    reg  [1:0]   judge_grade = 0;
    reg  [2:0]   judge_lane = 0;
    reg  [17:0]  judge_target_ms = 0, judge_hit_ms = 0;

    reg  [12:0]  pno_index = 0, drm_index = 0;
    wire [15:0]  pno_colour, drm_colour;

    display_top dut (
        .clk(clk), .rst(1'b0), .ms_tick(1'b0), .sw_mock(1'b0),
        .game_state(game_state), .countdown_num(countdown_num),
        .song_time_ms(song_time_ms), .song_len_ms(18'd25800),
        .pno_ev_valid(pno_ev_valid), .pno_ev_time(pno_ev_time),
        .pno_ev_lane(pno_ev_lane), .pno_ev_sync(pno_ev_sync),
        .drm_ev_valid(drm_ev_valid), .drm_ev_time(drm_ev_time),
        .drm_ev_lane(drm_ev_lane), .drm_ev_sync(drm_ev_sync),
        .pno_score(pno_score), .drm_score(drm_score),
        .pno_combo(8'd0), .drm_combo(8'd0), .difficulty(2'd0),
        .mult(4'd1), .buff_ms_left(12'd0),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade), .judge_lane(judge_lane),
        .judge_target_ms(judge_target_ms), .judge_hit_ms(judge_hit_ms),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok),
        .pno_index(pno_index), .pno_colour(pno_colour),
        .drm_index(drm_index), .drm_colour(drm_colour)
    );

    // one judgement, the way Pei Ling sends it: a 1-clock pulse with its details
    task judge(input player, input [2:0] lane, input [1:0] grade,
               input [17:0] target, input [17:0] hit);
        begin
            @(negedge clk);
            judge_pulse = 1; judge_player = player; judge_lane = lane; judge_grade = grade;
            judge_target_ms = target; judge_hit_ms = hit;
            @(negedge clk);
            judge_pulse = 0;
        end
    endtask

    task dump(input [8*16-1:0] tag);
        integer fp, fd, i;
        reg [8*48-1:0] name;
        begin
            repeat (60) @(posedge clk);                  // let bin2bcd finish counting
            $sformat(name, "scene_%0s_piano.ppm", tag); fp = $fopen(name, "w");
            $sformat(name, "scene_%0s_drum.ppm",  tag); fd = $fopen(name, "w");
            $fwrite(fp, "P3\n96 64\n255\n");
            $fwrite(fd, "P3\n96 64\n255\n");
            for (i = 0; i < 6144; i = i + 1) begin
                pno_index = dut.ROTATE_PNO ? 6143 - i : i;
                drm_index = dut.ROTATE_DRM ? 6143 - i : i;
                #1;
                $fwrite(fp, "%0d %0d %0d\n", pno_colour[15:11]*255/31, pno_colour[10:5]*255/63, pno_colour[4:0]*255/31);
                $fwrite(fd, "%0d %0d %0d\n", drm_colour[15:11]*255/31, drm_colour[10:5]*255/63, drm_colour[4:0]*255/31);
            end
            $fclose(fp); $fclose(fd);
            $display("wrote scene_%0s", tag);
        end
    endtask

    initial begin
        // ---- MENU ----
        game_state = ST_MENU;       dump("menu");

        // ---- COUNTDOWN: Meiyi's tiles are already queued, but must not show yet ----
        pno_ev_valid = 8'b0000_0111;  drm_ev_valid = 8'b0000_0111;
        pno_ev_time[17:0] = 18'd1000; pno_ev_time[35:18] = 18'd1400; pno_ev_time[53:36] = 18'd1800;
        pno_ev_lane[2:0]  = NOTE_E;   pno_ev_lane[5:3]   = NOTE_G;   pno_ev_lane[8:6]   = NOTE_C;
        drm_ev_time[17:0] = 18'd1000; drm_ev_time[35:18] = 18'd1200; drm_ev_time[53:36] = 18'd1600;
        drm_ev_lane[2:0]  = DRUM_BASS; drm_ev_lane[5:3]  = DRUM_SNARE; drm_ev_lane[8:6] = DRUM_CRASH;
        game_state = ST_COUNTDOWN;
        countdown_num = 2'd3;       dump("count3");
        countdown_num = 2'd2;       dump("count2");
        countdown_num = 2'd1;       dump("count1");
        countdown_num = 2'd0;       dump("countGO");

        // ---- PLAYING: both players hit the 1000 ms notes ----
        game_state = ST_PLAYING;
        song_time_ms = 18'd1060;
        judge(0, NOTE_E,    GRADE_PERFECT, 18'd1000, 18'd1020);   // piano 20 ms late
        judge(1, DRUM_BASS, GRADE_GOOD,    18'd1000, 18'd1090);   // kick 90 ms late
        pno_score = 16'd100; drm_score = 16'd50;
        song_time_ms = 18'd1150;    dump("play1150");
        judge(1, DRUM_SNARE, GRADE_PERFECT, 18'd1200, 18'd1170);  // snare 30 ms early
        song_time_ms = 18'd1280;    dump("play1280");

        // ---- PAUSED ----
        game_state = ST_PAUSED;     dump("paused");

        // ---- RESULTS: tallies from a short game ----
        game_state = ST_PLAYING;
        judge(0, NOTE_G, GRADE_PERFECT, 18'd1400, 18'd1410);
        judge(0, NOTE_C, GRADE_GOOD,    18'd1800, 18'd1900);
        judge(0, NOTE_D, GRADE_MISS,    18'd2200, 18'd0);
        judge(1, DRUM_CRASH, GRADE_MISS, 18'd1600, 18'd0);
        pno_score = 16'd1250; drm_score = 16'd700;
        game_state = ST_RESULTS;    dump("results");
        $finish;
    end

endmodule
