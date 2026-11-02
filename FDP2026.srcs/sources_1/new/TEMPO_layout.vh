// params that screen_layout and tile_calc both need. ie the hit line, tile height and colours


// Geometry (96 x 64 pixels; x 0,...,95 left to right, y 0,...,63 top to bottom)
localparam RIBBON_H = 11;     // ribbon is rows y = 0,...,10
localparam HIT_Y    = 55;     // a tile's bottom row touches this line y, at its event time
localparam PAD_Y0   = 57;     // pads are rows y = 57,...,63
localparam TILE_H   = 8;      // tiles are 8 rows tall
 
// Fall speed: 2^SHIFT ms per pixel. SHIFT = 5 -> 32 ms per pixel.
localparam SHIFT        = 5;
localparam LOOKAHEAD_MS = (HIT_Y - RIBBON_H) << SHIFT;   // 44 px * 32 ms = 1408 ms of warning
localparam LATE_MS      = 300;                           // a missed tile keeps falling this long

// Colours (RGB565)
localparam [15:0] BLACK   = 16'h0000,
                  WHITE   = 16'hFFFF,
                  NAVY    = 16'h0010,
                  DIVIDER = 16'h2104,
                  PAD     = 16'h18E3,
                  CYAN    = 16'h07FF,   // piano tiles
                  ORANGE  = 16'hFD00;   // drum tiles                  
                  