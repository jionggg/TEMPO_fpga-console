// TEMPO_layout.vh | v4 | 06 Nov 2026 SGT
// v4 (Ji Yong): scene screens (menu, countdown, pause, results), hit sprites under the
//     white line, dragging hit colour; letters A L N Q U; dark grade shades.
// v3 (Ji Yong): merged feat/ui-renderer: ribbon geometry, judgement colours, font codes.
// v2: LOOKAHEAD_MS renamed TILE_LOOKAHEAD_MS. TEMPO_defs.vh already has a LOOKAHEAD_MS
//     (Meiyi's 1500 ms spawn time); screen_layout includes both files, so the same
//     name twice was a 'already declared' compile error.
// params that screen_layout, tile_calc and ui_renderer need. ie the hit line, tile height and colours


// Geometry (96 x 64 pixels; x 0,...,95 left to right, y 0,...,63 top to bottom)
localparam RIBBON_H = 11;     // ribbon is rows y = 0,...,10
localparam HIT_Y    = 55;     // a tile's bottom row touches this line y, at its event time
localparam PAD_Y0   = 57;     // pads are rows y = 57,...,63
localparam TILE_H   = 8;      // tiles are 8 rows tall

// Fall speed: 2^SHIFT ms per pixel. SHIFT = 5 -> 32 ms per pixel.
localparam SHIFT             = 5;
localparam TILE_LOOKAHEAD_MS = (HIT_Y - RIBBON_H) << SHIFT;   // 44 px * 32 ms = 1408 ms of warning
localparam LATE_MS           = 300;                      // a missed tile keeps falling this long

// Ribbon (rows 0..10), top to bottom:
//   row 0      song progress bar (1 px thin)
//   rows 2..8  text: teammate's score (grey, left) | xN (green, centre) | my score (my colour, right)
//   row 10     divider line, doubles as the green buff fuse
// (sized like x [6:0] and y [5:0], so they plug straight into char_cell's ports)
// Each character is 6 px wide: 5 px of glyph + 1 px gap.
localparam       PROG_Y  = 0;        // progress bar row
localparam       FUSE_Y  = 10;       // divider / fuse row (last ribbon row)
localparam [5:0] TEXT_Y  = 6'd2;     // top row of the ribbon text (5x7 font: rows 2..8)
localparam [6:0] MATE_X  = 7'd1;     // teammate's score, 5 digits: x = 1..29
localparam [6:0] MINE_X  = 7'd66;    // my score, 5 digits: x = 66..94
localparam [6:0] MULT_X  = 7'd43;    // "x3": x = 43..53, centred on the screen
localparam [5:0] WORD_Y  = 6'd28;    // judgement word rows 28..34, in the middle of the field
localparam BUFF_MS = 3000;    // a full buff lasts 3 s: the fuse is full width at 3000 ms left
localparam FX_MS   = 250;     // judgement word, hit sprite and gold hit line last 250 ms

// Under the white line (rows 56..63): hit sprites and the dragging hit colour
localparam SPRITE_Y0 = 56;    // sprites are 16 x 8: rows 56..63
localparam MARK_MS   = 520;   // a hit's colour is kept until it has scrolled off the bottom

// Colours (RGB565)
localparam [15:0] BLACK   = 16'h0000,
                  WHITE   = 16'hFFFF,
                  NAVY    = 16'h0010,
                  DIVIDER = 16'h2104,
                  PAD     = 16'h18E3,
                  CYAN    = 16'h07FF,   // piano tiles, piano's own score
                  ORANGE  = 16'hFD00,   // drum tiles, drum's own score
                  GREY    = 16'h8410,   // teammate's score (medium grey)
                  BAR     = 16'hC618,   // song progress bar, played part (light grey)
                  GREEN   = 16'h07E0,   // PERFECT, and the buff (xN + fuse)
                  YELLOW  = 16'hFFE0,   // GOOD
                  RED     = 16'hF800,   // MISS
                  GOLD    = 16'hFEA0,   // hit line flash on a good sync
                  DK_GREEN  = 16'h03E0, // half-bright shades: the part of a hit that
                  DK_YELLOW = 16'h7BE0, //   lies outside its target tile (early / late)
                  DK_RED    = 16'h7800;

// Font character codes (font_rom). Digits 0..9 use their own value as the code,
// so a decimal digit d can be drawn with code {1'b0, d}.
localparam [4:0] CH_X  = 5'd10,   // small "x" for the multiplier
                 CH_SP = 5'd11,   // blank
                 CH_P  = 5'd12,
                 CH_E  = 5'd13,
                 CH_R  = 5'd14,
                 CH_F  = 5'd15,
                 CH_C  = 5'd16,
                 CH_T  = 5'd17,
                 CH_G  = 5'd18,
                 CH_O  = 5'd19,
                 CH_D  = 5'd20,
                 CH_M  = 5'd21,
                 CH_I  = 5'd22,
                 CH_S  = 5'd23,
                 CH_A  = 5'd24,
                 CH_L  = 5'd25,
                 CH_N  = 5'd26,
                 CH_Q  = 5'd27,
                 CH_U  = 5'd28;
