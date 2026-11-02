`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_mock_display - display_top in test mode (sw[0] up), with mock_feed playing
//
// ms_tick is held high so every 10 ns clock counts as 1 ms of song.
// The testbench lets the song run to a chosen time, stops the clock ticking, then
// asks about every pixel and saves both screens as .ppm images (board orientation).

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.10.2026 17:07:39
// Design Name: 
// Module Name: tb_mock_display
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


module tb_mock_display;

    reg clk = 0;
    always #5 clk = ~clk;

    reg         ms_tick = 0;
    reg         sw_mock = 1;              // test mode on
    reg  [12:0] pno_index = 0, drm_index = 0;
    wire [15:0] pno_colour, drm_colour;

    // Meiyi's and Pei Ling's inputs are all 0 here: in test mode they are ignored.
    display_top dut (
        .clk(clk), .rst(1'b0), .ms_tick(ms_tick), .sw_mock(sw_mock),
        .game_state(3'd0), .countdown_num(2'd0), .song_time_ms(18'd0), .song_len_ms(18'd0),
        .pno_ev_valid(8'd0), .pno_ev_time(144'd0), .pno_ev_lane(24'd0), .pno_ev_sync(8'd0),
        .drm_ev_valid(8'd0), .drm_ev_time(144'd0), .drm_ev_lane(24'd0), .drm_ev_sync(8'd0),
        .judge_pulse(1'b0), .judge_player(1'b0), .judge_grade(2'd0), .judge_lane(3'd0),
        .sync_pulse(1'b0), .sync_ok(1'b0),
        .pno_score(16'd0), .drm_score(16'd0), .pno_combo(8'd0), .drm_combo(8'd0),
        .difficulty(2'd0),
        .pno_index(pno_index), .pno_colour(pno_colour),
        .drm_index(drm_index), .drm_colour(drm_colour)
    );

    // let the fake song run until it reaches t_ms
    task run_song_to(input integer t_ms);
        begin
            // check on the falling edge, after the rising edge has updated the clock,
            // and stop ticking before the next rising edge
            ms_tick = 1;
            while (dut.mock_song_time_ms < t_ms) @(negedge clk);
            ms_tick = 0;
        end
    endtask

    // save both screens, the way the board shows them
    task dump_frames(input integer t_ms);
        integer fp, fd, i;
        reg [8*40-1:0] name;
        begin
            $sformat(name, "mock_piano_t%0d.ppm", t_ms); fp = $fopen(name, "w");
            $sformat(name, "mock_drum_t%0d.ppm",  t_ms); fd = $fopen(name, "w");
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
            $display("song time %0d ms: wrote mock_piano_t%0d.ppm and mock_drum_t%0d.ppm",
                     dut.mock_song_time_ms, t_ms, t_ms);
        end
    endtask

    initial begin
        #20;
        run_song_to(1000); dump_frames(1000);    // first tiles falling in from the top
        run_song_to(1700); dump_frames(1700);
        run_song_to(2048); dump_frames(2048);    // beat 4 (sync) exactly on the hit line
        run_song_to(2200); dump_frames(2200);    // 152 ms late: just below the line
        $finish;
    end

endmodule
