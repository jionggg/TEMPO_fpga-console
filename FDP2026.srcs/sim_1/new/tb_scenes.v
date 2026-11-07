`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_scenes - one picture of every scene, both screens (Ji Yong)
//
// Drives display_top's real inputs (sw[0] down) the way Meiyi and Pei Ling would:
//   MENU (NORMAL, then HARD chosen), COUNTDOWN 3 / GO, PLAYING with hits (sprites, lane
//   labels, hit colour, score flash, green and orange SYNC'D), PAUSED, wrong presses
//   (burgundy, in the lane actually played), RESULTS.
// Every press also arrives the way Annanya reports it (note_* / drum_* with a sample
// timestamp), so presses that Pei Ling grades as hits are seen to disappear again.
// Each frame is saved as scene_<name>_piano.ppm / _drum.ppm in the way the board shows
// them. ms_tick stays 0, so flashes stay on for the pictures.
// Vivado: simulation source, Set as Top, Run Behavioral Simulation, "run all".
//////////////////////////////////////////////////////////////////////////////////

module tb_scenes;

    `include "TEMPO_defs.vh"

    reg clk = 0;
    always #5 clk = ~clk;

    reg  [2:0]   game_state = ST_MENU;
    reg  [1:0]   countdown_num = 2'd3;
    reg  [1:0]   song_select = 2'd1;
    reg  [17:0]  song_time_ms = 0;
    reg  [7:0]   pno_ev_valid = 0, drm_ev_valid = 0, pno_ev_sync = 0, drm_ev_sync = 0;
    reg  [143:0] pno_ev_time = 0, drm_ev_time = 0;
    reg  [23:0]  pno_ev_lane = 0, drm_ev_lane = 0;
    reg  [15:0]  pno_score = 0, drm_score = 0;
    reg          judge_pulse = 0, judge_player = 0, sync_pulse = 0, sync_ok = 0;
    reg  [1:0]   judge_grade = 0;
    reg  [2:0]   judge_lane = 0;
    reg  [7:0]   judge_id = 0, sync_id = 0;
    reg  [17:0]  judge_target_ms = 0, judge_hit_ms = 0;

    // Annanya's raw reports. 16 samples per ms; sample 100000 is song time 0 here.
    reg          note_valid = 0, drum_valid = 0;
    reg  [3:0]   note_code = 0;
    reg  [2:0]   drum_type = 0;
    reg  [31:0]  note_timestamp = 0, drum_timestamp = 0;
    wire [31:0]  sample_tick = 32'd100000 + song_time_ms * 16;

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
        .pno_combo(8'd0), .drm_combo(8'd0), .song_select(song_select),
        .mult(4'd1), .buff_ms_left(12'd0),
        .judge_pulse(judge_pulse), .judge_player(judge_player),
        .judge_grade(judge_grade), .judge_lane(judge_lane),
        .judge_target_ms(judge_target_ms), .judge_hit_ms(judge_hit_ms),
        .judge_id(judge_id),
        .sync_pulse(sync_pulse), .sync_ok(sync_ok), .sync_id(sync_id),
        .note_valid(note_valid), .note_code(note_code), .note_timestamp(note_timestamp),
        .drum_valid(drum_valid), .drum_type(drum_type), .drum_timestamp(drum_timestamp),
        .sample_tick(sample_tick),
        .pno_index(pno_index), .pno_colour(pno_colour),
        .drm_index(drm_index), .drm_colour(drm_colour)
    );

    // one judgement, the way Pei Ling sends it: a 1-clock pulse with its details.
    // with_sync = 1: this is a duet's second half, so the sync result comes on the same clock
    task judge(input player, input [2:0] lane, input [1:0] grade,
               input [17:0] target, input [17:0] hit, input [7:0] id,
               input with_sync, input ok);
        begin
            @(negedge clk);
            judge_pulse = 1; judge_player = player; judge_lane = lane; judge_grade = grade;
            judge_target_ms = target; judge_hit_ms = hit; judge_id = id;
            sync_pulse = with_sync; sync_ok = ok; sync_id = id;
            @(negedge clk);
            judge_pulse = 0; sync_pulse = 0;
        end
    endtask

    // one press as Annanya reports it: code = note code (piano) or drum type (drums),
    // made at song time `onset` (reported now, so its timestamp is in the past)
    task press(input player, input [3:0] code, input [17:0] onset);
        begin
            @(negedge clk);
            if (player == 0) begin
                note_valid = 1; note_code = code; note_timestamp = 32'd100000 + onset * 16;
            end else begin
                drum_valid = 1; drum_type = code[2:0]; drum_timestamp = 32'd100000 + onset * 16;
            end
            @(negedge clk);
            note_valid = 0; drum_valid = 0;
            repeat (5) @(posedge clk);           // Pei Ling needs longer than this
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
        // ---- MENU: NORMAL chosen, then HARD (btnD in Meiyi's game_fsm) ----
        game_state = ST_MENU;  song_select = 2'd1;  dump("menu");
        song_select = 2'd2;                         dump("menuhard");

        // ---- COUNTDOWN: Meiyi's tiles are already queued, but must not show yet ----
        pno_ev_valid = 8'b0000_0111;  drm_ev_valid = 8'b0000_0111;
        pno_ev_time[17:0] = 18'd1000; pno_ev_time[35:18] = 18'd1400; pno_ev_time[53:36] = 18'd1800;
        pno_ev_lane[2:0]  = NOTE_E;   pno_ev_lane[5:3]   = NOTE_G;   pno_ev_lane[8:6]   = NOTE_C;
        drm_ev_time[17:0] = 18'd1000; drm_ev_time[35:18] = 18'd1400; drm_ev_time[53:36] = 18'd1600;
        drm_ev_lane[2:0]  = DRUM_BASS; drm_ev_lane[5:3]  = DRUM_SNARE; drm_ev_lane[8:6] = DRUM_CRASH;
        pno_ev_sync = 8'b0000_0011;   drm_ev_sync = 8'b0000_0011;
        game_state = ST_COUNTDOWN;
        countdown_num = 2'd3;       dump("count3");
        countdown_num = 2'd0;       dump("countGO");

        // ---- PLAYING: duet 0 at 1000 ms, piano judged first (its score flashes) ----
        song_time_ms = 18'd900;
        game_state = ST_PLAYING;
        repeat (5) @(posedge clk);
        song_time_ms = 18'd1060;
        press(0, 4'd3, 18'd1020);                                       // E4, a real hit
        judge(0, NOTE_E, GRADE_PERFECT, 18'd1000, 18'd1020, 8'd0, 0, 0);
        pno_score = 16'd100;
        song_time_ms = 18'd1150;    dump("play_a");
        // drum PERFECT too, in sync: green SYNC'D on both screens, +50 each
        press(1, 4'd1, 18'd1030);                                       // kick, a real hit
        judge(1, DRUM_BASS, GRADE_PERFECT, 18'd1000, 18'd1030, 8'd0, 1, 1);
        pno_score = 16'd150; drm_score = 16'd150;
        song_time_ms = 18'd1230;    dump("play_b");
        // duet 1 at 1400 ms: piano PERFECT, drum GOOD, still in sync -> orange SYNC'D
        song_time_ms = 18'd1460;
        press(0, 4'd5, 18'd1410);                                       // G4, a real hit
        judge(0, NOTE_G, GRADE_PERFECT, 18'd1400, 18'd1410, 8'd1, 0, 0);
        press(1, 4'd2, 18'd1450);                                       // snare, a real hit
        judge(1, DRUM_SNARE, GRADE_GOOD, 18'd1400, 18'd1450, 8'd1, 1, 1);
        pno_score = 16'd300; drm_score = 16'd250;
        song_time_ms = 18'd1560;    dump("play_c");

        // ---- PAUSED ----
        game_state = ST_PAUSED;     dump("paused");

        // ---- WRONG PRESSES (back to PLAYING) ----
        game_state = ST_PLAYING;
        repeat (5) @(posedge clk);
        song_time_ms = 18'd1850;
        // (both wrong presses are reported at song time 1850, so their bars start there)
        // piano: C was due at 1800 but D4 was played at 1790. Pei Ling marks the C tile
        // MISS with the wrong key's time; the burgundy slice goes in the D lane.
        press(0, 4'd2, 18'd1790);
        judge(0, NOTE_C, GRADE_MISS, 18'd1800, 18'd1790, 8'd2, 0, 0);
        // drums: a kick at 1780 with no bass tile near it (Pei Ling ignores it): burgundy
        // in the BASS lane. The hi-hat due at 1600 was never hit: duet 2 not in sync.
        press(1, 4'd1, 18'd1780);
        judge(1, DRUM_CRASH, GRADE_MISS, 18'd1600, 18'd0, 8'd2, 1, 0);
        song_time_ms = 18'd2000;    dump("wrong");          // 150 ms after the reports: half grown
        song_time_ms = 18'd2200;    dump("wrong2");         // 350 ms: full 8 rows, sliding down

        // ---- RESULTS: tallies from a short game (SYNC'D 02/03) ----
        judge(0, NOTE_D, GRADE_MISS,    18'd2200, 18'd0,    8'd3, 0, 0);
        pno_score = 16'd1250; drm_score = 16'd700;
        game_state = ST_RESULTS;    dump("results");
        $finish;
    end

endmodule
