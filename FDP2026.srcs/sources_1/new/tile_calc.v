`timescale 1ns / 1ps

// tldr: is pixel (x, y) a falling tile?
//   tile_slot  checks ONE event slot: "does this one tile cover pixel (x, y)?"
//   tile_calc  places 8 tile_slots (one per slot) and combines their answers.

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.10.2026 12:07:48
// Design Name: 
// Module Name: tile_calc
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


module tile_calc #(parameter SCREEN = 0) (     // SCREEN: 0 = piano, 1 = drum
    input  [6:0]   x,               // pixel column, 0,...,95 (left to right)
    input  [5:0]   y,               // pixel row, 0,...,63 (top to bottom)
    input  [17:0]  song_time_ms,    // how far into the song we are, in ms
    input  [7:0]   ev_valid,        // bit i = 1 if slot i holds a real event
    input  [143:0] ev_time,         // 8 slots x 18 bits: slot 0 = [17:0], slot 1 = [35:18], ...
    input  [23:0]  ev_lane,         // 8 slots x 3 bits:  slot 0 = [2:0],  slot 1 = [5:3],  ...
    input  [7:0]   ev_sync,         // bit i = 1 if slot i must land with the other player
    output         on_tile,         // 1 = some tile covers this pixel
    output [15:0]  tile_colour      // that tile's colour at this pixel
    );

    `include "TEMPO_layout.vh"     // HIT_Y, TILE_H, colours, ...

    // One answer pair per slot: hitN = "slot N's tile covers this pixel",
    // whiteN = "and this pixel is on the white rim of a sync tile".
    wire hit0, hit1, hit2, hit3, hit4, hit5, hit6, hit7;
    wire white0, white1, white2, white3, white4, white5, white6, white7;

    // Eight copies of the one-slot checker. Each gets its own 18 time bits and 3 lane bits.
    tile_slot #(.SCREEN(SCREEN)) s0 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[0]), .t(ev_time[17:0]),    .lane(ev_lane[2:0]),   .sync(ev_sync[0]), .hit(hit0), .white(white0));
    tile_slot #(.SCREEN(SCREEN)) s1 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[1]), .t(ev_time[35:18]),   .lane(ev_lane[5:3]),   .sync(ev_sync[1]), .hit(hit1), .white(white1));
    tile_slot #(.SCREEN(SCREEN)) s2 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[2]), .t(ev_time[53:36]),   .lane(ev_lane[8:6]),   .sync(ev_sync[2]), .hit(hit2), .white(white2));
    tile_slot #(.SCREEN(SCREEN)) s3 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[3]), .t(ev_time[71:54]),   .lane(ev_lane[11:9]),  .sync(ev_sync[3]), .hit(hit3), .white(white3));
    tile_slot #(.SCREEN(SCREEN)) s4 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[4]), .t(ev_time[89:72]),   .lane(ev_lane[14:12]), .sync(ev_sync[4]), .hit(hit4), .white(white4));
    tile_slot #(.SCREEN(SCREEN)) s5 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[5]), .t(ev_time[107:90]),  .lane(ev_lane[17:15]), .sync(ev_sync[5]), .hit(hit5), .white(white5));
    tile_slot #(.SCREEN(SCREEN)) s6 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[6]), .t(ev_time[125:108]), .lane(ev_lane[20:18]), .sync(ev_sync[6]), .hit(hit6), .white(white6));
    tile_slot #(.SCREEN(SCREEN)) s7 (.x(x), .y(y), .song_time_ms(song_time_ms),
        .valid(ev_valid[7]), .t(ev_time[143:126]), .lane(ev_lane[23:21]), .sync(ev_sync[7]), .hit(hit7), .white(white7));

    // Combine: the pixel is on a tile if ANY of the 8 tile slots actively cover it.
    assign on_tile = hit0 | hit1 | hit2 | hit3 | hit4 | hit5 | hit6 | hit7;

    // white if px sits on the rim of any sync tile.
    wire is_white = white0 | white1 | white2 | white3 | white4 | white5 | white6 | white7;
    
    assign tile_colour = is_white      ? WHITE :
                         (SCREEN == 0) ? CYAN  :
                                         ORANGE;
endmodule


//////////////////////////////////////////////////////////////////////////////////
// tile_slot - one event slot: does THIS tile cover pixel (x, y)?
//
// No negative numbers: instead of "ms until the hit" (negative once the player is
// late), we use "ms until the hit, plus 320". A tile stays on screen from 300 ms
// late to 1408 ms early, so that number is always positive while it matters.
// 320 is used (not 300) because it is a whole number of pixels: 320 / 32 = 10.
//////////////////////////////////////////////////////////////////////////////////

module tile_slot #(parameter SCREEN = 0) (
    input  [6:0]  x,
    input  [5:0]  y,
    input  [17:0] song_time_ms,     // now
    input         valid,            // this slot holds a real event
    input  [17:0] t,                // when this event should be hit, in ms
    input  [2:0]  lane,             // which lane it falls in
    input         sync,             // must land together with the other player
    output        hit,              // this tile covers the pixel
    output        white             // ... and the pixel is on a sync tile's rim
    );

    `include "tempo_layout.vh"
 
    localparam OFFSET_MS = 320;                              // keeps the numbers positive
    localparam BASE_Y    = HIT_Y + (OFFSET_MS >> SHIFT);     // 55 + 10 = 65
 
    // ms until the hit, plus 320. 19 bits so t + 320 can't overflow.
    // If the tile is very late this wraps round to a huge number, which the
    // window check below throws away.
    wire [18:0] ahead_ms = t + OFFSET_MS - song_time_ms;
 
    // Is the tile on screen? From 300 ms late (ahead_ms = 20) to 1408 ms early (1728).
    wire in_window = valid && (ahead_ms > OFFSET_MS - LATE_MS)
                           && (ahead_ms < OFFSET_MS + LOOKAHEAD_MS);
 
    // Convert ms to pixels: shift right by 5 = divide by 32 (32 ms per pixel).
    wire [13:0] steps = ahead_ms >> SHIFT;
 
    // The tile's bottom row. When the hit is due (ahead_ms = 320, steps = 10),
    // ybot = 65 - 10 = 55: exactly on the hit line.
    wire [6:0] ybot = BASE_Y - steps;
 
    // pno: 5x 19px lanes; grey dividers at x = 19, 38, 57, 76. 1-px gap on both sides of cols
    // drm: 5x 32px lanes; dividers at x = 32 and 64, with 2-pixel gaps
    wire [6:0] x0 = (SCREEN == 0) ? lane * 19 + 1  : lane * 32 + 2;
    wire [6:0] x1 = (SCREEN == 0) ? lane * 19 + 17 : lane * 32 + 29;
 
    // Is the pixel inside the tile? Columns x0..x1, rows ybot-3..ybot (4 rows).
    // (y + TILE_H > ybot) is the same as (y > ybot - 4), written so nothing goes negative.
    wire in_x = (x >= x0) && (x <= x1);
    wire in_y = (y <= ybot) && (y + TILE_H > ybot);
 
    assign hit = in_window && in_x && in_y;
 
    // On the tile's border: first or last column, bottom or top row.
    wire on_border = (x == x0) || (x == x1) || (y == ybot) || (y + TILE_H - 1 == ybot);
 
    assign white = hit && sync && on_border;
 
endmodule