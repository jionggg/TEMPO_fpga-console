`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 12:07:34
// Design Name: 
// Module Name: display_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Member D (Ji Yong) static layout graphics for OLEDs
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// to check both OLEDs, the pin map and the colours before any game logic:
//   ribbon (navy, y 0-10), lane dividers, white hit line (y 55), idle pads (y 57-63),
//   one parked tile per lane (piano cyan, 5 lanes; drum orange, 3 lanes:
//   crash | snare | bass). Lane codes come from tempo_defs.vh.
// Next steps from the plan: mock_feed + input_select, falling tiles, score ribbon,
// judgement flashes. All inputs below are already wired from the top.
//
// The colour logic is combinational in pixel_index: the OLED asks about a pixel and
// gets an answer straight away (see "The OLED asks, you answer" in the plan).
//////////////////////////////////////////////////////////////////////////////////

module display_top (
    input              clk,
    input              rst,
    input              ms_tick,
    input              sw_mock,
    // from Meiyi
    input  [2:0]       game_state,
    input  [1:0]       countdown_num,
    input  [17:0]      song_time_ms,
    input  [17:0]      song_len_ms,
    input  [7:0]       pno_ev_valid,
    input  [8*18-1:0]  pno_ev_time,
    input  [8*3-1:0]   pno_ev_lane,
    input  [7:0]       pno_ev_sync,
    input  [7:0]       drm_ev_valid,
    input  [8*18-1:0]  drm_ev_time,
    input  [8*3-1:0]   drm_ev_lane,
    input  [7:0]       drm_ev_sync,
    input  [15:0]      pno_score,
    input  [15:0]      drm_score,
    input  [7:0]       pno_combo,
    input  [7:0]       drm_combo,
    input  [1:0]       difficulty,
    // from Pei Ling
    input              judge_pulse,
    input              judge_player,
    input  [1:0]       judge_grade,
    input  [2:0]       judge_lane,
    input              sync_pulse,
    input              sync_ok,
    // OLED drivers
    input  [12:0]      pno_index,
    output [15:0]      pno_colour,
    input  [12:0]      drm_index,
    output [15:0]      drm_colour
    );
    
    
    // // Test mode: sw[0] up = show mock_feed's fake song instead of Meiyi's
        
    wire [17:0]  mock_song_time_ms;
    wire [7:0]   mock_pno_valid, mock_pno_sync, mock_drm_valid, mock_drm_sync;
    wire [143:0] mock_pno_time,  mock_drm_time;
    wire [23:0]  mock_pno_lane,  mock_drm_lane;

    mock_feed mock (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .enable(sw_mock),
        .song_time_ms(mock_song_time_ms),
        .pno_ev_valid(mock_pno_valid), .pno_ev_time(mock_pno_time),
        .pno_ev_lane(mock_pno_lane),   .pno_ev_sync(mock_pno_sync),
        .drm_ev_valid(mock_drm_valid), .drm_ev_time(mock_drm_time),
        .drm_ev_lane(mock_drm_lane),   .drm_ev_sync(mock_drm_sync)
    );

    // input_select: each "use_" signal is the mock one when sw[0] is up, else Meiyi's
    wire [17:0]  use_song_time = sw_mock ? mock_song_time_ms : song_time_ms;
    wire [7:0]   use_pno_valid = sw_mock ? mock_pno_valid    : pno_ev_valid;
    wire [143:0] use_pno_time  = sw_mock ? mock_pno_time     : pno_ev_time;
    wire [23:0]  use_pno_lane  = sw_mock ? mock_pno_lane     : pno_ev_lane;
    wire [7:0]   use_pno_sync  = sw_mock ? mock_pno_sync     : pno_ev_sync;
    wire [7:0]   use_drm_valid = sw_mock ? mock_drm_valid    : drm_ev_valid;
    wire [143:0] use_drm_time  = sw_mock ? mock_drm_time     : drm_ev_time;
    wire [23:0]  use_drm_lane  = sw_mock ? mock_drm_lane     : drm_ev_lane;
    wire [7:0]   use_drm_sync  = sw_mock ? mock_drm_sync     : drm_ev_sync;
    
    
    // rotate 180 degrees by reversing px order
    localparam ROTATE_PNO = 0, ROTATE_DRM = 1;     
    wire [12:0] pno_idx = ROTATE_PNO ? 13'd6143 - pno_index : pno_index;
    wire [12:0] drm_idx = ROTATE_DRM ? 13'd6143 - drm_index : drm_index;

    screen_layout #(.SCREEN(0)) piano_screen (
        .pixel_index(pno_idx), .song_time_ms(use_song_time),
        .ev_valid(use_pno_valid), .ev_time(use_pno_time),
        .ev_lane(use_pno_lane),   .ev_sync(use_pno_sync),
        .colour(pno_colour)
    );
    screen_layout #(.SCREEN(1)) drum_screen (
        .pixel_index(drm_idx), .song_time_ms(use_song_time),
        .ev_valid(use_drm_valid), .ev_time(use_drm_time),
        .ev_lane(use_drm_lane),   .ev_sync(use_drm_sync),
        .colour(drm_colour)
    );

endmodule


// One copy per screen. SCREEN = 0 piano (5 lanes), 1 drum (3 lanes).
module screen_layout #(parameter SCREEN = 0) (
    input      [12:0] pixel_index,
    input      [17:0]     song_time_ms,
    input      [7:0]      ev_valid,
    input      [8*18-1:0] ev_time,
    input      [8*3-1:0]  ev_lane,
    input      [7:0]      ev_sync,
    output reg [15:0] colour
    );

    `include "TEMPO_defs.vh"
    `include "TEMPO_layout.vh"

    wire [6:0] x = pixel_index % 96;      // 0..95, left to right
    wire [5:0] y = pixel_index / 96;      // 0..63, top to bottom

    // which lane is this pixel's column in? (tile area only, not the divider)
    reg       in_lane;
    reg [2:0] lane;
    always @(*) begin
        in_lane = 1'b0;
        lane    = 3'd0;
        if (SCREEN == 0) begin
            // 5 piano lanes, 19 px each: C | D | E | F | G
            if      (x >=  1 && x <= 17) begin in_lane = 1'b1; lane = NOTE_C; end
            else if (x >= 20 && x <= 36) begin in_lane = 1'b1; lane = NOTE_D; end
            else if (x >= 39 && x <= 55) begin in_lane = 1'b1; lane = NOTE_E; end
            else if (x >= 58 && x <= 74) begin in_lane = 1'b1; lane = NOTE_F; end
            else if (x >= 77 && x <= 93) begin in_lane = 1'b1; lane = NOTE_G; end
        end else begin
            // 3 drum lanes, 32 px each: crash | snare | bass
            if      (x >=  2 && x <= 29) begin in_lane = 1'b1; lane = DRUM_CRASH; end
            else if (x >= 34 && x <= 61) begin in_lane = 1'b1; lane = DRUM_SNARE; end
            else if (x >= 66 && x <= 93) begin in_lane = 1'b1; lane = DRUM_BASS;  end
        end
    end

    wire is_divider = (SCREEN == 0) ? (x == 19 || x == 38 || x == 57 || x == 76)
                                    : (x == 32 || x == 64);


    // falling tiles: one tile_calc per screen, same SCREEN setting as this copy
    wire        on_tile;
    wire [15:0] tile_colour;
    tile_calc #(.SCREEN(SCREEN)) tiles (
        .x(x), .y(y), .song_time_ms(song_time_ms),
        .ev_valid(ev_valid), .ev_time(ev_time), .ev_lane(ev_lane), .ev_sync(ev_sync),
        .on_tile(on_tile), .tile_colour(tile_colour)
    );

    // top layer first; the first test that says yes paints the pixel
    always @(*) begin
        if      (y < RIBBON_H)              colour = NAVY;
        else if (on_tile)                   colour = tile_colour;
        else if (y == HIT_Y)                colour = WHITE;
        else if (y >= PAD_Y0 && in_lane)    colour = PAD;
        else if (is_divider)                colour = DIVIDER;
        else                                colour = BLACK;
    end

endmodule
